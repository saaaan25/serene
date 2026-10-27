import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/controllers/app_settings_controller.dart';
import '../../../../app/controllers/monitoring_access_controller.dart';
import '../../../../core/localization/app_translations.dart';
import '../../../audio_monitoring/presentation/controllers/monitoring_controller.dart';

class MonitoringSetting extends StatelessWidget {
  const MonitoringSetting({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    final access = context.watch<MonitoringAccessController>();
    final monitoring = context.watch<MonitoringController>();
    String t(String key) => AppTranslations.tr(key, settings.locale);
    return SwitchListTile.adaptive(
      key: const ValueKey('monitoring_setting'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      secondary: Icon(settings.monitoringEnabled ? Icons.mic : Icons.mic_off),
      title: Text(t('monitoring_setting_title')),
      subtitle: Text(
        t(
          access.isBusy
              ? 'monitoring_changing'
              : monitoring.status == MonitoringStatus.error &&
                    settings.monitoringEnabled
              ? 'home_monitoring_unavailable'
              : settings.monitoringEnabled
              ? 'monitoring_setting_enabled'
              : 'monitoring_setting_disabled',
        ),
      ),
      value: settings.monitoringEnabled,
      onChanged: access.isBusy
          ? null
          : (enabled) async {
              final message = await access.changeEnabled(
                enabled,
                t('monitoring_auth_reason'),
              );
              if (!context.mounted || message == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(t(message)),
                  action: message == 'monitoring_permission_settings'
                      ? SnackBarAction(
                          label: t('monitoring_open_settings'),
                          onPressed: () async {
                            await access.microphone.openSettings();
                          },
                        )
                      : null,
                ),
              );
            },
    );
  }
}
