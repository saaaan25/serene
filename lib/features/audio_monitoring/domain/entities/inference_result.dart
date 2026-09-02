class InferenceResult {
  final String label; // 'no_violence', 'physical_violence', 'verbal_violence'
  final double confidence; // Probability [0.0 - 1.0]
  final Map<String, double> allScores;
  final bool isViolenceDetected; // true if it exceeds the threshold and is not 'no_violence'

  const InferenceResult({
    required this.label,
    required this.confidence,
    required this.allScores,
    required this.isViolenceDetected,
  });
}