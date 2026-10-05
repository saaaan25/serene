import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../../../app/controllers/app_settings_controller.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/localization/app_translations.dart';
import '../../../../core/services/session_manager.dart';
import '../../domain/entities/evidence_record.dart';
import '../../domain/repositories/evidence_repository.dart';
import '../widgets/in_memory_audio_player.dart';

class AudioPlaybackScreen extends StatefulWidget {
  const AudioPlaybackScreen({super.key, required this.record});

  final EvidenceRecord record;

  @override
  State<AudioPlaybackScreen> createState() => _AudioPlaybackScreenState();
}

class _AudioPlaybackScreenState extends State<AudioPlaybackScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  Uint8List? _decryptedWav;
  bool _isLoading = true;
  bool _authenticationInProgress = false;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticateAndLoad();
    });
  }

  Future<void> _authenticateAndLoad() async {
    if (_authenticationInProgress) return;
    _authenticationInProgress = true;

    setState(() {
      _isLoading = true;
      _errorKey = null;
    });

    final locale = context.read<AppSettingsController>().locale;
    final sessionManager = context.read<SessionManager>();
    final evidenceRepository = context.read<EvidenceRepository>();
    try {
      final isSupported =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!isSupported) {
        _setError('auth_not_supported');
        return;
      }

      sessionManager.beginAuthenticationPrompt();
      late final bool authenticated;
      try {
        authenticated = await _localAuth.authenticate(
          localizedReason: AppTranslations.tr('audio_auth_reason', locale),
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
      } finally {
        sessionManager.endAuthenticationPrompt();
      }

      if (!authenticated) {
        _setError('audio_auth_cancelled');
        return;
      }
      if (!mounted) return;

      final pcmBytes = await evidenceRepository.getDecryptedAudioBytes(
        widget.record,
      );
      late final Uint8List wavBytes;
      try {
        if (pcmBytes.isEmpty || pcmBytes.length.isOdd) {
          throw StateError('Decrypted audio is not valid 16-bit PCM data.');
        }
        wavBytes = _createWav(pcmBytes);
      } finally {
        pcmBytes.fillRange(0, pcmBytes.length, 0);
      }
      if (!mounted) {
        wavBytes.fillRange(0, wavBytes.length, 0);
        return;
      }
      setState(() {
        _decryptedWav = wavBytes;
        _isLoading = false;
        _authenticationInProgress = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not authenticate or decrypt evidence audio: $error');
      debugPrintStack(stackTrace: stackTrace);
      _setError('audio_load_error');
    }
  }

  Uint8List _createWav(Uint8List pcmBytes) {
    const headerLength = 44;
    const bitsPerSample = 16;
    const channels = AppConstants.audioChannels;
    const sampleRate = AppConstants.sampleRate;
    const bytesPerSample = bitsPerSample ~/ 8;
    const byteRate = sampleRate * channels * bytesPerSample;
    const blockAlign = channels * bytesPerSample;

    final wav = Uint8List(headerLength + pcmBytes.length);
    final header = ByteData.sublistView(wav, 0, headerLength);
    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, wav.length - 8, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, pcmBytes.length, Endian.little);
    wav.setRange(headerLength, wav.length, pcmBytes);
    return wav;
  }

  void _setError(String key) {
    if (!mounted) return;
    setState(() {
      _errorKey = key;
      _isLoading = false;
      _authenticationInProgress = false;
    });
  }

  @override
  void dispose() {
    _decryptedWav?.fillRange(0, _decryptedWav!.length, 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = context.watch<AppSettingsController>().locale;
    String t(String key) => AppTranslations.tr(key, locale);
    final timestamp = widget.record.timestamp.toLocal();

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: t('vault_cancel_action'),
        ),
        title: Text(t('audio_screen_title')),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 190,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                  _decryptedWav == null
                      ? Icons.lock_rounded
                      : Icons.graphic_eq_rounded,
                  size: 76,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                widget.record.predictionLabel,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${MaterialLocalizations.of(context).formatMediumDate(timestamp)}'
                '  •  ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(timestamp))}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 20),
              _EvidenceMetadata(
                record: widget.record,
                translate: t,
              ),
              const SizedBox(height: 24),
              if (_decryptedWav case final audio?)
                InMemoryAudioPlayer(
                  key: ValueKey(widget.record.id),
                  audioData: audio,
                  errorMessage: t('audio_playback_error'),
                  failureTitle: t('audio_playback_failure_title'),
                  retryLabel: t('audio_retry_action'),
                  autoPlay: true,
                )
              else
                _AuthenticationPanel(
                  isLoading: _isLoading,
                  errorMessage: _errorKey == null ? null : t(_errorKey!),
                  retryLabel: t('audio_auth_retry'),
                  loadingLabel: t('audio_auth_loading'),
                  onRetry: _isLoading ? null : _authenticateAndLoad,
                ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t('audio_privacy_note'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.75),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceMetadata extends StatelessWidget {
  const _EvidenceMetadata({
    required this.record,
    required this.translate,
  });

  final EvidenceRecord record;
  final String Function(String) translate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final location = record.gpsCoordinates.isEmpty
        ? translate('audio_metadata_location_unavailable')
        : record.gpsCoordinates.entries
              .map((entry) => '${entry.key}: ${entry.value}')
              .join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate('audio_metadata_title'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          _MetadataRow(label: translate('audio_metadata_id'), value: record.id),
          _MetadataRow(
            label: translate('audio_metadata_confidence'),
            value: '${record.confidenceScore * 100}%',
          ),
          _MetadataRow(
            label: translate('audio_metadata_location'),
            value: location,
          ),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthenticationPanel extends StatelessWidget {
  const _AuthenticationPanel({
    required this.isLoading,
    required this.errorMessage,
    required this.retryLabel,
    required this.loadingLabel,
    required this.onRetry,
  });

  final bool isLoading;
  final String? errorMessage;
  final String retryLabel;
  final String loadingLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          if (isLoading)
            const CircularProgressIndicator()
          else
            Icon(
              errorMessage == null
                  ? Icons.fingerprint_rounded
                  : Icons.error_outline_rounded,
              size: 42,
              color: errorMessage == null ? colors.primary : colors.error,
            ),
          const SizedBox(height: 16),
          Text(
            isLoading ? loadingLabel : (errorMessage ?? ''),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: errorMessage == null
                  ? colors.onSurface
                  : colors.onErrorContainer,
              height: 1.45,
            ),
          ),
          if (!isLoading) ...[
            const SizedBox(height: 18),
            if (errorMessage != null)
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(retryLabel),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: Text(retryLabel),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
