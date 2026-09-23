import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:serene/features/audio_monitoring/data/datasources/audio_stream_datasource.dart';
import 'package:serene/features/audio_monitoring/data/datasources/tflite_inference_engine.dart';
import 'package:serene/features/audio_monitoring/data/repositories/monitoring_repository_impl.dart';
import 'package:serene/features/audio_monitoring/domain/repositories/monitoring_repository.dart';
import 'package:serene/features/audio_monitoring/domain/usecases/process_audio_stream_usecase.dart';
import 'package:serene/features/audio_monitoring/presentation/controllers/monitoring_controller.dart';
import 'package:serene/features/evidence_vault/presentation/controllers/evidence_controller.dart';
import '../core/crypto/cipher_manager.dart';
import '../core/crypto/secure_key_storage.dart';
import '../core/models/app_settings.dart';
import '../app/controllers/app_settings_controller.dart';
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

  // App Settings
  final appSettingsBox = await Hive.openBox<AppSettings>('appSettings');
  sl.registerLazySingleton<AppSettingsController>(
    () => AppSettingsController(box: appSettingsBox),
  );

  // FEATURE: Evidence Vault
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

  // Controllers - Register as a singleton for persistence across screens
  sl.registerSingleton<EvidenceController>(
    EvidenceController(
      evidenceRepository: sl(),
      getDecryptedAudioUseCase: sl(),
    ),
  );

  // FEATURE: Audio Monitoring
  // Data sources
  sl.registerLazySingleton<TfliteInferenceEngine>(() => TfliteInferenceEngine());
  sl.registerLazySingleton<AudioStreamDataSource>(() => AudioStreamDataSourceImpl());

  // Repositories
  sl.registerLazySingleton<MonitoringRepository>(
    () => MonitoringRepositoryImpl(
      audioStreamDataSource: sl(),
      inferenceEngine: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => ProcessAudioStreamUseCase(sl()));

  // Controllers
  sl.registerFactory<MonitoringController>(
    () => MonitoringController(
      processAudioUseCase: sl(),
      saveEvidenceUseCase: sl(),
    ),
  );
}