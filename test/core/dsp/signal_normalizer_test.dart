import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:serene/core/dsp/signal_normalizer.dart';

void main() {
  group('SignalNormalizer - pcm16ToNormalizedFloat32', () {
    test('It should normalize the extreme limits and zero of the PCM 16-bit format', () {
      final byteData = ByteData(6)
        ..setInt16(0, 32767, Endian.little)   // Maximum positive
        ..setInt16(2, -32768, Endian.little)  // Minimum negative
        ..setInt16(4, 0, Endian.little);       // Absolute silence

      final result = SignalNormalizer.pcm16ToNormalizedFloat32(byteData.buffer.asUint8List());

      expect(result.length, 3);
      expect(result[0], closeTo(1.0, 0.0001));
      expect(result[1], closeTo(-1.0, 0.0001));
      expect(result[2], equals(0.0));
    });

    test('It should maintain all samples strictly within the range [-1.0, 1.0]', () {
      final byteData = ByteData(4)
        ..setInt16(0, 16384, Endian.little)
        ..setInt16(2, -16384, Endian.little);

      final result = SignalNormalizer.pcm16ToNormalizedFloat32(byteData.buffer.asUint8List());

      for (final sample in result) {
        expect(sample >= -1.0 && sample <= 1.0, isTrue);
      }
    });
  });

  group('SignalNormalizer - padOrTruncate', () {
    test('It should apply zero-padding when the signal is shorter than the expected window', () {
      final shortSignal = Float32List.fromList([0.2, 0.4]);
      final padded = SignalNormalizer.padOrTruncate(shortSignal, 5);

      expect(padded.length, 5);
      expect(padded[0], closeTo(0.2, 0.0001));
      expect(padded[1], closeTo(0.4, 0.0001));
      expect(padded[2], equals(0.0));
      expect(padded[3], equals(0.0));
      expect(padded[4], equals(0.0));
    });

    test('It should truncate the signal while preserving the initial data if it exceeds the expected window', () {
      final longSignal = Float32List.fromList([0.1, 0.2, 0.3, 0.4, 0.5]);
      final truncated = SignalNormalizer.padOrTruncate(longSignal, 3);

      expect(truncated.length, 3);
      expect(truncated[0], closeTo(0.1, 0.0001));
      expect(truncated[1], closeTo(0.2, 0.0001));
      expect(truncated[2], closeTo(0.3, 0.0001));
    });

    test('It should return the same reference or identical content if the size matches exactly', () {
      final exactSignal = Float32List.fromList([0.1, 0.2, 0.3]);
      final result = SignalNormalizer.padOrTruncate(exactSignal, 3);

      expect(result.length, 3);
      expect(result[0], closeTo(0.1, 0.0001));
      expect(result[1], closeTo(0.2, 0.0001));
      expect(result[2], closeTo(0.3, 0.0001));
    });
  });
}