import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../crypto/cipher_manager.dart';
import '../crypto/secure_key_storage.dart';
import '../../features/audio_monitoring/data/datasources/audio_stream_datasource.dart';
import '../../features/audio_monitoring/data/repositories/monitoring_repository_impl.dart';
import '../../features/audio_monitoring/domain/usecases/process_audio_stream_usecase.dart';
import '../../features/audio_monitoring/presentation/controllers/monitoring_controller.dart';
import '../../features/evidence_vault/data/datasources/background_evidence_journal.dart';
import '../../features/evidence_vault/data/models/evidence_record_model.dart';
import '../../features/evidence_vault/data/repositories/evidence_repository_impl.dart';
import '../../features/evidence_vault/domain/usecases/save_encrypted_evidence_usecase.dart';

class MonitoringForegroundService {
  bool _initialized = false;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;
  Completer<void>? _ready;
  Completer<void>? _stopped;
  int _diagnosticRequest = 0;
  final Map<int, Completer<Map<String, Object?>>> _diagnostics = {};

  void _onData(Object data) {
    if (data is! Map) return;
    final event = Map<String, dynamic>.from(data);
    if (event['diagnostics'] is Map) {
      _diagnostics
          .remove(event['diagnosticRequest'])
          ?.complete(Map<String, Object?>.from(event['diagnostics'] as Map));
      return;
    }
    _events.add(event);
    if (event['status'] == 'active' && !(_ready?.isCompleted ?? true)) {
      _ready!.complete();
    } else if (event['status'] == 'error' && !(_ready?.isCompleted ?? true)) {
      _ready!.completeError(
        StateError(event['error'] as String? ?? 'Monitoring failed'),
      );
    }
    if (event['stopped'] == true && !(_stopped?.isCompleted ?? true)) {
      if (event['status'] == 'error') {
        _stopped!.completeError(
          StateError(event['error'] as String? ?? 'Could not save incident'),
        );
      } else {
        _stopped!.complete();
      }
    }
  }

  void initialize() {
    if (!Platform.isAndroid || _initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'serene_monitoring',
        channelName: 'Monitoreo de Serene',
        channelDescription: 'Indica que la proteccion de audio esta activa.',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  Future<void> start({bool locationEnabled = false}) async {
    if (!Platform.isAndroid) return;
    initialize();
    await FlutterForegroundTask.saveData(
      key: 'locationEnabled',
      value: locationEnabled,
    );
    // Persist the shared encryption key before the second engine starts.
    await SecureKeyStorage().getOrCreateMasterKey();
    _ready = Completer<void>();
    final ready = _ready!.future.timeout(const Duration(seconds: 45));
    if (await FlutterForegroundTask.isRunningService) {
      requestStatus();
    } else {
      final result = await FlutterForegroundTask.startService(
        serviceId: 410,
        serviceTypes: [
          ForegroundServiceTypes.microphone,
          if (locationEnabled) ForegroundServiceTypes.location,
        ],
        notificationTitle: 'Serene esta protegiendote',
        notificationText: 'Iniciando monitoreo de audio',
        notificationButtons: const [
          NotificationButton(id: 'stop', text: 'Detener'),
        ],
        callback: startMonitoringForegroundTask,
      );
      if (result is ServiceRequestFailure) {
        _ready!.completeError(result.error);
      }
    }
    await ready;
  }

  void requestStatus() {
    if (Platform.isAndroid) {
      FlutterForegroundTask.sendDataToTask({'command': 'status'});
    }
  }

  Future<Map<String, Object?>?> collectDiagnostics() async {
    if (!Platform.isAndroid || !await FlutterForegroundTask.isRunningService) {
      return null;
    }
    initialize();
    final request = ++_diagnosticRequest;
    final completer = Completer<Map<String, Object?>>();
    _diagnostics[request] = completer;
    FlutterForegroundTask.sendDataToTask({
      'command': 'diagnostics',
      'request': request,
    });
    try {
      return await completer.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      return null;
    } finally {
      _diagnostics.remove(request);
    }
  }

  Future<void> disconnect() async {
    if (_initialized) FlutterForegroundTask.removeTaskDataCallback(_onData);
    await _events.close();
  }

  Future<void> stop() async {
    if (!Platform.isAndroid || !await FlutterForegroundTask.isRunningService) {
      return;
    }
    initialize();
    _stopped = Completer<void>();
    FlutterForegroundTask.sendDataToTask({'command': 'stop'});
    // Do not terminate the worker before it encrypts the final incident.
    await _stopped!.future.timeout(const Duration(seconds: 45));
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) throw result.error;
  }
}

@pragma('vm:entry-point')
void startMonitoringForegroundTask() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_MonitoringTaskHandler());
}

class _NotifyingJournal extends BackgroundEvidenceJournal {
  @override
  Future<void> insertRecord(EvidenceRecordModel record) async {
    await super.insertRecord(record);
    FlutterForegroundTask.sendDataToMain({'evidenceSaved': true});
  }
}

class _MonitoringTaskHandler extends TaskHandler {
  MonitoringController? _controller;
  Future<void>? _stopping;

  void _sendStatus() {
    final controller = _controller;
    if (controller == null) return;
    FlutterForegroundTask.sendDataToMain({
      'status': controller.status.name,
      'error': controller.errorMessage,
      'storageBlocked': controller.isStorageBlocked,
      'label': controller.lastDetectedClass,
    });
    unawaited(
      FlutterForegroundTask.updateService(
        notificationText: controller.status == MonitoringStatus.active
            ? 'Monitoreo de audio activo'
            : controller.status == MonitoringStatus.error
            ? 'Monitoreo interrumpido: abre Serene'
            : 'Preparando monitoreo de audio',
      ),
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final repository = EvidenceRepositoryImpl(
      localDataSource: _NotifyingJournal(),
      cipherManager: CipherManager(),
      keyStorage: SecureKeyStorage(),
    );
    _controller = MonitoringController(
      processAudioUseCase: ProcessAudioStreamUseCase(
        MonitoringRepositoryImpl(
          audioStreamDataSource: AudioStreamDataSourceImpl(),
        ),
      ),
      saveEvidenceUseCase: SaveEncryptedEvidenceUseCase(repository),
      runInService: true,
      locationEnabled:
          await FlutterForegroundTask.getData<bool>(key: 'locationEnabled') ??
          false,
    )..addListener(_sendStatus);
    await _controller!.startMonitoring();
    _sendStatus();
  }

  Future<void> _stop() => _stopping ??= () async {
    try {
      await _controller?.pauseMonitoring();
      if (_controller?.status == MonitoringStatus.error) {
        throw StateError(
          _controller?.errorMessage ?? 'Could not finish recording',
        );
      }
      FlutterForegroundTask.sendDataToMain({
        'stopped': true,
        'status': 'paused',
      });
    } catch (error) {
      FlutterForegroundTask.sendDataToMain({
        'stopped': true,
        'status': 'error',
        'error': '$error',
      });
      _stopping = null;
      rethrow;
    }
  }();

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    if (data['command'] == 'status') _sendStatus();
    if (data['command'] == 'diagnostics') {
      FlutterForegroundTask.sendDataToMain({
        'diagnosticRequest': data['request'],
        'diagnostics':
            _controller?.localDiagnosticSnapshot() ?? <String, Object?>{},
      });
    }
    if (data['command'] == 'stop') {
      unawaited(
        _stop().catchError((Object error) {
          debugPrint('Could not stop microphone service: $error');
        }),
      );
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      unawaited(() async {
        try {
          await _stop();
          await FlutterForegroundTask.stopService();
        } catch (error) {
          debugPrint('Could not finish recording from notification: $error');
        }
      }());
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _stop();
    _controller?.removeListener(_sendStatus);
    _controller?.dispose();
  }
}
