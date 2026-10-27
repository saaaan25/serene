import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/device_authentication.dart';
import '../../core/services/session_manager.dart';
import '../../features/audio_monitoring/presentation/controllers/monitoring_controller.dart';
import 'app_settings_controller.dart';

class MicrophoneAccess {
  Future<PermissionStatus> status() => Permission.microphone.status;
  Future<PermissionStatus> request() => Permission.microphone.request();
  Future<bool> openSettings() => openAppSettings();
}

class MonitoringAccessController extends ChangeNotifier {
  MonitoringAccessController({
    required this.settings,
    required this.monitoring,
    required this.authentication,
    required this.session,
    MicrophoneAccess? microphone,
  }) : microphone = microphone ?? MicrophoneAccess();

  final AppSettingsController settings;
  final MonitoringController monitoring;
  final DeviceAuthentication authentication;
  final SessionManager session;
  final MicrophoneAccess microphone;
  bool _busy = false;
  bool get isBusy => _busy;

  /// Null means success; otherwise returns a localized message key.
  Future<String?> changeEnabled(bool enabled, String reason) async {
    if (_busy) return 'monitoring_change_busy';
    _busy = true;
    notifyListeners();
    try {
      if (!await authentication.authenticate(reason, session)) {
        return 'auth_cancelled';
      }
      if (enabled) {
        var permission = await microphone.status();
        if (permission.isPermanentlyDenied || permission.isRestricted) {
          return 'monitoring_permission_settings';
        }
        if (!permission.isGranted) permission = await microphone.request();
        if (!permission.isGranted) {
          return permission.isPermanentlyDenied || permission.isRestricted
              ? 'monitoring_permission_settings'
              : 'monitoring_permission_denied';
        }
        if (session.checkSessionTimeout()) return 'auth_cancelled';
        await monitoring.startMonitoring();
        if (!monitoring.isMonitoring) return 'monitoring_change_failed';
        try {
          await settings.setMonitoringEnabled(true);
        } catch (_) {
          await monitoring.pauseMonitoring();
          rethrow;
        }
      } else {
        await monitoring.pauseMonitoring();
        if (monitoring.status == MonitoringStatus.error) {
          return 'monitoring_change_failed';
        }
        await settings.setMonitoringEnabled(false);
      }
      return null;
    } catch (_) {
      return 'monitoring_change_failed';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
