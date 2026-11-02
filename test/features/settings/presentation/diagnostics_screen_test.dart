import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:serene/app/controllers/app_settings_controller.dart';
import 'package:serene/core/models/app_settings.dart';
import 'package:serene/core/services/diagnostics_service.dart';
import 'package:serene/features/settings/presentation/screens/diagnostics_screen.dart';

class ScreenPlatform extends DiagnosticPlatform {
  String? shared;
  @override
  Future<void> begin() async {}
  @override
  Future<void> end() async {}
  @override
  Future<Map<String, dynamic>> sample() async => {
    'process_cpu_percent_one_core': 45.0,
    'process_footprint_bytes': 104857600,
    'battery_percent': 77,
    'thermal_state': 'nominal',
  };
  @override
  Future<void> share(String json) async {
    shared = json;
  }
}

void main() {
  late Directory directory;
  late AppSettingsController settings;
  late ScreenPlatform native;
  late DiagnosticsService diagnostics;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('serene_diag_ui_');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
    settings = AppSettingsController(
      box: await Hive.openBox<AppSettings>('appSettings'),
    );
    native = ScreenPlatform();
    diagnostics = DiagnosticsService(platform: native);
    PackageInfo.setMockInitialValues(
      appName: 'Serene',
      packageName: 'com.example.serene',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(() async {
    await diagnostics.stop();
    diagnostics.dispose();
    settings.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  testWidgets('phone screen measures, shows values and exports JSON', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(home: DiagnosticsScreen(service: diagnostics)),
      ),
    );
    final export = find.byKey(const ValueKey('diagnostics_export'));
    expect(tester.widget<OutlinedButton>(export).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('diagnostics_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('45.0 %'), findsOneWidget);
    expect(find.text('100.0 MiB'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(export).onPressed, isNotNull);
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(diagnostics.isRecording, isFalse);
    final report = jsonDecode(native.shared!) as Map;
    expect(report['samples'], hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
