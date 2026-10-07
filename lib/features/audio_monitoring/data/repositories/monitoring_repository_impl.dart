import 'dart:async';
import 'dart:typed_data';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/dsp/audio_buffer_manager.dart';
import '../../../../core/dsp/signal_normalizer.dart';
import '../../domain/entities/audio_window.dart';
import '../../domain/repositories/monitoring_repository.dart';
import '../datasources/audio_stream_datasource.dart';

class MonitoringRepositoryImpl implements MonitoringRepository {
  final AudioStreamDataSource audioStreamDataSource;
  final AudioBufferManager _bufferManager;

  StreamController<AudioWindow>? _windowStreamController;
  StreamSubscription<Uint8List>? _micSubscription;
  final List<int> _rawPcmAccumulator = [];
  int _samplesSinceLastWindow = 0;
  int _totalSamples = 0;

  MonitoringRepositoryImpl({
    required this.audioStreamDataSource,
    AudioBufferManager? bufferManager,
  }) : _bufferManager = bufferManager ?? AudioBufferManager();

  @override
  Future<bool> hasMicrophonePermission() =>
      audioStreamDataSource.hasPermission();

  @override
  Future<Stream<AudioWindow>> startMicrophoneStream() async {
    await _micSubscription?.cancel();
    await _windowStreamController?.close();
    _micSubscription = null;
    _bufferManager.purge();
    _rawPcmAccumulator.clear();
    _samplesSinceLastWindow = 0;
    _totalSamples = 0;
    _windowStreamController = StreamController<AudioWindow>.broadcast();

    try {
      final audioStream = await audioStreamDataSource.startStream();
      _micSubscription = audioStream.listen(
        (pcmChunk) {
          _rawPcmAccumulator.addAll(pcmChunk);

          final normalizedSamples = SignalNormalizer.pcm16ToNormalizedFloat32(
            pcmChunk,
          );
          _bufferManager.appendSamples(normalizedSamples);
          _samplesSinceLastWindow += normalizedSamples.length;
          _totalSamples += normalizedSamples.length;

          final maxRawBytes = AppConstants.expectedSampleCount * 2;
          if (_rawPcmAccumulator.length > maxRawBytes) {
            _rawPcmAccumulator.removeRange(
              0,
              _rawPcmAccumulator.length - maxRawBytes,
            );
          }

          if (_bufferManager.isFull &&
              _samplesSinceLastWindow >= AppConstants.sampleRate) {
            _samplesSinceLastWindow = 0;
            _windowStreamController?.add(
              AudioWindow(
                normalizedSamples: _bufferManager.getOrderedSnapshot(),
                rawPcmBytes: Uint8List.fromList(_rawPcmAccumulator),
                timestamp: DateTime.now(),
                endSampleIndex: _totalSamples,
              ),
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _windowStreamController?.addError(error, stackTrace);
        },
        onDone: () => _windowStreamController?.close(),
      );
    } catch (_) {
      await _windowStreamController?.close();
      _windowStreamController = null;
      rethrow;
    }

    return _windowStreamController!.stream;
  }

  @override
  Future<void> stopMicrophoneStream() async {
    await _micSubscription?.cancel();
    _micSubscription = null;
    await audioStreamDataSource.stopStream();
    if (_bufferManager.isFull && _samplesSinceLastWindow > 0) {
      _windowStreamController?.add(
        AudioWindow(
          normalizedSamples: _bufferManager.getOrderedSnapshot(),
          rawPcmBytes: Uint8List.fromList(_rawPcmAccumulator),
          timestamp: DateTime.now(),
          endSampleIndex: _totalSamples,
        ),
      );
    }
    _bufferManager.purge();
    _rawPcmAccumulator.clear();
    _samplesSinceLastWindow = 0;
    await _windowStreamController?.close();
    _windowStreamController = null;
  }
}
