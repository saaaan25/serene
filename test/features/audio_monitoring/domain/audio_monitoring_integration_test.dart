import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/core/errors/failures.dart';
import 'package:serene/features/audio_monitoring/domain/entities/audio_window.dart';
import 'package:serene/features/audio_monitoring/domain/entities/inference_result.dart';
import 'package:serene/features/audio_monitoring/domain/repositories/monitoring_repository.dart';
import 'package:serene/features/audio_monitoring/domain/usecases/process_audio_stream_usecase.dart';

class MockMonitoringRepository extends Mock implements MonitoringRepository {}

void main() {
  late MockMonitoringRepository mockRepository;
  late ProcessAudioStreamUseCase useCase;

  setUp(() {
    mockRepository = MockMonitoringRepository();
    useCase = ProcessAudioStreamUseCase(mockRepository);
  });

  test('ProcessAudioStreamUseCase should delegate the audio window to the repository without altering tensors', () async {
    final window = AudioWindow(
      normalizedSamples: Float32List(80000),
      rawPcmBytes: Uint8List(160000),
      timestamp: DateTime.now(),
    );

    const expectedResult = InferenceResult(
      label: 'physical_violence',
      confidence: 0.91,
      allScores: {
        'no_violence': 0.04,
        'physical_violence': 0.91,
        'verbal_violence': 0.05,
      },
      isViolenceDetected: true,
    );

    when(() => mockRepository.runInference(window.normalizedSamples))
        .thenAnswer((_) async => expectedResult);

    final result = await useCase.execute(window);

    expect(result.label, equals('physical_violence'));
    expect(result.confidence, equals(0.91));
    expect(result.isViolenceDetected, isTrue);
    verify(() => mockRepository.runInference(window.normalizedSamples)).called(1);
  });

  test('It should propagate AudioProcessingFailure if the audio hardware emits an error', () async {
    when(() => mockRepository.startMicrophoneStream()).thenAnswer(
      (_) => Stream.error(const AudioProcessingFailure('Error in audio hardware')),
    );

    expect(
      useCase.getAudioStream(),
      emitsError(isA<AudioProcessingFailure>()),
    );
  });
}