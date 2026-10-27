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
  @HiveField(9, defaultValue: '')
  final String incidentId;
  @HiveField(10, defaultValue: 1)
  final int schemaVersion;
  @HiveField(11, defaultValue: '')
  final String appVersion;
  @HiveField(12, defaultValue: '')
  final String modelHash;
  @HiveField(13, defaultValue: '')
  final String audioFormat;
  @HiveField(14)
  final DateTime? savedAt;
  @HiveField(15, defaultValue: '')
  final String previousVersionId;
  @HiveField(16)
  final Uint8List? metadataCiphertext;
  @HiveField(17)
  final Uint8List? metadataNonce;
  @HiveField(18)
  final Uint8List? metadataTag;

  bool get hasAuthenticatedMetadata => schemaVersion == 2;
  String get logicalIncidentId => incidentId.isEmpty ? id : incidentId;

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

  factory EvidenceRecordModel.fromEntity(EvidenceRecord entity) {
    return EvidenceRecordModel(
      id: entity.storageId.isEmpty ? entity.id : entity.storageId,
      timestamp: entity.timestamp,
      predictionLabel: entity.predictionLabel,
      confidenceScore: entity.confidenceScore,
      gpsCoordinates: entity.gpsCoordinates,
      encryptedAudioBlob: entity.encryptedAudioBlob,
      ivBytes: entity.ivBytes,
      authTag: entity.authTag,
      integrityHash: entity.integrityHash,
      incidentId: entity.incidentId,
      schemaVersion: entity.schemaVersion,
      appVersion: entity.appVersion,
      modelHash: entity.modelHash,
      audioFormat: entity.audioFormat,
      savedAt: entity.savedAt,
      previousVersionId: entity.previousVersionId,
      metadataCiphertext: entity.metadataCiphertext,
      metadataNonce: entity.metadataNonce,
      metadataTag: entity.metadataTag,
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
      incidentId: incidentId,
      schemaVersion: schemaVersion,
      appVersion: appVersion,
      modelHash: modelHash,
      audioFormat: audioFormat,
      savedAt: savedAt,
      previousVersionId: previousVersionId,
      metadataCiphertext: metadataCiphertext,
      metadataNonce: metadataNonce,
      metadataTag: metadataTag,
    );
  }
}
