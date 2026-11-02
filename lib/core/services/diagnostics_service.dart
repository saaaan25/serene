import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/app_constants.dart';
import 'evaluation_metrics.dart';

class DiagnosticPlatform {
  static const channel = MethodChannel('com.example.serene/diagnostics');

  Future<void> begin() => channel.invokeMethod<void>('begin');
  Future<void> end() => channel.invokeMethod<void>('end');
  Future<Map<String, dynamic>> sample() async => Map<String, dynamic>.from(
    await channel.invokeMapMethod<String, dynamic>('sample') ?? {},
  );
  Future<void> share(String json) =>
      channel.invokeMethod<void>('share', {'json': json});
}

/// Bounded, opt-in process sampling. Timing aggregates contain fixed names only.
/// No raw exceptions, audio, inference labels/scores, locations, paths or IDs.
class DiagnosticsService extends ChangeNotifier {
  DiagnosticsService({DiagnosticPlatform? platform})
    : _platform = platform ?? DiagnosticPlatform();

  static final instance = DiagnosticsService();
  static const sampleInterval = Duration(seconds: 5);
  static const maximumSamples = 180; // At most 15 minutes at nominal cadence.
  static const maximumDuration = Duration(minutes: 15);
  static const allowedTimings = {
    'model_initialize',
    'inference',
    'evidence_save',
  };
  static const allowedCounters = {
    'monitoring_start_failures',
    'processing_failures',
  };
  final DiagnosticPlatform _platform;
  final Map<String, _TimingSummary> _timings = {};
  final Map<String, int> _counters = {};
  final Map<String, double> _startup = {};
  final List<Map<String, Object?>> _samples = [];
  final Stopwatch _clock = Stopwatch();
  Future<Map<String, Object?>> Function()? monitoringSnapshot;
  Timer? _timer;
  Future<void>? _sampling;
  Future<void>? _stopping;
  DateTime? _startedAt;
  DateTime? _endedAt;
  Map<String, Object?>? _frozen;
  Map<String, Object?>? _monitoring;
  Map<String, Object?>? _lastMonitoringRuntime;
  String? _appVersion;
  bool _recording = false;
  bool _busy = false;
  bool _disposed = false;
  bool get isRecording => _recording;
  bool get isBusy => _busy || _stopping != null;
  bool get hasReport => _startedAt != null;
  int get sampleCount => _samples.length;
  double get elapsedSeconds => _clock.elapsedMilliseconds / 1000;
  Map<String, Object?>? get latestSample =>
      _samples.isEmpty ? null : Map.unmodifiable(_samples.last);
  Map<String, Object?>? get latestMonitoringRuntime => _lastMonitoringRuntime;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void recordDuration(String name, Duration duration) {
    if (!allowedTimings.contains(name) || duration.isNegative) return;
    (_timings[name] ??= _TimingSummary()).add(duration.inMicroseconds / 1000);
  }

  void recordFailure(String name) {
    if (allowedCounters.contains(name)) {
      _counters.update(name, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  void recordStartup({required Duration bootstrap, Duration? firstFrame}) {
    _startup['bootstrap_ms'] = bootstrap.inMicroseconds / 1000;
    if (firstFrame != null) {
      _startup['first_frame_callback_ms'] = firstFrame.inMicroseconds / 1000;
    }
  }

  Map<String, Object?> timingSnapshot() => {
    'scope': 'since_engine_start',
    'timings_ms': _timings.map((key, value) => MapEntry(key, value.toJson())),
    'counters': Map<String, int>.from(_counters),
  };

  Future<void> start() async {
    if (_recording || isBusy || _disposed) return;
    _busy = true;
    _notify();
    try {
      _samples.clear();
      _frozen = null;
      _monitoring = null;
      _lastMonitoringRuntime = null;
      _startedAt = DateTime.now().toUtc();
      _endedAt = null;
      _clock
        ..reset()
        ..start();
      _recording = true;
      try {
        await _platform.begin().timeout(const Duration(seconds: 3));
      } catch (_) {
        // Sampling will explicitly mark unavailable native metrics.
      }
      try {
        final package = await PackageInfo.fromPlatform();
        _appVersion = '${package.version}+${package.buildNumber}';
      } catch (_) {
        _appVersion = null;
      }
      if (_disposed || !_recording) return;
      await _takeSample();
      if (_disposed || !_recording) return;
      _timer = Timer.periodic(sampleInterval, (_) {
        unawaited(
          _takeSample().then((_) {
            if (_samples.length >= maximumSamples) unawaited(stop());
          }),
        );
      });
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _takeSample() {
    if (_recording && _clock.elapsed >= maximumDuration) {
      unawaited(stop());
      return Future.value();
    }
    if (!_recording || _samples.length >= maximumSamples) {
      return Future.value();
    }
    return _sampling ??= _sample().whenComplete(() => _sampling = null);
  }

  Future<void> _sample() async {
    Map<String, dynamic> native = {};
    var available = false;
    try {
      native = await _platform.sample().timeout(const Duration(seconds: 3));
      available = true;
    } catch (_) {
      /* No native measurements are invented on unsupported hosts. */
    }
    int? resident;
    try {
      resident = ProcessInfo.currentRss;
    } catch (_) {
      resident = null;
    }
    final sampledAt = elapsedSeconds;
    try {
      final read = monitoringSnapshot;
      if (read != null) {
        _monitoring = _sanitizeMonitoring(
          await read().timeout(const Duration(seconds: 3)),
        );
      }
    } catch (_) {
      _monitoring = {'available': false};
    }
    if (_disposed || !_recording) return;
    // Explicit allowlist: never serialize the platform payload wholesale.
    num? numeric(String key) {
      final value = native[key];
      return value is num && value.isFinite && value >= 0 ? value : null;
    }

    const thermalNames = {
      'nominal',
      'fair',
      'serious',
      'critical',
      'none',
      'light',
      'moderate',
      'severe',
      'emergency',
      'shutdown',
      'unknown',
    };
    final thermal = native['thermal_state'];
    final state = _monitoring?['worker'] is Map
        ? _monitoring!['worker'] as Map
        : _monitoring;
    final runtime = state?['runtime'];
    if (runtime is Map<String, Object?>) _lastMonitoringRuntime = runtime;
    _samples.add({
      'elapsed_seconds': sampledAt,
      'native_metrics_available': available,
      'process_cpu_percent_one_core': numeric('process_cpu_percent_one_core'),
      'process_resident_bytes': resident,
      'process_footprint_bytes': numeric('process_footprint_bytes'),
      'process_pss_bytes': numeric('process_pss_bytes'),
      'battery_percent': numeric('battery_percent'),
      'charging': native['charging'] is bool ? native['charging'] : null,
      'thermal_state': thermalNames.contains(thermal) ? thermal : null,
      'monitoring_status': state?['status'] ?? _monitoring?['ui_status'],
      'queued_windows': state?['queued_windows'],
      'pending_confirmation_windows': state?['pending_confirmation_windows'],
      'incident_pcm_bytes': state?['incident_pcm_bytes'],
      'monitoring_runtime': runtime,
      'platform_version': native['platform_version'] is String
          ? native['platform_version']
          : null,
      'device_model': native['device_model'] is String
          ? native['device_model']
          : null,
    });
    _notify();
  }

  Map<String, Object?> _sanitizeMonitoring(Map<String, Object?> raw) {
    const statuses = {'idle', 'initializing', 'active', 'paused', 'error'};
    final safe = <String, Object?>{};
    for (final key in ['status', 'ui_status']) {
      if (statuses.contains(raw[key])) safe[key] = raw[key];
    }
    for (final key in [
      'queued_windows',
      'pending_confirmation_windows',
      'incident_pcm_bytes',
    ]) {
      final value = raw[key];
      if (value is num && value.isFinite && value >= 0) safe[key] = value;
    }
    if (raw.containsKey('worker')) {
      final worker = raw['worker'];
      safe['worker'] = worker is Map
          ? _sanitizeMonitoring(Map<String, Object?>.from(worker))
          : null;
    }
    final runtime = raw['runtime'];
    if (runtime is Map) {
      final timings = <String, Object?>{};
      final source = runtime['timings_ms'];
      if (source is Map) {
        for (final name in allowedTimings) {
          final entry = source[name];
          if (entry is! Map) continue;
          final values = <String, num>{};
          for (final key in [
            'count',
            'mean',
            'max',
            'last',
            'recent_p95',
            'recent_count',
          ]) {
            final value = entry[key];
            if (value is num && value.isFinite && value >= 0) {
              values[key] = value;
            }
          }
          timings[name] = values;
        }
      }
      final counters = <String, num>{};
      final sourceCounters = runtime['counters'];
      if (sourceCounters is Map) {
        for (final key in allowedCounters) {
          final value = sourceCounters[key];
          if (value is num && value.isFinite && value >= 0) {
            counters[key] = value;
          }
        }
      }
      safe['runtime'] = {
        'scope': 'since_engine_start',
        'timings_ms': timings,
        'counters': counters,
      };
    }
    return safe;
  }

  Future<void> stop() {
    final stopping = _stopping;
    if (stopping != null) return stopping;
    if (!_recording) return Future.value();
    _recording = false;
    _timer?.cancel();
    _timer = null;
    _stopping = _finishStop().whenComplete(() {
      _stopping = null;
      _notify();
    });
    _notify();
    return _stopping!;
  }

  Future<void> _finishStop() async {
    await _sampling;
    _clock.stop();
    _endedAt = DateTime.now().toUtc();
    try {
      await _platform.end().timeout(const Duration(seconds: 3));
    } catch (_) {
      /* best effort */
    }
    _frozen = _report();
  }

  Map<String, Object?> _report() => {
    'schema_version': 1,
    'app_version': _appVersion,
    'platform': Platform.operatingSystem,
    'build_mode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'started_at_utc': _startedAt?.toIso8601String(),
    'ended_at_utc': _endedAt?.toIso8601String(),
    'duration_seconds': elapsedSeconds,
    'sample_interval_seconds': sampleInterval.inSeconds,
    'sample_limit': maximumSamples,
    'startup': Map<String, double>.from(_startup),
    'runtime': timingSnapshot(),
    'monitoring': _monitoring,
    'last_observed_monitoring_runtime': _lastMonitoringRuntime,
    'evaluation_metrics': pendingEvaluationMetrics(),
    'observed_memory_maxima': {
      'status': 'sampled_process_memory_not_official_background_peak',
      'background_only': false,
      for (final key in [
        'process_resident_bytes',
        'process_footprint_bytes',
        'process_pss_bytes',
      ])
        key: _samples
            .map((s) => s[key])
            .whereType<num>()
            .fold<num?>(
              null,
              (maximum, value) =>
                  maximum == null || value > maximum ? value : maximum,
            ),
    },
    'model_configuration': {
      'sample_rate': AppConstants.sampleRate,
      'window_samples': AppConstants.expectedSampleCount,
      'classification_threshold': AppConstants.classificationThreshold,
      'interpreter_threads': 2,
    },
    'samples': _samples.map((s) => Map<String, Object?>.from(s)).toList(),
    'limitations': [
      'CPU is process CPU time / elapsed time; 100% represents one core and values may exceed 100%.',
      'Footprint (iOS), PSS (Android), and resident memory are different measurements.',
      'Thermal state is not temperature in degrees; battery percentage is not a power measurement.',
      'Timers may be delayed or suspended in background; elapsed sample times show actual cadence.',
      'Timing aggregates are since engine start; recent percentile uses at most the last 128 observations.',
      'First-frame callback measures Dart bootstrap, not full OS cold launch.',
      'Diagnostic collection itself adds a small amount of work.',
    ],
    'privacy':
        'No audio, GPS, labels, probabilities, evidence IDs, keys, paths, or raw errors.',
  };

  Map<String, Object?> report() =>
      jsonDecode(jsonEncode(_frozen ?? _report())) as Map<String, dynamic>;

  Future<void> export() async {
    if (!hasReport || isBusy) return;
    _busy = true;
    _notify();
    try {
      await stop();
      await _platform.share(
        const JsonEncoder.withIndent('  ').convert(report()),
      );
    } finally {
      _busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _recording = false;
    _timer?.cancel();
    _clock.stop();
    unawaited(_platform.end().catchError((Object _) {}));
    super.dispose();
  }
}

class _TimingSummary {
  var count = 0;
  var total = 0.0;
  var maximum = 0.0;
  final List<double> _recent = [];
  void add(double ms) {
    count++;
    total += ms;
    if (ms > maximum) maximum = ms;
    if (_recent.length == 128) _recent.removeAt(0);
    _recent.add(ms);
  }

  Map<String, Object> toJson() {
    final sorted = List<double>.from(_recent)..sort();
    return {
      'count': count,
      'mean': total / count,
      'max': maximum,
      'last': _recent.last,
      'recent_p95': sorted[(sorted.length * .95).ceil() - 1],
      'recent_count': _recent.length,
    };
  }
}
