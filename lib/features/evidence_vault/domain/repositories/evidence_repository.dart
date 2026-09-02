import 'dart:typed_data';
import '../entities/evidence_record.dart';

abstract class EvidenceRepository {
  Future<void> saveEncryptedEvidence({
    required Uint8List rawAudioBytes,
    required String predictionLabel,
    required double confidenceScore,
    required Map<String, double> gpsCoordinates,
  });

  Future<List<EvidenceRecord>> getAllEvidenceRecords();

  Future<Uint8List> getDecryptedAudioBytes(EvidenceRecord record);

  Future<void> deleteEvidenceRecord(String id);
}