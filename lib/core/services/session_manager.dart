import 'dart:async';
import 'package:flutter/foundation.dart';

class SessionManager extends ChangeNotifier {
  static const Duration timeoutDuration = Duration(minutes: 5);
  DateTime _lastActivity = DateTime.now();
  bool _isAuthenticated = false;
  Timer? _timeoutTimer;
  int _activeAuthenticationPrompts = 0;

  bool get isAuthenticated => _isAuthenticated;
  bool get isAuthenticationPromptActive => _activeAuthenticationPrompts > 0;

  void beginAuthenticationPrompt() {
    _activeAuthenticationPrompts++;
  }

  void endAuthenticationPrompt() {
    if (_activeAuthenticationPrompts == 0) return;
    _activeAuthenticationPrompts--;
  }

  void markAuthenticated() {
    _isAuthenticated = true;
    _lastActivity = DateTime.now();
    _scheduleTimeout();
    notifyListeners();
  }

  void recordUserActivity() {
    if (!_isAuthenticated) return;
    if (checkSessionTimeout()) return;

    _lastActivity = DateTime.now();
    _scheduleTimeout();
  }

  /// Verifica si la sesión caducó por inactividad
  bool checkSessionTimeout() {
    if (!_isAuthenticated) return true;
    final difference = DateTime.now().difference(_lastActivity);
    if (difference >= timeoutDuration) {
      _expireSession();
      return true;
    }
    return false;
  }

  void logout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    if (!_isAuthenticated) return;
    _isAuthenticated = false;
    notifyListeners();
  }

  void _scheduleTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(timeoutDuration, checkSessionTimeout);
  }

  void _expireSession() {
    if (!_isAuthenticated) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _isAuthenticated = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }
}
