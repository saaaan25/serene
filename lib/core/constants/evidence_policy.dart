/// Operational defaults, independent of the classifier's decision threshold.
abstract class EvidencePolicy {
  static const maximumIncidentDuration = Duration(minutes: 5);
  static const minimumFreeBytes = 100 * 1024 * 1024;
  static const retainedUntilManualDeletion = true;
  static const automaticallyDeleteEvidence = false;
}
