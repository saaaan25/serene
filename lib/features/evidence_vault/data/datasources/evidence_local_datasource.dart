import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/constants/hive_constants.dart';
import '../../../../core/crypto/cipher_manager.dart';
import '../../../../core/crypto/secure_key_storage.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/evidence_storage_guard.dart';
import '../models/evidence_envelope.dart';
import '../models/evidence_record_model.dart';
import '../../domain/entities/evidence_record.dart';
import 'dart:typed_data';
import 'background_evidence_journal.dart';
import 'evidence_audit_store.dart';

abstract class EvidenceLocalDataSource {
  Future<void> insertRecord(EvidenceRecordModel record);
  Future<List<EvidenceRecordModel>> fetchAllRecords();
  Future<void> removeRecord(String id);
}

class EvidenceLocalDataSourceImpl implements EvidenceLocalDataSource {
  // Shared by all instances in the UI isolate, including recovery and imports.
  static Future<void> _work = Future.value();
  final SecureKeyStorage keyStorage;
  final CipherManager cipher;
  final EvidenceStorageGuard storageGuard;
  final Directory? journalDirectory;
  final Future<void> Function(AuditWriteStage)? onAuditStage;

  EvidenceLocalDataSourceImpl({
    SecureKeyStorage? keyStorage,
    CipherManager? cipher,
    EvidenceStorageGuard? storageGuard,
    this.journalDirectory,
    this.onAuditStage,
  }) : keyStorage = keyStorage ?? SecureKeyStorage(),
       cipher = cipher ?? CipherManager(),
       storageGuard = storageGuard ?? EvidenceStorageGuard();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final task = _work.then((_) async {
      try {
        return await action();
      } catch (error) {
        throw EvidenceStorageGuard.classifyWriteError(error);
      }
    });
    _work = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<EvidenceAuditStore> _open() async {
    final box = await Hive.openBox<EvidenceRecordModel>(
      HiveConstants.encryptedEvidenceBox,
    );
    final events = await Hive.openBox<dynamic>(EvidenceAuditStore.boxName);
    final audit = EvidenceAuditStore(
      records: box,
      events: events,
      keys: keyStorage,
      key: await keyStorage.getOrCreateMasterKey(),
      cipher: cipher,
      storageGuard: storageGuard,
      onStage: onAuditStage,
    );
    await audit.initializeAndVerify();
    await BackgroundEvidenceJournal.importInto(
      box,
      directory: journalDirectory,
      importer: (record) => _insert(audit, record),
      ordering: (record) async {
        final opened = await EvidenceEnvelope(cipher).open(record, audit.key);
        return opened.savedAt ?? opened.timestamp;
      },
    );
    await _migrateLegacy(audit);
    return audit;
  }

  Future<void> _migrateLegacy(EvidenceAuditStore audit) async {
    final codec = EvidenceEnvelope(cipher);
    for (final old in audit.records.values.toList()) {
      final record = await codec.open(old, audit.key);
      if (record.schemaVersion == 2 &&
          record.storageId.isNotEmpty &&
          record.integrityHash.isNotEmpty) {
        continue;
      }
      final audio = await cipher.decryptInMemory(
        cipherBytes: old.encryptedAudioBlob,
        ivBytes: old.ivBytes,
        authTag: old.authTag,
        secretKey: audit.key,
        aad: old.schemaVersion == 1
            ? const []
            : EvidenceEnvelope.metadataBytes(record),
      );
      try {
        final metadata = EvidenceRecord(
          id: record.id,
          incidentId: record.logicalIncidentId,
          schemaVersion: 2,
          timestamp: record.timestamp,
          savedAt: record.savedAt ?? record.timestamp,
          predictionLabel: record.predictionLabel,
          confidenceScore: record.confidenceScore,
          gpsCoordinates: record.gpsCoordinates,
          previousVersionId: record.previousVersionId,
          appVersion: record.appVersion,
          modelHash: record.modelHash,
          audioFormat: record.audioFormat,
          encryptedAudioBlob: Uint8List(0),
          ivBytes: Uint8List(0),
          authTag: Uint8List(0),
          integrityHash: '',
        );
        final sealed = await codec.seal(
          metadataRecord: metadata,
          audio: audio,
          key: audit.key,
        );
        // Authenticate both new blocks before committing the replacement.
        final verified = await codec.open(sealed, audit.key);
        final check = await cipher.decryptInMemory(
          cipherBytes: sealed.encryptedAudioBlob,
          ivBytes: sealed.ivBytes,
          authTag: sealed.authTag,
          secretKey: audit.key,
          aad: EvidenceEnvelope.metadataBytes(verified),
        );
        try {
          var matches = check.length == audio.length;
          for (var i = 0; matches && i < audio.length; i++) {
            matches = check[i] == audio[i];
          }
          if (!matches) {
            throw const CryptoFailure('Migrated audio differs from source');
          }
        } finally {
          check.fillRange(0, check.length, 0);
        }
        await audit.migrate(old, sealed, incidentId: record.logicalIncidentId);
      } finally {
        audio.fillRange(0, audio.length, 0);
      }
    }
  }

  Future<void> _insert(
    EvidenceAuditStore audit,
    EvidenceRecordModel record,
  ) async {
    final codec = EvidenceEnvelope(cipher);
    final opened = await codec.open(record, audit.key);
    if (record.schemaVersion == 2) {
      // Authenticate staged audio before admitting it to the local evidence log.
      final bytes = await cipher.decryptInMemory(
        cipherBytes: record.encryptedAudioBlob,
        ivBytes: record.ivBytes,
        authTag: record.authTag,
        secretKey: audit.key,
        aad: EvidenceEnvelope.metadataBytes(opened),
      );
      bytes.fillRange(0, bytes.length, 0);
    }
    final history = await audit.readVerifiedEvents();
    // A recovered/retried staging file must never resurrect a deleted incident.
    if (history.any(
      (event) =>
          event['operation'] == 'delete' &&
          event['incidentId'] == opened.logicalIncidentId,
    )) {
      return;
    }
    final historicalHashes = <String, String>{
      for (final event in history)
        for (final entry in (event['records'] as Map).entries)
          entry.key as String: entry.value as String,
    };
    if (historicalHashes[record.id] ==
            EvidenceAuditStore.recordDigest(record) &&
        !audit.records.values.any((r) => r.id == record.id)) {
      // Already admitted and replaced by migration: a staging retry is harmless.
      return;
    }
    if (historicalHashes.containsKey(record.id) &&
        historicalHashes[record.id] !=
            EvidenceAuditStore.recordDigest(record)) {
      if (record.schemaVersion != 1) {
        throw const CryptoFailure('Conflicting immutable evidence version');
      }
      // Old service checkpoints reused an incident ID. Preserve recovered v1
      // snapshots under deterministic version IDs rather than overwriting them.
      final encoded = EvidenceEnvelope.encode(record);
      encoded['incident'] = opened.logicalIncidentId;
      encoded['id'] = 'legacy-${EvidenceAuditStore.recordDigest(record)}';
      record = EvidenceEnvelope.decode(Map<String, dynamic>.from(encoded));
    }
    if (record.schemaVersion == 2 &&
        opened.previousVersionId.isNotEmpty &&
        !historicalHashes.containsKey(opened.previousVersionId) &&
        !(await Future.wait(
          audit.records.values.map((r) => codec.open(r, audit.key)),
        )).any((r) => r.id == opened.previousVersionId)) {
      throw const CryptoFailure('Missing predecessor evidence version');
    }
    final existing = await Future.wait(
      audit.records.values.map((r) => codec.open(r, audit.key)),
    );
    await audit.insert(
      record,
      incidentId: opened.logicalIncidentId,
      isNewVersion: existing.any(
        (r) => r.logicalIncidentId == opened.logicalIncidentId,
      ),
    );
  }

  @override
  Future<void> insertRecord(EvidenceRecordModel record) =>
      _serialized(() async {
        final audit = await _open();
        await _insert(audit, record);
      });

  @override
  Future<List<EvidenceRecordModel>> fetchAllRecords() => _serialized(() async {
    final audit = await _open();
    return audit.records.values.toList();
  });

  @override
  Future<void> removeRecord(String id) => _serialized(() async {
    final audit = await _open();
    final codec = EvidenceEnvelope(cipher);
    final records = await Future.wait(
      audit.records.values.map((r) => codec.open(r, audit.key)),
    );
    final matches = records.where(
      (r) => r.id == id || r.logicalIncidentId == id,
    );
    if (matches.isEmpty) return;
    final incident = matches.first.logicalIncidentId;
    await audit.delete(
      records
          .where((r) => r.logicalIncidentId == incident)
          .map((r) => r.storageId.isEmpty ? r.id : r.storageId)
          .toList(),
      incidentId: incident,
    );
  });

  Future<List<Map<String, dynamic>>> readVerifiedAuditEvents() =>
      _serialized(() async {
        final audit = await _open();
        return audit.readVerifiedEvents();
      });
}
