import '../../../../core/constants/app_constants.dart';

class IncidentCaptureGate {
  IncidentCaptureGate({
    this.minimumInterval = const Duration(
      seconds: AppConstants.windowDurationSeconds,
    ),
  });

  final Duration minimumInterval;
  DateTime? _lastCapturedAt;

  bool canCaptureAt(DateTime timestamp) {
    final lastCapturedAt = _lastCapturedAt;
    return lastCapturedAt == null ||
        timestamp.difference(lastCapturedAt) >= minimumInterval;
  }

  void markCapturedAt(DateTime timestamp) {
    _lastCapturedAt = timestamp;
  }

  void reset() {
    _lastCapturedAt = null;
  }
}
