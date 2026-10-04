import '../entities/audio_window.dart';
import '../repositories/monitoring_repository.dart';

class ProcessAudioStreamUseCase {
  final MonitoringRepository repository;

  ProcessAudioStreamUseCase(this.repository);

  Future<bool> hasMicrophonePermission() {
    return repository.hasMicrophonePermission();
  }

  Future<Stream<AudioWindow>> getAudioStream() {
    return repository.startMicrophoneStream();
  }

  Future<void> stop() async {
    await repository.stopMicrophoneStream();
  }
}