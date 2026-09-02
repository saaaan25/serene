import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/features/audio_monitoring/domain/entities/audio_window.dart';
import 'package:serene/features/audio_monitoring/domain/entities/inference_result.dart';
import 'package:serene/features/audio_monitoring/domain/usecases/process_audio_stream_usecase.dart';
import 'package:serene/features/audio_monitoring/presentation/isolates/audio_processing_isolate.dart';

class MockProcessAudioStreamUseCase extends Mock
    implements ProcessAudioStreamUseCase {}

void main() {
  late MockProcessAudioStreamUseCase mockUseCase;

  setUp(() {
    mockUseCase = MockProcessAudioStreamUseCase();
  });

  group('AudioProcessingIsolate', () {
    test('IncidentDetectionPayload should encapsulate the audio window and inference result correctly', () {
      final window = AudioWindow(
        normalizedSamples: Float32List(80000),
        rawPcmBytes: Uint8List(160000),
        timestamp: DateTime.now(),
      );

      const result = InferenceResult(
        label: 'physical_violence',
        confidence: 0.89,
        allScores: {'physical_violence': 0.89},
        isViolenceDetected: true,
      );

      final payload = IncidentDetectionPayload(window: window, result: result);

      expect(payload.window, equals(window));
      expect(payload.result.label, equals('physical_violence'));
      expect(payload.result.isViolenceDetected, isTrue);
    });

    test('IsolateMessage should encapsulate valid control commands', () {
      const startMsg = IsolateMessage(IsolateCommand.start);
      const stopMsg = IsolateMessage(IsolateCommand.stop);
      const disposeMsg = IsolateMessage(IsolateCommand.dispose);

      expect(startMsg.command, equals(IsolateCommand.start));
      expect(stopMsg.command, equals(IsolateCommand.stop));
      expect(disposeMsg.command, equals(IsolateCommand.dispose));
    });

    test('It should process and filter positive violence events from the stream', () async {
      final controller = StreamController<AudioWindow>();

      when(() => mockUseCase.getAudioStream())
          .thenAnswer((_) => controller.stream);

      final dummyWindow = AudioWindow(
        normalizedSamples: Float32List(100),
        rawPcmBytes: Uint8List(200),
        timestamp: DateTime.now(),
      );

      const violenceResult = InferenceResult(
        label: 'verbal_violence',
        confidence: 0.82,
        allScores: {'verbal_violence': 0.82},
        isViolenceDetected: true,
      );

      when(() => mockUseCase.execute(dummyWindow))
          .thenAnswer((_) async => violenceResult);

      IncidentDetectionPayload? detectedPayload;
      final completer = Completer<void>();

      final streamSubscription = mockUseCase.getAudioStream().listen((window) async {
        final result = await mockUseCase.execute(window);
        if (result.isViolenceDetected) {
          detectedPayload = IncidentDetectionPayload(window: window, result: result);
          completer.complete();
        }
      });

      controller.add(dummyWindow);
      await completer.future;

      expect(detectedPayload, isNotNull);
      expect(detectedPayload!.result.label, equals('verbal_violence'));
      expect(detectedPayload!.result.confidence, equals(0.82));

      await streamSubscription.cancel();
      await controller.close();
    });

    test('It should not emit a payload if the inference results in no_violence', () async {
      final controller = StreamController<AudioWindow>();

      when(() => mockUseCase.getAudioStream())
          .thenAnswer((_) => controller.stream);

      final dummyWindow = AudioWindow(
        normalizedSamples: Float32List(100),
        rawPcmBytes: Uint8List(200),
        timestamp: DateTime.now(),
      );

      const peacefulResult = InferenceResult(
        label: 'no_violence',
        confidence: 0.95,
        allScores: {'no_violence': 0.95},
        isViolenceDetected: false,
      );

      when(() => mockUseCase.execute(dummyWindow))
          .thenAnswer((_) async => peacefulResult);

      bool incidentTriggered = false;

      final streamSubscription = mockUseCase.getAudioStream().listen((window) async {
        final result = await mockUseCase.execute(window);
        if (result.isViolenceDetected) {
          incidentTriggered = true;
        }
      });

      controller.add(dummyWindow);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(incidentTriggered, isFalse);

      await streamSubscription.cancel();
      await controller.close();
    });
  });
}