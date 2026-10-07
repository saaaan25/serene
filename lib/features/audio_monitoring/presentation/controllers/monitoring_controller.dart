import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/services/monitoring_foreground_service.dart';
import '../../../evidence_vault/domain/usecases/save_encrypted_evidence_usecase.dart';
import '../../domain/entities/audio_window.dart';
import '../../domain/entities/inference_result.dart';
import '../../domain/usecases/process_audio_stream_usecase.dart';
import '../isolates/audio_processing_isolate.dart';
import 'incident_recording.dart';

enum MonitoringStatus { idle, initializing, active, paused, error }

class MonitoringController extends ChangeNotifier with WidgetsBindingObserver {
  final ProcessAudioStreamUseCase _processAudioUseCase;
  final SaveEncryptedEvidenceUseCase _saveEvidenceUseCase;
  final MonitoringForegroundService _foregroundService;
  final bool runInService;
  final AudioInferenceIsolate Function() _inferenceFactory;
  final Future<Map<String, double>> Function()? _coordinatesProvider;
  IncidentRecording? _incident;
  Future<void> _windowWork = Future.value();
  int _queuedWindows = 0;
  StreamSubscription<Map<String, dynamic>>? _serviceSubscription;
  bool _monitoringRequested = false;
  bool _disposed = false;
  Timer? _retryTimer;
  Future<void>? _resourceStop;
  bool _stoppingResources = false;
  InferenceResult? _latestInference;
  DateTime? _lastInferenceAt;
  Duration _inferenceInterval = const Duration(seconds: 1);

  AudioInferenceIsolate? _inferenceIsolate;
  StreamSubscription<AudioWindow>? _audioSubscription;
  MonitoringStatus _status = MonitoringStatus.idle;
  String? _errorMessage;
  String _lastDetectedClass = 'None';
  bool _microphoneStreamStarted = false;
  bool _foregroundServiceStarted = false;
  int _startGeneration = 0;
  Future<void>? _startFuture;
  Future<void>? _lifecycleStopFuture;

  MonitoringController({
    required ProcessAudioStreamUseCase processAudioUseCase,
    required SaveEncryptedEvidenceUseCase saveEvidenceUseCase,
    MonitoringForegroundService? foregroundService,
    this.runInService = false,
    AudioInferenceIsolate Function()? inferenceFactory,
    Future<Map<String, double>> Function()? coordinatesProvider,
  }) : _processAudioUseCase = processAudioUseCase,
       _saveEvidenceUseCase = saveEvidenceUseCase,
       _foregroundService = foregroundService ?? MonitoringForegroundService(),
       _inferenceFactory = inferenceFactory ?? AudioInferenceIsolate.new,
       _coordinatesProvider = coordinatesProvider {
    if (!runInService) WidgetsBinding.instance.addObserver(this);
    if (_usesAndroidService) {
      _serviceSubscription = _foregroundService.events.listen(_onServiceEvent);
    }
  }

  void _notify() {
    if (!_disposed) super.notifyListeners();
  }

  MonitoringStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String get lastDetectedClass => _lastDetectedClass;
  bool get isMonitoring => _status == MonitoringStatus.active;

  bool get _usesAndroidService => Platform.isAndroid && !runInService;

  void _onServiceEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    final status = event['status'] as String?;
    if (status != null) {
      _status = MonitoringStatus.values.firstWhere(
        (s) => s.name == status,
        orElse: () => MonitoringStatus.error,
      );
      _errorMessage = event['error'] as String?;
      if (_status == MonitoringStatus.paused) _monitoringRequested = false;
      _lastDetectedClass = event['label'] as String? ?? _lastDetectedClass;
      _notify();
    }
    if (event['evidenceSaved'] == true) {
      unawaited(_importBackgroundEvidence());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep an established microphone session alive when hidden/locked.
    // A new Android microphone service must still start from a visible app.
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        _status == MonitoringStatus.initializing) {
      unawaited(_stopAfterLeavingForeground());
    } else if (state == AppLifecycleState.resumed) {
      if (_usesAndroidService && _status == MonitoringStatus.active) {
        _foregroundService.requestStatus();
      } else if (_monitoringRequested &&
          (_status == MonitoringStatus.paused ||
              _status == MonitoringStatus.error)) {
        unawaited(startMonitoring());
      }
      unawaited(_importBackgroundEvidence());
    }
  }

  Future<void> _importBackgroundEvidence() async {
    try {
      await _saveEvidenceUseCase.repository.getVaultStats();
    } catch (error) {
      debugPrint('Could not refresh evidence: $error');
    }
  }

  Future<void> _stopAfterLeavingForeground() async {
    final pendingStop = _lifecycleStopFuture;
    if (pendingStop != null) return pendingStop;

    ++_startGeneration;
    _status = MonitoringStatus.paused;
    _errorMessage = null;
    _notify();

    final stopFuture = () async {
      try {
        final startFuture = _startFuture;
        if (startFuture != null) await startFuture;
        await _stopResources(forceForegroundServiceStop: true);
      } catch (error) {
        debugPrint('Could not release audio resources on app detach: $error');
        _status = MonitoringStatus.error;
        _errorMessage = 'Could not release audio resources: $error';
      }
      _notify();
    }();
    _lifecycleStopFuture = stopFuture;
    try {
      await stopFuture;
    } finally {
      if (identical(_lifecycleStopFuture, stopFuture)) {
        _lifecycleStopFuture = null;
      }
    }
  }

  Future<void> startMonitoring() async {
    if (_disposed) return;
    _monitoringRequested = true;
    _retryTimer?.cancel();
    final lifecycleStop = _lifecycleStopFuture;
    if (lifecycleStop != null) await lifecycleStop;

    if (_status == MonitoringStatus.active ||
        _status == MonitoringStatus.initializing) {
      return;
    }

    final generation = ++_startGeneration;
    _status = MonitoringStatus.initializing;
    _errorMessage = null;
    _notify();

    final startFuture = _startMonitoring(generation);
    _startFuture = startFuture;
    try {
      await startFuture;
    } finally {
      if (identical(_startFuture, startFuture)) _startFuture = null;
    }
  }

  Future<void> _startMonitoring(int generation) async {
    try {
      await _stopResources(forceForegroundServiceStop: !_usesAndroidService);
      if (generation != _startGeneration) return;

      debugPrint('Checking microphone permission for monitoring.');
      if (!await _processAudioUseCase.hasMicrophonePermission()) {
        throw StateError('Microphone permission was not granted.');
      }
      if (generation != _startGeneration) return;
      if (_usesAndroidService) {
        await _foregroundService.start();
        _foregroundServiceStarted = true;
        if (generation != _startGeneration) {
          await _foregroundService.stop();
          _foregroundServiceStarted = false;
          return;
        }
        _status = MonitoringStatus.active;
        _notify();
        return;
      }
      debugPrint('Initializing TensorFlow Lite inference worker.');

      _inferenceIsolate = _inferenceFactory();
      await _inferenceIsolate!.initialize();
      if (generation != _startGeneration) return;
      debugPrint('TensorFlow Lite inference worker is ready.');

      final audioStream = await _processAudioUseCase.getAudioStream();
      _microphoneStreamStarted = true;
      if (generation != _startGeneration) return;
      debugPrint('Microphone audio stream is running.');
      _audioSubscription = audioStream.listen(
        _enqueueWindow,
        onError: (Object error, StackTrace stackTrace) {
          _failMonitoring('Microphone stream failed: $error', retry: true);
        },
        onDone: () {
          if (_status == MonitoringStatus.active && !_stoppingResources) {
            _failMonitoring(
              'Microphone stream ended unexpectedly.',
              retry: true,
            );
          }
        },
      );

      if (generation != _startGeneration) return;
      _status = MonitoringStatus.active;
      _notify();
    } catch (error) {
      if (generation != _startGeneration) {
        try {
          await _stopResources(forceForegroundServiceStop: true);
        } catch (cleanupError) {
          debugPrint(
            'Error cleaning up cancelled monitoring startup: $cleanupError',
          );
        }
        return;
      }
      var startupError = error;
      try {
        await _stopResources(forceForegroundServiceStop: true);
      } catch (cleanupError) {
        startupError = '$error; resource cleanup also failed: $cleanupError';
      }
      _status = MonitoringStatus.error;
      _errorMessage = startupError.toString();
      debugPrint('Audio monitoring startup failed: $startupError');
      _notify();
    }
  }

  Future<void> pauseMonitoring() async {
    _monitoringRequested = false;
    _retryTimer?.cancel();
    ++_startGeneration;
    if (_status != MonitoringStatus.active &&
        _status != MonitoringStatus.error) {
      return;
    }

    try {
      await _stopResources();
      _status = MonitoringStatus.paused;
      _errorMessage = null;
    } catch (error) {
      _status = MonitoringStatus.error;
      _errorMessage = 'No se pudo detener el monitoreo: $error';
    }
    _notify();
  }

  void _enqueueWindow(AudioWindow window) {
    if (_queuedWindows >= 30) {
      _failMonitoring(
        'Audio inference cannot keep up with recording',
        retry: true,
      );
      return;
    }
    _queuedWindows++;
    _windowWork = _windowWork
        .then((_) => _processAudioWindow(window))
        .whenComplete(() {
          _queuedWindows--;
        });
  }

  Future<void> _processAudioWindow(AudioWindow window) async {
    try {
      InferenceResult? result;
      if (_containsSignal(window.normalizedSamples)) {
        if (_lastInferenceAt == null ||
            window.timestamp.difference(_lastInferenceAt!) >=
                _inferenceInterval) {
          final timer = Stopwatch()..start();
          _latestInference = await _inferenceIsolate!.predict(
            window.normalizedSamples,
          );
          timer.stop();
          _lastInferenceAt = window.timestamp;
          // Slow phones classify less often, but retain every PCM sample.
          final milliseconds = (timer.elapsedMilliseconds * 1.25).ceil();
          _inferenceInterval = Duration(
            milliseconds: milliseconds < 1000 ? 1000 : milliseconds,
          );
        }
        result = _latestInference;
      } else {
        _latestInference = null;
        _lastInferenceAt = null;
      }
      var incident = _incident;
      if (incident == null) {
        if (!(result?.isViolenceDetected ?? false)) return;
        incident = IncidentRecording(window, result!);
        _incident = incident;
        _lastDetectedClass = result.label;
        if (!_disposed) _notify();
        // First checkpoint persists the trigger window immediately.
        await _saveIncident(incident);
      } else {
        incident.append(window, result);
        if (incident.shouldClose) {
          await _saveIncident(incident);
          _incident = null;
        } else if (incident.checkpointDue) {
          await _saveIncident(incident);
        }
      }
    } catch (error) {
      _failMonitoring('Audio inference or evidence persistence failed: $error');
    }
  }

  Future<void> _saveIncident(IncidentRecording incident) async {
    final coordinates = incident.coordinates ??=
        await _captureCurrentCoordinates();
    await _saveEvidenceUseCase(
      SaveEncryptedEvidenceParams(
        rawAudioBytes: incident.snapshot(),
        predictionLabel: incident.label,
        confidenceScore: incident.confidence,
        gpsCoordinates: coordinates,
        evidenceId: incident.id,
        startedAt: incident.startedAt,
      ),
    );
    incident.markCheckpoint();
    debugPrint('Saved incident ${incident.id}: ${incident.length} PCM bytes');
  }

  bool _containsSignal(Float32List samples) {
    for (final sample in samples) {
      if (sample != 0) return true;
    }
    return false;
  }

  Future<Map<String, double>> _captureCurrentCoordinates() async {
    if (_coordinatesProvider != null) return _coordinatesProvider();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('Location unavailable: device location services are off.');
        return {};
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Background recording must not open a permission dialog.
        if (!runInService &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          permission = await Geolocator.requestPermission();
        }
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

  void _failMonitoring(String message, {bool retry = false}) {
    if (_status == MonitoringStatus.error) return;
    _status = MonitoringStatus.error;
    _errorMessage = message;
    debugPrint(message);
    if (!_disposed) _notify();
    unawaited(
      _stopResources()
          .catchError((Object error) {
            debugPrint('Error stopping audio monitoring: $error');
          })
          .then((_) {
            if (retry && _monitoringRequested && !_disposed) {
              _retryTimer = Timer(
                const Duration(seconds: 3),
                () => unawaited(startMonitoring()),
              );
            }
          }),
    );
  }

  Future<void> _stopResources({bool forceForegroundServiceStop = false}) {
    return _resourceStop ??=
        _releaseResources(
          forceForegroundServiceStop: forceForegroundServiceStop,
        ).whenComplete(() {
          _resourceStop = null;
          _stoppingResources = false;
        });
  }

  Future<void> _releaseResources({
    bool forceForegroundServiceStop = false,
  }) async {
    _stoppingResources = true;
    final errors = <Object>[];
    if (_microphoneStreamStarted) {
      try {
        await _processAudioUseCase.stop();
        _microphoneStreamStarted = false;
      } catch (error) {
        errors.add(error);
      }
    }

    final subscription = _audioSubscription;
    if (subscription != null) {
      try {
        await subscription.cancel();
        _audioSubscription = null;
      } catch (error) {
        errors.add(error);
      }
    }

    // Drain classified windows before disposing the interpreter; persist the
    // same incident on graceful stop instead of losing its last samples.
    await _windowWork;
    final incident = _incident;
    if (incident != null) {
      try {
        await _saveIncident(incident);
        _incident = null;
      } catch (error) {
        errors.add(error);
      }
    }

    final inferenceIsolate = _inferenceIsolate;
    if (inferenceIsolate != null) {
      try {
        await inferenceIsolate.dispose();
        _inferenceIsolate = null;
        _latestInference = null;
        _lastInferenceAt = null;
      } catch (error) {
        errors.add(error);
      }
    }

    if (!runInService &&
        (_foregroundServiceStarted || forceForegroundServiceStop)) {
      try {
        await _foregroundService.stop();
        _foregroundServiceStarted = false;
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
    if (!runInService) WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _retryTimer?.cancel();
    unawaited(_serviceSubscription?.cancel());
    ++_startGeneration;
    // UI engine can go away while the Android service continues recording.
    if (_usesAndroidService) {
      unawaited(_foregroundService.disconnect());
      super.dispose();
      return;
    }
    final startFuture = _startFuture;
    unawaited(() async {
      try {
        if (startFuture != null) await startFuture;
        await _stopResources(forceForegroundServiceStop: true);
      } catch (error) {
        debugPrint('Error disposing audio monitoring: $error');
      }
    }());
    super.dispose();
  }
}
