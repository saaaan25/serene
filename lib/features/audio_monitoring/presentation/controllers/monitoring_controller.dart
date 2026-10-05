import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/services/monitoring_foreground_service.dart';
import '../../../evidence_vault/domain/usecases/save_encrypted_evidence_usecase.dart';
import '../../domain/entities/audio_window.dart';
import '../../domain/entities/inference_result.dart';
import '../../domain/usecases/process_audio_stream_usecase.dart';
import '../isolates/audio_processing_isolate.dart';
import 'incident_capture_gate.dart';

enum MonitoringStatus { idle, initializing, active, paused, error }

class MonitoringController extends ChangeNotifier with WidgetsBindingObserver {
  final ProcessAudioStreamUseCase _processAudioUseCase;
  final SaveEncryptedEvidenceUseCase _saveEvidenceUseCase;
  final MonitoringForegroundService _foregroundService;
  final IncidentCaptureGate _incidentCaptureGate;

  AudioInferenceIsolate? _inferenceIsolate;
  StreamSubscription<AudioWindow>? _audioSubscription;
  MonitoringStatus _status = MonitoringStatus.idle;
  String? _errorMessage;
  String _lastDetectedClass = 'None';
  bool _isProcessingWindow = false;
  bool _microphoneStreamStarted = false;
  bool _foregroundServiceStarted = false;

  MonitoringController({
    required ProcessAudioStreamUseCase processAudioUseCase,
    required SaveEncryptedEvidenceUseCase saveEvidenceUseCase,
    MonitoringForegroundService? foregroundService,
    IncidentCaptureGate? incidentCaptureGate,
  }) : _processAudioUseCase = processAudioUseCase,
       _saveEvidenceUseCase = saveEvidenceUseCase,
       _foregroundService = foregroundService ?? MonitoringForegroundService(),
       _incidentCaptureGate = incidentCaptureGate ?? IncidentCaptureGate() {
    WidgetsBinding.instance.addObserver(this);
  }

  MonitoringStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String get lastDetectedClass => _lastDetectedClass;
  bool get isMonitoring => _status == MonitoringStatus.active;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_stopAfterLeavingForeground());
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _stopAfterLeavingForeground() async {
    if (_status != MonitoringStatus.active &&
        _status != MonitoringStatus.initializing) {
      return;
    }
    try {
      await _stopResources();
      _status = MonitoringStatus.paused;
      _errorMessage = null;
    } catch (error) {
      debugPrint('Could not release audio resources on app detach: $error');
      _status = MonitoringStatus.error;
      _errorMessage = 'Could not release audio resources: $error';
    }
    notifyListeners();
  }

  Future<void> startMonitoring() async {
    if (_status == MonitoringStatus.active ||
        _status == MonitoringStatus.initializing) {
      return;
    }

    _status = MonitoringStatus.initializing;
    _errorMessage = null;
    _incidentCaptureGate.reset();
    notifyListeners();

    try {
      debugPrint('Checking microphone permission for monitoring.');
      if (!await _processAudioUseCase.hasMicrophonePermission()) {
        throw StateError('Microphone permission was not granted.');
      }
      debugPrint('Initializing TensorFlow Lite inference worker.');

      _inferenceIsolate = AudioInferenceIsolate();
      await _inferenceIsolate!.initialize();
      debugPrint('TensorFlow Lite inference worker is ready.');

      await _foregroundService.start();
      _foregroundServiceStarted = true;
      debugPrint('Android foreground monitoring service is running.');

      final audioStream = await _processAudioUseCase.getAudioStream();
      _microphoneStreamStarted = true;
      debugPrint('Microphone audio stream is running.');
      _audioSubscription = audioStream.listen(
        _processAudioWindow,
        onError: (Object error, StackTrace stackTrace) {
          _failMonitoring('Microphone stream failed: $error');
        },
        onDone: () {
          if (_status == MonitoringStatus.active) {
            _failMonitoring('Microphone stream ended unexpectedly.');
          }
        },
      );

      _status = MonitoringStatus.active;
      notifyListeners();
    } catch (error) {
      var startupError = error;
      try {
        await _stopResources();
      } catch (cleanupError) {
        startupError = '$error; resource cleanup also failed: $cleanupError';
      }
      _status = MonitoringStatus.error;
      _errorMessage = startupError.toString();
      debugPrint('Audio monitoring startup failed: $startupError');
      notifyListeners();
    }
  }

  Future<void> pauseMonitoring() async {
    if (_status != MonitoringStatus.active) return;

    try {
      await _stopResources();
      _status = MonitoringStatus.paused;
      _errorMessage = null;
    } catch (error) {
      _status = MonitoringStatus.error;
      _errorMessage = 'No se pudo detener el monitoreo: $error';
    }
    notifyListeners();
  }

  Future<void> _processAudioWindow(AudioWindow window) async {
    if (_isProcessingWindow) return;
    _isProcessingWindow = true;
    try {
      if (!_containsSignal(window.normalizedSamples)) {
        debugPrint(
          'Ignoring an all-zero audio window; microphone input may be silent.',
        );
        return;
      }
      final result = await _inferenceIsolate!.predict(window.normalizedSamples);
      if (_status == MonitoringStatus.active && result.isViolenceDetected) {
        if (!_incidentCaptureGate.canCaptureAt(window.timestamp)) {
          debugPrint(
            'Skipping repeated detection inside the '
            '${_incidentCaptureGate.minimumInterval.inSeconds}-second '
            'evidence interval: ${result.label} '
            '(${(result.confidence * 100).toStringAsFixed(1)}%).',
          );
          return;
        }
        await _handleIncidentDetected(window, result);
        _incidentCaptureGate.markCapturedAt(window.timestamp);
        debugPrint(
          'Saved ${result.label} evidence at '
          '${(result.confidence * 100).toStringAsFixed(1)}% confidence.',
        );
      }
    } catch (error) {
      _failMonitoring('Audio inference failed: $error');
    } finally {
      _isProcessingWindow = false;
    }
  }

  bool _containsSignal(Float32List samples) {
    for (final sample in samples) {
      if (sample != 0) return true;
    }
    return false;
  }

  Future<void> _handleIncidentDetected(
    AudioWindow window,
    InferenceResult result,
  ) async {
    _lastDetectedClass = result.label;
    notifyListeners();

    final coordinates = await _captureCurrentCoordinates();
    await _saveEvidenceUseCase(
      SaveEncryptedEvidenceParams(
        rawAudioBytes: window.rawPcmBytes,
        predictionLabel: result.label,
        confidenceScore: result.confidence,
        gpsCoordinates: coordinates,
      ),
    );
  }

  Future<Map<String, double>> _captureCurrentCoordinates() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('Location unavailable: device location services are off.');
        return {};
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Location unavailable: permission was not granted.');
        return {};
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      return {'lat': position.latitude, 'lng': position.longitude};
    } catch (error) {
      debugPrint('Location could not be captured: $error');
      return {};
    }
  }

  void _failMonitoring(String message) {
    if (_status == MonitoringStatus.error) return;
    _status = MonitoringStatus.error;
    _errorMessage = message;
    debugPrint(message);
    notifyListeners();
    unawaited(
      _stopResources().catchError((Object error) {
        debugPrint('Error stopping audio monitoring: $error');
      }),
    );
  }

  Future<void> _stopResources() async {
    final errors = <Object>[];
    final subscription = _audioSubscription;
    _audioSubscription = null;
    try {
      await subscription?.cancel();
    } catch (error) {
      errors.add(error);
    }

    if (_microphoneStreamStarted) {
      _microphoneStreamStarted = false;
      try {
        await _processAudioUseCase.stop();
      } catch (error) {
        errors.add(error);
      }
    }

    final inferenceIsolate = _inferenceIsolate;
    _inferenceIsolate = null;
    try {
      await inferenceIsolate?.dispose();
    } catch (error) {
      errors.add(error);
    }

    if (_foregroundServiceStarted) {
      _foregroundServiceStarted = false;
      try {
        await _foregroundService.stop();
      } catch (error) {
        errors.add(error);
      }
    }

    if (errors.isNotEmpty) {
      throw StateError('Resource cleanup failed: ${errors.join('; ')}');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _stopResources().catchError((Object error) {
        debugPrint('Error disposing audio monitoring: $error');
      }),
    );
    super.dispose();
  }
}
