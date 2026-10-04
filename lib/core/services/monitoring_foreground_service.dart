import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class MonitoringForegroundService {
  bool _initialized = false;

  void initialize() {
    if (!Platform.isAndroid || _initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'serene_monitoring',
        channelName: 'Monitoreo de Serene',
        channelDescription: 'Indica que la protección de audio está activa.',
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

  Future<void> start() async {
    if (!Platform.isAndroid) return;
    initialize();
    var notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      notificationPermission =
          await FlutterForegroundTask.requestNotificationPermission();
    }
    if (notificationPermission != NotificationPermission.granted) {
      throw StateError(
        'Notification permission is required for visible background monitoring.',
      );
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 410,
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: 'Serene está protegiéndote',
      notificationText: 'Monitoreo de audio activo',
      callback: startMonitoringForegroundTask,
    );
    if (result is ServiceRequestFailure) throw result.error;
  }

  Future<void> stop() async {
    if (!Platform.isAndroid || !await FlutterForegroundTask.isRunningService) {
      return;
    }
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) throw result.error;
  }
}

@pragma('vm:entry-point')
void startMonitoringForegroundTask() {
  FlutterForegroundTask.setTaskHandler(_MonitoringTaskHandler());
}

class _MonitoringTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
