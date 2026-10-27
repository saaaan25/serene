import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto_hash;
import 'package:uuid/uuid.dart';

import '../../../../core/crypto/cipher_manager.dart';
import '../../../../core/crypto/secure_key_storage.dart';
import '../../../../core/crypto/evidence_provenance.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/evidence_record.dart';
import '../../domain/entities/vault_stats.dart';
import '../../domain/repositories/evidence_repository.dart';
import '../datasources/evidence_local_datasource.dart';
import '../models/evidence_record_model.dart';
import '../models/evidence_envelope.dart';

class EvidenceRepositoryImpl implements EvidenceRepository {
  final EvidenceLocalDataSource localDataSource;
  final CipherManager cipherManager;
  final SecureKeyStorage keyStorage;
  final Uuid _uuid;
  final Future<String> Function() modelHashProvider;
  final Future<String> Function() appVersionProvider;
  final Map<String, String> _previousVersions = {};
  Future<void> _saving = Future.value();
  DateTime? _lastSavedAt;

  EvidenceRepositoryImpl({
    required this.localDataSource,
    required this.cipherManager,
    required this.keyStorage,
    Uuid? uuid,
    Future<String> Function()? modelHashProvider,
    String? appVersion,
  }) : _uuid = uuid ?? const Uuid(),
       modelHashProvider = modelHashProvider ?? EvidenceProvenance.modelHash,
       appVersionProvider = appVersion == null
           ? EvidenceProvenance.appVersion
           : (() async => appVersion);

  @override
  Future<void> saveEncryptedEvidence({
    required Uint8List rawAudioBytes,
    required String predictionLabel,
    required double confidenceScore,
    required Map<String, double> gpsCoordinates,
    String? evidenceId,
    DateTime? startedAt,
  }) {
    // Serialize snapshots so their predecessor and timestamps are unambiguous.
    final audio = Uint8List.fromList(rawAudioBytes);
    final gps = Map<String, double>.from(gpsCoordinates);
    final task = _saving.then((_) async {
      try {
        await _save(
          audio,
          predictionLabel,
          confidenceScore,
          gps,
          evidenceId,
          startedAt,
        );
      } finally {
        audio.fillRange(0, audio.length, 0);
      }
    });
    _saving = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> _save(
    Uint8List audio,
    String label,
    double confidence,
    Map<String, double> gps,
    String? evidenceId,
    DateTime? startedAt,
  ) async {
    final secretKey = await keyStorage.getOrCreateMasterKey();
    final incidentId = evidenceId ?? _uuid.v4();
    var savedAt = DateTime.now().toUtc();
    if (_lastSavedAt != null && !savedAt.isAfter(_lastSavedAt!)) {
      savedAt = _lastSavedAt!.add(const Duration(microseconds: 1));
    }
    final metadata = EvidenceRecord(
      id: _uuid.v4(),
      incidentId: incidentId,
      schemaVersion: 2,
      timestamp: (startedAt ?? savedAt).toUtc(),
      savedAt: savedAt,
      previousVersionId: _previousVersions[incidentId] ?? '',
      predictionLabel: label,
      confidenceScore: confidence,
      gpsCoordinates: gps,
      appVersion: await appVersionProvider(),
      modelHash: await modelHashProvider(),
      audioFormat: 'pcm_s16le;sampleRate=${AppConstants.sampleRate};channels=1',
      encryptedAudioBlob: Uint8List(0),
      ivBytes: Uint8List(0),
      authTag: Uint8List(0),
      integrityHash: '',
    );
    final recordModel = await EvidenceEnvelope(
      cipherManager,
    ).seal(metadataRecord: metadata, audio: audio, key: secretKey);
    await localDataSource.insertRecord(recordModel);
    _previousVersions[incidentId] = metadata.id;
    _lastSavedAt = savedAt;
  }

  @override
  Future<List<EvidenceRecord>> getAllEvidenceRecords() async {
    final models = await localDataSource.fetchAllRecords();
    final records = await _openModels(models);
    final latest = <String, EvidenceRecord>{};
    for (final record in records) {
      final old = latest[record.logicalIncidentId];
      if (old == null ||
          (record.savedAt ?? record.timestamp).isAfter(
            old.savedAt ?? old.timestamp,
          ) ||
          (record.savedAt ?? record.timestamp).isAtSameMomentAs(
                old.savedAt ?? old.timestamp,
              ) &&
              record.encryptedAudioBlob.length >
                  old.encryptedAudioBlob.length) {
        latest[record.logicalIncidentId] = record;
      }
    }
    return latest.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<List<EvidenceRecord>> _openModels(
    List<EvidenceRecordModel> models,
  ) async {
    if (models.isEmpty) return [];
    final key = await keyStorage.getOrCreateMasterKey();
    final codec = EvidenceEnvelope(cipherManager);
    return Future.wait(models.map((model) => codec.open(model, key)));
  }

  @override
  Future<Uint8List> getDecryptedAudioBytes(EvidenceRecord record) async {
    if (record.schemaVersion == 2) {
      await _verifyPersisted(record);
      final key = await keyStorage.getOrCreateMasterKey();
      final authenticated = await EvidenceEnvelope(
        cipherManager,
      ).open(EvidenceRecordModel.fromEntity(record), key);
      final aad = canonicalJson(EvidenceEnvelope.metadata(record));
      if (aad != canonicalJson(EvidenceEnvelope.metadata(authenticated))) {
        throw const CryptoFailure(
          'Authenticated evidence metadata was modified',
        );
      }
      return cipherManager.decryptInMemory(
        cipherBytes: record.encryptedAudioBlob,
        ivBytes: record.ivBytes,
        authTag: record.authTag,
        secretKey: key,
        aad: utf8.encode(aad),
      );
    }
    if (record.schemaVersion != 1) {
      throw const CryptoFailure('Unsupported evidence schema');
    }
    final currentDigest = crypto_hash.sha256
        .convert(record.encryptedAudioBlob)
        .toString();
    if (currentDigest != record.integrityHash) {
      throw const CryptoFailure(
        'The integrity of the encrypted audio blob has been compromised',
      );
    }

    final secretKey = await keyStorage.getOrCreateMasterKey();

    await _verifyPersisted(record);

    return await cipherManager.decryptInMemory(
      cipherBytes: record.encryptedAudioBlob,
      ivBytes: record.ivBytes,
      authTag: record.authTag,
      secretKey: secretKey,
    );
  }

  Future<void> _verifyPersisted(EvidenceRecord record) async {
    final persisted = (await localDataSource.fetchAllRecords()).where(
      (r) => r.id == (record.storageId.isEmpty ? record.id : record.storageId),
    );
    if (persisted.isEmpty ||
        canonicalJson(EvidenceEnvelope.encode(persisted.first)) !=
            canonicalJson(
              EvidenceEnvelope.encode(EvidenceRecordModel.fromEntity(record)),
            )) {
      throw const CryptoFailure(
        'Evidence is missing or differs from its audited version',
      );
    }
  }

  @override
  Future<void> deleteEvidenceRecord(String id) async {
    final records = await _openModels(await localDataSource.fetchAllRecords());
    final matches = records.where(
      (r) => r.id == id || r.logicalIncidentId == id,
    );
    if (matches.isEmpty) return;
    // The data source deletes the incident in one recoverable transaction.
    await localDataSource.removeRecord(matches.first.id);
  }

  @override
  Future<VaultStats> getVaultStats() async {
    final models = await localDataSource.fetchAllRecords();
    int totalBytes = 0;

    for (final model in models) {
      // Suma el peso del blob cifrado persistido en Hive
      totalBytes += model.encryptedAudioBlob.length;
    }

    final records = await _openModels(models);
    return VaultStats(
      totalCount: records.map((r) => r.logicalIncidentId).toSet().length,
      totalBytes: totalBytes,
    );
  }
}
