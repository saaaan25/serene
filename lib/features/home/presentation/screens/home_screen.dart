import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../../app/controllers/app_settings_controller.dart';
import '../../../../app/widgets/serene_app_bar.dart';
import '../../../../core/constants/hive_constants.dart';
import '../../../../core/localization/app_translations.dart';
import '../../../../core/services/session_manager.dart';
import '../../../../features/audio_monitoring/presentation/controllers/monitoring_controller.dart';
import '../../../evidence_vault/data/models/evidence_record_model.dart';
import '../../../evidence_vault/domain/repositories/evidence_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _totalAssets = 0;
  String _encryptedSpace = '0 B';
  bool _isLoadingStats = true;
  StreamSubscription<BoxEvent>? _evidenceChanges;
  final PageController _statusPageController = PageController();
  int _currentStatusPage = 0;

  @override
  void initState() {
    super.initState();
    if (Hive.isBoxOpen(HiveConstants.encryptedEvidenceBox)) {
      _evidenceChanges = Hive.box<EvidenceRecordModel>(
        HiveConstants.encryptedEvidenceBox,
      ).watch().listen((_) => _loadStats());
    }
    _loadStats();
  }

  @override
  void dispose() {
    _evidenceChanges?.cancel();
    _statusPageController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final repository = context.read<EvidenceRepository>();
      final stats = await repository.getVaultStats();
      if (mounted) {
        setState(() {
          _totalAssets = stats.totalCount;
          _encryptedSpace = stats.formattedSpace;
          _isLoadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingStats = false;
        });
      }
    }
  }

  Future<void> _retryMonitoring() async {
    try {
      var permission = await Permission.microphone.status;
      if (permission.isPermanentlyDenied || permission.isRestricted) {
        final opened = await openAppSettings();
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppTranslations.tr(
                  'home_monitoring_settings_error',
                  context.read<AppSettingsController>().locale,
                ),
              ),
            ),
          );
        }
        return;
      }

      if (!permission.isGranted) {
        permission = await Permission.microphone.request();
      }
      if (permission.isGranted && mounted) {
        await context.read<MonitoringController>().startMonitoring();
      }
    } catch (error) {
      debugPrint('Unable to request microphone permission: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final monitoringController = context.watch<MonitoringController>();
    final sessionManager = context.watch<SessionManager>();
    final statusTextKey = switch (monitoringController.status) {
      MonitoringStatus.idle => 'home_monitoring_idle',
      MonitoringStatus.initializing => 'home_monitoring_initializing',
      MonitoringStatus.active => 'home_monitoring_active',
      MonitoringStatus.paused => 'home_monitoring_paused',
      MonitoringStatus.error => 'home_monitoring_unavailable',
    };
    final statusColor = switch (monitoringController.status) {
      MonitoringStatus.active => Colors.green,
      MonitoringStatus.error => Theme.of(context).colorScheme.error,
      _ => primaryColor,
    };
    final lastDetection = monitoringController.lastDetectedClass;
    final hasDetection = lastDetection.toLowerCase() != 'none';

    // Obtención del idioma reactivo desde AppSettingsController
    final settingsController = context.watch<AppSettingsController>();
    final currentLocale = settingsController.locale;
    String t(String key) => AppTranslations.tr(key, currentLocale);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SereneAppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // Swipe between monitoring, latest event, and session status.
                Center(
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.2),
                      ),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                    ),
                    child: Stack(
                      children: [
                        PageView(
                          controller: _statusPageController,
                          onPageChanged: (index) {
                            setState(() => _currentStatusPage = index);
                          },
                          children: [
                            _HomeStatusPage(
                              icon: Icons.graphic_eq,
                              title: t('home_monitoring_title'),
                              value: t(statusTextKey),
                              iconColor: statusColor,
                              indicatorColor: statusColor,
                            ),
                            _HomeStatusPage(
                              icon: hasDetection
                                  ? Icons.notifications_active_outlined
                                  : Icons.notifications_none,
                              title: t('home_latest_event_title'),
                              value: hasDetection
                                  ? lastDetection
                                  : t('home_no_events'),
                              iconColor: primaryColor,
                              indicatorColor: primaryColor,
                            ),
                            _HomeStatusPage(
                              icon: sessionManager.isAuthenticated
                                  ? Icons.lock_outline
                                  : Icons.lock_open_outlined,
                              title: t('home_session_title'),
                              value: t(
                                sessionManager.isAuthenticated
                                    ? 'home_session_active'
                                    : 'home_session_auth_required',
                              ),
                              iconColor: primaryColor,
                              indicatorColor: primaryColor,
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            // Increase bottom padding here to move the page dots
                            // farther from the circle's lower edge.
                            padding: const EdgeInsets.only(bottom: 30),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(3, (index) {
                                final isSelected = index == _currentStatusPage;
                                return GestureDetector(
                                  onTap: () =>
                                      _statusPageController.animateToPage(
                                        index,
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        curve: Curves.easeInOut,
                                      ),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: isSelected ? 18 : 6,
                                    height: 6,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? primaryColor
                                          : primaryColor.withValues(
                                              alpha: 0.25,
                                            ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (monitoringController.status == MonitoringStatus.error) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('home_monitoring_error_hint'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (monitoringController.errorMessage
                            case final detail?)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _retryMonitoring,
                            icon: const Icon(Icons.mic),
                            label: Text(t('home_monitoring_retry')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 40),

                // Capture and Recording Cards
                Row(
                  children: [
                    Expanded(
                      child: _RecordCard(
                        icon: Icons.videocam,
                        title: t('home_record_camera'),
                        description: t('home_record_camera_desc'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _RecordCard(
                        icon: Icons.mic,
                        title: t('home_record_audio'),
                        description: t('home_record_audio_desc'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Secure Vault Section con métricas reales
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
                          const Icon(Icons.lock, color: Colors.pink),
                          const SizedBox(width: 12),
                          Text(
                            t('home_secure_vault'),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _VaultStat(
                              label: t('home_total_assets'),
                              value: _isLoadingStats
                                  ? '...'
                                  : '$_totalAssets ${currentLocale == 'es' ? 'Elementos' : 'Items'}',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _VaultStat(
                              label: t('home_encrypted_space'),
                              value: _isLoadingStats ? '...' : _encryptedSpace,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: () => context.go('/vault'),
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: Text(
                            t('home_access_vault_btn'),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeStatusPage extends StatelessWidget {
  const _HomeStatusPage({
    required this.icon,
    required this.title,
    required this.value,
    required this.iconColor,
    required this.indicatorColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color iconColor;
  final Color indicatorColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Increase bottom padding to shift the carousel content slightly upward.
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: 0.1),
            ),
            child: Icon(icon, size: 44, color: iconColor),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: iconColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: indicatorColor,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _RecordCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: primaryColor, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultStat extends StatelessWidget {
  final String label;
  final String value;

  const _VaultStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.pink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
