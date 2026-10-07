import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:serene/core/constants/app_constants.dart';
import 'package:serene/features/audio_monitoring/domain/entities/audio_window.dart';
import 'package:serene/features/audio_monitoring/domain/entities/inference_result.dart';
import 'package:serene/features/audio_monitoring/presentation/controllers/incident_recording.dart';

const violence = InferenceResult(
  label: 'physical_violence',
  confidence: .95,
  allScores: {'physical_violence': .95},
  isViolenceDetected: true,
);
const normal = InferenceResult(
  label: 'no_violence',
  confidence: .99,
  allScores: {'no_violence': .99},
  isViolenceDetected: false,
);

AudioWindow window(int second) {
  final bytes = BytesBuilder();
  for (var i = second - 4; i <= second; i++) {
    bytes.add(
      Uint8List(AppConstants.sampleRate * 2)
        ..fillRange(0, AppConstants.sampleRate * 2, i),
    );
  }
  return AudioWindow(
    normalizedSamples: Float32List(80000),
    rawPcmBytes: bytes.toBytes(),
    timestamp: DateTime.utc(2026).add(Duration(seconds: second)),
    endSampleIndex: second * AppConstants.sampleRate,
  );
}

void main() {
  test(
    'overlapping windows produce one continuous clip without duplicate PCM',
    () {
      final incident = IncidentRecording(window(5), violence);
      for (var second = 6; second <= 8; second++) {
        incident.append(window(second), violence);
      }
      final bytes = incident.snapshot();
      expect(bytes.length, 8 * AppConstants.sampleRate * 2);
      for (var second = 1; second <= 8; second++) {
        expect(
          bytes.sublist((second - 1) * 32000, second * 32000),
          everyElement(second),
        );
      }
      expect(incident.startedAt, DateTime.utc(2026));
    },
  );

  test(
    'short negative fluctuation keeps the incident open; three quiet seconds close it',
    () {
      final incident = IncidentRecording(window(5), violence);
      incident.append(window(6), normal);
      incident.append(window(7), violence);
      incident.append(window(8), normal);
      incident.append(window(9), null); // silent audio counts as negative
      expect(incident.shouldClose, isFalse);
      incident.append(window(10), normal);
      expect(incident.shouldClose, isTrue);
      expect(incident.length, 10 * 32000);
    },
  );

  test(
    'rejects missing audio instead of silently producing a discontinuous clip',
    () {
      final incident = IncidentRecording(window(5), violence);
      expect(() => incident.append(window(11), violence), throwsStateError);
    },
  );

  test('repeated sample position does not duplicate data', () {
    final incident = IncidentRecording(window(5), violence);
    incident.append(window(5), violence);
    expect(incident.length, 5 * 32000);
  });
}
