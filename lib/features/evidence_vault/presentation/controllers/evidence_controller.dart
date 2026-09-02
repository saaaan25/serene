import 'package:flutter/foundation.dart';
import '../../domain/entities/evidence_record.dart';
import '../../domain/repositories/evidence_repository.dart';
import '../../domain/usecases/get_decrypted_audio_stream_usecase.dart';

enum VaultState { loading, success, error, empty }

class EvidenceController extends ChangeNotifier {
  final EvidenceRepository _evidenceRepository;
  final GetDecryptedAudioStreamUseCase _getDecryptedAudioUseCase;

  VaultState _state = VaultState.loading;
  List<EvidenceRecord> _evidenceList = [];
  String? _errorMessage;

  EvidenceController({
    required EvidenceRepository evidenceRepository,
    required GetDecryptedAudioStreamUseCase getDecryptedAudioUseCase,
  })  : _evidenceRepository = evidenceRepository,
        _getDecryptedAudioUseCase = getDecryptedAudioUseCase;

  VaultState get state => _state;
  List<EvidenceRecord> get evidenceList => _evidenceList;
  String? get errorMessage => _errorMessage;

  /// Loads all evidence records from the repository and updates the state accordingly
  Future<void> fetchEvidenceRecords() async {
    _state = VaultState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final records = await _evidenceRepository.getAllEvidenceRecords();
      _evidenceList = records;

      _state = _evidenceList.isEmpty ? VaultState.empty : VaultState.success;
      notifyListeners();
    } catch (e) {
      _state = VaultState.error;
      _errorMessage = 'Error: $e';
      notifyListeners();
    }
  }

  /// Decrypts the audio stream of a given evidence record using the GetDecryptedAudioStreamUseCase
  Future<Uint8List> getDecryptedAudio(EvidenceRecord record) async {
    try {
      return await _getDecryptedAudioUseCase(record);
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  /// Deletes an evidence record by its ID and updates the state accordingly
  Future<void> deleteRecord(String id) async {
    try {
      await _evidenceRepository.deleteEvidenceRecord(id);
      _evidenceList.removeWhere((item) => item.id == id);
      _state = _evidenceList.isEmpty ? VaultState.empty : VaultState.success;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error: $e';
      notifyListeners();
    }
  }
}