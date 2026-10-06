abstract class AppConstants {
  static const int sampleRate = 16000; // 16 kHz
  static const int audioChannels = 1;  // Monocanal
  
  static const int windowDurationSeconds = 5; // V5 s
  static const int expectedSampleCount = sampleRate * windowDurationSeconds; // 80 k samples

  // Normalize audio range
  static const double minAudioRange = -1.0;
  static const double maxAudioRange = 1.0;

  static const String classNoViolence = 'no_violence';
  static const String classVerbalViolence = 'verbal_violence';
  static const String classPhysicalViolence = 'physical_violence';

  static const double classificationThreshold = 0.90; // to change
}