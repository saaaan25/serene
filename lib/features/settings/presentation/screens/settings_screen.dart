import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/controllers/app_settings_controller.dart';
import '../../../../core/localization/app_translations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final settingsController = context.watch<AppSettingsController>();
    final currentLocale = settingsController.locale; // 'es' or 'en'

    String t(String key) => AppTranslations.tr(key, currentLocale);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.shield, color: primaryColor, size: 24),
            const SizedBox(width: 12),
            Text(
              'serene',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Settings Title
                Text(
                  t('settings_title'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                ),

                const SizedBox(height: 16),

                // Settings Items
                _SettingItem(
                  icon: Icons.lock,
                  title: t('vault_password'),
                  subtitle: t('vault_password_sub'),
                  onTap: () {},
                ),

                const SizedBox(height: 12),

                _SettingItem(
                  icon: Icons.fingerprint,
                  title: t('biometrics'),
                  subtitle: t('biometrics_sub'),
                  onTap: () {},
                ),

                const SizedBox(height: 12),

                _SettingItem(
                  icon: Icons.notifications,
                  title: t('notifications'),
                  subtitle: t('notifications_sub'),
                  onTap: () {},
                ),

                const SizedBox(height: 12),

                _SettingItem(
                  icon: Icons.language,
                  title: t('app_language'),
                  subtitle: currentLocale == 'es' ? t('spanish') : t('english'),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(t('language_dialog_title')),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              title: Text(t('spanish')),
                              trailing: currentLocale == 'es'
                                  ? Icon(Icons.check, color: primaryColor)
                                  : null,
                              onTap: () {
                                settingsController.setLocale('es');
                                Navigator.pop(context);
                              },
                            ),
                            ListTile(
                              title: Text(t('english')),
                              trailing: currentLocale == 'en'
                                  ? Icon(Icons.check, color: primaryColor)
                                  : null,
                              onTap: () {
                                settingsController.setLocale('en');
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Display Settings
                Text(
                  t('display_title'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            settingsController.isDarkMode
                                ? Icons.dark_mode
                                : Icons.light_mode,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('dark_mode'),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              Text(
                                settingsController.isDarkMode
                                    ? t('enabled')
                                    : t('disabled'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Switch(
                        value: settingsController.isDarkMode,
                        onChanged: (value) {
                          settingsController.setDarkMode(value);
                        },
                        activeThumbColor: primaryColor,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: primaryColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: primaryColor.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}