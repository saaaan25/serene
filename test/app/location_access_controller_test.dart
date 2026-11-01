import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/app/controllers/app_settings_controller.dart';
import 'package:serene/app/controllers/location_access_controller.dart';
import 'package:serene/core/models/app_settings.dart';
import 'package:serene/core/services/device_authentication.dart';
import 'package:serene/core/services/session_manager.dart';
import 'package:serene/features/audio_monitoring/presentation/controllers/monitoring_controller.dart';

class AuthMock extends Mock implements DeviceAuthentication {}

class LocationMock extends Mock implements LocationAccess {}

class MonitoringMock extends Mock implements MonitoringController {}

void main() {
  late Directory root;
  late AppSettingsController settings;
  late SessionManager session;
  late AuthMock auth;
  late LocationMock location;
  late MonitoringMock monitoring;
  late LocationAccessController access;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('serene_location_');
    Hive.init(root.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
    settings = AppSettingsController(
      box: await Hive.openBox<AppSettings>('appSettings'),
    );
    session = SessionManager()..markAuthenticated();
    auth = AuthMock();
    location = LocationMock();
    monitoring = MonitoringMock();
    when(() => auth.authenticate(any(), session)).thenAnswer((_) async => true);
    when(() => location.serviceEnabled()).thenAnswer((_) async => true);
    when(
      () => location.status(),
    ).thenAnswer((_) async => LocationPermission.whileInUse);
    when(() => monitoring.setLocationEnabled(any())).thenAnswer((_) async {});
    access = LocationAccessController(
      settings: settings,
      monitoring: monitoring,
      authentication: auth,
      session: session,
      location: location,
    );
  });
  tearDown(() async {
    access.dispose();
    settings.dispose();
    session.dispose();
    await Hive.close();
    await root.delete(recursive: true);
  });
  test('cancelled authentication never requests or enables location', () async {
    when(
      () => auth.authenticate(any(), session),
    ).thenAnswer((_) async => false);
    expect(await access.changeEnabled(true, 'reason'), 'auth_cancelled');
    verifyNever(() => location.status());
    verifyNever(() => monitoring.setLocationEnabled(any()));
  });
  test(
    'requests OS permission and persists opt in across reopening and mic changes',
    () async {
      when(
        () => location.status(),
      ).thenAnswer((_) async => LocationPermission.denied);
      when(
        () => location.request(),
      ).thenAnswer((_) async => LocationPermission.whileInUse);
      expect(await access.changeEnabled(true, 'reason'), isNull);
      verify(() => location.request()).called(1);
      verify(() => monitoring.setLocationEnabled(true)).called(1);
      await settings.setMonitoringEnabled(false);
      await Hive.close();
      final reopened = AppSettingsController(
        box: await Hive.openBox<AppSettings>('appSettings'),
      );
      expect(reopened.locationEnabled, isTrue);
      expect(reopened.monitoringEnabled, isFalse);
      reopened.dispose();
    },
  );
  test('denied permission leaves location disabled', () async {
    when(
      () => location.status(),
    ).thenAnswer((_) async => LocationPermission.denied);
    when(
      () => location.request(),
    ).thenAnswer((_) async => LocationPermission.denied);
    expect(
      await access.changeEnabled(true, 'reason'),
      'location_permission_denied',
    );
    expect(settings.locationEnabled, isFalse);
    verifyNever(() => monitoring.setLocationEnabled(true));
  });
  test(
    'permanent denial directs to settings without another request',
    () async {
      when(
        () => location.status(),
      ).thenAnswer((_) async => LocationPermission.deniedForever);
      expect(
        await access.changeEnabled(true, 'reason'),
        'location_permission_settings',
      );
      verifyNever(() => location.request());
    },
  );
  test('device GPS off has a separate message', () async {
    when(() => location.serviceEnabled()).thenAnswer((_) async => false);
    expect(
      await access.changeEnabled(true, 'reason'),
      'location_services_disabled',
    );
    verifyNever(() => location.request());
  });
  test('disable does not request permission', () async {
    await settings.setLocationEnabled(true);
    expect(await access.changeEnabled(false, 'reason'), isNull);
    expect(settings.locationEnabled, isFalse);
    verify(() => monitoring.setLocationEnabled(false)).called(1);
    verifyNever(() => location.status());
  });
  test('home restores missing permission only for opted in location', () async {
    expect(await access.restorePermission(), isNull);
    verifyNever(() => location.status());
    await settings.setLocationEnabled(true);
    when(
      () => location.status(),
    ).thenAnswer((_) async => LocationPermission.denied);
    when(
      () => location.request(),
    ).thenAnswer((_) async => LocationPermission.whileInUse);
    expect(await access.restorePermission(), isNull);
    verify(() => location.request()).called(1);
    verifyNever(() => auth.authenticate(any(), session));
  });
}
