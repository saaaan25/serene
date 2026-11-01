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

    final sessionManager = context.read<SessionManager>();
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

      sessionManager.beginAuthenticationPrompt();
      late final bool authenticated;
      try {
        authenticated = await _localAuth.authenticate(
          localizedReason: AppTranslations.tr('auth_reason', currentLocale),
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
      } finally {
        sessionManager.endAuthenticationPrompt();
      }

      if (authenticated && mounted) {
        sessionManager.markAuthenticated();
        context.go('/home');
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
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shield_rounded,
                          color: primaryColor,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'serene',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: onSurfaceColor,
                                letterSpacing: -0.4,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: primaryColor.withValues(alpha: 0.12),
                                  border: Border.all(
                                    color: primaryColor.withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Icon(
                                  Icons.fingerprint_rounded,
                                  size: 62,
                                  color: primaryColor,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                t('auth_welcome_title'),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.7,
                                      height: 1.2,
                                      color: onSurfaceColor,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                t('auth_welcome_subtitle'),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: onSurfaceColor.withValues(
                                        alpha: 0.7,
                                      ),
                                      height: 1.5,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: FilledButton.icon(
                                  onPressed: _isAuthenticating
                                      ? null
                                      : _attemptBiometricAuth,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  icon: _isAuthenticating
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: onSurfaceColor,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.fingerprint_rounded,
                                          size: 22,
                                        ),
                                  label: Text(t('auth_button')),
                                ),
                              ),
                              // Reserve room so cancellation does not move the action.
                              const SizedBox(height: 12),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 64,
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: _errorMessageKey == null
                                      ? const SizedBox.shrink()
                                      : Container(
                                          key: ValueKey(_errorMessageKey),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error
                                                .withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.info_outline_rounded,
                                                size: 18,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  t(_errorMessageKey!),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.error,
                                                        height: 1.4,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
