import 'dart:async';
import 'dart:isolate';
import 'package:flutter/services.dart';
import '../../domain/entities/audio_window.dart';
import '../../domain/entities/inference_result.dart';
import '../../domain/usecases/process_audio_stream_usecase.dart';

enum IsolateCommand { start, stop, dispose }

class IsolateMessage {
  final IsolateCommand command;
  final dynamic payload;

  const IsolateMessage(this.command, [this.payload]);
}

/// Paquete emitido desde el Isolate hacia el hilo principal ante una detección positiva
class IncidentDetectionPayload {
  final AudioWindow window;
  final InferenceResult result;

  const IncidentDetectionPayload({
    required this.window,
    required this.result,
  });
}

class AudioProcessingIsolate {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _isolateSendPort;
  StreamSubscription? _portSubscription;

  final void Function(IncidentDetectionPayload payload) onIncidentDetected;
  final void Function(String error) onError;

  AudioProcessingIsolate({
    required this.onIncidentDetected,
    required this.onError,
  });

  /// Start the isolate and set up communication channels
  Future<void> spawn({
    required RootIsolateToken rootToken,
    required ProcessAudioStreamUseCase processUseCase,
  }) async {
    _receivePort = ReceivePort();

    // Spawn the isolate and pass the initialization parameters
    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _IsolateInitParams(
        token: rootToken,
        sendPort: _receivePort!.sendPort,
        useCase: processUseCase,
      ),
    );

    // Listen for incoming events from the Isolate
    _portSubscription = _receivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        // Once the port is connected, send the start command
        _isolateSendPort?.send(const IsolateMessage(IsolateCommand.start));
      } else if (message is IncidentDetectionPayload) {
        onIncidentDetected(message);
      } else if (message is String) {
        onError(message);
      }
    });
  }

  /// Static entry function that runs in the isolate
  static void _isolateEntryPoint(_IsolateInitParams params) {
    // Initialize the binary messenger so the Isolate can use native plugins
    BackgroundIsolateBinaryMessenger.ensureInitialized(params.token);

    final isolateReceivePort = ReceivePort();
    params.sendPort.send(isolateReceivePort.sendPort);

    StreamSubscription<AudioWindow>? audioSubscription;

    isolateReceivePort.listen((message) async {
      if (message is IsolateMessage) {
        switch (message.command) {
          case IsolateCommand.start:
            audioSubscription = params.useCase.getAudioStream().listen(
              (window) async {
                try {
                  // Execution of the TFLite inference in the background isolate
                  final result = await params.useCase.execute(window);

                  // If violence is confirmed, notify the main isolate
                  if (result.isViolenceDetected) {
                    params.sendPort.send(
                      IncidentDetectionPayload(window: window, result: result),
                    );
                  }
                } catch (e) {
                  params.sendPort.send('Inference failure in Isolate: $e');
                }
              },
              onError: (err) => params.sendPort.send('Error: $err'),
            );
            break;

          case IsolateCommand.stop:
            await audioSubscription?.cancel();
            await params.useCase.stop();
            break;

          case IsolateCommand.dispose:
            await audioSubscription?.cancel();
            await params.useCase.stop();
            isolateReceivePort.close();
            break;
        }
      }
    });
  }

  Future<void> stop() async {
    _isolateSendPort?.send(const IsolateMessage(IsolateCommand.stop));
  }

  void dispose() {
    _isolateSendPort?.send(const IsolateMessage(IsolateCommand.dispose));
    _portSubscription?.cancel();
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

class _IsolateInitParams {
  final RootIsolateToken token;
  final SendPort sendPort;
  final ProcessAudioStreamUseCase useCase;

  const _IsolateInitParams({
    required this.token,
    required this.sendPort,
    required this.useCase,
  });
}