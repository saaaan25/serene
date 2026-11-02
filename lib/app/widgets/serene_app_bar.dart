import 'package:flutter/material.dart';

import 'settings_profile_button.dart';
import 'serene_logo.dart';

class SereneAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SereneAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Align(
        alignment: Alignment.centerLeft,
        child: SereneLogo.horizontal(),
      ),
      actions: const [SettingsProfileButton()],
    );
  }
}
