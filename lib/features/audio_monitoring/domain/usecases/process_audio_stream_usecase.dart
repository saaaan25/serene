import '../entities/audio_window.dart';
import '../entities/inference_result.dart';
import '../repositories/monitoring_repository.dart';

class ProcessAudioStreamUseCase {
  final MonitoringRepository repository;

  ProcessAudioStreamUseCase(this.repository);

  Future<InferenceResult> execute(AudioWindow window) async {
    return await repository.runInference(window.normalizedSamples);
  }

  Stream<AudioWindow> getAudioStream() {
    return repository.startMicrophoneStream();
  }

  Future<void> stop() async {
    await repository.stopMicrophoneStream();
  }
}