import 'dart:typed_data';

class EvidenceRecord {
  /// Opaque persistence reference; the logical ID remains encrypted.
  final String storageId;
  final String id;
  final DateTime timestamp;
  final String predictionLabel;
  final double confidenceScore;
  final Map<String, double> gpsCoordinates;
  final Uint8List encryptedAudioBlob;
  final Uint8List ivBytes;
  final Uint8List authTag;
  final String integrityHash;
  final String incidentId;
  final int schemaVersion;
  final String appVersion;
  final String modelHash;
  final String audioFormat;
  final DateTime? savedAt;
  final String previousVersionId;
  final Uint8List? metadataCiphertext;
  final Uint8List? metadataNonce;
  final Uint8List? metadataTag;

  bool get hasAuthenticatedMetadata => schemaVersion == 2;
  String get logicalIncidentId => incidentId.isEmpty ? id : incidentId;

  const EvidenceRecord({
    this.storageId = '',
    required this.id,
    required this.timestamp,
    required this.predictionLabel,
    required this.confidenceScore,
    required this.gpsCoordinates,
    required this.encryptedAudioBlob,
    required this.ivBytes,
    required this.authTag,
    required this.integrityHash,
    this.incidentId = '',
    this.schemaVersion = 1,
    this.appVersion = '',
    this.modelHash = '',
    this.audioFormat = '',
    this.savedAt,
    this.previousVersionId = '',
    this.metadataCiphertext,
    this.metadataNonce,
    this.metadataTag,
  });
}
