import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:serene/core/dsp/signal_quality.dart';

void main() {
  for (final value in [0.0, 1 / 32768, .3, 1.0, -1.0]) {
    test('rejects constant PCM $value including DC offset', () {
      expect(
        SignalQuality.analyze(
          Float32List.fromList(List.filled(80000, value)),
        ).isUsable,
        isFalse,
      );
    });
  }
  test('rejects invalid, empty, and quantization-floor noise', () {
    for (final samples in [
      Float32List(0),
      Float32List.fromList([double.nan]),
      Float32List.fromList([double.infinity]),
      Float32List.fromList([1.01]),
      Float32List.fromList(
        List.generate(80000, (i) => i.isEven ? 1 / 32768 : -1 / 32768),
      ),
    ]) {
      expect(SignalQuality.analyze(samples).isUsable, isFalse);
    }
  });
  test(
    'retains quiet varying audio and a brief impact without requiring speech',
    () {
      final quiet = Float32List.fromList(
        List.generate(80000, (i) => .0002 * sin(2 * pi * 200 * i / 16000)),
      );
      final impact = Float32List(80000)..[1000] = .05;
      expect(SignalQuality.analyze(quiet).isUsable, isTrue);
      expect(SignalQuality.analyze(impact).isUsable, isTrue);
    },
  );
}
