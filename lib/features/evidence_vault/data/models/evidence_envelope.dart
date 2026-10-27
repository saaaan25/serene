import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as hashing;
import 'package:uuid/uuid.dart';

import '../../../../core/crypto/cipher_manager.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/evidence_record.dart';
import 'evidence_record_model.dart';

/// Canonical JSON: recursively sorted keys, UTC dates supplied by the caller.
String canonicalJson(Object? value) {
  Object? normalize(Object? item) {
    if (item is Map) {
      return SplayTreeMap<String, Object?>.from(
        item.map((key, value) => MapEntry(key as String, normalize(value))),
      );
    }
    if (item is List) return item.map(normalize).toList();
    return item;
  }

  return jsonEncode(normalize(value));
}

class EvidenceEnvelope {
  final CipherManager cipher;
  EvidenceEnvelope(this.cipher);

  static void requireSealed(EvidenceRecordModel record) {
    if (record.schemaVersion == 1) {
      if (record.metadataCiphertext != null ||
          record.metadataNonce != null ||
          record.metadataTag != null) {
        throw const CryptoFailure(
          'Encrypted metadata cannot be downgraded to legacy schema',
        );
      }
      return;
    }
    if (record.schemaVersion != 2 ||
        record.timestamp.microsecondsSinceEpoch != 0 ||
        record.predictionLabel.isNotEmpty ||
        record.confidenceScore != 0 ||
        record.gpsCoordinates.isNotEmpty ||
        record.incidentId.isNotEmpty ||
        record.appVersion.isNotEmpty ||
        record.modelHash.isNotEmpty ||
        record.audioFormat.isNotEmpty ||
        record.savedAt != null ||
        record.previousVersionId.isNotEmpty ||
        record.metadataCiphertext == null ||
        record.metadataNonce == null ||
        record.metadataTag == null) {
      throw const CryptoFailure(
        'Persistent v2 evidence must contain only sealed metadata',
      );
    }
  }

  static Map<String, Object?> metadata(EvidenceRecord record) => {
    if (record.storageId.isNotEmpty) 'storageId': record.storageId,
    'schema': record.schemaVersion,
    'id': record.id,
    'incident': record.incidentId,
    'timestamp': record.timestamp.toUtc().toIso8601String(),
    'savedAt': record.savedAt?.toUtc().toIso8601String(),
    'previousVersion': record.previousVersionId,
    'label': record.predictionLabel,
    'confidence': record.confidenceScore,
    'gps': record.gpsCoordinates,
    'appVersion': record.appVersion,
    'modelHash': record.modelHash,
    'audioFormat': record.audioFormat,
  };

  static List<int> metadataAad(String id) => utf8.encode(
    canonicalJson({'purpose': 'serene-metadata', 'schema': 2, 'id': id}),
  );

  static List<int> metadataBytes(EvidenceRecord record) =>
      utf8.encode(canonicalJson(metadata(record)));

  Future<EvidenceRecordModel> seal({
    required EvidenceRecord metadataRecord,
    required Uint8List audio,
    required SecretKey key,
    String? storageId,
  }) async {
    final reference = storageId ?? const Uuid().v4();
    final bytes = Uint8List.fromList(
      utf8.encode(
        canonicalJson({...metadata(metadataRecord), 'storageId': reference}),
      ),
    );
    try {
      final payload = await cipher.encryptInMemory(
        rawAudioBytes: audio,
        secretKey: key,
        aad: bytes,
      );
      final envelope = await cipher.encryptInMemory(
        rawAudioBytes: bytes,
        secretKey: key,
        aad: metadataAad(reference),
      );
      // All descriptive metadata lives exclusively inside the encrypted envelope.
      return EvidenceRecordModel(
        id: reference,
        schemaVersion: 2,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        predictionLabel: '',
        confidenceScore: 0,
        gpsCoordinates: const {},
        encryptedAudioBlob: payload.cipherBytes,
        ivBytes: payload.ivBytes,
        authTag: payload.authTag,
        integrityHash: hashing.sha256.convert(payload.cipherBytes).toString(),
        metadataCiphertext: envelope.cipherBytes,
        metadataNonce: envelope.ivBytes,
        metadataTag: envelope.authTag,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<EvidenceRecord> open(EvidenceRecordModel stored, SecretKey key) async {
    if (stored.integrityHash.isNotEmpty &&
        hashing.sha256.convert(stored.encryptedAudioBlob).toString() !=
            stored.integrityHash) {
      throw const CryptoFailure('Encrypted audio checksum mismatch');
    }
    if (stored.schemaVersion == 1) {
      requireSealed(stored);
      return stored.toEntity();
    }
    if (stored.schemaVersion != 2 ||
        stored.metadataCiphertext == null ||
        stored.metadataNonce == null ||
        stored.metadataTag == null) {
      throw const CryptoFailure('Unsupported or incomplete evidence envelope');
    }
    final bytes = await cipher.decryptInMemory(
      cipherBytes: stored.metadataCiphertext!,
      ivBytes: stored.metadataNonce!,
      authTag: stored.metadataTag!,
      secretKey: key,
      aad: metadataAad(stored.id),
    );
    try {
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (data['schema'] != 2 ||
          (data['storageId'] ?? data['id']) != stored.id ||
          canonicalJson(data) != utf8.decode(bytes)) {
        throw const CryptoFailure('Evidence metadata/header mismatch');
      }
      return EvidenceRecord(
        id: data['id'] as String,
        storageId: (data['storageId'] as String?) ?? '',
        schemaVersion: 2,
        incidentId: data['incident'] as String,
        timestamp: DateTime.parse(data['timestamp'] as String).toUtc(),
        savedAt: data['savedAt'] == null
            ? null
            : DateTime.parse(data['savedAt'] as String).toUtc(),
        previousVersionId: data['previousVersion'] as String,
        predictionLabel: data['label'] as String,
        confidenceScore: (data['confidence'] as num).toDouble(),
        gpsCoordinates: (data['gps'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        appVersion: data['appVersion'] as String,
        modelHash: data['modelHash'] as String,
        audioFormat: data['audioFormat'] as String,
        encryptedAudioBlob: stored.encryptedAudioBlob,
        ivBytes: stored.ivBytes,
        authTag: stored.authTag,
        integrityHash: stored.integrityHash,
        metadataCiphertext: stored.metadataCiphertext,
        metadataNonce: stored.metadataNonce,
        metadataTag: stored.metadataTag,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Shared persistence representation for Hive digests, staging and recovery.
  static Map<String, Object?> encode(EvidenceRecordModel record) => {
    'schema': record.schemaVersion,
    'id': record.id,
    if (record.schemaVersion == 1) ...metadata(record.toEntity()),
    'audio': base64Encode(record.encryptedAudioBlob),
    'iv': base64Encode(record.ivBytes),
    'tag': base64Encode(record.authTag),
    'hash': record.integrityHash,
    if (record.schemaVersion == 2) ...{
      'metadata': base64Encode(record.metadataCiphertext!),
      'metadataIv': base64Encode(record.metadataNonce!),
      'metadataTag': base64Encode(record.metadataTag!),
    },
  };

  static EvidenceRecordModel decode(Map<String, dynamic> data) {
    final schema = (data['schema'] as int?) ?? 1;
    if (schema != 1 && schema != 2) {
      throw const CryptoFailure('Unsupported evidence schema');
    }
    return EvidenceRecordModel(
      id: data['id'] as String,
      schemaVersion: schema,
      incidentId: schema == 1 ? (data['incident'] as String?) ?? '' : '',
      appVersion: schema == 1 ? (data['appVersion'] as String?) ?? '' : '',
      modelHash: schema == 1 ? (data['modelHash'] as String?) ?? '' : '',
      audioFormat: schema == 1 ? (data['audioFormat'] as String?) ?? '' : '',
      savedAt: schema == 1 && data['savedAt'] != null
          ? DateTime.parse(data['savedAt'] as String)
          : null,
      previousVersionId: schema == 1
          ? (data['previousVersion'] as String?) ?? ''
          : '',
      timestamp: schema == 1
          ? DateTime.parse(data['timestamp'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      predictionLabel: schema == 1 ? data['label'] as String : '',
      confidenceScore: schema == 1 ? (data['confidence'] as num).toDouble() : 0,
      gpsCoordinates: schema == 1
          ? (data['gps'] as Map).map(
              (k, v) => MapEntry(k as String, (v as num).toDouble()),
            )
          : const {},
      encryptedAudioBlob: base64Decode(data['audio'] as String),
      ivBytes: base64Decode(data['iv'] as String),
      authTag: base64Decode(data['tag'] as String),
      integrityHash: data['hash'] as String,
      metadataCiphertext: schema == 2
          ? base64Decode(data['metadata'] as String)
          : null,
      metadataNonce: schema == 2
          ? base64Decode(data['metadataIv'] as String)
          : null,
      metadataTag: schema == 2
          ? base64Decode(data['metadataTag'] as String)
          : null,
    );
  }
}
