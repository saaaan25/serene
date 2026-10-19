import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/evidence_policy.dart';
import '../../domain/entities/audio_window.dart';
import '../../domain/entities/inference_result.dart';

/// Accumulates only the new PCM samples from overlapping inference windows.
class IncidentRecording {
  final String id;
  final DateTime startedAt;
  final Duration maximumDuration;
  final BytesBuilder _audio = BytesBuilder(copy: true);
  String label;
  double confidence;
  Map<String, double>? coordinates;
  int _lastEndSample;
  int _quietSamples = 0;
  int _checkpointSamples = 0;

  IncidentRecording(
    AudioWindow window,
    InferenceResult result, {
    this.maximumDuration = EvidencePolicy.maximumIncidentDuration,
    int? afterSample,
  }) : id = const Uuid().v4(),
       startedAt = window.timestamp.subtract(
         Duration(
           microseconds:
               _initialBytes(window, afterSample) *
               1000000 ~/
               (AppConstants.sampleRate * 2),
         ),
       ),
       label = result.label,
       confidence = result.confidence,
       _lastEndSample =
           window.endSampleIndex ?? window.rawPcmBytes.length ~/ 2 {
    if (maximumDuration.inSeconds < AppConstants.windowDurationSeconds) {
      throw ArgumentError(
        'An incident must accommodate the initial audio window',
      );
    }
    final initialBytes = _initialBytes(window, afterSample);
    _audio.add(
      Uint8List.sublistView(
        window.rawPcmBytes,
        window.rawPcmBytes.length - initialBytes,
      ),
    );
  }

  static int _initialBytes(AudioWindow window, int? afterSample) {
    if (afterSample == null || window.endSampleIndex == null) {
      return window.rawPcmBytes.length;
    }
    final samples = window.endSampleIndex! - afterSample;
    if (samples <= 0 || samples * 2 > window.rawPcmBytes.length) {
      throw StateError('Audio gap detected while continuing an incident');
    }
    return samples * 2;
  }

  int get length => _audio.length;
  int get endSampleIndex => _lastEndSample;
  bool get durationLimitReached =>
      length >=
      maximumDuration.inMicroseconds * AppConstants.sampleRate * 2 ~/ 1000000;
  Uint8List snapshot() => _audio.toBytes();
  void discard() {
    final bytes = _audio.takeBytes();
    bytes.fillRange(0, bytes.length, 0);
  }

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
    final remaining =
        (maximumDuration.inMicroseconds *
                AppConstants.sampleRate *
                2 ~/
                1000000 -
            length) ~/
        2;
    final retainedSamples = newSamples < remaining ? newSamples : remaining;
    if (retainedSamples <= 0) return;
    final offset = window.rawPcmBytes.length - newSamples * 2;
    _audio.add(
      Uint8List.sublistView(
        window.rawPcmBytes,
        offset,
        offset + retainedSamples * 2,
      ),
    );
    _lastEndSample += retainedSamples;
    _checkpointSamples += retainedSamples;
    if (result?.isViolenceDetected ?? false) {
      _quietSamples = 0;
      if (result!.confidence > confidence) {
        label = result.label;
        confidence = result.confidence;
      }
    } else {
      _quietSamples += retainedSamples;
    }
  }
}
