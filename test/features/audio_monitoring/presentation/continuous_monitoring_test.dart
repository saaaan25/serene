import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/core/errors/failures.dart';
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

  for (final cap in [
    const Duration(seconds: 6),
    const Duration(milliseconds: 6500),
  ]) {
    test(
      'duration cap ${cap.inMilliseconds}ms continues without duplicated or missing samples',
      () async {
        final process = ProcessMock();
        final save = SaveMock();
        final stream = StreamController<AudioWindow>();
        final saved = <SaveEncryptedEvidenceParams>[];
        final inference = InferenceFake(List.filled(5, fixtures.violence));
        when(
          () => process.hasMicrophonePermission(),
        ).thenAnswer((_) async => true);
        when(
          () => process.getAudioStream(),
        ).thenAnswer((_) async => stream.stream);
        when(() => process.stop()).thenAnswer((_) async {
          await stream.close();
        });
        when(() => save.call(any())).thenAnswer((call) async {
          saved.add(
            call.positionalArguments.first as SaveEncryptedEvidenceParams,
          );
        });
        final controller = MonitoringController(
          processAudioUseCase: process,
          saveEvidenceUseCase: save,
          inferenceFactory: () => inference,
          coordinatesProvider: () async => {},
          maximumIncidentDuration: cap,
        );
        await controller.startMonitoring();
        for (var second = 5; second <= 9; second++) {
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
        await Future<void>.delayed(Duration.zero);
        await controller.pauseMonitoring();
        final latest = <String, SaveEncryptedEvidenceParams>{
          for (final item in saved) item.evidenceId!: item,
        };
        expect(latest.length, 2);
        final audio = BytesBuilder();
        for (final item in latest.values) {
          expect(
            item.rawAudioBytes.length,
            lessThanOrEqualTo(cap.inMicroseconds * 32000 ~/ 1000000),
          );
          audio.add(item.rawAudioBytes);
        }
        final bytes = audio.toBytes();
        expect(bytes.length, 9 * 32000);
        for (var second = 1; second <= 9; second++) {
          expect(
            bytes.sublist((second - 1) * 32000, second * 32000),
            everyElement(second),
          );
        }
        controller.dispose();
        await Future<void>.delayed(Duration.zero);
      },
    );
  }

  test(
    'capacity failure stops capture, preserves the last checkpoint, and skips queued saves',
    () async {
      final process = ProcessMock();
      final save = SaveMock();
      final stream = StreamController<AudioWindow>();
      final stopped = Completer<void>();
      final inference = InferenceFake(List.filled(20, fixtures.violence));
      var attempts = 0;
      when(
        () => process.hasMicrophonePermission(),
      ).thenAnswer((_) async => true);
      when(
        () => process.getAudioStream(),
      ).thenAnswer((_) async => stream.stream);
      when(() => process.stop()).thenAnswer((_) async {
        await stream.close();
        stopped.complete();
      });
      when(() => save.call(any())).thenAnswer((_) async {
        attempts++;
        if (attempts == 2) {
          throw const StorageCapacityFailure('Espacio insuficiente');
        }
      });
      final controller = MonitoringController(
        processAudioUseCase: process,
        saveEvidenceUseCase: save,
        inferenceFactory: () => inference,
        coordinatesProvider: () async => {},
      );
      await controller.startMonitoring();
      for (var second = 5; second <= 22; second++) {
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
      await stopped.future;
      expect(controller.status, MonitoringStatus.error);
      expect(controller.isStorageBlocked, isTrue);
      expect(controller.errorMessage, contains('Espacio insuficiente'));
      await controller.pauseMonitoring();
      expect(attempts, 2); // no repeated final save into the full volume
      expect(inference.disposed, isTrue);
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

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
    expect(saved.last.rawAudioBytes.length, (closeWithQuiet ? 7 : 6) * 32000);
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
