import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../../../app/controllers/app_settings_controller.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptBiometricAuth();
    });
  }

  Future<void> _attemptBiometricAuth() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      bool isDeviceSupported = await _localAuth.canCheckBiometrics;

      if (!isDeviceSupported) {
        if (mounted) {
          setState(() {
            _errorMessage =
                'Biometría no disponible.\nIntenta de nuevo o contacta soporte.';
            _isAuthenticating = false;
          });
        }
        return;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Acceder a serene',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (authenticated && mounted) {
        context.go('/home');
      } else if (mounted) {
        setState(() {
          _errorMessage = 'Autenticación cancelada. Intenta de nuevo.';
          _isAuthenticating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: ${e.toString().substring(0, 50)}...';
          _isAuthenticating = false;
        });
      }
    }
  }

  void _showThemeSettings() {
    final settingsController = context.read<AppSettingsController>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Preferencias'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Modo Oscuro'),
                Switch(
                  value: settingsController.isDarkMode,
                  onChanged: (value) {
                    settingsController.setDarkMode(value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Idioma'),
                DropdownButton<String>(
                  value: settingsController.locale,
                  items: const [
                    DropdownMenuItem(
                      value: 'es',
                      child: Text('Español'),
                    ),
                    DropdownMenuItem(
                      value: 'en',
                      child: Text('English'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      settingsController.setLocale(value);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: surfaceColor,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24.0, vertical: 32.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shield,
                              color: primaryColor,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'serene',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: onSurfaceColor,
                                  ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: _showThemeSettings,
                          icon: Icon(
                            Icons.settings,
                            color: primaryColor,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                primaryColor.withValues(alpha: 0.15),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Main content
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Biometric icon
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(80),
                              ),
                            ),
                            Icon(
                              Icons.fingerprint,
                              size: 100,
                              color: primaryColor,
                            ),
                          ],
                        ),

                        const SizedBox(height: 48.0),

                        // Welcome message
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            children: [
                              Text(
                                'Bienvenido de vuelta',
                                style: Theme.of(context)
                                    .textTheme
                                    .displaySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: onSurfaceColor,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12.0),
                              Text(
                                'Re-enter the circle of protection.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: onSurfaceColor.withValues(
                                          alpha: 0.7),
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Error message
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                  if (_errorMessage != null)
                    const SizedBox(height: 24.0),

                  // Authenticate button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        onPressed: _isAuthenticating
                            ? null
                            : _attemptBiometricAuth,
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          disabledBackgroundColor:
                              primaryColor.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28.0),
                          ),
                        ),
                        child: _isAuthenticating
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                'AUTENTICAR',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 48.0),

                  // Footer
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Text(
                      '© 2026 serene\nALL RIGHTS RESERVED.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: onSurfaceColor.withValues(alpha: 0.5),
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
