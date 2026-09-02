import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../../evidence_vault/domain/usecases/save_encrypted_evidence_usecase.dart';
import '../../domain/usecases/process_audio_stream_usecase.dart';
import '../isolates/audio_processing_isolate.dart';

enum MonitoringStatus { idle, initializing, active, paused, error }

class MonitoringController extends ChangeNotifier {
  final ProcessAudioStreamUseCase _processAudioUseCase;
  final SaveEncryptedEvidenceUseCase _saveEvidenceUseCase;

  AudioProcessingIsolate? _audioIsolate;
  MonitoringStatus _status = MonitoringStatus.idle;
  String? _errorMessage;
  String _lastDetectedClass = 'None';

  MonitoringController({
    required ProcessAudioStreamUseCase processAudioUseCase,
    required SaveEncryptedEvidenceUseCase saveEvidenceUseCase,
  })  : _processAudioUseCase = processAudioUseCase,
        _saveEvidenceUseCase = saveEvidenceUseCase;

  MonitoringStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String get lastDetectedClass => _lastDetectedClass;
  bool get isMonitoring => _status == MonitoringStatus.active;

  /// Start the passive monitoring service, initializing the isolate and audio stream
  Future<void> startMonitoring() async {
    if (_status == MonitoringStatus.active) return;

    _status = MonitoringStatus.initializing;
    _errorMessage = null;
    notifyListeners();

    try {
      final rootToken = RootIsolateToken.instance;
      if (rootToken == null) {
        throw Exception('Could not obtain RootIsolateToken. Ensure this is called from the main isolate');
      }

      _audioIsolate = AudioProcessingIsolate(
        onIncidentDetected: _handleIncidentDetected,
        onError: (err) {
          _errorMessage = err;
          _status = MonitoringStatus.error;
          notifyListeners();
        },
      );

      await _audioIsolate!.spawn(
        rootToken: rootToken,
        processUseCase: _processAudioUseCase,
      );

      _status = MonitoringStatus.active;
      notifyListeners();
    } catch (e) {
      _status = MonitoringStatus.error;
      _errorMessage = 'Error al arrancar servicio de monitoreo: $e';
      notifyListeners();
    }
  }

  /// Stop the passive monitoring service, terminating the isolate and audio stream
  Future<void> pauseMonitoring() async {
    if (_status != MonitoringStatus.active) return;

    await _audioIsolate?.stop();
    _status = MonitoringStatus.paused;
    notifyListeners();
  }

  /// Manually dispose of the isolate and clean up resources
  Future<void> _handleIncidentDetected(IncidentDetectionPayload payload) async {
    _lastDetectedClass = payload.result.label;
    notifyListeners();

    // Get current GPS coordinates
    final coordinates = await _captureCurrentCoordinates();

    // Persist the evidence using the SaveEncryptedEvidenceUseCase
    await _saveEvidenceUseCase(
      SaveEncryptedEvidenceParams(
        rawAudioBytes: payload.window.rawPcmBytes,
        predictionLabel: payload.result.label,
        confidenceScore: payload.result.confidence,
        gpsCoordinates: coordinates,
      ),
    );
  }

  /// Extract the current GPS coordinates, returning a default of (0.0, 0.0) if unavailable
  Future<Map<String, double>> _captureCurrentCoordinates() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return {'lat': 0.0, 'lng': 0.0};
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return {'lat': 0.0, 'lng': 0.0};
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      return {'lat': position.latitude, 'lng': position.longitude};
    } catch (_) {
      return {'lat': 0.0, 'lng': 0.0};
    }
  }

  @override
  void dispose() {
    _audioIsolate?.dispose();
    super.dispose();
  }
}