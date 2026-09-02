import 'dart:typed_data';
import '../constants/app_constants.dart';

class SignalNormalizer {
  /// Converts PCM 16-bit signed little-endian audio bytes to normalized Float32 values in the range [-1.0, 1.0]
  static Float32List pcm16ToNormalizedFloat32(Uint8List pcmBuffer) {
    final byteData = ByteData.sublistView(pcmBuffer);
    final sampleCount = pcmBuffer.lengthInBytes ~/ 2;
    final floatList = Float32List(sampleCount);

    for (int i = 0; i < sampleCount; i++) {
      // PCM 16-bit Signed Little Endian
      final sample = byteData.getInt16(i * 2, Endian.little);
      // Linear mapping by dividing by 32768.0
      final normalized = (sample / 32768.0).clamp(
        AppConstants.minAudioRange,
        AppConstants.maxAudioRange,
      );
      floatList[i] = normalized;
    }

    return floatList;
  }

  /// Adjusts the size of the window to AppConstants.expectedSampleCount using padding or truncation
  static Float32List padOrTruncate(Float32List signal, int targetLength) {
    if (signal.length == targetLength) {
      return signal;
    }

    final output = Float32List(targetLength);
    if (signal.length > targetLength) {
      output.setRange(0, targetLength, signal.sublist(0, targetLength));
    } else {
      output.setRange(0, signal.length, signal);
    }
    return output;
  }
}