import 'dart:typed_data';

class EvidenceRecord {
  final String id;
  final DateTime timestamp;
  final String predictionLabel;
  final double confidenceScore;
  final Map<String, double> gpsCoordinates;
  final Uint8List encryptedAudioBlob;
  final Uint8List ivBytes;
  final Uint8List authTag;
  final String integrityHash;

  const EvidenceRecord({
    required this.id,
    required this.timestamp,
    required this.predictionLabel,
    required this.confidenceScore,
    required this.gpsCoordinates,
    required this.encryptedAudioBlob,
    required this.ivBytes,
    required this.authTag,
    required this.integrityHash,
  });
}