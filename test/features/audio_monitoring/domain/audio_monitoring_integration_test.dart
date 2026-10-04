import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/core/errors/failures.dart';
import 'package:serene/features/audio_monitoring/domain/entities/audio_window.dart';
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

  test('microphone permission checks are delegated to the repository', () async {
    when(() => mockRepository.hasMicrophonePermission())
        .thenAnswer((_) async => true);

    expect(await useCase.hasMicrophonePermission(), isTrue);
    verify(() => mockRepository.hasMicrophonePermission()).called(1);
  });

  test('audio stream startup is awaited and returns repository windows',
      () async {
    final windows = Stream<AudioWindow>.value(
      AudioWindow(
        normalizedSamples: Float32List(80000),
        rawPcmBytes: Uint8List(160000),
        timestamp: DateTime.now(),
      ),
    );
    when(() => mockRepository.startMicrophoneStream())
        .thenAnswer((_) async => windows);

    expect(await useCase.getAudioStream(), same(windows));
    verify(() => mockRepository.startMicrophoneStream()).called(1);
  });

  test('microphone startup errors are propagated to the caller', () async {
    const failure = AudioProcessingFailure('Audio hardware unavailable');
    when(() => mockRepository.startMicrophoneStream())
        .thenAnswer((_) async => throw failure);

    await expectLater(
      useCase.getAudioStream(),
      throwsA(same(failure)),
    );
  });
}
