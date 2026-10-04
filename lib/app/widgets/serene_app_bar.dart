import 'package:flutter/material.dart';

import 'settings_profile_button.dart';

class SereneAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SereneAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return AppBar(
      title: Row(
        children: [
          Icon(Icons.shield, color: primaryColor, size: 24),
          const SizedBox(width: 12),
          Text(
            'serene',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: const [SettingsProfileButton()],
    );
  }
}
