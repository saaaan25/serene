import 'dart:math' as math;
import 'dart:typed_data';

/// Rejects invalid/degenerate PCM, not speech or particular sound categories.
class SignalQuality {
  const SignalQuality({required this.centeredRms, required this.isFinite});

  // One PCM16 quantization step. This is a numerical floor, not a calibrated
  // ambient-noise or voice-activity threshold.
  static const minimumCenteredRms = 1 / 32768;
  final double centeredRms;
  final bool isFinite;

  bool get isUsable =>
      isFinite && centeredRms.isFinite && centeredRms > minimumCenteredRms;

  factory SignalQuality.analyze(Float32List samples) {
    if (samples.isEmpty) {
      return const SignalQuality(centeredRms: 0, isFinite: false);
    }
    var mean = 0.0;
    var m2 = 0.0;
    var count = 0;
    for (final sample in samples) {
      if (!sample.isFinite || sample < -1 || sample > 1) {
        return const SignalQuality(centeredRms: 0, isFinite: false);
      }
      count++;
      final delta = sample - mean;
      mean += delta / count;
      m2 += delta * (sample - mean);
    }
    return SignalQuality(
      centeredRms: math.sqrt(math.max(0, m2 / count)),
      isFinite: true,
    );
  }
}
