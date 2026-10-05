import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../../data/datasources/tflite_inference_engine.dart';
import '../../domain/entities/inference_result.dart';

class AudioInferenceIsolate {
  static const _flexDelegateChannel = MethodChannel(
    'com.example.serene/tflite_flex',
  );

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _disposed = Completer<void>();
  final Map<int, Completer<InferenceResult>> _pending = {};
  int? _flexDelegateAddress;
  int _nextRequestId = 0;

  Future<void> initialize() async {
    final modelData = await rootBundle.load('assets/models/model.tflite');
    final modelBytes = modelData.buffer.asUint8List(
      modelData.offsetInBytes,
      modelData.lengthInBytes,
    );
    final labelsRaw = await rootBundle.loadString('assets/labels/labels.txt');
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        _flexDelegateAddress = await _flexDelegateChannel.invokeMethod<int>(
          'createFlexDelegate',
        );
        if (_flexDelegateAddress == null || _flexDelegateAddress == 0) {
          throw StateError(
            'The platform did not create the TensorFlow Flex delegate',
          );
        }
      }

      _receivePort = ReceivePort();
      _receivePort!.listen(_handleMessage);
      _isolate = await Isolate.spawn(
        _inferenceWorkerEntryPoint,
        _InferenceWorkerParams(
          mainSendPort: _receivePort!.sendPort,
          modelBytes: TransferableTypedData.fromList([modelBytes]),
          labelsRaw: labelsRaw,
          flexDelegateAddress: _flexDelegateAddress,
        ),
      );
      await _ready.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  Future<InferenceResult> predict(Float32List samples) {
    final sendPort = _sendPort;
    if (sendPort == null || !_ready.isCompleted) {
      throw StateError('Audio inference worker is not initialized');
    }

    final requestId = _nextRequestId++;
    final completer = Completer<InferenceResult>();
    _pending[requestId] = completer;
    sendPort.send({'type': 'predict', 'id': requestId, 'samples': samples});
    return completer.future;
  }

  void _handleMessage(Object? message) {
    if (message is SendPort) {
      _sendPort = message;
      return;
    }
    if (message is! Map) return;

    switch (message['type']) {
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
      case 'initializationError':
        _sendPort = null;
        if (!_ready.isCompleted) {
          _ready.completeError(StateError(message['message'] as String));
        }
      case 'result':
        final requestId = message['id'] as int;
        final completer = _pending.remove(requestId);
        if (completer == null) return;
        final scores = (message['scores'] as Map).map(
          (key, value) => MapEntry(key as String, value as double),
        );
        completer.complete(
          InferenceResult(
            label: message['label'] as String,
            confidence: message['confidence'] as double,
            allScores: scores,
            isViolenceDetected: message['isViolenceDetected'] as bool,
          ),
        );
      case 'predictionError':
        final requestId = message['id'] as int;
        final completer = _pending.remove(requestId);
        completer?.completeError(StateError(message['message'] as String));
      case 'disposed':
        if (!_disposed.isCompleted) _disposed.complete();
    }
  }

  Future<void> dispose() async {
    final sendPort = _sendPort;
    if (sendPort != null) {
      sendPort.send({'type': 'dispose'});
      try {
        await _disposed.future.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        _isolate?.kill(priority: Isolate.immediate);
      }
    } else {
      _isolate?.kill(priority: Isolate.immediate);
    }

    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Audio inference worker stopped'));
      }
    }
    _pending.clear();
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;
    _isolate = null;

    if (_flexDelegateAddress != null) {
      await _flexDelegateChannel.invokeMethod<void>('disposeFlexDelegate');
      _flexDelegateAddress = null;
    }
  }
}

@pragma('vm:entry-point')
void _inferenceWorkerEntryPoint(_InferenceWorkerParams params) {
  final receivePort = ReceivePort();
  params.mainSendPort.send(receivePort.sendPort);

  final engine = TfliteInferenceEngine();
  try {
    engine
        .initialize(
          modelBytes: params.modelBytes.materialize().asUint8List(),
          labelsRaw: params.labelsRaw,
          flexDelegateAddress: params.flexDelegateAddress,
        )
        .then((_) {
          params.mainSendPort.send({'type': 'ready'});
          receivePort.listen((message) {
            if (message is! Map) return;
            if (message['type'] == 'dispose') {
              engine.close();
              params.mainSendPort.send({'type': 'disposed'});
              receivePort.close();
              return;
            }
            if (message['type'] != 'predict') return;

            final requestId = message['id'] as int;
            try {
              final result = engine.predict(message['samples'] as Float32List);
              params.mainSendPort.send({
                'type': 'result',
                'id': requestId,
                'label': result.label,
                'confidence': result.confidence,
                'scores': result.allScores,
                'isViolenceDetected': result.isViolenceDetected,
              });
            } catch (error) {
              params.mainSendPort.send({
                'type': 'predictionError',
                'id': requestId,
                'message': error.toString(),
              });
            }
          });
        })
        .catchError((Object error) {
          params.mainSendPort.send({
            'type': 'initializationError',
            'message': error.toString(),
          });
          receivePort.close();
        });
  } catch (error) {
    params.mainSendPort.send({
      'type': 'initializationError',
      'message': error.toString(),
    });
    receivePort.close();
  }
}

class _InferenceWorkerParams {
  const _InferenceWorkerParams({
    required this.mainSendPort,
    required this.modelBytes,
    required this.labelsRaw,
    required this.flexDelegateAddress,
  });

  final SendPort mainSendPort;
  final TransferableTypedData modelBytes;
  final String labelsRaw;
  final int? flexDelegateAddress;
}
