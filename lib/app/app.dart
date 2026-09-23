import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/controllers/app_settings_controller.dart';
import 'routes.dart';

/// Root application widget
/// Configures Material theme with dynamic dark/light mode, router, and providers
class SereneApp extends StatelessWidget {
  const SereneApp({super.key});

  static ThemeData _buildTheme(bool isDarkMode) {
    if (isDarkMode) {
      return _darkTheme;
    } else {
      return _lightTheme;
    }
  }

  // Dark theme colors according to the design system
  static final ThemeData _darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF060e20), // Surface Base
    colorScheme: ColorScheme.dark(
      primary: const Color(0xFFa1d1fe), // Primary Blue
      secondary: const Color(0xFFf1d6ff), // Secondary Lavender
      tertiary: const Color(0xFFffc1d6), // Tertiary Pink
      background: const Color(0xFF060e20), // Surface Base
      surface: const Color(0xFF1f2b49), // Surface Bright
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onTertiary: Colors.white,
      onBackground: const Color(0xFFdee5ff), // On-Surface
      onSurface: const Color(0xFFdee5ff), // On-Surface
      error: const Color(0xFFffc1d6),
      onError: Colors.white,
    ),
    textTheme: _darkTextTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1f2b49),
      foregroundColor: Color(0xFFdee5ff),
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFa1d1fe),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      fillColor: const Color(0xFF1f2b49),
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Color(0xFF40485d)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Color(0xFFa1d1fe), width: 2),
      ),
    ),
  );

  // Light theme colors
  static final ThemeData _lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFfaf8ff), // Inverse-Surface
    colorScheme: ColorScheme.light(
      primary: const Color(0xFF5b8ac0), // Adjusted for light mode
      secondary: const Color(0xFFd4a5f0), // Adjusted for light mode
      tertiary: const Color(0xFFd98dc3), // Adjusted for light mode
      background: const Color(0xFFfaf8ff),
      surface: const Color(0xFFf5f3f9),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onTertiary: Colors.white,
      onBackground: const Color(0xFF192540),
      onSurface: const Color(0xFF192540),
      error: const Color(0xFFb3261e),
      onError: Colors.white,
    ),
    textTheme: _lightTextTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFf5f3f9),
      foregroundColor: Color(0xFF192540),
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF5b8ac0),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      fillColor: Colors.white,
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Color(0xFFe0e0e0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Color(0xFF5b8ac0), width: 2),
      ),
    ),
  );

  static const TextTheme _darkTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 56,
      fontWeight: FontWeight.w700,
      color: Color(0xFFdee5ff),
    ),
    displayMedium: TextStyle(
      fontSize: 44,
      fontWeight: FontWeight.w700,
      color: Color(0xFFdee5ff),
    ),
    displaySmall: TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w600,
      color: Color(0xFFdee5ff),
    ),
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      color: Color(0xFFdee5ff),
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      color: Color(0xFFdee5ff),
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: Color(0xFFdee5ff),
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: Color(0xFFdee5ff),
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: Color(0xFFdee5ff),
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: Color(0xFFdee5ff),
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Color(0xFFdee5ff),
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(0xFFdee5ff),
    ),
    labelSmall: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: Color(0xFFdee5ff),
    ),
  );

  static const TextTheme _lightTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 56,
      fontWeight: FontWeight.w700,
      color: Color(0xFF192540),
    ),
    displayMedium: TextStyle(
      fontSize: 44,
      fontWeight: FontWeight.w700,
      color: Color(0xFF192540),
    ),
    displaySmall: TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w600,
      color: Color(0xFF192540),
    ),
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      color: Color(0xFF192540),
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      color: Color(0xFF192540),
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: Color(0xFF192540),
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: Color(0xFF192540),
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: Color(0xFF192540),
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: Color(0xFF192540),
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Color(0xFF192540),
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(0xFF192540),
    ),
    labelSmall: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: Color(0xFF192540),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSettingsController>(
      builder: (context, settingsController, _) {
        return MaterialApp.router(
          title: 'serene',
          theme: _buildTheme(settingsController.isDarkMode),
          routerConfig: goRouter,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

