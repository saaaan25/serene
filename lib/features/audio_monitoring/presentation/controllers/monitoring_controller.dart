import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/services/monitoring_foreground_service.dart';
import '../../../../core/constants/evidence_policy.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/dsp/signal_quality.dart';
import '../../../../core/services/diagnostics_service.dart';
import '../../domain/detection_policy.dart';
import '../../../../core/errors/failures.dart';
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
  bool _locationEnabled;
  final AudioInferenceIsolate Function() _inferenceFactory;
  final Future<Map<String, double>> Function()? _coordinatesProvider;
  IncidentRecording? _incident;
  int? _continuationEndSample;
  bool _storageBlocked = false;
  final Duration? maximumIncidentDuration;
  Future<void> _windowWork = Future.value();
  int _queuedWindows = 0;
  StreamSubscription<Map<String, dynamic>>? _serviceSubscription;
  bool _monitoringRequested = false;
  bool _disposed = false;
  Timer? _retryTimer;
  Future<void>? _resourceStop;
  bool _stoppingResources = false;
  final DetectionPolicy _detection = DetectionPolicy();
  final List<(AudioWindow, InferenceResult?)> _pendingWindows = [];
  InferenceResult? _lastConfirmedResult;
  int? _lastInferredEndSample;
  int _lastProcessedEndSample = 0;
  int _inferenceStrideSamples = AppConstants.sampleRate;

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
    bool locationEnabled = false,
    this.maximumIncidentDuration = EvidencePolicy.maximumIncidentDuration,
    AudioInferenceIsolate Function()? inferenceFactory,
    Future<Map<String, double>> Function()? coordinatesProvider,
  }) : _locationEnabled = locationEnabled,
       _processAudioUseCase = processAudioUseCase,
       _saveEvidenceUseCase = saveEvidenceUseCase,
       _foregroundService = foregroundService ?? MonitoringForegroundService(),
       _inferenceFactory = inferenceFactory ?? AudioInferenceIsolate.new,
       _coordinatesProvider = coordinatesProvider {
    if (!runInService) WidgetsBinding.instance.addObserver(this);
    if (_usesAndroidService) {
      _serviceSubscription = _foregroundService.events.listen(_onServiceEvent);
    }
  }

  Future<void> setLocationEnabled(bool enabled) async {
    // An in-flight Android service start may already have read its types.
    // Finish it before deciding whether a restart is necessary.
    if (_usesAndroidService && _startFuture != null) await _startFuture;
    if (_locationEnabled == enabled) return;
    final restart = _usesAndroidService && isMonitoring;
    if (restart) await pauseMonitoring();
    _locationEnabled = enabled;
    if (!enabled) _incident?.coordinates = null;
    if (restart) {
      await startMonitoring();
      if (!isMonitoring) {
        throw StateError('Could not apply location service configuration');
      }
    }
  }

  void _notify() {
    if (!_disposed) super.notifyListeners();
  }

  MonitoringStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String get lastDetectedClass => _lastDetectedClass;
  bool get isMonitoring => _status == MonitoringStatus.active;
  bool get isStorageBlocked => _storageBlocked;

  Map<String, Object?> localDiagnosticSnapshot() => {
    'status': _status.name,
    'queued_windows': _queuedWindows,
    'pending_confirmation_windows': _pendingWindows.length,
    'incident_pcm_bytes': _incident?.length ?? 0,
    'runtime': DiagnosticsService.instance.timingSnapshot(),
  };

  Future<Map<String, Object?>> collectDiagnostics() async {
    if (_usesAndroidService) {
      return {
        'ui_status': _status.name,
        'worker': await _foregroundService.collectDiagnostics(),
      };
    }
    return localDiagnosticSnapshot();
  }

  bool get _usesAndroidService => Platform.isAndroid && !runInService;

  void _onServiceEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    final status = event['status'] as String?;
    if (event['storageBlocked'] == true) {
      _storageBlocked = true;
      _monitoringRequested = false;
    }
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
    _storageBlocked = false;
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
        if (_locationEnabled) {
          final permission = await Geolocator.checkPermission();
          _locationEnabled =
              permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always;
        }
        await _foregroundService.start(locationEnabled: _locationEnabled);
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
      final initializeClock = Stopwatch()..start();
      await _inferenceIsolate!.initialize();
      DiagnosticsService.instance.recordDuration(
        'model_initialize',
        initializeClock.elapsed,
      );
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
      DiagnosticsService.instance.recordFailure('monitoring_start_failures');
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
        _status != MonitoringStatus.error &&
        _status != MonitoringStatus.initializing) {
      return;
    }

    try {
      // A settings toggle may cancel startup while native resources are pending.
      // Wait for that generation to finish before reporting the microphone off.
      final starting = _startFuture;
      if (starting != null) await starting;
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
    if (_storageBlocked) return;
    try {
      final endSample =
          window.endSampleIndex ??
          (_lastProcessedEndSample == 0
              ? window.normalizedSamples.length
              : _lastProcessedEndSample + AppConstants.sampleRate);
      if (endSample <= _lastProcessedEndSample) return;
      _lastProcessedEndSample = endSample;
      final quality = SignalQuality.analyze(window.normalizedSamples);
      InferenceResult? result;
      if (quality.isUsable &&
          (_lastInferredEndSample == null ||
              endSample - _lastInferredEndSample! >= _inferenceStrideSamples)) {
        final timer = Stopwatch()..start();
        result = await _inferenceIsolate!.predict(window.normalizedSamples);
        timer.stop();
        DiagnosticsService.instance.recordDuration('inference', timer.elapsed);
        _lastInferredEndSample = endSample;
        final stride =
            (timer.elapsedMicroseconds *
                    1.25 *
                    AppConstants.sampleRate /
                    1000000)
                .ceil();
        _inferenceStrideSamples = stride < AppConstants.sampleRate
            ? AppConstants.sampleRate
            : stride;
      }
      // Null is an unclassified window, never another vote for an old result.
      final decision = _detection.observe(
        endSample: endSample,
        usableSignal: quality.isUsable,
        freshResult: result,
      );
      if (kDebugMode) {
        debugPrint(
          'AudioDetection ${jsonEncode({'end_sample': endSample, 'usable_signal': quality.isUsable, 'centered_rms': quality.isFinite ? quality.centeredRms : null, 'fresh_inference': result != null, 'scores': result?.allScores, 'decision': decision.name})}',
        );
      }
      switch (decision) {
        case DetectionDecision.idle:
          _pendingWindows.clear();
        case DetectionDecision.candidate:
          if (_detection.candidateAt == endSample) _pendingWindows.clear();
          _pendingWindows.add((window, result));
        case DetectionDecision.confirmed:
          _pendingWindows.add((window, result));
          // Replay retained PCM only after a second fresh positive. This keeps
          // the trigger audio without persisting unconfirmed candidates.
          for (final (pending, prediction) in _pendingWindows) {
            await _appendConfirmedWindow(pending, prediction);
          }
          _pendingWindows.clear();
        case DetectionDecision.active:
          await _appendConfirmedWindow(window, result);
        case DetectionDecision.close:
          await _appendConfirmedWindow(window, result, closing: true);
          _incident?.discard();
          _incident = null;
          _continuationEndSample = null;
          _lastConfirmedResult = null;
          _pendingWindows.clear();
        case DetectionDecision.ignored:
          break;
      }
    } catch (error) {
      DiagnosticsService.instance.recordFailure('processing_failures');
      if (error is StorageCapacityFailure) {
        _storageBlocked = true;
        _monitoringRequested = false;
        _failMonitoring(error.message);
      } else {
        _failMonitoring(
          'Audio inference or evidence persistence failed: $error',
        );
      }
    }
  }

  Future<void> _saveIncident(IncidentRecording incident) async {
    final captured = _locationEnabled
        ? incident.coordinates ?? await _captureCurrentCoordinates()
        : <String, double>{};
    // A permission dialog or a location fix can finish after the switch changes.
    final coordinates = _locationEnabled ? captured : <String, double>{};
    incident.coordinates = coordinates;
    final saveClock = Stopwatch()..start();
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
    DiagnosticsService.instance.recordDuration(
      'evidence_save',
      saveClock.elapsed,
    );
    incident.markCheckpoint();
  }

  Future<void> _appendConfirmedWindow(
    AudioWindow window,
    InferenceResult? result, {
    bool closing = false,
  }) async {
    if (result?.isViolenceDetected ?? false) _lastConfirmedResult = result;
    final metadata = _lastConfirmedResult!;
    final isNew = _incident == null;
    final incident = _incident ??= IncidentRecording(
      window,
      metadata,
      maximumDuration: maximumIncidentDuration,
      afterSample: _continuationEndSample,
    );
    _continuationEndSample = null;
    if (!isNew) {
      incident.append(window, result, hasNewClassification: result != null);
    } else {
      _lastDetectedClass = metadata.label;
      if (!_disposed) _notify();
    }
    if (isNew ||
        closing ||
        incident.durationLimitReached ||
        incident.checkpointDue) {
      await _saveIncident(incident);
    }
    if (incident.durationLimitReached) {
      final end = incident.endSampleIndex;
      _incident = null;
      _continuationEndSample = end;
      incident.discard();
      // Continue a confirmed episode across size-limited records, including
      // unclassified PCM; this does not count as a new detection or vote.
      if ((window.endSampleIndex ?? end) > end) {
        await _appendConfirmedWindow(window, result, closing: closing);
      }
    }
  }

  Future<Map<String, double>> _captureCurrentCoordinates() async {
    if (_coordinatesProvider != null) return _coordinatesProvider();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('Location unavailable: device location services are off.');
        return {};
      }

      final permission = await Geolocator.checkPermission();
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
    if (incident != null && !_storageBlocked) {
      try {
        await _saveIncident(incident);
        _incident = null;
      } catch (error) {
        errors.add(error);
      }
    }

    final inferenceIsolate = _inferenceIsolate;
    if (_storageBlocked) {
      _incident?.discard();
      _incident = null;
      _continuationEndSample = null;
    }
    if (inferenceIsolate != null) {
      try {
        await inferenceIsolate.dispose();
        _inferenceIsolate = null;
      } catch (error) {
        errors.add(error);
      }
    }

    // Unconfirmed candidates are never persisted, including on manual stop.
    _pendingWindows.clear();
    _detection.reset();
    _lastConfirmedResult = null;
    _continuationEndSample = null;
    _lastInferredEndSample = null;
    _lastProcessedEndSample = 0;
    _inferenceStrideSamples = AppConstants.sampleRate;

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
