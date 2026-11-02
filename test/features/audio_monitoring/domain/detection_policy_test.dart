import 'package:flutter_test/flutter_test.dart';
import 'package:serene/features/audio_monitoring/domain/detection_policy.dart';
import '../presentation/incident_recording_test.dart' as fixtures;

void main() {
  test(
    'requires two fresh advancing predictions, not skipped or repeated PCM',
    () {
      final policy = DetectionPolicy();
      expect(
        policy.observe(
          endSample: 80000,
          usableSignal: true,
          freshResult: fixtures.violence,
        ),
        DetectionDecision.candidate,
      );
      expect(
        policy.observe(
          endSample: 80000,
          usableSignal: true,
          freshResult: fixtures.violence,
        ),
        DetectionDecision.ignored,
      );
      expect(
        policy.observe(endSample: 96000, usableSignal: true),
        DetectionDecision.candidate,
      );
      expect(
        policy.observe(
          endSample: 112000,
          usableSignal: true,
          freshResult: fixtures.violence,
        ),
        DetectionDecision.confirmed,
      );
    },
  );
  test('negative and degenerate windows break confirmation', () {
    final policy = DetectionPolicy();
    policy.observe(
      endSample: 80000,
      usableSignal: true,
      freshResult: fixtures.violence,
    );
    expect(
      policy.observe(
        endSample: 96000,
        usableSignal: true,
        freshResult: fixtures.normal,
      ),
      DetectionDecision.idle,
    );
    expect(
      policy.observe(
        endSample: 112000,
        usableSignal: true,
        freshResult: fixtures.violence,
      ),
      DetectionDecision.candidate,
    );
    expect(
      policy.observe(endSample: 128000, usableSignal: false),
      DetectionDecision.idle,
    );
  });
  test('confirmation cannot accumulate votes indefinitely', () {
    final policy = DetectionPolicy();
    policy.observe(
      endSample: 80000,
      usableSignal: true,
      freshResult: fixtures.violence,
    );
    expect(
      policy.observe(
        endSample: 192000,
        usableSignal: true,
        freshResult: fixtures.violence,
      ),
      DetectionDecision.candidate,
    );
  });
  test('unclassified audio neither closes immediately nor extends forever', () {
    final policy = DetectionPolicy();
    policy.observe(
      endSample: 80000,
      usableSignal: true,
      freshResult: fixtures.violence,
    );
    policy.observe(
      endSample: 96000,
      usableSignal: true,
      freshResult: fixtures.violence,
    );
    expect(
      policy.observe(endSample: 112000, usableSignal: true),
      DetectionDecision.active,
    );
    expect(
      policy.observe(endSample: 208000, usableSignal: true),
      DetectionDecision.close,
    );
    expect(
      policy.observe(
        endSample: 224000,
        usableSignal: true,
        freshResult: fixtures.violence,
      ),
      DetectionDecision.candidate,
    );
  });
  test('fresh negative closes; reset cannot reuse a previous confirmation', () {
    final policy = DetectionPolicy();
    policy.observe(
      endSample: 80000,
      usableSignal: true,
      freshResult: fixtures.violence,
    );
    policy.observe(
      endSample: 96000,
      usableSignal: true,
      freshResult: fixtures.violence,
    );
    expect(
      policy.observe(
        endSample: 112000,
        usableSignal: true,
        freshResult: fixtures.normal,
      ),
      DetectionDecision.close,
    );
    policy.reset();
    expect(
      policy.observe(
        endSample: 80000,
        usableSignal: true,
        freshResult: fixtures.violence,
      ),
      DetectionDecision.candidate,
    );
  });
}
