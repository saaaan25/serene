import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'setting_icon.dart';

import '../../../../app/controllers/app_settings_controller.dart';
import '../../../../app/controllers/location_access_controller.dart';
import '../../../../core/localization/app_translations.dart';

class LocationSetting extends StatelessWidget {
  const LocationSetting({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    final access = context.watch<LocationAccessController>();
    String t(String key) => AppTranslations.tr(key, settings.locale);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        ),
      ),
      child: SwitchListTile(
        key: const ValueKey('location_setting'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        activeThumbColor: Theme.of(context).colorScheme.primary,
        secondary: SettingIcon(
          icon: settings.locationEnabled
              ? Icons.location_on
              : Icons.location_off,
        ),
        title: Text(
          t('location_setting_title'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          t(
            access.isBusy
                ? 'location_changing'
                : settings.locationEnabled
                ? 'location_setting_enabled'
                : 'location_setting_disabled',
          ),
        ),
        value: settings.locationEnabled,
        onChanged: access.isBusy
            ? null
            : (enabled) async {
                final message = await access.changeEnabled(
                  enabled,
                  t('location_auth_reason'),
                );
                if (!context.mounted || message == null) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t(message)),
                    action:
                        message == 'location_permission_settings' ||
                            message == 'location_services_disabled'
                        ? SnackBarAction(
                            label: t('monitoring_open_settings'),
                            onPressed: () async {
                              if (message == 'location_services_disabled') {
                                await access.location.openLocationSettings();
                              } else {
                                await access.location.openSettings();
                              }
                            },
                          )
                        : null,
                  ),
                );
              },
      ),
    );
  }
}
