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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive and set up encrypted evidence storage + app settings
  await Hive.initFlutter();

  // Register adapters
  Hive.registerAdapter(EvidenceRecordModelAdapter());
  Hive.registerAdapter(AppSettingsAdapter());

  // Open Hive boxes
  await Hive.openBox<EvidenceRecordModel>(HiveConstants.encryptedEvidenceBox);

  // Initialize service locator (dependency injection)
  // This will open the appSettings box and create AppSettingsController
  await di.initServiceLocator();

  final monitoringController = di.sl<MonitoringController>();

  final sessionManager = SessionManager();
  final router = createRouter(sessionManager);

  runApp(
    MultiProvider(
      providers: [
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
    unawaited(monitoringController.startMonitoring());
  });
}
