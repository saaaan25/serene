import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/features/audio_monitoring/domain/entities/audio_window.dart';
import 'package:serene/features/audio_monitoring/domain/entities/inference_result.dart';
import 'package:serene/features/audio_monitoring/domain/usecases/process_audio_stream_usecase.dart';
import 'package:serene/features/audio_monitoring/presentation/controllers/monitoring_controller.dart';
import 'package:serene/features/audio_monitoring/presentation/isolates/audio_processing_isolate.dart';
import 'package:serene/features/evidence_vault/domain/usecases/save_encrypted_evidence_usecase.dart';
import 'incident_recording_test.dart' as fixtures;

class ProcessMock extends Mock implements ProcessAudioStreamUseCase {}

class SaveMock extends Mock implements SaveEncryptedEvidenceUseCase {}

class ParamsFake extends Fake implements SaveEncryptedEvidenceParams {}

class InferenceFake extends AudioInferenceIsolate {
  final List<InferenceResult> results;
  int calls = 0;
  bool disposed = false;
  InferenceFake(this.results);
  @override
  Future<void> initialize() async {}
  @override
  Future<InferenceResult> predict(Float32List samples) async =>
      results[calls++];
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(ParamsFake()));

  Future<void> exercise({required bool closeWithQuiet}) async {
    final process = ProcessMock();
    final save = SaveMock();
    final stream = StreamController<AudioWindow>();
    final saved = <SaveEncryptedEvidenceParams>[];
    final inference = InferenceFake([
      fixtures.violence,
      fixtures.violence,
      if (closeWithQuiet) ...[
        fixtures.normal,
        fixtures.normal,
        fixtures.normal,
      ],
    ]);
    when(() => process.hasMicrophonePermission()).thenAnswer((_) async => true);
    when(() => process.getAudioStream()).thenAnswer((_) async => stream.stream);
    when(() => process.stop()).thenAnswer((_) async {
      await stream.close();
    });
    when(() => save.call(any())).thenAnswer((invocation) async {
      saved.add(
        invocation.positionalArguments.first as SaveEncryptedEvidenceParams,
      );
    });
    final controller = MonitoringController(
      processAudioUseCase: process,
      saveEvidenceUseCase: save,
      inferenceFactory: () => inference,
      coordinatesProvider: () async => {},
    );
    await controller.startMonitoring();
    expect(controller.status, MonitoringStatus.active);
    controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(controller.status, MonitoringStatus.active);
    for (var second = 5; second <= (closeWithQuiet ? 9 : 6); second++) {
      final raw = fixtures.window(second);
      stream.add(
        AudioWindow(
          normalizedSamples: Float32List.fromList(List.filled(80000, .1)),
          rawPcmBytes: raw.rawPcmBytes,
          timestamp: raw.timestamp,
          endSampleIndex: raw.endSampleIndex,
        ),
      );
    }
    // pause drains all queued windows and checkpoints an open incident.
    await Future<void>.delayed(Duration.zero);
    await controller.pauseMonitoring();
    expect(controller.status, MonitoringStatus.paused);
    expect(saved.length, 2);
    expect(saved.map((p) => p.evidenceId).toSet().length, 1);
    expect(saved.first.rawAudioBytes.length, 5 * 32000);
    expect(saved.last.rawAudioBytes.length, (closeWithQuiet ? 9 : 6) * 32000);
    expect(saved.last.startedAt, DateTime.utc(2026));
    expect(inference.disposed, isTrue);
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'one incident continues through positive windows and closes after quiet',
    () => exercise(closeWithQuiet: true),
  );
  test(
    'manual stop saves the entire open incident before releasing inference',
    () => exercise(closeWithQuiet: false),
  );
}
