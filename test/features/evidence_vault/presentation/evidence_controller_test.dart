import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/features/evidence_vault/domain/entities/evidence_record.dart';
import 'package:serene/features/evidence_vault/domain/repositories/evidence_repository.dart';
import 'package:serene/features/evidence_vault/domain/usecases/get_decrypted_audio_stream_usecase.dart';
import 'package:serene/features/evidence_vault/presentation/controllers/evidence_controller.dart';

class MockEvidenceRepository extends Mock implements EvidenceRepository {}

class MockGetDecryptedAudioStreamUseCase extends Mock
    implements GetDecryptedAudioStreamUseCase {}

void main() {
  late MockEvidenceRepository mockRepository;
  late MockGetDecryptedAudioStreamUseCase mockGetDecryptedUseCase;
  late EvidenceController controller;

  setUp(() {
    mockRepository = MockEvidenceRepository();
    mockGetDecryptedUseCase = MockGetDecryptedAudioStreamUseCase();

    controller = EvidenceController(
      evidenceRepository: mockRepository,
      getDecryptedAudioUseCase: mockGetDecryptedUseCase,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  final dummyRecord = EvidenceRecord(
    id: 'vault-uuid-001',
    timestamp: DateTime.now(),
    predictionLabel: 'verbal_violence',
    confidenceScore: 0.94,
    gpsCoordinates: const {'lat': -12.05, 'lng': -77.08},
    encryptedAudioBlob: Uint8List.fromList([1, 2, 3]),
    ivBytes: Uint8List.fromList([0, 1]),
    authTag: Uint8List.fromList([9, 9]),
    integrityHash: 'mock-sha256-hash',
  );

  group('Loading Evidence Records', () {
    test('It should initialize with an empty state', () async {
      when(() => mockRepository.getAllEvidenceRecords())
          .thenAnswer((_) async => []);

      await controller.fetchEvidenceRecords();

      expect(controller.state, equals(VaultState.empty));
      expect(controller.evidenceList, isEmpty);
      expect(controller.errorMessage, isNull);
      verify(() => mockRepository.getAllEvidenceRecords()).called(1);
    });

    test('It should transition to VaultState.success when there are indexed records', () async {
      when(() => mockRepository.getAllEvidenceRecords())
          .thenAnswer((_) async => [dummyRecord]);

      await controller.fetchEvidenceRecords();

      expect(controller.state, equals(VaultState.success));
      expect(controller.evidenceList.length, equals(1));
      expect(controller.evidenceList.first.id, equals('vault-uuid-001'));
      expect(controller.errorMessage, isNull);
    });

    test('It should transition to VaultState.error when an exception occurs in the repository', () async {
      when(() => mockRepository.getAllEvidenceRecords())
          .thenThrow(Exception('Error in loading evidence records'));

      await controller.fetchEvidenceRecords();

      expect(controller.state, equals(VaultState.error));
      expect(controller.errorMessage, contains('Error in loading evidence records'));
    });
  });

  group('User Actions', () {
    test('deleteRecord should remove the item and call the repository', () async {
      when(() => mockRepository.getAllEvidenceRecords())
          .thenAnswer((_) async => [dummyRecord]);
      when(() => mockRepository.deleteEvidenceRecord('vault-uuid-001'))
          .thenAnswer((_) async => Future.value());

      await controller.fetchEvidenceRecords();
      expect(controller.evidenceList.length, equals(1));

      await controller.deleteRecord('vault-uuid-001');

      expect(controller.evidenceList, isEmpty);
      expect(controller.state, equals(VaultState.empty));
      verify(() => mockRepository.deleteEvidenceRecord('vault-uuid-001')).called(1);
    });

    test('getDecryptedAudio should return the raw decrypted bytes in RAM', () async {
      final expectedBytes = Uint8List.fromList([10, 20, 30, 40]);

      when(() => mockGetDecryptedUseCase.call(dummyRecord))
          .thenAnswer((_) async => expectedBytes);

      final result = await controller.getDecryptedAudio(dummyRecord);

      expect(result, equals(expectedBytes));
      verify(() => mockGetDecryptedUseCase.call(dummyRecord)).called(1);
    });
  });
}