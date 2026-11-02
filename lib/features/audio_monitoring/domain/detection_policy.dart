import '../../../core/constants/app_constants.dart';
import 'entities/inference_result.dart';

enum DetectionDecision { idle, candidate, confirmed, active, close, ignored }

/// Counts only fresh model invocations on advancing audio sample positions.
/// Overlapping windows are correlated: two votes are temporal confirmation,
/// not independent evidence or a guarantee of accuracy.
class DetectionPolicy {
  int? _lastObservedSample;
  int? _candidateAt;
  int? _lastPositiveAt;
  bool _confirmed = false;

  int? get candidateAt => _candidateAt;

  DetectionDecision observe({
    required int endSample,
    required bool usableSignal,
    InferenceResult? freshResult,
  }) {
    if (_lastObservedSample != null && endSample <= _lastObservedSample!) {
      return DetectionDecision.ignored;
    }
    _lastObservedSample = endSample;
    if (!usableSignal) return _clearEvent();

    final positive = freshResult?.isViolenceDetected;
    if (_confirmed) {
      if (positive == false) return _clearEvent();
      if (positive == true) _lastPositiveAt = endSample;
      if (endSample - _lastPositiveAt! >
          AppConstants.maximumUnclassifiedSamples) {
        return _clearEvent();
      }
      return DetectionDecision.active;
    }

    if (positive == false ||
        (_candidateAt != null &&
            endSample - _candidateAt! >
                AppConstants.confirmationTimeoutSamples)) {
      _candidateAt = null;
    }
    if (positive == true) {
      if (_candidateAt == null) {
        _candidateAt = endSample;
      } else if (endSample - _candidateAt! >=
          AppConstants.confirmationSeparationSamples) {
        _confirmed = true;
        _lastPositiveAt = endSample;
        return DetectionDecision.confirmed;
      }
    }
    return _candidateAt == null
        ? DetectionDecision.idle
        : DetectionDecision.candidate;
  }

  DetectionDecision _clearEvent() {
    final decision = _confirmed
        ? DetectionDecision.close
        : DetectionDecision.idle;
    _candidateAt = null;
    _lastPositiveAt = null;
    _confirmed = false;
    return decision;
  }

  void reset() {
    _clearEvent();
    _lastObservedSample = null;
  }
}
