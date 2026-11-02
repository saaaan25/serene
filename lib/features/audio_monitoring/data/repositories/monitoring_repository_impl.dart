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
  int? _pendingByte;
  DateTime? _streamStartedAt;

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
    _pendingByte = null;
    _streamStartedAt = DateTime.now();
    _windowStreamController = StreamController<AudioWindow>.broadcast();

    try {
      final audioStream = await audioStreamDataSource.startStream();
      _micSubscription = audioStream.listen(
        _consumeChunk,
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

  void _consumeChunk(Uint8List chunk) {
    if (chunk.isEmpty) return;
    final Uint8List bytes;
    if (_pendingByte != null) {
      bytes = Uint8List(chunk.length + 1)..[0] = _pendingByte!;
      bytes.setRange(1, bytes.length, chunk);
      _pendingByte = null;
    } else {
      bytes = chunk;
    }
    final alignedLength = bytes.length - bytes.length % 2;
    if (bytes.length.isOdd) _pendingByte = bytes.last;
    var offset = 0;
    while (offset < alignedLength) {
      final needed = !_bufferManager.isFull
          ? AppConstants.expectedSampleCount - _totalSamples
          : AppConstants.sampleRate - _samplesSinceLastWindow;
      final available = (alignedLength - offset) ~/ 2;
      final count = available < needed ? available : needed;
      final pcm = Uint8List.sublistView(bytes, offset, offset + count * 2);
      _rawPcmAccumulator.addAll(pcm);
      _bufferManager.appendSamples(
        SignalNormalizer.pcm16ToNormalizedFloat32(pcm),
      );
      _samplesSinceLastWindow += count;
      _totalSamples += count;
      offset += count * 2;
      final excess =
          _rawPcmAccumulator.length - AppConstants.expectedSampleCount * 2;
      if (excess > 0) _rawPcmAccumulator.removeRange(0, excess);
      if (_bufferManager.isFull &&
          _samplesSinceLastWindow >= AppConstants.sampleRate) {
        _samplesSinceLastWindow = 0;
        _emitWindow();
      }
    }
  }

  void _emitWindow() {
    _windowStreamController?.add(
      AudioWindow(
        normalizedSamples: _bufferManager.getOrderedSnapshot(),
        rawPcmBytes: Uint8List.fromList(_rawPcmAccumulator),
        timestamp: _streamStartedAt!.add(
          Duration(
            microseconds: _totalSamples * 1000000 ~/ AppConstants.sampleRate,
          ),
        ),
        endSampleIndex: _totalSamples,
      ),
    );
  }

  @override
  Future<void> stopMicrophoneStream() async {
    await _micSubscription?.cancel();
    _micSubscription = null;
    await audioStreamDataSource.stopStream();
    if (_bufferManager.isFull && _samplesSinceLastWindow > 0) {
      _emitWindow();
    }
    _bufferManager.purge();
    _rawPcmAccumulator.clear();
    _samplesSinceLastWindow = 0;
    _pendingByte = null;
    _streamStartedAt = null;
    await _windowStreamController?.close();
    _windowStreamController = null;
  }
}
