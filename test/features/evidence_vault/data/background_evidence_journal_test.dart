import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:serene/features/evidence_vault/data/datasources/background_evidence_journal.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_record_model.dart';

EvidenceRecordModel record(int size) => EvidenceRecordModel(
  id: 'incident',
  timestamp: DateTime.utc(2026),
  predictionLabel: 'physical_violence',
  confidenceScore: .95,
  gpsCoordinates: {},
  encryptedAudioBlob: Uint8List(size),
  ivBytes: Uint8List(12),
  authTag: Uint8List(16),
  integrityHash: 'test',
);

void main() {
  late Directory root;
  late Directory journalDirectory;
  late Box<EvidenceRecordModel> box;
  late BackgroundEvidenceJournal journal;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('serene_journal_test_');
    journalDirectory = await Directory('${root.path}/journal').create();
    Hive.init(root.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(EvidenceRecordModelAdapter());
    }
    box = await Hive.openBox<EvidenceRecordModel>('test_evidence');
    journal = BackgroundEvidenceJournal(
      directoryProvider: () async => journalDirectory,
    );
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test(
    'service checkpoints update one encrypted record rather than creating clips',
    () async {
      await journal.insertRecord(record(100));
      await journal.insertRecord(record(200));
      expect(box.isEmpty, isTrue); // service never opens Hive
      await BackgroundEvidenceJournal.importInto(
        box,
        directory: journalDirectory,
      );
      expect(box.length, 1);
      expect(box.get('incident')!.encryptedAudioBlob.length, 200);
      expect(await journalDirectory.list().length, 0);
      await journal.insertRecord(record(300));
      await BackgroundEvidenceJournal.importInto(
        box,
        directory: journalDirectory,
      );
      expect(box.length, 1);
      expect(box.get('incident')!.encryptedAudioBlob.length, 300);
    },
  );

  test(
    'older recovered checkpoint cannot overwrite a longer imported incident',
    () async {
      await box.put('incident', record(300));
      await journal.insertRecord(record(100));
      final file = File('${journalDirectory.path}/incident.json');
      await file.rename('${journalDirectory.path}/recovered.claimed.json');
      await BackgroundEvidenceJournal.importInto(
        box,
        directory: journalDirectory,
      );
      expect(box.get('incident')!.encryptedAudioBlob.length, 300);
    },
  );
}
