import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:serene/app/controllers/app_settings_controller.dart';
import 'package:serene/app/controllers/monitoring_access_controller.dart';
import 'package:serene/core/models/app_settings.dart';
import 'package:serene/core/services/device_authentication.dart';
import 'package:serene/core/services/session_manager.dart';
import 'package:serene/features/audio_monitoring/presentation/controllers/monitoring_controller.dart';

class AuthMock extends Mock implements DeviceAuthentication {}

class MicrophoneMock extends Mock implements MicrophoneAccess {}

class MonitoringMock extends Mock implements MonitoringController {}

void main() {
  late Directory root;
  late AppSettingsController settings;
  late SessionManager session;
  late AuthMock auth;
  late MicrophoneMock microphone;
  late MonitoringMock monitoring;
  late MonitoringAccessController access;
  var active = false;
  var status = MonitoringStatus.paused;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('serene_monitoring_access_');
    Hive.init(root.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
    settings = AppSettingsController(
      box: await Hive.openBox<AppSettings>('appSettings'),
    );
    await settings.setMonitoringEnabled(false);
    session = SessionManager()..markAuthenticated();
    auth = AuthMock();
    microphone = MicrophoneMock();
    monitoring = MonitoringMock();
    active = false;
    status = MonitoringStatus.paused;
    when(() => auth.authenticate(any(), session)).thenAnswer((_) async => true);
    when(
      () => microphone.status(),
    ).thenAnswer((_) async => PermissionStatus.granted);
    when(() => monitoring.isMonitoring).thenAnswer((_) => active);
    when(() => monitoring.status).thenAnswer((_) => status);
    when(() => monitoring.startMonitoring()).thenAnswer((_) async {
      active = true;
      status = MonitoringStatus.active;
    });
    when(() => monitoring.pauseMonitoring()).thenAnswer((_) async {
      active = false;
      status = MonitoringStatus.paused;
    });
    access = MonitoringAccessController(
      settings: settings,
      monitoring: monitoring,
      authentication: auth,
      session: session,
      microphone: microphone,
    );
  });
  tearDown(() async {
    access.dispose();
    session.dispose();
    settings.dispose();
    await Hive.close();
    await root.delete(recursive: true);
  });

  test(
    'cancelled authentication never checks permission or changes monitoring',
    () async {
      when(
        () => auth.authenticate(any(), session),
      ).thenAnswer((_) async => false);
      expect(await access.changeEnabled(true, 'reason'), 'auth_cancelled');
      expect(settings.monitoringEnabled, isFalse);
      verifyNever(() => microphone.status());
      verifyNever(() => monitoring.startMonitoring());
      expect(await access.changeEnabled(false, 'reason'), 'auth_cancelled');
      verifyNever(() => monitoring.pauseMonitoring());
    },
  );

  test(
    'every enable rechecks permission; disable persists across reopening',
    () async {
      expect(await access.changeEnabled(true, 'reason'), isNull);
      expect(active, isTrue);
      expect(settings.monitoringEnabled, isTrue);
      expect(await access.changeEnabled(false, 'reason'), isNull);
      expect(active, isFalse);
      await Hive.close();
      Hive.init(root.path);
      final reopened = AppSettingsController(
        box: await Hive.openBox<AppSettings>('appSettings'),
      );
      expect(reopened.monitoringEnabled, isFalse);
      reopened.dispose();
      // The existing controller uses the closed box; reopen it before continuing.
      settings.dispose();
      settings = AppSettingsController(
        box: Hive.box<AppSettings>('appSettings'),
      );
      access.dispose();
      access = MonitoringAccessController(
        settings: settings,
        monitoring: monitoring,
        authentication: auth,
        session: session,
        microphone: microphone,
      );
      expect(await access.changeEnabled(true, 'reason'), isNull);
      verify(() => microphone.status()).called(2);
      verify(() => auth.authenticate(any(), session)).called(3);
      verifyNever(() => microphone.request());
    },
  );

  test('denied permission is requested and enables only after grant', () async {
    when(
      () => microphone.status(),
    ).thenAnswer((_) async => PermissionStatus.denied);
    when(
      () => microphone.request(),
    ).thenAnswer((_) async => PermissionStatus.granted);
    expect(await access.changeEnabled(true, 'reason'), isNull);
    expect(active, isTrue);
    verify(() => microphone.request()).called(1);
  });

  test('denial leaves monitoring off', () async {
    when(
      () => microphone.status(),
    ).thenAnswer((_) async => PermissionStatus.denied);
    when(
      () => microphone.request(),
    ).thenAnswer((_) async => PermissionStatus.denied);
    expect(
      await access.changeEnabled(true, 'reason'),
      'monitoring_permission_denied',
    );
    expect(settings.monitoringEnabled, isFalse);
    verifyNever(() => monitoring.startMonitoring());
  });

  test(
    'permanently denied permission offers settings without starting',
    () async {
      when(
        () => microphone.status(),
      ).thenAnswer((_) async => PermissionStatus.permanentlyDenied);
      expect(
        await access.changeEnabled(true, 'reason'),
        'monitoring_permission_settings',
      );
      verifyNever(() => microphone.request());
      verifyNever(() => monitoring.startMonitoring());
      expect(settings.monitoringEnabled, isFalse);
    },
  );

  test('failed model initialization does not persist enabled state', () async {
    when(() => monitoring.startMonitoring()).thenAnswer((_) async {
      status = MonitoringStatus.error;
    });
    expect(
      await access.changeEnabled(true, 'reason'),
      'monitoring_change_failed',
    );
    expect(settings.monitoringEnabled, isFalse);
  });

  test('concurrent changes cannot produce overlapping auth prompts', () async {
    final pending = Completer<bool>();
    when(
      () => auth.authenticate(any(), session),
    ).thenAnswer((_) => pending.future);
    final first = access.changeEnabled(true, 'reason');
    expect(access.isBusy, isTrue);
    expect(
      await access.changeEnabled(false, 'reason'),
      'monitoring_change_busy',
    );
    pending.complete(false);
    await first;
    expect(access.isBusy, isFalse);
    verify(() => auth.authenticate(any(), session)).called(1);
  });
}
