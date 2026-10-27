import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashing;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:serene/core/constants/hive_constants.dart';
import 'package:serene/core/crypto/cipher_manager.dart';
import 'package:serene/core/crypto/evidence_provenance.dart';
import 'package:serene/core/errors/failures.dart';
import 'package:serene/core/services/evidence_storage_guard.dart';
import 'package:serene/core/constants/evidence_policy.dart';
import 'package:serene/features/evidence_vault/data/datasources/evidence_audit_store.dart';
import 'package:serene/features/evidence_vault/data/datasources/evidence_local_datasource.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_envelope.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_record_model.dart';

import '../../../support/evidence_fixtures.dart';
import '../../../support/memory_evidence_keys.dart';

/// Writes exactly the original Hive schema, without any fields 9..18.
class LegacyV1Writer extends TypeAdapter<EvidenceRecordModel> {
  @override
  int get typeId => 0;
  @override
  EvidenceRecordModel read(BinaryReader reader) =>
      EvidenceRecordModelAdapter().read(reader);
  @override
  void write(BinaryWriter writer, EvidenceRecordModel record) {
    final fields = <Object>[
      record.id,
      record.timestamp,
      record.predictionLabel,
      record.confidenceScore,
      record.gpsCoordinates,
      record.encryptedAudioBlob,
      record.ivBytes,
      record.authTag,
      record.integrityHash,
    ];
    writer.writeByte(fields.length);
    for (var index = 0; index < fields.length; index++) {
      writer.writeByte(index);
      writer.write(fields[index]);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late MemoryEvidenceKeys keys;
  late EvidenceLocalDataSourceImpl source;
  final cipher = CipherManager();
  final codec = EvidenceEnvelope(cipher);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('serene_integrity_');
    Hive.init(root.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(EvidenceRecordModelAdapter());
    }
    keys = MemoryEvidenceKeys();
    source = EvidenceLocalDataSourceImpl(
      storageGuard: ampleStorage(),
      keyStorage: keys,
    );
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<EvidenceRecordModel> previousV2() async {
    final fixture = await sealedFixture(keys);
    final opened = await codec.open(fixture, keys.secret);
    final metadata = EvidenceEnvelope.metadata(opened)..remove('storageId');
    final bytes = Uint8List.fromList(utf8.encode(canonicalJson(metadata)));
    final audio = await cipher.encryptInMemory(
      rawAudioBytes: Uint8List.fromList(List.generate(100, (i) => i)),
      secretKey: keys.secret,
      aad: bytes,
    );
    final protected = await cipher.encryptInMemory(
      rawAudioBytes: bytes,
      secretKey: keys.secret,
      aad: EvidenceEnvelope.metadataAad(fixture.id),
    );
    final encoded = EvidenceEnvelope.encode(fixture);
    encoded['audio'] = base64Encode(audio.cipherBytes);
    encoded['iv'] = base64Encode(audio.ivBytes);
    encoded['tag'] = base64Encode(audio.authTag);
    encoded['metadata'] = base64Encode(protected.cipherBytes);
    encoded['metadataIv'] = base64Encode(protected.ivBytes);
    encoded['metadataTag'] = base64Encode(protected.authTag);
    encoded['hash'] = '';
    return EvidenceEnvelope.decode(Map<String, dynamic>.from(encoded));
  }

  for (final stage in AuditWriteStage.values) {
    test(
      'privacy migration recovers after interruption at ${stage.name}',
      () async {
        await source.insertRecord(await previousV2());
        source = EvidenceLocalDataSourceImpl(
          storageGuard: ampleStorage(),
          keyStorage: keys,
          onAuditStage: (current) async {
            if (current == stage) throw StateError('interrupted migration');
          },
        );
        await expectLater(source.fetchAllRecords(), throwsStateError);
        await Hive.close();
        Hive.init(root.path);
        source = EvidenceLocalDataSourceImpl(
          storageGuard: ampleStorage(),
          keyStorage: keys,
        );
        final repository = testRepository(source, keys);
        final visible = (await repository.getAllEvidenceRecords()).single;
        expect(visible.id, 'version-1');
        expect(visible.storageId, isNot(visible.id));
        expect(visible.integrityHash, hasLength(64));
        expect(
          await repository.getDecryptedAudioBytes(visible),
          List.generate(100, (i) => i),
        );
        expect(await source.fetchAllRecords(), hasLength(1));
      },
    );
  }

  test('real bundled model provenance is a SHA-256 digest', () async {
    expect(
      await EvidenceProvenance.modelHash(),
      matches(RegExp(r'^[a-f0-9]{64}$')),
    );
  });

  test(
    'low storage rejects a new version without modifying committed evidence',
    () async {
      await source.insertRecord(await sealedFixture(keys));
      source = EvidenceLocalDataSourceImpl(
        keyStorage: keys,
        storageGuard: EvidenceStorageGuard(
          freeBytes: (_) async => EvidencePolicy.minimumFreeBytes,
        ),
      );
      await expectLater(
        source.insertRecord(
          await sealedFixture(
            keys,
            id: 'version-2',
            second: 2,
            previous: 'version-1',
          ),
        ),
        throwsA(isA<StorageCapacityFailure>()),
      );
      expect((await source.fetchAllRecords()).single.id, 'version-1');
      expect((await source.readVerifiedAuditEvents()).length, 1);
    },
  );

  test(
    'manual deletion commits in low space and deferred compaction retries later',
    () async {
      await source.insertRecord(await sealedFixture(keys, size: 400000));
      var available = 200 * 1024;
      source = EvidenceLocalDataSourceImpl(
        keyStorage: keys,
        storageGuard: EvidenceStorageGuard(freeBytes: (_) async => available),
      );
      await source.removeRecord('version-1');
      expect(await source.fetchAllRecords(), isEmpty);
      expect((jsonDecode(keys.anchor!) as Map)['maintenancePending'], isTrue);
      final box = Hive.box<EvidenceRecordModel>(
        HiveConstants.encryptedEvidenceBox,
      );
      expect(await File(box.path!).length(), greaterThan(0));
      available = 10 * 1024 * 1024;
      expect(await source.fetchAllRecords(), isEmpty);
      expect((jsonDecode(keys.anchor!) as Map)['maintenancePending'], isFalse);
      expect(await File(box.path!).length(), 0);
      expect(
        (await source.readVerifiedAuditEvents()).map((e) => e['operation']),
        ['create', 'delete'],
      );
    },
  );

  test('app provenance reads the installed version and build number', () async {
    PackageInfo.setMockInitialValues(
      appName: 'serene',
      packageName: 'com.example.serene',
      version: '7.4.0',
      buildNumber: '99',
      buildSignature: '',
    );
    expect(await EvidenceProvenance.appVersion(), '7.4.0+99');
  });

  test(
    'tampered pending WAL is rejected without accepting a new anchor',
    () async {
      source = EvidenceLocalDataSourceImpl(
        storageGuard: ampleStorage(),
        keyStorage: keys,
        onAuditStage: (stage) async {
          if (stage == AuditWriteStage.pendingAnchored) {
            throw StateError('interrupted');
          }
        },
      );
      await expectLater(
        source.insertRecord(await sealedFixture(keys)),
        throwsStateError,
      );
      final anchor = keys.anchor;
      final events = Hive.box<dynamic>(EvidenceAuditStore.boxName);
      final walKey = events.keys.whereType<String>().single;
      final wal = Map<String, dynamic>.from(events.get(walKey) as Map);
      final ciphertext = base64Decode(wal['cipher'] as String)..[0] ^= 1;
      wal['cipher'] = base64Encode(ciphertext);
      await events.put(walKey, wal);
      source = EvidenceLocalDataSourceImpl(
        storageGuard: ampleStorage(),
        keyStorage: keys,
      );
      await expectLater(
        source.fetchAllRecords(),
        throwsA(isA<CryptoFailure>()),
      );
      expect(keys.anchor, anchor);
    },
  );

  for (final field in [
    'id',
    'incident',
    'timestamp',
    'savedAt',
    'previousVersion',
    'label',
    'confidence',
    'gps',
    'appVersion',
    'modelHash',
    'audioFormat',
    'schema',
  ]) {
    test('GCM rejects modified authenticated metadata: $field', () async {
      final stored = await sealedFixture(keys);
      final record = await codec.open(stored, keys.secret);
      final modified = EvidenceEnvelope.metadata(record);
      modified[field] = switch (field) {
        'confidence' => .1,
        'gps' => {'lat': 0.0, 'lng': 0.0},
        'schema' => 3,
        _ => 'modified',
      };
      await expectLater(
        cipher.decryptInMemory(
          cipherBytes: stored.encryptedAudioBlob,
          ivBytes: stored.ivBytes,
          authTag: stored.authTag,
          secretKey: keys.secret,
          aad: utf8.encode(canonicalJson(modified)),
        ),
        throwsA(isA<CryptoFailure>()),
      );
    });
  }

  for (final field in ['audio', 'iv', 'tag']) {
    test(
      'GCM rejects changed $field independently of a public SHA-256',
      () async {
        final stored = await sealedFixture(keys);
        final record = await codec.open(stored, keys.secret);
        final encoded = EvidenceEnvelope.encode(stored);
        final bytes = base64Decode(encoded[field] as String);
        bytes[0] ^= 1;
        encoded[field] = base64Encode(bytes);
        final altered = EvidenceEnvelope.decode(
          Map<String, dynamic>.from(encoded),
        );
        await expectLater(
          cipher.decryptInMemory(
            cipherBytes: altered.encryptedAudioBlob,
            ivBytes: altered.ivBytes,
            authTag: altered.authTag,
            secretKey: keys.secret,
            aad: EvidenceEnvelope.metadataBytes(record),
          ),
          throwsA(isA<CryptoFailure>()),
        );
      },
    );
  }

  for (final field in ['metadata', 'metadataIv', 'metadataTag']) {
    test('encrypted metadata rejects changed $field', () async {
      final encoded = EvidenceEnvelope.encode(await sealedFixture(keys));
      final bytes = base64Decode(encoded[field] as String);
      bytes[0] ^= 1;
      encoded[field] = base64Encode(bytes);
      await expectLater(
        codec.open(
          EvidenceEnvelope.decode(Map<String, dynamic>.from(encoded)),
          keys.secret,
        ),
        throwsA(isA<CryptoFailure>()),
      );
    });
  }

  test(
    'canonical metadata is stable across GPS insertion order and UTC conversion',
    () async {
      final stored = await sealedFixture(keys);
      final record = await codec.open(stored, keys.secret);
      final data = EvidenceEnvelope.metadata(record);
      data['gps'] = {'lng': -77.08, 'lat': -12.05};
      final audio = await cipher.decryptInMemory(
        cipherBytes: stored.encryptedAudioBlob,
        ivBytes: stored.ivBytes,
        authTag: stored.authTag,
        secretKey: keys.secret,
        aad: utf8.encode(canonicalJson(data)),
      );
      expect(audio.length, 100);
      expect(
        canonicalJson({
          'z': 1,
          'a': {'z': 2, 'a': 3},
        }),
        '{"a":{"a":3,"z":2},"z":1}',
      );
    },
  );

  test(
    'new Hive records and audit entries do not expose descriptive metadata',
    () async {
      await source.insertRecord(await sealedFixture(keys));
      await Hive.close();
      final files = await root.list().toList();
      for (final file in files.whereType<File>()) {
        final bytes = await file.readAsBytes();
        final text = latin1.decode(bytes);
        for (final sensitive in [
          'sensitive-label',
          '1.2.3+4',
          'pcm_s16le',
          '2026-01-01',
        ]) {
          expect(text, isNot(contains(sensitive)), reason: file.path);
        }
      }
      final records = await testRepository(
        source,
        keys,
      ).getAllEvidenceRecords();
      expect(records.single.predictionLabel, 'sensitive-label');
      expect(records.single.hasAuthenticatedMetadata, isTrue);
    },
  );

  test(
    'persisted ciphertext modification is detected by audit before playback',
    () async {
      await source.insertRecord(await sealedFixture(keys));
      final box = Hive.box<EvidenceRecordModel>(
        HiveConstants.encryptedEvidenceBox,
      );
      final encoded = EvidenceEnvelope.encode(box.values.single);
      final audio = base64Decode(encoded['audio'] as String)..[0] ^= 1;
      encoded['audio'] = base64Encode(audio);
      await box.put(
        'version-1',
        EvidenceEnvelope.decode(Map<String, dynamic>.from(encoded)),
      );
      await expectLater(
        source.fetchAllRecords(),
        throwsA(isA<CryptoFailure>()),
      );
    },
  );

  for (final manipulation in [
    'delete_middle',
    'delete_tail',
    'edit',
    'reorder',
    'append',
    'missing_anchor',
  ]) {
    test('audit detects $manipulation', () async {
      for (var i = 1; i <= 3; i++) {
        await source.insertRecord(
          await sealedFixture(keys, id: 'v-$i', incident: 'i-$i', second: i),
        );
      }
      final events = Hive.box<dynamic>(EvidenceAuditStore.boxName);
      switch (manipulation) {
        case 'delete_middle':
          await events.delete(2);
        case 'delete_tail':
          await events.delete(3);
        case 'edit':
          final event = Map<String, dynamic>.from(events.get(2) as Map);
          final payload = Map<String, dynamic>.from(event['payload'] as Map);
          final bytes = base64Decode(payload['cipher'] as String)..[0] ^= 1;
          payload['cipher'] = base64Encode(bytes);
          event['payload'] = payload;
          await events.put(2, event);
        case 'reorder':
          final first = events.get(1);
          await events.put(1, events.get(2));
          await events.put(2, first);
        case 'append':
          await events.put(4, events.get(3));
        case 'missing_anchor':
          keys.anchor = null;
      }
      await expectLater(
        source.fetchAllRecords(),
        throwsA(isA<CryptoFailure>()),
      );
    });
  }

  test(
    'persisted version removal outside the audited delete is detected',
    () async {
      await source.insertRecord(await sealedFixture(keys));
      await Hive.box<EvidenceRecordModel>(
        HiveConstants.encryptedEvidenceBox,
      ).delete('version-1');
      await expectLater(
        source.fetchAllRecords(),
        throwsA(isA<CryptoFailure>()),
      );
    },
  );

  for (final stage in AuditWriteStage.values) {
    for (final deletion in [false, true]) {
      test(
        'recover ${deletion ? 'delete' : 'create'} interrupted at ${stage.name}',
        () async {
          final record = await sealedFixture(keys);
          if (deletion) await source.insertRecord(record);
          var interrupted = false;
          source = EvidenceLocalDataSourceImpl(
            storageGuard: ampleStorage(),
            keyStorage: keys,
            onAuditStage: (at) async {
              if (at == stage && !interrupted) {
                interrupted = true;
                throw StateError('simulated process exit');
              }
            },
          );
          await expectLater(
            deletion
                ? source.removeRecord(record.id)
                : source.insertRecord(record),
            throwsStateError,
          );
          expect(interrupted, isTrue);
          await Hive.close();
          Hive.init(root.path);
          source = EvidenceLocalDataSourceImpl(
            storageGuard: ampleStorage(),
            keyStorage: keys,
          );
          final recovered = await source.fetchAllRecords();
          final committed = stage != AuditWriteStage.walFlushed;
          expect(
            recovered.length,
            deletion ? (committed ? 0 : 1) : (committed ? 1 : 0),
          );
          expect(
            (await source.readVerifiedAuditEvents()).length,
            (deletion ? 1 : 0) + (committed ? 1 : 0),
          );
          expect(
            Hive.box<dynamic>(
              EvidenceAuditStore.boxName,
            ).keys.whereType<String>(),
            isEmpty,
          );
        },
      );
    }
  }

  test(
    'concurrent saves are serialized and immutable retries add no events',
    () async {
      final fixtures = await Future.wait(
        List.generate(
          5,
          (i) =>
              sealedFixture(keys, id: 'v-$i', incident: 'i-$i', second: i + 1),
        ),
      );
      await Future.wait(fixtures.map(source.insertRecord));
      await Future.wait(fixtures.map(source.insertRecord));
      final history = await source.readVerifiedAuditEvents();
      expect(history.map((e) => e['sequence']), [1, 2, 3, 4, 5]);
      expect(history.map((e) => e['eventId']).toSet().length, 5);
      expect((await source.fetchAllRecords()).length, 5);
      await expectLater(
        source.insertRecord(await sealedFixture(keys, id: 'v-0', size: 200)),
        throwsA(isA<CryptoFailure>()),
      );
    },
  );

  test(
    'repository keeps all advances, shows latest, and deletes every version atomically',
    () async {
      final repository = testRepository(source, keys);
      for (final size in [100, 200, 300]) {
        await repository.saveEncryptedEvidence(
          rawAudioBytes: Uint8List(size),
          predictionLabel: 'label',
          confidenceScore: .9,
          gpsCoordinates: {},
          evidenceId: 'incident',
        );
      }
      expect((await source.fetchAllRecords()).length, 3);
      final visible = await repository.getAllEvidenceRecords();
      expect(visible.length, 1);
      expect(
        (await repository.getDecryptedAudioBytes(visible.single)).length,
        300,
      );
      final stats = await repository.getVaultStats();
      expect(stats.totalCount, 1);
      expect(stats.totalBytes, 600);
      await repository.deleteEvidenceRecord(visible.single.id);
      expect(await repository.getAllEvidenceRecords(), isEmpty);
      final events = await source.readVerifiedAuditEvents();
      expect(events.map((e) => e['operation']), [
        'create',
        'new_version',
        'new_version',
        'delete',
      ]);
      expect((events.last['deleted'] as List).length, 3);
    },
  );

  test('legacy Hive evidence migrates without changing audio', () async {
    final payload = await cipher.encryptInMemory(
      rawAudioBytes: Uint8List.fromList([1, 2, 3, 4]),
      secretKey: keys.secret,
    );
    final legacy = EvidenceRecordModel(
      id: 'legacy',
      timestamp: DateTime.utc(2025),
      predictionLabel: 'old-label',
      confidenceScore: .9,
      gpsCoordinates: const {},
      encryptedAudioBlob: payload.cipherBytes,
      ivBytes: payload.ivBytes,
      authTag: payload.authTag,
      integrityHash: hashing.sha256.convert(payload.cipherBytes).toString(),
    );
    Hive.registerAdapter(LegacyV1Writer(), override: true);
    final box = await Hive.openBox<EvidenceRecordModel>(
      HiveConstants.encryptedEvidenceBox,
    );
    await box.add(legacy); // old auto-generated key
    await Hive.close();
    Hive.registerAdapter(EvidenceRecordModelAdapter(), override: true);
    Hive.init(root.path);
    final repository = testRepository(source, keys);
    final records = await repository.getAllEvidenceRecords();
    expect(records.single.schemaVersion, 2);
    expect(records.single.hasAuthenticatedMetadata, isTrue);
    expect(records.single.id, 'legacy');
    expect(records.single.storageId, isNot('legacy'));
    expect(await repository.getDecryptedAudioBytes(records.single), [
      1,
      2,
      3,
      4,
    ]);
    expect(
      (await source.readVerifiedAuditEvents()).map((e) => e['operation']),
      ['legacy_import', 'privacy_migration'],
    );
    await repository.deleteEvidenceRecord('legacy');
    expect(await source.fetchAllRecords(), isEmpty);
  });
}
