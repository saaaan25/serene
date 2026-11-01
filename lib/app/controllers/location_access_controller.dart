import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/services/device_authentication.dart';
import '../../core/services/session_manager.dart';
import '../../features/audio_monitoring/presentation/controllers/monitoring_controller.dart';
import 'app_settings_controller.dart';

class LocationAccess {
  Future<LocationPermission> status() => Geolocator.checkPermission();
  Future<LocationPermission> request() => Geolocator.requestPermission();
  Future<bool> serviceEnabled() => Geolocator.isLocationServiceEnabled();
  Future<bool> openSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

class LocationAccessController extends ChangeNotifier {
  LocationAccessController({
    required this.settings,
    required this.monitoring,
    required this.authentication,
    required this.session,
    LocationAccess? location,
  }) : location = location ?? LocationAccess();

  final AppSettingsController settings;
  final MonitoringController monitoring;
  final DeviceAuthentication authentication;
  final SessionManager session;
  final LocationAccess location;
  bool _busy = false;
  bool get isBusy => _busy;

  Future<String?> _ensurePermission() async {
    if (!await location.serviceEnabled()) return 'location_services_disabled';
    var permission = await location.status();
    if (permission == LocationPermission.denied) {
      permission = await location.request();
    }
    if (permission == LocationPermission.deniedForever) {
      return 'location_permission_settings';
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return 'location_permission_denied';
    }
    return null;
  }

  Future<String?> changeEnabled(bool enabled, String reason) async {
    if (_busy) return 'location_change_busy';
    _busy = true;
    notifyListeners();
    final previous = settings.locationEnabled;
    try {
      if (!await authentication.authenticate(reason, session)) {
        return 'auth_cancelled';
      }
      if (enabled) {
        final message = await _ensurePermission();
        if (message != null) return message;
      }
      if (session.checkSessionTimeout()) return 'auth_cancelled';
      await monitoring.setLocationEnabled(enabled);
      await settings.setLocationEnabled(enabled);
      return null;
    } catch (_) {
      try {
        await monitoring.setLocationEnabled(previous);
      } catch (error) {
        debugPrint('Could not restore location setting: $error');
      }
      return 'location_change_failed';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<String?> restorePermission() async {
    if (_busy || !settings.locationEnabled) return null;
    _busy = true;
    notifyListeners();
    try {
      final message = await _ensurePermission();
      await monitoring.setLocationEnabled(message == null);
      return message;
    } catch (_) {
      return 'location_change_failed';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
