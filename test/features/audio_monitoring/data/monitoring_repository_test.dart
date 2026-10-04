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
