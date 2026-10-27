import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:serene/core/constants/hive_constants.dart';
import 'package:serene/features/evidence_vault/data/datasources/evidence_local_datasource.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_record_model.dart';
import '../../../support/memory_evidence_keys.dart';
import '../../../support/evidence_fixtures.dart';
import 'package:serene/core/crypto/cipher_manager.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_envelope.dart';

void main() {
  late EvidenceLocalDataSourceImpl dataSource;
  late Directory tempDir;
  late MemoryEvidenceKeys keys;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_unit_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(HiveConstants.evidenceRecordTypeId)) {
      Hive.registerAdapter(EvidenceRecordModelAdapter());
    }
    keys = MemoryEvidenceKeys();
    dataSource = EvidenceLocalDataSourceImpl(
      storageGuard: ampleStorage(),
      keyStorage: keys,
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<EvidenceRecordModel> createTestModel({String id = 'test-uuid-123'}) =>
      sealedFixture(keys, id: id);

  test(
    'It should insert and fetch an EvidenceRecordModel in Hive Box',
    () async {
      final model = await createTestModel();
      await dataSource.insertRecord(model);
      final records = await dataSource.fetchAllRecords();

      expect(records.length, equals(1));
      expect(records.first.id, equals('test-uuid-123'));
      expect(records.first.predictionLabel, isEmpty);
      final opened = await EvidenceEnvelope(
        CipherManager(),
      ).open(records.first, keys.secret);
      expect(opened.predictionLabel, 'sensitive-label');
      expect(
        records.first.encryptedAudioBlob,
        equals(model.encryptedAudioBlob),
      );
    },
  );

  test('It should remove a specific record by its primary key', () async {
    final model = await createTestModel();
    await dataSource.insertRecord(model);
    await dataSource.removeRecord('test-uuid-123');
    final records = await dataSource.fetchAllRecords();

    expect(records.isEmpty, isTrue);
  });

  test('It should remove records stored under an auto-generated key', () async {
    final model = await createTestModel();
    final box = await Hive.openBox<EvidenceRecordModel>(
      HiveConstants.encryptedEvidenceBox,
    );
    await dataSource.insertRecord(model);
    await box.delete(model.id);
    await box.add(model);

    await dataSource.removeRecord(model.id);

    expect(box.isEmpty, isTrue);
  });
}
