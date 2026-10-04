import '../entities/audio_window.dart';

abstract class MonitoringRepository {
  Future<bool> hasMicrophonePermission();
  Future<Stream<AudioWindow>> startMicrophoneStream();
  Future<void> stopMicrophoneStream();
}