import 'dart:typed_data';

class AudioWindow {
  final Float32List normalizedSamples; // Tensor [1, 80000]
  final Uint8List rawPcmBytes; // PCM 16-bit little-endian bytes [160000]
  final DateTime timestamp;

  /// Exclusive PCM sample position in this recording session.
  final int? endSampleIndex;

  const AudioWindow({
    required this.normalizedSamples,
    required this.rawPcmBytes,
    required this.timestamp,
    this.endSampleIndex,
  });
}
