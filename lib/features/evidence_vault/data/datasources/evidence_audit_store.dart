import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/crypto/cipher_manager.dart';
import '../../../../core/crypto/secure_key_storage.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/evidence_storage_guard.dart';
import '../models/evidence_envelope.dart';
import '../models/evidence_record_model.dart';

enum AuditWriteStage {
  walFlushed,
  pendingAnchored,
  eventFlushed,
  recordsFlushed,
  committed,
}

/// UI isolate is the sole writer. Background engines only stage encrypted files.
/// A small secure-storage anchor authenticates the head and any pending WAL.
class EvidenceAuditStore {
  static const boxName = 'evidence_audit_v2';
  static const genesis =
      '0000000000000000000000000000000000000000000000000000000000000000';
  final Box<EvidenceRecordModel> records;
  final Box<dynamic> events;
  final SecureKeyStorage keys;
  final SecretKey key;
  final CipherManager cipher;
  final EvidenceStorageGuard storageGuard;
  final Future<void> Function(AuditWriteStage)? onStage;

  EvidenceAuditStore({
    required this.records,
    required this.events,
    required this.keys,
    required this.key,
    required this.cipher,
    required this.storageGuard,
    this.onStage,
  });

  static String digest(Object? data) =>
      hashing.sha256.convert(utf8.encode(canonicalJson(data))).toString();
  static String recordDigest(EvidenceRecordModel record) {
    EvidenceEnvelope.requireSealed(record);
    return digest(EvidenceEnvelope.encode(record));
  }

  Future<Map<String, dynamic>> _state() async {
    final raw = await keys.readAuditState();
    if (raw == null) {
      throw const CryptoFailure('Missing protected audit anchor');
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<Map<String, Object?>> _encrypt(Object value, List<int> aad) async {
    final bytes = Uint8List.fromList(utf8.encode(canonicalJson(value)));
    try {
      final payload = await cipher.encryptInMemory(
        rawAudioBytes: bytes,
        secretKey: key,
        aad: aad,
      );
      return {
        'cipher': base64Encode(payload.cipherBytes),
        'nonce': base64Encode(payload.ivBytes),
        'tag': base64Encode(payload.authTag),
      };
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Map<String, dynamic>> _decrypt(Map data, List<int> aad) async {
    final bytes = await cipher.decryptInMemory(
      cipherBytes: base64Decode(data['cipher'] as String),
      ivBytes: base64Decode(data['nonce'] as String),
      authTag: base64Decode(data['tag'] as String),
      secretKey: key,
      aad: aad,
    );
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static List<int> _eventAad(int sequence, String previous) => utf8.encode(
    canonicalJson({
      'purpose': 'serene-audit',
      'sequence': sequence,
      'previous': previous,
    }),
  );
  static List<int> _walAad(String id) => utf8.encode('serene-audit-wal-v2:$id');

  Future<void> initializeAndVerify() async {
    if (await keys.readAuditState() == null) {
      if (events.keys.any((key) => key is int) ||
          records.values.any((record) => record.schemaVersion != 1)) {
        throw const CryptoFailure(
          'Audit anchor missing for protected evidence',
        );
      }
      final baseline = records.values.toList();
      if (baseline.isEmpty) {
        await keys.writeAuditState(
          canonicalJson({'sequence': 0, 'hash': genesis}),
        );
      } else {
        // Existing v1 records are anchored as a baseline, never claimed as v2.
        await _commit(
          {'sequence': 0, 'hash': genesis},
          'legacy_import',
          baseline,
          const [],
          incidentId: '',
        );
      }
    }
    var state = await _state();
    await _verifyHistory(state, compareRecords: state['pending'] == null);
    if (state['pending'] != null) {
      await _recover(state);
      state = await _state();
      await _verifyHistory(state, compareRecords: true);
    }
    // Orphan WALs precede the protected pending marker: no commit was accepted.
    final orphans = events.keys
        .where((key) => key is String && key.startsWith('wal:'))
        .toList();
    for (final orphan in orphans) {
      await events.delete(orphan);
    }
    await _retryMaintenance(await _state());
  }

  Future<void> _verifyHistory(
    Map<String, dynamic> state, {
    required bool compareRecords,
  }) async {
    final head = state['sequence'] as int;
    var previous = genesis;
    final expected = <String, String>{};
    for (var sequence = 1; sequence <= head; sequence++) {
      final event = events.get(sequence);
      if (event is! Map ||
          event['sequence'] != sequence ||
          event['previous'] != previous) {
        throw const CryptoFailure('Audit chain discontinuity');
      }
      final body = await _decrypt(
        event['payload'] as Map,
        _eventAad(sequence, previous),
      );
      for (final entry in (body['records'] as Map).entries) {
        if (expected.containsKey(entry.key)) {
          throw const CryptoFailure('Audit attempted to overwrite a version');
        }
        expected[entry.key as String] = entry.value as String;
      }
      for (final id in body['deleted'] as List) {
        if (expected.remove(id) == null) {
          throw const CryptoFailure(
            'Audit deletion references missing evidence',
          );
        }
      }
      previous = digest(event);
    }
    if (previous != state['hash']) {
      throw const CryptoFailure('Audit head does not match protected anchor');
    }
    final pending = state['pending'] as Map?;
    for (final sequence in events.keys.whereType<int>()) {
      if (sequence < 1 ||
          sequence > head &&
              (pending == null ||
                  sequence != pending['sequence'] ||
                  digest(events.get(sequence)) != pending['eventHash'])) {
        throw const CryptoFailure('Unexpected audit event');
      }
    }
    if (!compareRecords) return;
    final actual = <String, String>{};
    for (final record in records.values) {
      if (actual.containsKey(record.id)) {
        throw const CryptoFailure('Duplicate persisted version');
      }
      actual[record.id] = recordDigest(record);
    }
    if (canonicalJson(actual) != canonicalJson(expected)) {
      throw const CryptoFailure(
        'Persisted evidence differs from authenticated audit',
      );
    }
  }

  Future<void> insert(
    EvidenceRecordModel record, {
    required String incidentId,
    required bool isNewVersion,
  }) async {
    final existing = records.values.where((r) => r.id == record.id);
    if (existing.isNotEmpty) {
      if (recordDigest(existing.first) != recordDigest(record)) {
        throw const CryptoFailure('An immutable evidence version was replaced');
      }
      return; // Retry/import of the exact same immutable version is idempotent.
    }
    await _commit(
      await _state(),
      isNewVersion
          ? 'new_version'
          : record.schemaVersion == 1
          ? 'legacy_import'
          : 'create',
      [record],
      const [],
      incidentId: incidentId,
    );
  }

  Future<void> delete(List<String> ids, {required String incidentId}) async {
    if (ids.isEmpty) return;
    await _commit(
      await _state(),
      'delete',
      const [],
      ids,
      incidentId: incidentId,
    );
  }

  /// Replace a legacy container through the same recoverable transaction as writes.
  Future<void> migrate(
    EvidenceRecordModel old,
    EvidenceRecordModel sealed, {
    required String incidentId,
  }) async {
    await _commit(
      await _state(),
      'privacy_migration',
      [sealed],
      [old.id],
      incidentId: incidentId,
    );
  }

  Future<void> _commit(
    Map<String, dynamic> state,
    String operation,
    List<EvidenceRecordModel> inserted,
    List<String> deleted, {
    required String incidentId,
  }) async {
    final sequence = (state['sequence'] as int) + 1;
    final previous = state['hash'] as String;
    final id = const Uuid().v4();
    final event = <String, Object?>{
      'sequence': sequence,
      'previous': previous,
      'payload': await _encrypt({
        'eventId': id,
        'sequence': sequence,
        'previousEventHash': previous,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'operation': operation,
        'incidentId': incidentId,
        'records': {
          for (final record in inserted) record.id: recordDigest(record),
        },
        'deleted': deleted,
      }, _eventAad(sequence, previous)),
    };
    final wal = await _encrypt({
      'event': event,
      'inserted': inserted.map(EvidenceEnvelope.encode).toList(),
      'deleted': deleted,
    }, _walAad(id));
    // Allow audited deletion even below the admission reserve. Never prune
    // existing evidence automatically to admit a new recording.
    final path = records.path!;
    final bytesNeeded =
        utf8.encode(canonicalJson(wal)).length * 2 +
        inserted.fold<int>(
          0,
          (sum, record) => sum + record.encryptedAudioBlob.length * 2,
        ) +
        64 * 1024;
    await storageGuard.ensureWrite(
      File(path).parent.path,
      bytesNeeded,
      deletion: operation == 'delete' || operation == 'legacy_import',
    );
    await events.put('wal:$id', wal);
    await events.flush();
    await onStage?.call(AuditWriteStage.walFlushed);
    final pendingState = <String, dynamic>{
      ...state,
      'pending': {
        'id': id,
        'sequence': sequence,
        'eventHash': digest(event),
        'walHash': digest(wal),
      },
    };
    await keys.writeAuditState(canonicalJson(pendingState));
    await onStage?.call(AuditWriteStage.pendingAnchored);
    await _recover(pendingState);
  }

  Future<void> _recover(Map<String, dynamic> state) async {
    final pending = state['pending'] as Map;
    final id = pending['id'] as String;
    final wal = events.get('wal:$id');
    if (wal is! Map || digest(wal) != pending['walHash']) {
      throw const CryptoFailure(
        'Missing or modified pending audit transaction',
      );
    }
    final transaction = await _decrypt(wal, _walAad(id));
    final event = transaction['event'] as Map;
    final sequence = pending['sequence'] as int;
    if (sequence != (state['sequence'] as int) + 1 ||
        event['previous'] != state['hash'] ||
        digest(event) != pending['eventHash']) {
      throw const CryptoFailure('Invalid pending audit transaction');
    }
    final existing = events.get(sequence);
    if (existing != null && digest(existing) != pending['eventHash']) {
      throw const CryptoFailure('Pending event conflicts with audit history');
    }
    if (existing == null) await events.put(sequence, event);
    await events.flush();
    await onStage?.call(AuditWriteStage.eventFlushed);
    for (final encoded in transaction['inserted'] as List) {
      final record = EvidenceEnvelope.decode(
        Map<String, dynamic>.from(encoded as Map),
      );
      // Legacy baseline keeps its original key; new versions use their own ID.
      final existingRecords = records.values.where((r) => r.id == record.id);
      if (existingRecords.isNotEmpty) {
        if (recordDigest(existingRecords.first) != recordDigest(record)) {
          throw const CryptoFailure(
            'Recovery conflicts with persisted evidence',
          );
        }
      } else {
        await records.put(record.id, record);
      }
    }
    final deleted = (transaction['deleted'] as List).cast<String>().toSet();
    final deleteKeys = records.keys
        .where((key) => deleted.contains(records.get(key)?.id))
        .toList();
    await records.deleteAll(deleteKeys);
    await records.flush();
    await onStage?.call(AuditWriteStage.recordsFlushed);
    final committedState = <String, dynamic>{
      'sequence': sequence,
      'hash': pending['eventHash'],
      'maintenancePending':
          deleted.isNotEmpty || state['maintenancePending'] == true,
    };
    await keys.writeAuditState(canonicalJson(committedState));
    await onStage?.call(AuditWriteStage.committed);
    await events.delete('wal:$id');
    await events.flush();
    await _retryMaintenance(committedState);
  }

  Future<void> _retryMaintenance(Map<String, dynamic> state) async {
    if (state['maintenancePending'] != true) return;
    if (await _compactAfterDeletion()) {
      // Housekeeping never changes the authenticated sequence or head digest.
      try {
        await keys.writeAuditState(
          canonicalJson({...state, 'maintenancePending': false}),
        );
      } catch (_) {
        /* Committed deletion remains successful; retry on next open. */
      }
    }
  }

  Future<bool> _compactAfterDeletion() async {
    // Compaction rewrites live frames. It is best effort after the committed
    // logical deletion and cannot establish forensic erasure.
    var completed = true;
    for (final box in [records, events]) {
      final path = box.path;
      if (path == null) continue;
      try {
        final file = File(path);
        if (await storageGuard.canCompact(
          file.parent.path,
          await file.length(),
        )) {
          await box.compact();
          await box.flush();
        } else {
          completed = false;
        }
      } catch (_) {
        completed = false;
        // Do not report an already committed deletion as unsuccessful.
        // A later verified opening can attempt maintenance again.
      }
    }
    return completed;
  }

  Future<List<Map<String, dynamic>>> readVerifiedEvents() async {
    await initializeAndVerify();
    final state = await _state();
    final result = <Map<String, dynamic>>[];
    var previous = genesis;
    for (var sequence = 1; sequence <= (state['sequence'] as int); sequence++) {
      final event = events.get(sequence) as Map;
      result.add(
        await _decrypt(event['payload'] as Map, _eventAad(sequence, previous)),
      );
      previous = digest(event);
    }
    return result;
  }
}
