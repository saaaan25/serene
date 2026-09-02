import 'dart:typed_data';
import '../entities/audio_window.dart';
import '../entities/inference_result.dart';

abstract class MonitoringRepository {
  Stream<AudioWindow> startMicrophoneStream();
  Future<void> stopMicrophoneStream();
  Future<InferenceResult> runInference(Float32List audioWindow);
  Future<void> initializeEngine();
  void disposeEngine();
}