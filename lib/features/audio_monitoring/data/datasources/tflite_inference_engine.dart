import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
// tflite_flutter does not publicly export the native delegate pointer type.
// ignore: implementation_imports
import 'package:tflite_flutter/src/bindings/tensorflow_lite_bindings_generated.dart'
    show TfLiteDelegate;
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/inference_result.dart';

/// Simbolo C exportado por el pod `TensorFlowLiteSelectTfOps`
/// (`tensorflow/lite/delegates/flex/delegate_symbol.cc`).
///
/// TensorFlow Lite lo resuelve por su cuenta desde
/// `InterpreterBuilder::ApplyDelegates()`, pero unicamente si el modelo tiene
/// ops Flex y mediante `dlsym(RTLD_DEFAULT, "TF_AcquireFlexDelegate")`. Si el
/// enlazador elimina ese simbolo del binario, el delegate nunca se aplica, el
/// op `FlexErf` del modelo queda sin resolver y `TfLiteInterpreterCreate`
/// devuelve `nullptr` ("Unable to create interpreter").
const _flexDelegateSymbol = 'TF_AcquireFlexDelegate';

/// Verifica, en iOS, que el delegate Select TF Ops quedo enlazado.
///
/// En Android el delegate se crea explicitamente desde `MainActivity` a traves
/// del MethodChannel `com.example.serene/tflite_flex`, asi que aqui solo
/// interesa iOS, donde la aplicacion depende por completo del enlace estatico.
void _ensureFlexDelegateIsLinked() {
  if (!Platform.isIOS) return;

  final DynamicLibrary process;
  try {
    process = DynamicLibrary.process();
  } on Object catch (error) {
    throw AudioProcessingFailure(
      'No se pudo inspeccionar el proceso para verificar el delegate Flex: '
      '$error',
    );
  }

  try {
    process.lookup<Void>(_flexDelegateSymbol);
    return;
  } on ArgumentError {
    // El simbolo no esta en el binario: cae al mensaje de error de abajo.
  }

  throw AudioProcessingFailure(
    'El delegate Select TF Ops no esta enlazado: no se encontro el simbolo '
    '$_flexDelegateSymbol. El modelo usa FlexErf, que solo existe dentro del '
    'pod TensorFlowLiteSelectTfOps. Revisa que ios/Podfile declare el pod y que '
    'ios/Runner.xcodeproj enlace con -force_load y '
    '-Wl,-u,$_flexDelegateSymbol para todas las configuraciones.',
  );
}

class TfliteInferenceEngine {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize({
    Uint8List? modelBytes,
    String? labelsRaw,
    int? flexDelegateAddress,
  }) async {
    try {
      _ensureFlexDelegateIsLinked();

      final resolvedModelBytes = modelBytes ?? await _loadModelBytes();
      if (resolvedModelBytes.isEmpty) {
        throw const AudioProcessingFailure(
          'TFLite model asset is empty or unreadable. Check the asset path and bundle contents.',
        );
      }

      if (flexDelegateAddress != null && flexDelegateAddress <= 0) {
        throw AudioProcessingFailure(
          'Flex delegate was created with an invalid native handle: $flexDelegateAddress. '
          'Verify the Android Select TF Ops delegate or the iOS link configuration.',
        );
      }

      final labelText =
          labelsRaw ?? await rootBundle.loadString('assets/labels/labels.txt');
      _labels = labelText
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final options = InterpreterOptions()..threads = 2;
      if (flexDelegateAddress != null) {
        final delegatePointer = Pointer<TfLiteDelegate>.fromAddress(
          flexDelegateAddress,
        );
        options.addDelegate(_FlexDelegatePointer(delegatePointer));
      }

      try {
        _interpreter = Interpreter.fromBuffer(
          resolvedModelBytes,
          options: options,
        );
      } on Object catch (error) {
        throw AudioProcessingFailure(
          'Unable to create the TensorFlow Lite interpreter. '
          'The model bytes are present, but the runtime could not initialize them. '
          'Cause: $error',
        );
      }

      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      if (inputShape.length != 2 ||
          inputShape.first != 1 ||
          inputShape.last != AppConstants.expectedSampleCount) {
        throw AudioProcessingFailure(
          'Unexpected model input shape: $inputShape',
        );
      }
      if (_labels.isEmpty ||
          outputShape.length != 2 ||
          outputShape.first != 1 ||
          outputShape.last != _labels.length) {
        throw AudioProcessingFailure(
          'Model output shape $outputShape does not match ${_labels.length} labels',
        );
      }

      _isInitialized = true;
    } on AudioProcessingFailure {
      close();
      rethrow;
    } catch (e) {
      close();
      throw AudioProcessingFailure('Error: $e');
    }
  }

  Future<Uint8List> _loadModelBytes() async {
    try {
      final modelData = await rootBundle.load('assets/models/model.tflite');
      final bytes = modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      );
      if (bytes.isEmpty) {
        throw const AudioProcessingFailure(
          'Model asset is empty. Check the asset file and Git/LFS state.',
        );
      }
      return bytes;
    } on FlutterError catch (error) {
      throw AudioProcessingFailure(
        'Model asset could not be loaded from assets/models/model.tflite. '
        'Check pubspec.yaml and the bundle: $error',
      );
    }
  }

  InferenceResult predict(Float32List normalizedSamples) {
    if (!_isInitialized || _interpreter == null) {
      throw const AudioProcessingFailure('TFLite engine not initialized');
    }
    if (normalizedSamples.length != AppConstants.expectedSampleCount) {
      throw AudioProcessingFailure(
        'Expected ${AppConstants.expectedSampleCount} audio samples, '
        'received ${normalizedSamples.length}',
      );
    }

    try {
      // Input tensor: shape [1, 80000] for a single audio window
      final input = [normalizedSamples];

      // Output tensor: shape [1, number_of_labels], initialized to zeros
      final output = List<double>.filled(
        _labels.length,
        0.0,
      ).reshape([1, _labels.length]);

      _interpreter!.run(input, output);

      final List<double> rawScores = List<double>.from(output[0]);
      final List<double> probabilities = _applySoftmax(rawScores);

      // Search for the label with the highest probability
      int maxIndex = 0;
      double maxScore = probabilities[0];

      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > maxScore) {
          maxScore = probabilities[i];
          maxIndex = i;
        }
      }

      final predictedLabel = _labels[maxIndex];

      final scoresMap = <String, double>{};
      for (int i = 0; i < _labels.length; i++) {
        scoresMap[_labels[i]] = probabilities[i];
      }

      // Violence detection logic: check if the max score exceeds the threshold and is not 'no_violence'
      final isViolence =
          (maxScore >= AppConstants.classificationThreshold) &&
          (predictedLabel != AppConstants.classNoViolence);

      return InferenceResult(
        label: predictedLabel,
        confidence: maxScore,
        allScores: scoresMap,
        isViolenceDetected: isViolence,
      );
    } catch (e) {
      throw AudioProcessingFailure('Error: $e');
    }
  }

  List<double> _applySoftmax(List<double> logits) {
    if (logits.isEmpty) {
      throw const AudioProcessingFailure('Model returned no output scores');
    }
    final maxLogit = logits.reduce(max);
    final expValues = logits.map((val) => exp(val - maxLogit)).toList();
    final sumExp = expValues.reduce((a, b) => a + b);
    return expValues.map((val) => val / sumExp).toList();
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

class _FlexDelegatePointer extends Delegate {
  _FlexDelegatePointer(this._delegate);

  final Pointer<TfLiteDelegate> _delegate;

  @override
  Pointer<TfLiteDelegate> get base => _delegate;

  @override
  void delete() {}
}
