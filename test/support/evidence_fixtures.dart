import 'dart:typed_data';

import 'package:serene/core/crypto/cipher_manager.dart';
import 'package:serene/features/evidence_vault/data/datasources/evidence_local_datasource.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_envelope.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_record_model.dart';
import 'package:serene/features/evidence_vault/data/repositories/evidence_repository_impl.dart';
import 'package:serene/features/evidence_vault/domain/entities/evidence_record.dart';

import 'memory_evidence_keys.dart';

EvidenceRepositoryImpl testRepository(
  EvidenceLocalDataSource source,
  MemoryEvidenceKeys keys,
) => EvidenceRepositoryImpl(
  localDataSource: source,
  keyStorage: keys,
  cipherManager: CipherManager(),
  appVersion: '1.2.3+4',
  modelHashProvider: () async => 'a' * 64,
);

Future<EvidenceRecordModel> sealedFixture(
  MemoryEvidenceKeys keys, {
  String id = 'version-1',
  String incident = 'incident',
  int size = 100,
  int second = 1,
  String previous = '',
}) => EvidenceEnvelope(CipherManager()).seal(
  key: keys.secret,
  audio: Uint8List.fromList(List.generate(size, (i) => i % 256)),
  metadataRecord: EvidenceRecord(
    id: id,
    incidentId: incident,
    schemaVersion: 2,
    timestamp: DateTime.utc(2026, 1, 1),
    savedAt: DateTime.utc(2026, 1, 1, 0, 0, second),
    previousVersionId: previous,
    predictionLabel: 'sensitive-label',
    confidenceScore: .95,
    gpsCoordinates: const {'lat': -12.05, 'lng': -77.08},
    appVersion: '1.2.3+4',
    modelHash: 'a' * 64,
    audioFormat: 'pcm_s16le;sampleRate=16000;channels=1',
    encryptedAudioBlob: Uint8List(0),
    ivBytes: Uint8List(0),
    authTag: Uint8List(0),
    integrityHash: '',
  ),
);
