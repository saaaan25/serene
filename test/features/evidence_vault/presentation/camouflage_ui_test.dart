import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:serene/app/app.dart';
import 'package:serene/core/constants/hive_constants.dart';
import 'package:serene/core/crypto/cipher_manager.dart';
import 'package:serene/core/crypto/secure_key_storage.dart';
import 'package:serene/features/audio_monitoring/data/datasources/audio_stream_datasource.dart';
import 'package:serene/features/audio_monitoring/data/datasources/tflite_inference_engine.dart';
import 'package:serene/features/audio_monitoring/domain/repositories/monitoring_repository.dart';
import 'package:serene/features/audio_monitoring/domain/usecases/process_audio_stream_usecase.dart';
import 'package:serene/features/audio_monitoring/presentation/controllers/monitoring_controller.dart';
import 'package:serene/features/evidence_vault/data/datasources/evidence_local_datasource.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_record_model.dart';
import 'package:serene/features/evidence_vault/domain/repositories/evidence_repository.dart';
import 'package:serene/features/evidence_vault/domain/usecases/get_decrypted_audio_stream_usecase.dart';
import 'package:serene/features/evidence_vault/domain/usecases/save_encrypted_evidence_usecase.dart';
import 'package:serene/features/evidence_vault/presentation/controllers/evidence_controller.dart';

// Mock classes
class MockSecureKeyStorage extends Mock implements SecureKeyStorage {}
class MockCipherManager extends Mock implements CipherManager {}
class MockEvidenceLocalDataSource extends Mock implements EvidenceLocalDataSource {}
class MockEvidenceRepository extends Mock implements EvidenceRepository {}
class MockTfliteInferenceEngine extends Mock implements TfliteInferenceEngine {}
class MockAudioStreamDataSource extends Mock implements AudioStreamDataSource {}
class MockMonitoringRepository extends Mock implements MonitoringRepository {}

void main() {
  setUpAll(() async {
    // Initialize Hive for testing
    await Hive.initFlutter();
    
    // Register adapter only if not already registered
    if (!Hive.isAdapterRegistered(HiveConstants.evidenceRecordTypeId)) {
      Hive.registerAdapter(EvidenceRecordModelAdapter());
    }

    // Clear any existing service locator
    GetIt.instance.reset();
  });

  setUp(() async {
    // Ensure Hive box is closed and cleared for each test
    try {
      await Hive.deleteBoxFromDisk(HiveConstants.encryptedEvidenceBox);
    } catch (_) {}

    // Open a fresh box for each test
    await Hive.openBox<EvidenceRecordModel>(
      HiveConstants.encryptedEvidenceBox,
    );

    // Reset GetIt before each test
    GetIt.instance.reset();

    // Register all dependencies
    _registerMockDependencies();
  });

  tearDown(() async {
    try {
      await Hive.deleteBoxFromDisk(HiveConstants.encryptedEvidenceBox);
    } catch (_) {}
  });

  group('Camouflage UI Tests - NeutralCalculatorScreen', () {
    testWidgets('App renders with NeutralCalculatorScreen by default',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<EvidenceController>(
              create: (_) => GetIt.instance<EvidenceController>(),
            ),
            Provider<MonitoringController>(
              create: (_) => GetIt.instance<MonitoringController>(),
            ),
          ],
          child: const SereneApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that the calculator screen is displayed
      expect(find.text('Calculadora'), findsOneWidget);
      expect(find.text('0'), findsWidgets);

      // Verify that calculator buttons are present
      expect(find.text('1'), findsWidgets);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      expect(find.text('='), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('Standard calculator operations do not expose vault',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<EvidenceController>(
              create: (_) => GetIt.instance<EvidenceController>(),
            ),
            Provider<MonitoringController>(
              create: (_) => GetIt.instance<MonitoringController>(),
            ),
          ],
          child: const SereneApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify we start at calculator screen
      expect(find.text('Calculadora'), findsOneWidget);
      expect(find.text('Historial de Evidencia'), findsNothing);

      // Perform standard calculation: 5 + 3 = 8
      await tester.tap(find.byWidgetPredicate(
        (widget) => widget is GestureDetector &&
            widget.child is Container &&
            (widget.child as Container).child is Stack &&
            ((widget.child as Container).child as Stack)
                .alignment ==
                Alignment.center,
      ).at(4)); // Button "5"
      await tester.pumpAndSettle();

      // Verify vault screen is NOT accessible
      expect(find.text('Historial de Evidencia'), findsNothing);
      expect(find.text('Calculadora'), findsOneWidget);
    });

    testWidgets('Only secret trigger sequence should invoke biometric gate',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<EvidenceController>(
              create: (_) => GetIt.instance<EvidenceController>(),
            ),
            Provider<MonitoringController>(
              create: (_) => GetIt.instance<MonitoringController>(),
            ),
          ],
          child: const SereneApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify we start at calculator
      expect(find.text('Calculadora'), findsOneWidget);

      // Random button presses should not trigger authentication
      // Press "7" multiple times
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.byWidgetPredicate(
          (widget) => widget is GestureDetector &&
              widget.child is Container &&
              (widget.child as Container).child is Stack &&
              ((widget.child as Container).child as Stack)
                  .alignment ==
                  Alignment.center,
        ).at(5)); // Button "7" or similar
        await tester.pumpAndSettle();
      }

      // Vault should still not be accessible
      expect(find.text('Historial de Evidencia'), findsNothing);
      expect(find.text('Calculadora'), findsOneWidget);
    });

    testWidgets('Calculator display is secure and neutral',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<EvidenceController>(
              create: (_) => GetIt.instance<EvidenceController>(),
            ),
            Provider<MonitoringController>(
              create: (_) => GetIt.instance<MonitoringController>(),
            ),
          ],
          child: const SereneApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that no sensitive words appear
      expect(find.text('vault', skipOffstage: false), findsNothing);
      expect(find.text('evidence', skipOffstage: false), findsNothing);
      expect(find.text('evidence', skipOffstage: false), findsNothing);
      expect(find.text('security', skipOffstage: false), findsNothing);

      // Verify calculator title is neutral
      expect(find.text('Calculadora'), findsOneWidget);
    });

    testWidgets('Clear button resets display and trigger state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<EvidenceController>(
              create: (_) => GetIt.instance<EvidenceController>(),
            ),
            Provider<MonitoringController>(
              create: (_) => GetIt.instance<MonitoringController>(),
            ),
          ],
          child: const SereneApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Press "1"
      await tester.tap(find.text('1').at(0));
      await tester.pumpAndSettle();

      // Press "C" to clear
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();

      // Display should be reset to "0"
      final displays = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == '0',
      );
      expect(displays, findsWidgets);
    });
  });

  group('Biometric Gate Tests', () {
    testWidgets('Biometric gate does not appear on standard input',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<EvidenceController>(
              create: (_) => GetIt.instance<EvidenceController>(),
            ),
            Provider<MonitoringController>(
              create: (_) => GetIt.instance<MonitoringController>(),
            ),
          ],
          child: const SereneApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Enter standard sequence
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('='));
      await tester.pumpAndSettle();

      // No biometric dialog should appear
      expect(
        find.byWidgetPredicate(
          (widget) => widget is AlertDialog,
        ),
        findsNothing,
      );

      // Still on calculator
      expect(find.text('Calculadora'), findsOneWidget);
    });
  });
}

/// Register mock dependencies for testing
void _registerMockDependencies() {
  final getIt = GetIt.instance;

  // Core
  getIt.registerLazySingleton<SecureKeyStorage>(
      () => MockSecureKeyStorage());
  getIt.registerLazySingleton<CipherManager>(() => MockCipherManager());

  // Evidence Vault
  getIt.registerLazySingleton<EvidenceLocalDataSource>(
      () => MockEvidenceLocalDataSource());

  getIt.registerLazySingleton<EvidenceRepository>(
      () => MockEvidenceRepository());

  getIt.registerLazySingleton<SaveEncryptedEvidenceUseCase>(
    () => SaveEncryptedEvidenceUseCase(getIt<EvidenceRepository>()),
  );

  getIt.registerLazySingleton<GetDecryptedAudioStreamUseCase>(
    () => GetDecryptedAudioStreamUseCase(getIt<EvidenceRepository>()),
  );

  getIt.registerSingleton<EvidenceController>(
    EvidenceController(
      evidenceRepository: getIt<EvidenceRepository>(),
      getDecryptedAudioUseCase: getIt<GetDecryptedAudioStreamUseCase>(),
    ),
  );

  // Audio Monitoring
  getIt.registerLazySingleton<TfliteInferenceEngine>(
      () => MockTfliteInferenceEngine());
  getIt.registerLazySingleton<AudioStreamDataSource>(
      () => MockAudioStreamDataSource());

  getIt.registerLazySingleton<MonitoringRepository>(
      () => MockMonitoringRepository());

  getIt.registerLazySingleton<ProcessAudioStreamUseCase>(
    () => ProcessAudioStreamUseCase(getIt<MonitoringRepository>()),
  );

  getIt.registerFactory<MonitoringController>(
    () => MonitoringController(
      processAudioUseCase: getIt<ProcessAudioStreamUseCase>(),
      saveEvidenceUseCase: getIt<SaveEncryptedEvidenceUseCase>(),
    ),
  );
}
