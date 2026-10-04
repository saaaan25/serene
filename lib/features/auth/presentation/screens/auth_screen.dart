import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../../../app/controllers/app_settings_controller.dart';
import '../../../../core/localization/app_translations.dart';
import '../../../../core/services/session_manager.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isAuthenticating = false;
  String? _errorMessageKey;

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
      _errorMessageKey = null;
    });

    final settingsController = context.read<AppSettingsController>();
    final currentLocale = settingsController.locale;

    try {
      final isSupported =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();

      if (!isSupported) {
        if (mounted) {
          setState(() {
            _errorMessageKey = 'auth_not_supported';
            _isAuthenticating = false;
          });
        }
        return;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: AppTranslations.tr('auth_reason', currentLocale),
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (authenticated && mounted) {
        _onAuthSuccess();
      } else if (mounted) {
        setState(() {
          _errorMessageKey = 'auth_cancelled';
          _isAuthenticating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessageKey = 'auth_cancelled';
          _isAuthenticating = false;
        });
      }
    }
  }

  void _onAuthSuccess() {
    context.read<SessionManager>().markAuthenticated();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onSurfaceColor = Theme.of(context).colorScheme.onSurface;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    final settingsController = context.watch<AppSettingsController>();
    final currentLocale = settingsController.locale;
    String t(String key) => AppTranslations.tr(key, currentLocale);

    return Scaffold(
      backgroundColor: surfaceColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield, color: primaryColor, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'serene',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: onSurfaceColor,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 40),
              GestureDetector(
                onTap: _attemptBiometricAuth,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(70),
                      ),
                    ),
                    Icon(Icons.fingerprint, size: 90, color: primaryColor),
                  ],
                ),
              ),
              const SizedBox(height: 32.0),
              Text(
                t('auth_welcome_title'),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: onSurfaceColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8.0),
              Text(
                t('auth_welcome_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: onSurfaceColor.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32.0),

              if (_errorMessageKey != null)
                Text(
                  t(_errorMessageKey!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),

              const SizedBox(height: 24.0),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _isAuthenticating ? null : _attemptBiometricAuth,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28.0),
                    ),
                  ),
                  child: _isAuthenticating
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(t('auth_button')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
