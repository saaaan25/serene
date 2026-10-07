import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/audio_window.dart';
import '../../domain/entities/inference_result.dart';

/// Accumulates only the new PCM samples from overlapping inference windows.
class IncidentRecording {
  final String id;
  final DateTime startedAt;
  final BytesBuilder _audio = BytesBuilder(copy: true);
  String label;
  double confidence;
  Map<String, double>? coordinates;
  int _lastEndSample;
  int _quietSamples = 0;
  int _checkpointSamples = 0;

  IncidentRecording(AudioWindow window, InferenceResult result)
    : id = const Uuid().v4(),
      startedAt = window.timestamp.subtract(
        Duration(
          microseconds:
              window.rawPcmBytes.length *
              1000000 ~/
              (AppConstants.sampleRate * 2),
        ),
      ),
      label = result.label,
      confidence = result.confidence,
      _lastEndSample = window.endSampleIndex ?? window.rawPcmBytes.length ~/ 2 {
    _audio.add(window.rawPcmBytes);
  }

  int get length => _audio.length;
  Uint8List snapshot() => _audio.toBytes();

  /// Ends after three seconds of negative decisions, bridging short fluctuations.
  bool get shouldClose => _quietSamples >= AppConstants.sampleRate * 3;
  bool get checkpointDue => _checkpointSamples >= AppConstants.sampleRate * 15;
  void markCheckpoint() => _checkpointSamples = 0;

  void append(AudioWindow window, InferenceResult? result) {
    final end =
        window.endSampleIndex ?? _lastEndSample + AppConstants.sampleRate;
    final newSamples = end - _lastEndSample;
    if (newSamples <= 0) return;
    if (newSamples * 2 > window.rawPcmBytes.length) {
      throw StateError('Audio gap detected while recording an incident');
    }
    _audio.add(
      Uint8List.sublistView(
        window.rawPcmBytes,
        window.rawPcmBytes.length - newSamples * 2,
      ),
    );
    _lastEndSample = end;
    _checkpointSamples += newSamples;
    if (result?.isViolenceDetected ?? false) {
      _quietSamples = 0;
      if (result!.confidence > confidence) {
        label = result.label;
        confidence = result.confidence;
      }
    } else {
      _quietSamples += newSamples;
    }
  }
}
