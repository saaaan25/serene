import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:serene/core/constants/hive_constants.dart';
import 'package:serene/features/evidence_vault/data/datasources/evidence_local_datasource.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_record_model.dart';

void main() {
  late EvidenceLocalDataSourceImpl dataSource;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_unit_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(HiveConstants.evidenceRecordTypeId)) {
      Hive.registerAdapter(EvidenceRecordModelAdapter());
    }
    dataSource = EvidenceLocalDataSourceImpl();
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // To generate clean instances
  EvidenceRecordModel createTestModel({String id = 'test-uuid-123'}) {
    return EvidenceRecordModel(
      id: id,
      timestamp: DateTime.now().toUtc(),
      predictionLabel: 'physical_violence',
      confidenceScore: 0.89,
      gpsCoordinates: const {'lat': -12.0463, 'lng': -77.0427},
      encryptedAudioBlob: Uint8List.fromList([1, 2, 3]),
      ivBytes: Uint8List.fromList([0, 1]),
      authTag: Uint8List.fromList([9, 9]),
      integrityHash: 'mock-hash',
    );
  }

  test(
    'It should insert and fetch an EvidenceRecordModel in Hive Box',
    () async {
      final model = createTestModel();
      await dataSource.insertRecord(model);
      final records = await dataSource.fetchAllRecords();

      expect(records.length, equals(1));
      expect(records.first.id, equals('test-uuid-123'));
      expect(records.first.predictionLabel, equals('physical_violence'));
      expect(
        records.first.encryptedAudioBlob,
        equals(Uint8List.fromList([1, 2, 3])),
      );
    },
  );

  test('It should remove a specific record by its primary key', () async {
    final model = createTestModel();
    await dataSource.insertRecord(model);
    await dataSource.removeRecord('test-uuid-123');
    final records = await dataSource.fetchAllRecords();

    expect(records.isEmpty, isTrue);
  });

  test(
    'It should remove legacy records stored under an auto-generated key',
    () async {
      final model = createTestModel();
      final box = await Hive.openBox<EvidenceRecordModel>(
        HiveConstants.encryptedEvidenceBox,
      );
      await box.add(model);

      await dataSource.removeRecord(model.id);

      expect(box.isEmpty, isTrue);
    },
  );
}
