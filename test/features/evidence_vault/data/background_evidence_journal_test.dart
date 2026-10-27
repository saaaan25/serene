import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:crypto/crypto.dart' as hashing;
import 'package:serene/core/crypto/cipher_manager.dart';
import 'package:serene/core/services/evidence_storage_guard.dart';
import 'package:serene/core/constants/hive_constants.dart';
import 'package:serene/core/errors/failures.dart';
import 'package:serene/features/evidence_vault/data/datasources/background_evidence_journal.dart';
import 'package:serene/features/evidence_vault/data/datasources/evidence_local_datasource.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_record_model.dart';

import '../../../support/memory_evidence_keys.dart';
import '../../../support/evidence_fixtures.dart';

void main() {
  late Directory root;
  late Directory journalDirectory;
  late MemoryEvidenceKeys keys;
  late EvidenceLocalDataSourceImpl source;
  late BackgroundEvidenceJournal journal;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('serene_journal_test_');
    journalDirectory = await Directory('${root.path}/journal').create();
    Hive.init(root.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(EvidenceRecordModelAdapter());
    }
    keys = MemoryEvidenceKeys();
    source = EvidenceLocalDataSourceImpl(
      storageGuard: ampleStorage(),
      keyStorage: keys,
      journalDirectory: journalDirectory,
    );
    journal = BackgroundEvidenceJournal(
      storageGuard: ampleStorage(),
      directoryProvider: () async => journalDirectory,
    );
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test(
    'low storage creates no staging file and preserves confirmed records',
    () async {
      journal = BackgroundEvidenceJournal(
        directoryProvider: () async => journalDirectory,
        storageGuard: EvidenceStorageGuard(freeBytes: (_) async => 0),
      );
      await expectLater(
        journal.insertRecord(await sealedFixture(keys)),
        throwsA(isA<StorageCapacityFailure>()),
      );
      expect(await journalDirectory.list().length, 0);
    },
  );

  test(
    'old JSON checkpoints sharing an incident ID are preserved as legacy versions',
    () async {
      for (final size in [300, 100]) {
        final payload = await CipherManager().encryptInMemory(
          rawAudioBytes: Uint8List(size),
          secretKey: keys.secret,
        );
        await File('${journalDirectory.path}/old-$size.json').writeAsString(
          jsonEncode({
            'id': 'old-incident',
            'timestamp': DateTime.utc(2025).toIso8601String(),
            'label': 'old-label',
            'confidence': .9,
            'gps': <String, double>{},
            'audio': base64Encode(payload.cipherBytes),
            'iv': base64Encode(payload.ivBytes),
            'tag': base64Encode(payload.authTag),
            'hash': hashing.sha256.convert(payload.cipherBytes).toString(),
          }),
          flush: true,
        );
      }
      final repository = testRepository(source, keys);
      final visible = await repository.getAllEvidenceRecords();
      expect((await source.fetchAllRecords()).length, 2);
      expect(visible.single.logicalIncidentId, 'old-incident');
      expect(visible.single.hasAuthenticatedMetadata, isTrue);
      expect(
        (await repository.getDecryptedAudioBytes(visible.single)).length,
        300,
      );
      await Hive.close();
      Hive.init(root.path);
      expect((await repository.getAllEvidenceRecords()).length, 1);
      await repository.deleteEvidenceRecord(visible.single.id);
      expect(await source.fetchAllRecords(), isEmpty);
    },
  );

  test(
    'all checkpoints remain immutable; vault shows latest incident version',
    () async {
      final first = await sealedFixture(keys);
      final second = await sealedFixture(
        keys,
        id: 'version-2',
        size: 200,
        second: 2,
        previous: first.id,
      );
      // Out-of-order directory enumeration is sorted by authenticated savedAt.
      await journal.insertRecord(second);
      await journal.insertRecord(first);
      expect(Hive.isBoxOpen(HiveConstants.encryptedEvidenceBox), isFalse);
      final stored = await source.fetchAllRecords();
      expect(stored.length, 2);
      final repository = testRepository(source, keys);
      final visible = await repository.getAllEvidenceRecords();
      expect(visible.single.id, second.id);
      expect(
        (await repository.getDecryptedAudioBytes(visible.single)).length,
        200,
      );
      expect(
        (await source.readVerifiedAuditEvents()).map((e) => e['operation']),
        ['create', 'new_version'],
      );
      expect(await journalDirectory.list().length, 0);
    },
  );

  test('staging hides metadata and rejects replacement of a version', () async {
    final first = await sealedFixture(keys);
    await journal.insertRecord(first);
    final text = await File(
      '${journalDirectory.path}/version-1.json',
    ).readAsString();
    for (final sensitive in [
      'sensitive-label',
      '-12.05',
      '-77.08',
      '1.2.3+4',
      'pcm_s16le',
      '2026-01-01',
    ]) {
      expect(text, isNot(contains(sensitive)));
    }
    await journal.insertRecord(first); // identical retry
    await expectLater(
      journal.insertRecord(await sealedFixture(keys, size: 200)),
      throwsA(isA<CryptoFailure>()),
    );
  });

  test('claimed-file retry is idempotent after durable import', () async {
    final record = await sealedFixture(keys);
    await journal.insertRecord(record);
    final file = File('${journalDirectory.path}/version-1.json');
    final text = await file.readAsString();
    await source.fetchAllRecords();
    await File(
      '${journalDirectory.path}/retry.claimed.json',
    ).writeAsString(text, flush: true);
    expect((await source.fetchAllRecords()).length, 1);
    expect((await source.readVerifiedAuditEvents()).length, 1);
  });

  test(
    'flushed temporary envelope recovers after interruption before rename',
    () async {
      journal = BackgroundEvidenceJournal(
        storageGuard: ampleStorage(),
        directoryProvider: () async => journalDirectory,
        afterStagingFlush: () async =>
            throw StateError('simulated process exit'),
      );
      await expectLater(
        journal.insertRecord(await sealedFixture(keys)),
        throwsStateError,
      );
      expect((await source.fetchAllRecords()).length, 1);
      expect(await journalDirectory.list().length, 0);
    },
  );

  test('partial uncommitted temporary file does not break import', () async {
    await File(
      '${journalDirectory.path}/partial.tmp',
    ).writeAsString('{"schema":');
    expect(await source.fetchAllRecords(), isEmpty);
    expect(await journalDirectory.list().length, 0);
  });

  test(
    'modified staged envelope is rejected and retained for inspection',
    () async {
      await journal.insertRecord(await sealedFixture(keys));
      final file = File('${journalDirectory.path}/version-1.json');
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final metadata = base64Decode(data['metadata'] as String);
      metadata[0] ^= 1;
      data['metadata'] = base64Encode(metadata);
      await file.writeAsString(jsonEncode(data), flush: true);
      await expectLater(
        source.fetchAllRecords(),
        throwsA(isA<CryptoFailure>()),
      );
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'missing predecessor is detectable rather than silently dropping an advance',
    () async {
      await journal.insertRecord(
        await sealedFixture(
          keys,
          id: 'version-2',
          previous: 'version-1',
          second: 2,
        ),
      );
      await expectLater(
        source.fetchAllRecords(),
        throwsA(isA<CryptoFailure>()),
      );
      expect(await journalDirectory.list().length, 1);
    },
  );

  test('recovered staging files cannot resurrect a deleted incident', () async {
    final record = await sealedFixture(keys);
    await journal.insertRecord(record);
    final text = await File(
      '${journalDirectory.path}/version-1.json',
    ).readAsString();
    await source.fetchAllRecords();
    await source.removeRecord(record.id);
    await File(
      '${journalDirectory.path}/retry.claimed.json',
    ).writeAsString(text);
    await journal.insertRecord(
      await sealedFixture(
        keys,
        id: 'late-version',
        previous: record.id,
        second: 2,
      ),
    );
    expect(await source.fetchAllRecords(), isEmpty);
    expect(
      (await source.readVerifiedAuditEvents()).map((e) => e['operation']),
      ['create', 'delete'],
    );
  });
}
