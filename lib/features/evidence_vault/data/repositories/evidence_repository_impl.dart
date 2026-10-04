import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto_hash;
import 'package:uuid/uuid.dart';

import '../../../../core/crypto/cipher_manager.dart';
import '../../../../core/crypto/secure_key_storage.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/evidence_record.dart';
import '../../domain/entities/vault_stats.dart';
import '../../domain/repositories/evidence_repository.dart';
import '../datasources/evidence_local_datasource.dart';
import '../models/evidence_record_model.dart';

class EvidenceRepositoryImpl implements EvidenceRepository {
  final EvidenceLocalDataSource localDataSource;
  final CipherManager cipherManager;
  final SecureKeyStorage keyStorage;
  final Uuid _uuid;

  EvidenceRepositoryImpl({
    required this.localDataSource,
    required this.cipherManager,
    required this.keyStorage,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  @override
  Future<void> saveEncryptedEvidence({
    required Uint8List rawAudioBytes,
    required String predictionLabel,
    required double confidenceScore,
    required Map<String, double> gpsCoordinates,
  }) async {
    final secretKey = await keyStorage.getOrCreateMasterKey();

    final encryptedPayload = await cipherManager.encryptInMemory(
      rawAudioBytes: rawAudioBytes,
      secretKey: secretKey,
    );

    final digest = crypto_hash.sha256.convert(encryptedPayload.cipherBytes);
    final integrityHash = digest.toString();

    final recordModel = EvidenceRecordModel(
      id: _uuid.v4(),
      timestamp: DateTime.now().toUtc(),
      predictionLabel: predictionLabel,
      confidenceScore: confidenceScore,
      gpsCoordinates: gpsCoordinates,
      encryptedAudioBlob: encryptedPayload.cipherBytes,
      ivBytes: encryptedPayload.ivBytes,
      authTag: encryptedPayload.authTag,
      integrityHash: integrityHash,
    );

    await localDataSource.insertRecord(recordModel);
  }

  @override
  Future<List<EvidenceRecord>> getAllEvidenceRecords() async {
    final models = await localDataSource.fetchAllRecords();
    models.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<Uint8List> getDecryptedAudioBytes(EvidenceRecord record) async {
    final currentDigest =
        crypto_hash.sha256.convert(record.encryptedAudioBlob).toString();
    if (currentDigest != record.integrityHash) {
      throw const CryptoFailure(
          'The integrity of the encrypted audio blob has been compromised');
    }

    final secretKey = await keyStorage.getOrCreateMasterKey();

    return await cipherManager.decryptInMemory(
      cipherBytes: record.encryptedAudioBlob,
      ivBytes: record.ivBytes,
      authTag: record.authTag,
      secretKey: secretKey,
    );
  }

  @override
  Future<void> deleteEvidenceRecord(String id) async {
    await localDataSource.removeRecord(id);
  }

  @override
  Future<VaultStats> getVaultStats() async {
    final models = await localDataSource.fetchAllRecords();
    int totalBytes = 0;

    for (final model in models) {
      // Suma el peso del blob cifrado persistido en Hive
      totalBytes += model.encryptedAudioBlob.length;
    }

    return VaultStats(
      totalCount: models.length,
      totalBytes: totalBytes,
    );
  }
}