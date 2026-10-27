import 'package:local_auth/local_auth.dart';

import 'session_manager.dart';

/// Brackets native prompts so app privacy lifecycle events do not log out the user.
class DeviceAuthentication {
  DeviceAuthentication({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;
  bool _busy = false;

  Future<bool> authenticate(String reason, SessionManager session) async {
    if (_busy || session.checkSessionTimeout()) return false;
    _busy = true;
    session.beginAuthenticationPrompt();
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      final accepted = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (!accepted || session.checkSessionTimeout()) return false;
      session.recordUserActivity();
      return true;
    } catch (_) {
      return false;
    } finally {
      session.endAuthenticationPrompt();
      _busy = false;
    }
  }
}
