import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/constants/hive_constants.dart';
import '../../domain/entities/evidence_record.dart';

part 'evidence_record_model.g.dart';

@HiveType(typeId: HiveConstants.evidenceRecordTypeId)
class EvidenceRecordModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime timestamp;

  @HiveField(2)
  final String predictionLabel;

  @HiveField(3)
  final double confidenceScore;

  @HiveField(4)
  final Map<String, double> gpsCoordinates;

  @HiveField(5)
  final Uint8List encryptedAudioBlob;

  @HiveField(6)
  final Uint8List ivBytes;

  @HiveField(7)
  final Uint8List authTag;

  @HiveField(8)
  final String integrityHash;

  EvidenceRecordModel({
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

  factory EvidenceRecordModel.fromEntity(EvidenceRecord entity) {
    return EvidenceRecordModel(
      id: entity.id,
      timestamp: entity.timestamp,
      predictionLabel: entity.predictionLabel,
      confidenceScore: entity.confidenceScore,
      gpsCoordinates: entity.gpsCoordinates,
      encryptedAudioBlob: entity.encryptedAudioBlob,
      ivBytes: entity.ivBytes,
      authTag: entity.authTag,
      integrityHash: entity.integrityHash,
    );
  }

  EvidenceRecord toEntity() {
    return EvidenceRecord(
      id: id,
      timestamp: timestamp,
      predictionLabel: predictionLabel,
      confidenceScore: confidenceScore,
      gpsCoordinates: Map<String, double>.from(gpsCoordinates),
      encryptedAudioBlob: encryptedAudioBlob,
      ivBytes: ivBytes,
      authTag: authTag,
      integrityHash: integrityHash,
    );
  }
}