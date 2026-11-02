import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'app/controllers/app_settings_controller.dart';
import 'app/routes.dart';
import 'app/service_locator.dart' as di;
import 'core/models/app_settings.dart';
import 'core/services/session_manager.dart';
import 'features/audio_monitoring/presentation/controllers/monitoring_controller.dart';
import 'features/evidence_vault/data/models/evidence_record_model.dart';
import 'features/evidence_vault/domain/repositories/evidence_repository.dart';
import 'features/evidence_vault/presentation/controllers/evidence_controller.dart';
import 'core/constants/hive_constants.dart';
import 'core/services/recorder_leak_guard.dart';
import 'core/services/device_authentication.dart';
import 'app/controllers/monitoring_access_controller.dart';
import 'app/controllers/location_access_controller.dart';
import 'core/services/diagnostics_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startupClock = Stopwatch()..start();

  // Initialize Hive and set up encrypted evidence storage + app settings
  await Hive.initFlutter();

  // Register adapters
  Hive.registerAdapter(EvidenceRecordModelAdapter());
  Hive.registerAdapter(AppSettingsAdapter());

  // Open Hive boxes
  await Hive.openBox<EvidenceRecordModel>(HiveConstants.encryptedEvidenceBox);

  await RecorderLeakGuard.install();

  // Initialize service locator (dependency injection)
  // This will open the appSettings box and create AppSettingsController
  await di.initServiceLocator();

  final monitoringController = di.sl<MonitoringController>();
  DiagnosticsService.instance.monitoringSnapshot =
      monitoringController.collectDiagnostics;

  final sessionManager = SessionManager();
  final deviceAuthentication = DeviceAuthentication();
  final monitoringAccess = MonitoringAccessController(
    settings: di.sl<AppSettingsController>(),
    monitoring: monitoringController,
    authentication: deviceAuthentication,
    session: sessionManager,
  );
  final locationAccess = LocationAccessController(
    settings: di.sl<AppSettingsController>(),
    monitoring: monitoringController,
    authentication: deviceAuthentication,
    session: sessionManager,
  );
  final router = createRouter(sessionManager);

  final bootstrapDuration = startupClock.elapsed;
  DiagnosticsService.instance.recordStartup(bootstrap: bootstrapDuration);
  runApp(
    MultiProvider(
      providers: [
        Provider<DeviceAuthentication>.value(value: deviceAuthentication),
        ChangeNotifierProvider<LocationAccessController>.value(
          value: locationAccess,
        ),
        ChangeNotifierProvider<MonitoringAccessController>.value(
          value: monitoringAccess,
        ),
        ChangeNotifierProvider<AppSettingsController>.value(
          value: di.sl<AppSettingsController>(),
        ),
        ChangeNotifierProvider<EvidenceController>.value(
          value: di.sl<EvidenceController>(),
        ),
        Provider<EvidenceRepository>.value(value: di.sl<EvidenceRepository>()),
        ChangeNotifierProvider<MonitoringController>.value(
          value: monitoringController,
        ),
      ],
      child: SereneApp(router: router, sessionManager: sessionManager),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    DiagnosticsService.instance.recordStartup(
      bootstrap: bootstrapDuration,
      firstFrame: startupClock.elapsed,
    );
    startupClock.stop();
    if (di.sl<AppSettingsController>().monitoringEnabled) {
      unawaited(monitoringController.startMonitoring());
    }
  });
}
