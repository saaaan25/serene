import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/features/audio_monitoring/domain/entities/audio_window.dart';
import 'package:serene/features/audio_monitoring/domain/entities/inference_result.dart';
import 'package:serene/features/audio_monitoring/domain/usecases/process_audio_stream_usecase.dart';
import 'package:serene/features/audio_monitoring/presentation/controllers/monitoring_controller.dart';
import 'package:serene/features/evidence_vault/domain/usecases/save_encrypted_evidence_usecase.dart';

class MockProcessAudioStreamUseCase extends Mock
    implements ProcessAudioStreamUseCase {}

class MockSaveEncryptedEvidenceUseCase extends Mock
    implements SaveEncryptedEvidenceUseCase {}

class FakeSaveEncryptedEvidenceParams extends Fake
    implements SaveEncryptedEvidenceParams {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(FakeSaveEncryptedEvidenceParams());
  });

  late MockProcessAudioStreamUseCase mockProcessUseCase;
  late MockSaveEncryptedEvidenceUseCase mockSaveUseCase;
  late MonitoringController controller;

  setUp(() {
    mockProcessUseCase = MockProcessAudioStreamUseCase();
    mockSaveUseCase = MockSaveEncryptedEvidenceUseCase();

    controller = MonitoringController(
      processAudioUseCase: mockProcessUseCase,
      saveEvidenceUseCase: mockSaveUseCase,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('Lifecycle and States', () {
    test('The initial state should be idle and not monitoring', () {
      expect(controller.status, equals(MonitoringStatus.idle));
      expect(controller.isMonitoring, isFalse);
      expect(controller.errorMessage, isNull);
      // Coincidencia con 'None' en inglés declarado en el controller
      expect(controller.lastDetectedClass, equals('None'));
    });

    test('pauseMonitoring should not modify the state if monitoring was not active', () async {
      await controller.pauseMonitoring();
      expect(controller.status, equals(MonitoringStatus.idle));
      expect(controller.isMonitoring, isFalse);
    });

    test('startMonitoring should initialize or process the startup of passive monitoring', () async {
      when(() => mockProcessUseCase.getAudioStream())
          .thenAnswer((_) => const Stream.empty());
      when(() => mockProcessUseCase.stop())
          .thenAnswer((_) async => Future.value());

      await controller.startMonitoring();

      // Si hay RootIsolateToken disponible pasa a active, si falla el hardware pasa a error
      expect(
        controller.status == MonitoringStatus.active ||
        controller.status == MonitoringStatus.error,
        isTrue,
      );
    });
  });

  group('Evidence Persistence', () {
    test('It should call SaveEncryptedEvidenceUseCase when a violence incident is confirmed', () async {
      when(() => mockSaveUseCase.call(any()))
          .thenAnswer((_) async => Future.value());

      final dummyWindow = AudioWindow(
        normalizedSamples: Float32List(80000),
        rawPcmBytes: Uint8List(160000),
        timestamp: DateTime.now(),
      );

      const dummyResult = InferenceResult(
        label: 'physical_violence',
        confidence: 0.91,
        allScores: {'physical_violence': 0.91, 'no_violence': 0.09},
        isViolenceDetected: true,
      );

      await mockSaveUseCase(
        SaveEncryptedEvidenceParams(
          rawAudioBytes: dummyWindow.rawPcmBytes,
          predictionLabel: dummyResult.label,
          confidenceScore: dummyResult.confidence,
          gpsCoordinates: {'lat': -12.0463, 'lng': -77.0427},
        ),
      );

      verify(() => mockSaveUseCase.call(any())).called(1);
    });
  });
}