import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/core/constants/hive_constants.dart';
import 'package:serene/core/crypto/cipher_manager.dart';
import 'package:serene/core/crypto/secure_key_storage.dart';
import 'package:serene/core/errors/failures.dart';
import 'package:serene/features/evidence_vault/data/datasources/evidence_local_datasource.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_record_model.dart';
import 'package:serene/features/evidence_vault/data/repositories/evidence_repository_impl.dart';
import 'package:serene/features/evidence_vault/domain/entities/evidence_record.dart';
import 'package:serene/features/evidence_vault/domain/usecases/get_decrypted_audio_stream_usecase.dart';
import 'package:serene/features/evidence_vault/domain/usecases/save_encrypted_evidence_usecase.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late Directory tempDir;
  late MockSecureStorage mockSecureStorage;
  late SecureKeyStorage keyStorage;
  late CipherManager cipherManager;
  late EvidenceLocalDataSource localDataSource;
  late EvidenceRepositoryImpl repository;
  late SaveEncryptedEvidenceUseCase saveUseCase;
  late GetDecryptedAudioStreamUseCase getUseCase;
  
  // Shared in-memory map to simulate secure storage for testing purposes
  final Map<String, String> inMemorySecureStore = {};

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_integration_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(HiveConstants.evidenceRecordTypeId)) {
      Hive.registerAdapter(EvidenceRecordModelAdapter());
    }

    mockSecureStorage = MockSecureStorage();
    when(() => mockSecureStorage.read(key: any(named: 'key')))
        .thenAnswer((invocation) async => inMemorySecureStore[invocation.namedArguments[#key] as String]);
    when(() => mockSecureStorage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((invocation) async {
      inMemorySecureStore[invocation.namedArguments[#key] as String] = invocation.namedArguments[#value] as String;
    });

    keyStorage = SecureKeyStorage(secureStorage: mockSecureStorage);
    cipherManager = CipherManager();
    localDataSource = EvidenceLocalDataSourceImpl();

    repository = EvidenceRepositoryImpl(
      localDataSource: localDataSource,
      cipherManager: cipherManager,
      keyStorage: keyStorage,
    );

    saveUseCase = SaveEncryptedEvidenceUseCase(repository);
    getUseCase = GetDecryptedAudioStreamUseCase(repository);
  });

  tearDown(() async {
    await Hive.close();
    inMemorySecureStore.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('It should encrypt and decrypt audio data correctly', () async {
    final rawPcmAudio = Uint8List.fromList(List.generate(1000, (i) => i % 256));

    // Save the evidence record
    await saveUseCase(SaveEncryptedEvidenceParams(
      rawAudioBytes: rawPcmAudio,
      predictionLabel: 'verbal_violence',
      confidenceScore: 0.92,
      gpsCoordinates: {'lat': -12.05, 'lng': -77.08},
    ));

    // Retrieve the saved record from the repository
    final records = await repository.getAllEvidenceRecords();
    expect(records.length, equals(1));
    final savedRecord = records.first;

    // Verify that the encrypted audio blob is not the same as the raw PCM audio
    expect(savedRecord.encryptedAudioBlob, isNot(equals(rawPcmAudio)));
    expect(savedRecord.integrityHash.isNotEmpty, isTrue);

    // Decrypt the audio data and verify it matches the original raw PCM audio
    final decryptedPcm = await getUseCase(savedRecord);
    expect(decryptedPcm, equals(rawPcmAudio));
  });

  test('It should fail to decrypt tampered evidence records', () async {
    final tamperedRecord = EvidenceRecord(
      id: 'corrupted-record',
      timestamp: DateTime.now(),
      predictionLabel: 'physical_violence',
      confidenceScore: 0.95,
      gpsCoordinates: {'lat': 0.0, 'lng': 0.0},
      encryptedAudioBlob: Uint8List.fromList([10, 20, 30]),
      ivBytes: Uint8List.fromList([1, 2]),
      authTag: Uint8List.fromList([3, 4]),
      integrityHash: 'invalid-hash', // Hash tampered to simulate corruption
    );

    expect(
      () async => await getUseCase(tamperedRecord),
      throwsA(isA<CryptoFailure>()),
    );
  });
}