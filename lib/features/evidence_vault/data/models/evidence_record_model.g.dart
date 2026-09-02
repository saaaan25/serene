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
    );
  }

  @override
  void write(BinaryWriter writer, EvidenceRecordModel obj) {
    writer
      ..writeByte(9)
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
      ..write(obj.integrityHash);
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
