import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
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

    test(
      'pauseMonitoring should not modify the state if monitoring was not active',
      () async {
        await controller.pauseMonitoring();
        expect(controller.status, equals(MonitoringStatus.idle));
        expect(controller.isMonitoring, isFalse);
      },
    );

    test('startMonitoring reports a denied microphone permission', () async {
      when(
        () => mockProcessUseCase.hasMicrophonePermission(),
      ).thenAnswer((_) async => false);

      await controller.startMonitoring();

      expect(controller.status, equals(MonitoringStatus.error));
      expect(controller.isMonitoring, isFalse);
      expect(controller.errorMessage, contains('Microphone permission'));
      verify(() => mockProcessUseCase.hasMicrophonePermission()).called(1);
    });

    test(
      'leaving the foreground cancels a pending monitoring startup',
      () async {
        final permissionCheck = Completer<bool>();
        when(
          () => mockProcessUseCase.hasMicrophonePermission(),
        ).thenAnswer((_) => permissionCheck.future);

        final start = controller.startMonitoring();
        await Future<void>.delayed(Duration.zero);
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        permissionCheck.complete(true);

        await start;
        await Future<void>.delayed(Duration.zero);

        expect(controller.status, MonitoringStatus.paused);
        verifyNever(() => mockProcessUseCase.getAudioStream());
      },
    );

    test(
      'background/resume does not start an idle or explicitly paused monitor',
      () async {
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        expect(controller.status, MonitoringStatus.idle);
        verifyNever(() => mockProcessUseCase.hasMicrophonePermission());
      },
    );
  });

  group('Evidence Persistence', () {
    test(
      'It should call SaveEncryptedEvidenceUseCase when a violence incident is confirmed',
      () async {
        when(
          () => mockSaveUseCase.call(any()),
        ).thenAnswer((_) async => Future.value());

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
      },
    );
  });
}
