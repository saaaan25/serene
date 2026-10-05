import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/constants/hive_constants.dart';
import '../../../../core/errors/failures.dart';
import '../models/evidence_record_model.dart';

abstract class EvidenceLocalDataSource {
  Future<void> insertRecord(EvidenceRecordModel record);
  Future<List<EvidenceRecordModel>> fetchAllRecords();
  Future<void> removeRecord(String id);
}

class EvidenceLocalDataSourceImpl implements EvidenceLocalDataSource {
  Future<Box<EvidenceRecordModel>> _openBox() async {
    try {
      if (Hive.isBoxOpen(HiveConstants.encryptedEvidenceBox)) {
        return Hive.box<EvidenceRecordModel>(HiveConstants.encryptedEvidenceBox);
      }
      return await Hive.openBox<EvidenceRecordModel>(HiveConstants.encryptedEvidenceBox);
    } catch (e) {
      throw DatabaseFailure('Error: $e');
    }
  }

  @override
  Future<void> insertRecord(EvidenceRecordModel record) async {
    try {
      final box = await _openBox();
      await box.put(record.id, record);
    } catch (e) {
      throw DatabaseFailure('Error: $e');
    }
  }

  @override
  Future<List<EvidenceRecordModel>> fetchAllRecords() async {
    try {
      final box = await _openBox();
      return box.values.toList();
    } catch (e) {
      throw DatabaseFailure('Error: $e');
    }
  }

  @override
  Future<void> removeRecord(String id) async {
    try {
      final box = await _openBox();
      if (box.containsKey(id)) {
        await box.delete(id);
        return;
      }

      Object? legacyKey;
      for (final key in box.keys) {
        if (box.get(key)?.id == id) {
          legacyKey = key;
          break;
        }
      }
      if (legacyKey != null) {
        await box.delete(legacyKey);
      }
    } catch (e) {
      throw DatabaseFailure('Error: $e');
    }
  }
}