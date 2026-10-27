import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../app/controllers/app_settings_controller.dart';
import '../../../../app/dialogs/confirm_delete_dialog.dart';
import '../../../../app/widgets/serene_app_bar.dart';
import '../../../../core/constants/hive_constants.dart';
import '../../../../core/localization/app_translations.dart';
import '../../../../core/services/device_authentication.dart';
import '../../../../core/services/session_manager.dart';
import '../../domain/repositories/evidence_repository.dart';
import '../../data/models/evidence_record_model.dart';
import '../../domain/entities/evidence_record.dart';
import '../../domain/entities/vault_item.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  List<EvidenceRecord> _records = [];
  StreamSubscription<BoxEvent>? _changes;
  String? _loadError;
  Future<void>? _loading;
  bool _reloadRequested = false;
  bool _isLoading = true;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _refreshRecords();
  }

  Future<void> _refreshRecords() {
    _reloadRequested = true;
    return _loading ??= _refreshLoop().whenComplete(() {
      _loading = null;
    });
  }

  Future<void> _refreshLoop() async {
    do {
      _reloadRequested = false;
      await _loadRecords();
    } while (mounted && _reloadRequested);
  }

  Future<void> _loadRecords() async {
    try {
      if (_changes == null) {
        // Observe changes before reading through the authenticated repository.
        final box = await Hive.openBox<EvidenceRecordModel>(
          HiveConstants.encryptedEvidenceBox,
        );
        if (!mounted) return;
        _changes = box.watch().listen((_) {
          unawaited(_refreshRecords());
        });
      }
      final records = await context
          .read<EvidenceRepository>()
          .getAllEvidenceRecords();
      if (!mounted) return;
      setState(() {
        _records = records;
        _loadError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _records = [];
          _loadError = 'vault_integrity_error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  List<VaultItem> _getRealVaultItems() {
    final records = _records;

    return records.map((record) {
      return VaultItem(
        id: record.id,
        name:
            '${record.predictionLabel}_${record.logicalIncidentId.substring(0, record.logicalIncidentId.length < 6 ? record.logicalIncidentId.length : 6)}',
        legacy: !record.hasAuthenticatedMetadata,
        date: record.timestamp.toLocal(),
        encrypted: true,
        type: 'audio',
      );
    }).toList();
  }

  Future<bool> _deleteRecord(String id) async {
    if (_deleting) return false;
    setState(() => _deleting = true);
    try {
      final locale = context.read<AppSettingsController>().locale;
      final authenticated = await context
          .read<DeviceAuthentication>()
          .authenticate(
            AppTranslations.tr('vault_delete_auth_reason', locale),
            context.read<SessionManager>(),
          );
      if (!authenticated || !mounted) return false;
      await context.read<EvidenceRepository>().deleteEvidenceRecord(id);
      if (mounted) await _refreshRecords();
      return true;
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _openAudio(
    VaultItem item,
    String Function(String) translate,
  ) async {
    EvidenceRecord? record;
    for (final candidate in _records) {
      if (candidate.id == item.id) {
        record = candidate;
        break;
      }
    }

    if (record == null || record.encryptedAudioBlob.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translate('vault_audio_unavailable'))),
      );
      return;
    }
    await context.push<void>('/vault/audio', extra: record);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    final settingsController = context.watch<AppSettingsController>();
    final currentLocale = settingsController.locale;
    String t(String key) => AppTranslations.tr(key, currentLocale);

    final vaultItems = _getRealVaultItems();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SereneAppBar(),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('vault_title'),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t('vault_subtitle'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Tarjeta de estado
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                t('vault_private_access_badge'),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: primaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t('vault_private_access_title'),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t('vault_private_access_desc'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                  height: 1.6,
                                ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          t('vault_recent_assets'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${vaultItems.length} items',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: primaryColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_loadError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          t(_loadError!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      )
                    else if (vaultItems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0),
                        child: Center(
                          child: Text(
                            t('vault_empty_message'),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                ),
                          ),
                        ),
                      )
                    else
                      ...vaultItems.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _VaultItemCard(
                            item: item,
                            deleteActionText: t('vault_delete_action'),
                            legacyText: t('vault_legacy_record'),
                            onTap: () => _openAudio(item, t),
                            onDelete: _deleting
                                ? null
                                : () {
                                    showGeneralDialog<void>(
                                      context: context,
                                      barrierDismissible: true,
                                      barrierLabel: t('vault_cancel_action'),
                                      barrierColor: Colors.transparent,
                                      pageBuilder: (dialogContext, _, _) =>
                                          ConfirmDeleteDialog(
                                            title: t('vault_delete_title'),
                                            message:
                                                '${t('vault_delete_msg')}\n\n${item.name}',
                                            confirmLabel: t(
                                              'vault_confirm_action',
                                            ),
                                            cancelLabel: t(
                                              'vault_cancel_action',
                                            ),
                                            onConfirm: () async {
                                              try {
                                                final deleted =
                                                    await _deleteRecord(
                                                      item.id,
                                                    );
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      t(
                                                        deleted
                                                            ? 'vault_delete_success'
                                                            : 'auth_cancelled',
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              } catch (_) {
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      t('vault_delete_error'),
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                    );
                                  },
                          ),
                        ),
                      ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
      ),
    );
  }
}

class _VaultItemCard extends StatelessWidget {
  final VaultItem item;
  final String deleteActionText;
  final String legacyText;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _VaultItemCard({
    required this.item,
    required this.deleteActionText,
    required this.legacyText,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor.withValues(alpha: 0.15),
                  ),
                  child: Icon(Icons.mic, color: primaryColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.legacy ? '${item.name} · $legacyText' : item.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatDate(item.date)} • ${_formatTime(item.date)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<void>(
                  enabled: onDelete != null,
                  itemBuilder: (context) => [
                    PopupMenuItem<void>(
                      onTap: onDelete,
                      child: Text(deleteActionText),
                    ),
                  ],
                  child: Icon(
                    Icons.more_vert,
                    color: primaryColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
