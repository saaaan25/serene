import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../controllers/app_settings_controller.dart';
import '../../core/localization/app_translations.dart';

class SettingsProfileButton extends StatelessWidget {
  const SettingsProfileButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (GoRouterState.of(context).uri.path == '/settings') {
      return const SizedBox.shrink();
    }

    final primaryColor = Theme.of(context).colorScheme.primary;
    final currentLocale = context.watch<AppSettingsController>().locale;

    return Tooltip(
      message: AppTranslations.tr('nav_settings', currentLocale),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () => context.go('/settings'),
            borderRadius: BorderRadius.circular(20),
            child: const CircleAvatar(child: Icon(Icons.person)),
          ),
        ),
      ),
    );
  }
}
