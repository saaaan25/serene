import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/controllers/app_settings_controller.dart';
import '../../../../core/localization/app_translations.dart';
import '../../../../core/services/diagnostics_service.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key, this.service});

  final DiagnosticsService? service;

  @override
  Widget build(BuildContext context) {
    final diagnostics = service ?? DiagnosticsService.instance;
    final locale = context.watch<AppSettingsController>().locale;
    String t(String key) => AppTranslations.tr(key, locale);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('diagnostics_title'))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: diagnostics,
          builder: (context, _) {
            final sample = diagnostics.latestSample;
            String number(
              Object? value, {
              int digits = 1,
              String suffix = '',
            }) => value is num
                ? '${value.toStringAsFixed(digits)}$suffix'
                : t('diagnostics_unavailable');
            final memory =
                sample?['process_footprint_bytes'] ??
                sample?['process_pss_bytes'] ??
                sample?['process_resident_bytes'];
            final memoryKey = sample?['process_footprint_bytes'] != null
                ? 'diagnostics_footprint'
                : sample?['process_pss_bytes'] != null
                ? 'diagnostics_pss'
                : 'diagnostics_resident';
            final report = diagnostics.report();
            final timings = (report['runtime'] as Map)['timings_ms'] as Map;
            final inference = timings['inference'] as Map?;
            final initialization = timings['model_initialize'] as Map?;
            final saving = timings['evidence_save'] as Map?;
            final monitoring = report['monitoring'] as Map?;
            final worker = monitoring?['worker'] as Map?;
            final workerTimings =
                (worker?['runtime'] as Map?)?['timings_ms'] as Map? ??
                diagnostics.latestMonitoringRuntime?['timings_ms'] as Map?;
            final displayedInference =
                workerTimings?['inference'] as Map? ?? inference;
            final displayedInitialization =
                workerTimings?['model_initialize'] as Map? ?? initialization;
            final displayedSaving =
                workerTimings?['evidence_save'] as Map? ?? saving;
            final seconds = diagnostics.elapsedSeconds.toInt();
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t('diagnostics_intro'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                t(
                                  diagnostics.isRecording
                                      ? 'diagnostics_recording'
                                      : diagnostics.hasReport
                                      ? 'diagnostics_finished'
                                      : 'diagnostics_ready',
                                ),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')} · ${diagnostics.sampleCount} ${t('diagnostics_samples')}',
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                key: const ValueKey('diagnostics_toggle'),
                                onPressed: diagnostics.isBusy
                                    ? null
                                    : () async {
                                        try {
                                          if (diagnostics.isRecording) {
                                            await diagnostics.stop();
                                          } else {
                                            await diagnostics.start();
                                          }
                                        } catch (_) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  t(
                                                    'diagnostics_capture_error',
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                icon: Icon(
                                  diagnostics.isRecording
                                      ? Icons.stop_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                label: Text(
                                  t(
                                    diagnostics.isRecording
                                        ? 'diagnostics_stop'
                                        : 'diagnostics_start',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                key: const ValueKey('diagnostics_export'),
                                onPressed:
                                    !diagnostics.hasReport || diagnostics.isBusy
                                    ? null
                                    : () async {
                                        try {
                                          await diagnostics.export();
                                        } catch (_) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  t('diagnostics_export_error'),
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.ios_share_rounded),
                                label: Text(t('diagnostics_export')),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Metric(
                        label: t('diagnostics_cpu'),
                        value: number(
                          sample?['process_cpu_percent_one_core'],
                          suffix: ' %',
                        ),
                      ),
                      _Metric(
                        label: t(memoryKey),
                        value: number(
                          memory is num ? memory / (1024 * 1024) : null,
                          suffix: ' MiB',
                        ),
                      ),
                      _Metric(
                        label: t('diagnostics_battery'),
                        value: number(
                          sample?['battery_percent'],
                          digits: 0,
                          suffix: ' %',
                        ),
                      ),
                      _Metric(
                        label: t('diagnostics_thermal'),
                        value: sample?['thermal_state'] is String
                            ? t('thermal_${sample!['thermal_state']}')
                            : t('diagnostics_unavailable'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t('diagnostics_model_times'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      _Metric(
                        label: t('diagnostics_model_init'),
                        value: number(
                          displayedInitialization?['last'],
                          suffix: ' ms',
                        ),
                      ),
                      _Metric(
                        label: t('diagnostics_inference_mean'),
                        value: number(
                          displayedInference?['mean'],
                          suffix: ' ms',
                        ),
                      ),
                      _Metric(
                        label: t('diagnostics_inference_p95'),
                        value: number(
                          displayedInference?['recent_p95'],
                          suffix: ' ms',
                        ),
                      ),
                      _Metric(
                        label: t('diagnostics_save'),
                        value: number(displayedSaving?['mean'], suffix: ' ms'),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        t('diagnostics_instructions'),
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t('diagnostics_privacy'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
