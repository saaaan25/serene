import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:serene/features/audio_monitoring/data/datasources/audio_stream_datasource.dart';
import 'package:serene/features/audio_monitoring/data/repositories/monitoring_repository_impl.dart';
import 'package:serene/features/audio_monitoring/domain/entities/audio_window.dart';

class FakeAudioStreamDataSource implements AudioStreamDataSource {
  final StreamController<Uint8List> controller = StreamController<Uint8List>();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream() async => controller.stream;

  @override
  Future<void> stopStream() async {
    await controller.close();
  }
}

void main() {
  for (final chunks in [
    <int>[256000],
    <int>[1, 32002, 70003, 153994],
  ]) {
    test(
      'PCM alignment and exact strides survive chunk sizes $chunks',
      () async {
        final source = FakeAudioStreamDataSource();
        final repository = MonitoringRepositoryImpl(
          audioStreamDataSource: source,
        );
        final windows = <AudioWindow>[];
        final subscription = (await repository.startMicrophoneStream()).listen(
          windows.add,
        );
        final pcm = Uint8List(256000);
        final data = ByteData.sublistView(pcm);
        for (var i = 0; i < 128000; i++) {
          data.setInt16(i * 2, (i % 20000) - 10000, Endian.little);
        }
        var offset = 0;
        for (final size in chunks) {
          source.controller.add(
            Uint8List.sublistView(pcm, offset, offset + size),
          );
          offset += size;
        }
        await Future<void>.delayed(Duration.zero);
        expect(windows.map((w) => w.endSampleIndex), [
          80000,
          96000,
          112000,
          128000,
        ]);
        for (final window in windows) {
          final end = window.endSampleIndex!;
          expect(
            window.rawPcmBytes,
            orderedEquals(pcm.sublist((end - 80000) * 2, end * 2)),
          );
          for (final index in [0, 100, 79999]) {
            expect(
              window.normalizedSamples[index],
              closeTo(
                data.getInt16((end - 80000 + index) * 2, Endian.little) / 32768,
                1e-7,
              ),
            );
          }
        }
        expect(
          windows.last.timestamp.difference(windows.first.timestamp),
          const Duration(seconds: 3),
        );
        await repository.stopMicrophoneStream();
        await subscription.cancel();
      },
    );
  }

  test(
    'graceful stop emits the remaining partial second for incident persistence',
    () async {
      final source = FakeAudioStreamDataSource();
      final repository = MonitoringRepositoryImpl(
        audioStreamDataSource: source,
      );
      final windows = <AudioWindow>[];
      final stream = await repository.startMicrophoneStream();
      final subscription = stream.listen(windows.add);
      source.controller.add(Uint8List(160000));
      await Future<void>.delayed(Duration.zero);
      source.controller.add(Uint8List(16000));
      await Future<void>.delayed(Duration.zero);
      await repository.stopMicrophoneStream();
      expect(windows, hasLength(2));
      expect(windows.first.endSampleIndex, 80000);
      expect(windows.last.endSampleIndex, 88000);
      expect(windows.last.rawPcmBytes.length, 160000);
      await subscription.cancel();
    },
  );

  test('only emits full five-second windows and samples each second', () async {
    final source = FakeAudioStreamDataSource();
    final repository = MonitoringRepositoryImpl(audioStreamDataSource: source);
    final windows = <AudioWindow>[];
    final stream = await repository.startMicrophoneStream();
    final subscription = stream.listen(windows.add);
    final halfSecondChunk = Uint8List(16000);

    for (var i = 0; i < 9; i++) {
      source.controller.add(halfSecondChunk);
    }
    await Future<void>.delayed(Duration.zero);
    expect(windows, isEmpty);

    source.controller.add(halfSecondChunk);
    await Future<void>.delayed(Duration.zero);
    expect(windows, hasLength(1));
    expect(windows.first.normalizedSamples, hasLength(80000));
    expect(windows.first.rawPcmBytes, hasLength(160000));

    source.controller
      ..add(halfSecondChunk)
      ..add(halfSecondChunk);
    await Future<void>.delayed(Duration.zero);
    expect(windows, hasLength(2));

    await subscription.cancel();
    await repository.stopMicrophoneStream();
  });
}
