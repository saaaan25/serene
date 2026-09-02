import 'package:get_it/get_it.dart';
import '../core/crypto/cipher_manager.dart';
import '../core/crypto/secure_key_storage.dart';
import '../features/evidence_vault/data/datasources/evidence_local_datasource.dart';
import '../features/evidence_vault/data/repositories/evidence_repository_impl.dart';
import '../features/evidence_vault/domain/repositories/evidence_repository.dart';
import '../features/evidence_vault/domain/usecases/get_decrypted_audio_stream_usecase.dart';
import '../features/evidence_vault/domain/usecases/save_encrypted_evidence_usecase.dart';

final sl = GetIt.instance;

Future<void> initServiceLocator() async {
  // Core
  sl.registerLazySingleton<SecureKeyStorage>(() => SecureKeyStorage());
  sl.registerLazySingleton<CipherManager>(() => CipherManager());

  // Evidence Vault
  // Data sources
  sl.registerLazySingleton<EvidenceLocalDataSource>(
    () => EvidenceLocalDataSourceImpl(),
  );

  // Repositories
  sl.registerLazySingleton<EvidenceRepository>(
    () => EvidenceRepositoryImpl(
      localDataSource: sl(),
      cipherManager: sl(),
      keyStorage: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => SaveEncryptedEvidenceUseCase(sl()));
  sl.registerLazySingleton(() => GetDecryptedAudioStreamUseCase(sl()));
}