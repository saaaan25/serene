import 'dart:async';
import 'dart:typed_data';
import '../../../../core/dsp/audio_buffer_manager.dart';
import '../../../../core/dsp/signal_normalizer.dart';
import '../../domain/entities/audio_window.dart';
import '../../domain/entities/inference_result.dart';
import '../../domain/repositories/monitoring_repository.dart';
import '../datasources/audio_stream_datasource.dart';
import '../datasources/tflite_inference_engine.dart';

class MonitoringRepositoryImpl implements MonitoringRepository {
  final AudioStreamDataSource audioStreamDataSource;
  final TfliteInferenceEngine inferenceEngine;
  final AudioBufferManager _bufferManager;

  StreamController<AudioWindow>? _windowStreamController;
  StreamSubscription<Uint8List>? _micSubscription;
  final List<int> _rawPcmAccumulator = [];

  MonitoringRepositoryImpl({
    required this.audioStreamDataSource,
    required this.inferenceEngine,
    AudioBufferManager? bufferManager,
  }) : _bufferManager = bufferManager ?? AudioBufferManager();

  @override
  Future<void> initializeEngine() async {
    if (!inferenceEngine.isInitialized) {
      await inferenceEngine.initialize();
    }
  }

  @override
  Stream<AudioWindow> startMicrophoneStream() {
    _windowStreamController = StreamController<AudioWindow>.broadcast();

    audioStreamDataSource.startStream().then((stream) {
      _micSubscription = stream.listen((pcmChunk) {
        _rawPcmAccumulator.addAll(pcmChunk);

        // Normalization [-1.0, 1.0]
        final normalizedFloats = SignalNormalizer.pcm16ToNormalizedFloat32(pcmChunk);

        // Append normalized samples to the buffer manager
        _bufferManager.appendSamples(normalizedFloats);

        // Generate an AudioWindow from the current buffer snapshot
        final windowFloats = _bufferManager.getOrderedSnapshot();

        _windowStreamController?.add(
          AudioWindow(
            normalizedSamples: windowFloats,
            rawPcmBytes: Uint8List.fromList(_rawPcmAccumulator),
            timestamp: DateTime.now(),
          ),
        );

        // Cleanup of raw PCM buffer (maximum 5 seconds = 160,000 bytes)
        const maxRawBytes = 160000;
        if (_rawPcmAccumulator.length > maxRawBytes) {
          _rawPcmAccumulator.removeRange(0, _rawPcmAccumulator.length - maxRawBytes);
        }
      }, onError: (error) {
        _windowStreamController?.addError(error);
      });
    }).catchError((error) {
      _windowStreamController?.addError(error);
    });

    return _windowStreamController!.stream;
  }

  @override
  Future<void> stopMicrophoneStream() async {
    await _micSubscription?.cancel();
    _micSubscription = null;
    await audioStreamDataSource.stopStream();
    _bufferManager.purge();
    _rawPcmAccumulator.clear();
    await _windowStreamController?.close();
    _windowStreamController = null;
  }

  @override
  Future<InferenceResult> runInference(Float32List audioWindow) async {
    return inferenceEngine.predict(audioWindow);
  }

  @override
  void disposeEngine() {
    inferenceEngine.close();
  }
}