import 'package:flutter_test/flutter_test.dart';
import 'package:serene/features/audio_monitoring/presentation/controllers/incident_capture_gate.dart';

void main() {
  group('IncidentCaptureGate', () {
    test('allows the first detection and throttles overlapping windows', () {
      final gate = IncidentCaptureGate();
      final first = DateTime(2026, 10, 3, 12);

      expect(gate.canCaptureAt(first), isTrue);
      gate.markCapturedAt(first);

      expect(gate.canCaptureAt(first.add(const Duration(seconds: 1))), isFalse);
      expect(gate.canCaptureAt(first.add(const Duration(seconds: 4))), isFalse);
      expect(gate.canCaptureAt(first.add(const Duration(seconds: 5))), isTrue);
    });

    test('reset allows capturing immediately in a new monitoring session', () {
      final gate = IncidentCaptureGate();
      final first = DateTime(2026, 10, 3, 12);
      gate.markCapturedAt(first);

      gate.reset();

      expect(gate.canCaptureAt(first), isTrue);
    });
  });
}
