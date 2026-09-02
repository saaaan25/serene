import 'dart:typed_data';
import '../entities/evidence_record.dart';
import '../repositories/evidence_repository.dart';

class GetDecryptedAudioStreamUseCase {
  final EvidenceRepository repository;

  GetDecryptedAudioStreamUseCase(this.repository);

  Future<Uint8List> call(EvidenceRecord record) async {
    return await repository.getDecryptedAudioBytes(record);
  }
}