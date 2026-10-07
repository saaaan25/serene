import 'dart:typed_data';
import '../repositories/evidence_repository.dart';

class SaveEncryptedEvidenceParams {
  final Uint8List rawAudioBytes;
  final String predictionLabel;
  final double confidenceScore;
  final Map<String, double> gpsCoordinates;
  final String? evidenceId;
  final DateTime? startedAt;

  SaveEncryptedEvidenceParams({
    required this.rawAudioBytes,
    required this.predictionLabel,
    required this.confidenceScore,
    required this.gpsCoordinates,
    this.evidenceId,
    this.startedAt,
  });
}

class SaveEncryptedEvidenceUseCase {
  final EvidenceRepository repository;

  SaveEncryptedEvidenceUseCase(this.repository);

  Future<void> call(SaveEncryptedEvidenceParams params) async {
    await repository.saveEncryptedEvidence(
      rawAudioBytes: params.rawAudioBytes,
      predictionLabel: params.predictionLabel,
      confidenceScore: params.confidenceScore,
      gpsCoordinates: params.gpsCoordinates,
      evidenceId: params.evidenceId,
      startedAt: params.startedAt,
    );
  }
}
