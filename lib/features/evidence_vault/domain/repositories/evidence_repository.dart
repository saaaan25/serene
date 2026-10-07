import 'dart:typed_data';
import '../entities/evidence_record.dart';
import '../entities/vault_stats.dart';

abstract class EvidenceRepository {
  Future<void> saveEncryptedEvidence({
    required Uint8List rawAudioBytes,
    required String predictionLabel,
    required double confidenceScore,
    required Map<String, double> gpsCoordinates,
    String? evidenceId,
    DateTime? startedAt,
  });

  Future<List<EvidenceRecord>> getAllEvidenceRecords();

  Future<Uint8List> getDecryptedAudioBytes(EvidenceRecord record);

  Future<void> deleteEvidenceRecord(String id);

  /// Obtiene las métricas de cantidad de registros y bytes reales cifrados
  Future<VaultStats> getVaultStats();
}
