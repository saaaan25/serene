import 'package:flutter/material.dart';

/// Shared leading icon for preference rows.
class SettingIcon extends StatelessWidget {
  const SettingIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primary.withValues(alpha: 0.15),
      ),
      child: Icon(icon, color: primary, size: 24),
    );
  }
}
