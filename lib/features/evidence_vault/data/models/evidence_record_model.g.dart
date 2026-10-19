// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'evidence_record_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EvidenceRecordModelAdapter extends TypeAdapter<EvidenceRecordModel> {
  @override
  final int typeId = 0;

  @override
  EvidenceRecordModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EvidenceRecordModel(
      id: fields[0] as String,
      timestamp: fields[1] as DateTime,
      predictionLabel: fields[2] as String,
      confidenceScore: fields[3] as double,
      gpsCoordinates: (fields[4] as Map).cast<String, double>(),
      encryptedAudioBlob: fields[5] as Uint8List,
      ivBytes: fields[6] as Uint8List,
      authTag: fields[7] as Uint8List,
      integrityHash: fields[8] as String,
      incidentId: fields[9] == null ? '' : fields[9] as String,
      schemaVersion: fields[10] == null ? 1 : fields[10] as int,
      appVersion: fields[11] == null ? '' : fields[11] as String,
      modelHash: fields[12] == null ? '' : fields[12] as String,
      audioFormat: fields[13] == null ? '' : fields[13] as String,
      savedAt: fields[14] as DateTime?,
      previousVersionId: fields[15] == null ? '' : fields[15] as String,
      metadataCiphertext: fields[16] as Uint8List?,
      metadataNonce: fields[17] as Uint8List?,
      metadataTag: fields[18] as Uint8List?,
    );
  }

  @override
  void write(BinaryWriter writer, EvidenceRecordModel obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.timestamp)
      ..writeByte(2)
      ..write(obj.predictionLabel)
      ..writeByte(3)
      ..write(obj.confidenceScore)
      ..writeByte(4)
      ..write(obj.gpsCoordinates)
      ..writeByte(5)
      ..write(obj.encryptedAudioBlob)
      ..writeByte(6)
      ..write(obj.ivBytes)
      ..writeByte(7)
      ..write(obj.authTag)
      ..writeByte(8)
      ..write(obj.integrityHash)
      ..writeByte(9)
      ..write(obj.incidentId)
      ..writeByte(10)
      ..write(obj.schemaVersion)
      ..writeByte(11)
      ..write(obj.appVersion)
      ..writeByte(12)
      ..write(obj.modelHash)
      ..writeByte(13)
      ..write(obj.audioFormat)
      ..writeByte(14)
      ..write(obj.savedAt)
      ..writeByte(15)
      ..write(obj.previousVersionId)
      ..writeByte(16)
      ..write(obj.metadataCiphertext)
      ..writeByte(17)
      ..write(obj.metadataNonce)
      ..writeByte(18)
      ..write(obj.metadataTag);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvidenceRecordModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
