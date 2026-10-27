import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/controllers/app_settings_controller.dart';
import '../../../../core/localization/app_translations.dart';
import '../../../../core/services/device_authentication.dart';
import '../../../../core/services/session_manager.dart';

/// Observes the actual route, including links and retained shell branches.
/// The repository screen is only mounted after a fresh authentication.
class VaultAccessGate extends StatelessWidget {
  const VaultAccessGate({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final route = GoRouter.of(context).routeInformationProvider;
    return ListenableBuilder(
      listenable: route,
      builder: (context, _) => _VaultBoundary(
        active: route.value.uri.path == '/vault',
        builder: builder,
      ),
    );
  }
}

class _VaultBoundary extends StatefulWidget {
  const _VaultBoundary({required this.active, required this.builder});
  final bool active;
  final WidgetBuilder builder;

  @override
  State<_VaultBoundary> createState() => _VaultBoundaryState();
}

class _VaultBoundaryState extends State<_VaultBoundary> {
  bool _authenticated = false;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) _scheduleAuthentication();
  }

  @override
  void didUpdateWidget(covariant _VaultBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    _generation++;
    _authenticated = false;
    _busy = false;
    if (widget.active) _scheduleAuthentication();
  }

  void _scheduleAuthentication() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _authenticate();
    });
  }

  Future<void> _authenticate() async {
    if (_busy || !widget.active) return;
    final generation = _generation;
    setState(() => _busy = true);
    final locale = context.read<AppSettingsController>().locale;
    final accepted = await context.read<DeviceAuthentication>().authenticate(
      AppTranslations.tr('vault_access_reason', locale),
      context.read<SessionManager>(),
    );
    if (!mounted || generation != _generation || !widget.active) return;
    setState(() {
      _authenticated = accepted;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    if (_authenticated) return widget.builder(context);
    final locale = context.watch<AppSettingsController>().locale;
    String t(String key) => AppTranslations.tr(key, locale);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              Text(t('vault_private_access_desc'), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (_busy)
                const CircularProgressIndicator()
              else
                FilledButton.icon(
                  onPressed: _authenticate,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(t('vault_unlock')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
