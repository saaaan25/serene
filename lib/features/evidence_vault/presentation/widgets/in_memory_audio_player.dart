import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

// just_audio currently exposes no stable alternative for an in-memory source.
// ignore_for_file: experimental_member_use

/// Custom StreamAudioSource that serves WAV audio data from memory without
/// ever writing decrypted audio to disk.
class InMemoryAudioSource extends StreamAudioSource {
  final Uint8List audioData;

  InMemoryAudioSource({required this.audioData});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final length = audioData.length;

    if (length == 0) {
      return StreamAudioResponse(
        rangeRequestsSupported: false,
        contentLength: 0,
        offset: null,
        sourceLength: 0,
        stream: const Stream<List<int>>.empty(),
        contentType: 'audio/wav',
      );
    }

    final actualStart = (start ?? 0).clamp(0, length);
    final requestedEnd = end ?? length;
    final actualEnd = requestedEnd.clamp(actualStart, length);

    if (actualStart >= length || actualEnd <= actualStart) {
      return StreamAudioResponse(
        rangeRequestsSupported: false,
        contentLength: 0,
        offset: null,
        sourceLength: length,
        stream: const Stream<List<int>>.empty(),
        contentType: 'audio/wav',
      );
    }

    final data = audioData.sublist(actualStart, actualEnd);

    return StreamAudioResponse(
      contentLength: data.length,
      offset: actualStart,
      sourceLength: length,
      stream: Stream.value(data),
      contentType: 'audio/wav',
    );
  }
}

/// Widget that plays in-memory audio with full playback controls
/// Implements Play/Pause, progress slider, and time display
/// SECURITY: Never writes audio to disk; all data stays in RAM
class InMemoryAudioPlayer extends StatefulWidget {
  final Uint8List audioData;
  final String? title;
  final VoidCallback? onDispose;
  final String errorMessage;
  final String failureTitle;
  final String retryLabel;
  final bool autoPlay;

  const InMemoryAudioPlayer({
    super.key,
    required this.audioData,
    this.title,
    this.onDispose,
    this.errorMessage = 'Could not play this audio.',
    this.failureTitle = 'Playback unavailable',
    this.retryLabel = 'Retry',
    this.autoPlay = false,
  });

  @override
  State<InMemoryAudioPlayer> createState() => _InMemoryAudioPlayerState();
}

class _InMemoryAudioPlayerState extends State<InMemoryAudioPlayer> {
  late AudioPlayer _audioPlayer;
  late StreamSubscription<PlayerState> _playerStateSubscription;
  late StreamSubscription<Duration> _positionSubscription;
  late StreamSubscription<Duration?> _durationSubscription;

  bool _isPlaying = false;
  bool _isLoading = true;
  bool _hasLoadError = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _setupAudioPlayer();
    unawaited(_initializeAudio());
  }

  void _setupAudioPlayer() {
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });

    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });

    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _totalDuration = duration ?? Duration.zero;
        });
      }
    });
  }

  Future<void> _initializeAudio() async {
    if (_isLoading && _hasLoadError) return;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasLoadError = false;
      });
    }
    try {
      final source = InMemoryAudioSource(audioData: widget.audioData);
      await _audioPlayer.setAudioSource(source);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      if (widget.autoPlay) await _audioPlayer.play();
    } catch (error) {
      debugPrint('Could not load in-memory audio for playback: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasLoadError = true;
        });
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (_isLoading || _hasLoadError) return;
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    } catch (error) {
      debugPrint('Could not control in-memory audio playback: $error');
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _hasLoadError = true;
        });
      }
    }
  }

  Future<void> _onSliderChanged(double value) async {
    try {
      await _audioPlayer.seek(Duration(milliseconds: value.toInt()));
    } catch (error) {
      debugPrint('Could not seek in-memory audio playback: $error');
      if (mounted) {
        setState(() {
          _hasLoadError = true;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxDuration = _totalDuration.inMilliseconds.toDouble();
    final currentPosition = _currentPosition.inMilliseconds
        .toDouble()
        .clamp(0, maxDuration > 0 ? maxDuration : 1)
        .toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.title != null) ...[
            Text(
              widget.title!,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
          ],
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            )
          else if (_hasLoadError)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.error.withValues(alpha: 0.18)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.error.withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      color: colors.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.failureTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.errorMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onErrorContainer.withValues(alpha: 0.85),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _initializeAudio,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(widget.retryLabel),
                  ),
                ],
              ),
            )
          else ...[
            IconButton.filled(
              onPressed: _togglePlayPause,
              iconSize: 34,
              padding: const EdgeInsets.all(16),
              style: IconButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
              ),
              icon: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
            const SizedBox(height: 16),
            Slider(
              value: currentPosition,
              max: maxDuration > 0 ? maxDuration : 1,
              onChanged: maxDuration > 0 ? _onSliderChanged : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_currentPosition),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                  Text(
                    _formatDuration(_totalDuration),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _playerStateSubscription.cancel();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _audioPlayer.dispose();
    widget.onDispose?.call();
    super.dispose();
  }
}
