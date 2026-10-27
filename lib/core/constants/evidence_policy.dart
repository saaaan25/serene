/// Operational defaults, independent of the classifier's decision threshold.
abstract class EvidencePolicy {
  // No product duration limit. Device memory and free space remain finite.
  static const Duration? maximumIncidentDuration = null;
  static const minimumFreeBytes = 100 * 1024 * 1024;
  static const retainedUntilManualDeletion = true;
  static const automaticallyDeleteEvidence = false;
}
