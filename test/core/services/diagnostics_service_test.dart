import 'dart:convert';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:serene/core/services/diagnostics_service.dart';

class FakeDiagnosticPlatform extends DiagnosticPlatform {
  int samples = 0;
  int starts = 0;
  int stops = 0;
  bool unavailable = false;
  bool shareFails = false;
  Completer<void>? endGate;
  String? shared;
  @override
  Future<void> begin() async {
    starts++;
  }

  @override
  Future<void> end() async {
    stops++;
    await endGate?.future;
  }

  @override
  Future<Map<String, dynamic>> sample() async {
    if (unavailable) throw MissingPluginException();
    samples++;
    return {
      'process_cpu_percent_one_core': 125.0,
      'process_footprint_bytes': 123000000,
      'battery_percent': 80,
      'thermal_state': 'fair',
      'charging': false,
      'device_model': 'iPhone14,2',
      'platform_version': '26.0',
      'audio': 'do-not-export',
      'gps': 'do-not-export',
      'exception': '/private/do-not-export',
    };
  }

  @override
  Future<void> share(String json) async {
    if (shareFails) throw PlatformException(code: 'sharing_failed');
    shared = json;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Serene',
      packageName: 'com.example.serene',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'exports pending official metrics separately from sampled maxima',
    (tester) async {
      final service = DiagnosticsService(platform: FakeDiagnosticPlatform());
      addTearDown(service.dispose);
      await service.start();
      await service.stop();
      final report = service.report();
      final metrics = report['evaluation_metrics'] as Map;
      expect((metrics['host_invoke'] as Map)['median_ms'], isNull);
      expect((metrics['storage_reduction'] as Map)['percent'], isNull);
      expect(
        (metrics['official_background_peak_ram'] as Map)['peak_bytes'],
        isNull,
      );
      final observed = report['observed_memory_maxima'] as Map;
      expect(observed['process_footprint_bytes'], 123000000);
      expect(observed['background_only'], isFalse);
    },
  );

  testWidgets('cannot restart while a previous native stop is pending', (
    tester,
  ) async {
    final native = FakeDiagnosticPlatform();
    final service = DiagnosticsService(platform: native);
    addTearDown(service.dispose);
    await service.start();
    native.endGate = Completer<void>();
    final stopping = service.stop();
    expect(service.isBusy, isTrue);
    await service.start();
    expect(native.starts, 1);
    native.endGate!.complete();
    await stopping;
    expect(service.isBusy, isFalse);
    await service.start();
    expect(native.starts, 2);
    await service.stop();
  });

  testWidgets(
    'sampling is opt in, periodic, and stops without changing monitoring',
    (tester) async {
      final native = FakeDiagnosticPlatform();
      final service = DiagnosticsService(platform: native);
      addTearDown(service.dispose);
      service.recordDuration('inference', const Duration(milliseconds: 200));
      expect(native.samples, 0);
      await service.start();
      expect(native.samples, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(native.samples, 2);
      await service.stop();
      await tester.pump(const Duration(seconds: 20));
      expect(native.samples, 2);
      expect(service.isRecording, isFalse);
      expect(service.report()['ended_at_utc'], isNotNull);
      expect(service.latestSample!['process_cpu_percent_one_core'], 125);
    },
  );

  testWidgets(
    'exports a frozen JSON and strips private platform and worker fields',
    (tester) async {
      final native = FakeDiagnosticPlatform();
      final service = DiagnosticsService(platform: native);
      addTearDown(service.dispose);
      service.recordDuration('inference', const Duration(milliseconds: 100));
      service.recordDuration('do-not-export', const Duration(milliseconds: 99));
      service.monitoringSnapshot = () async => {
        'ui_status': 'active',
        'audio': 'do-not-export',
        'worker': {
          'status': 'active',
          'queued_windows': 2,
          'record_id': 'do-not-export',
          'runtime': {
            'timings_ms': {
              'inference': {
                'count': 1,
                'mean': 250,
                'raw_audio': 'do-not-export',
              },
              'do-not-export': {'mean': 3},
            },
            'counters': {
              'processing_failures': 0,
              'raw_error': 'do-not-export',
            },
          },
        },
      };
      await service.start();
      await service.export();
      expect(service.isRecording, isFalse);
      final report = jsonDecode(native.shared!) as Map;
      expect(report['schema_version'], 1);
      expect(report['app_version'], '1.0.0+1');
      expect((report['samples'] as List).single['queued_windows'], 2);
      expect(native.shared, isNot(contains('do-not-export')));
      service.recordDuration('inference', const Duration(seconds: 5));
      final after = service.report();
      expect(
        ((after['runtime'] as Map)['timings_ms'] as Map)['inference']['count'],
        1,
      );
    },
  );

  testWidgets(
    'native metrics unavailable remain null instead of estimated CPU',
    (tester) async {
      final native = FakeDiagnosticPlatform()..unavailable = true;
      final service = DiagnosticsService(platform: native);
      addTearDown(service.dispose);
      await service.start();
      expect(service.latestSample!['native_metrics_available'], isFalse);
      expect(service.latestSample!['process_cpu_percent_one_core'], isNull);
      expect(service.latestSample!['thermal_state'], isNull);
      await service.stop();
    },
  );

  testWidgets('sample count is bounded and measurement stops automatically', (
    tester,
  ) async {
    final native = FakeDiagnosticPlatform();
    final service = DiagnosticsService(platform: native);
    addTearDown(service.dispose);
    await service.start();
    for (var i = 0; i < DiagnosticsService.maximumSamples + 5; i++) {
      await tester.pump(DiagnosticsService.sampleInterval);
    }
    expect(service.sampleCount, DiagnosticsService.maximumSamples);
    expect(service.isRecording, isFalse);
    final calls = native.samples;
    await tester.pump(const Duration(hours: 1));
    expect(native.samples, calls);
  });

  testWidgets(
    'failed export preserves report and releases busy state for retry',
    (tester) async {
      final native = FakeDiagnosticPlatform()..shareFails = true;
      final service = DiagnosticsService(platform: native);
      addTearDown(service.dispose);
      await service.start();
      await expectLater(service.export(), throwsA(isA<PlatformException>()));
      expect(service.isBusy, isFalse);
      expect(service.hasReport, isTrue);
      native.shareFails = false;
      await service.export();
      expect(native.shared, isNotNull);
    },
  );

  test('timing aggregates keep totals and bound recent observations', () {
    final native = FakeDiagnosticPlatform();
    final service = DiagnosticsService(platform: native);
    addTearDown(service.dispose);
    for (var i = 0; i < 1000; i++) {
      service.recordDuration('inference', Duration(milliseconds: i));
    }
    final summary =
        (service.timingSnapshot()['timings_ms'] as Map)['inference'] as Map;
    expect(summary['count'], 1000);
    expect(summary['mean'], 499.5);
    expect(summary['max'], 999);
    expect(summary['recent_count'], 128);
    service.recordFailure('raw_error');
    expect(service.timingSnapshot()['counters'], isEmpty);
  });
}
