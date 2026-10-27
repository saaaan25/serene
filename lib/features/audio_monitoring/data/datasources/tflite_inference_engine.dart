import 'dart:ffi';
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

class TfliteInferenceEngine {
  TfliteInferenceEngine({
    Interpreter Function(Uint8List, int?)? interpreterFactory,
  }) : _interpreterFactory = interpreterFactory ?? _createInterpreter;

  final Interpreter Function(Uint8List, int?) _interpreterFactory;
  int _pcmInputIndex = -1;
  int _lengthInputIndex = -1;
  static const _labelOrder = [
    AppConstants.classNoViolence,
    AppConstants.classPhysicalViolence,
    AppConstants.classVerbalViolence,
  ];

  static Interpreter _createInterpreter(Uint8List bytes, int? delegateAddress) {
    final options = InterpreterOptions()..threads = 2;
    try {
      if (delegateAddress != null) {
        options.addDelegate(
          _FlexDelegatePointer(
            Pointer<TfLiteDelegate>.fromAddress(delegateAddress),
          ),
        );
      }
      return Interpreter.fromBuffer(bytes, options: options);
    } finally {
      options.delete();
    }
  }

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize({
    Uint8List? modelBytes,
    String? labelsRaw,
    int? flexDelegateAddress,
  }) async {
    close();
    try {
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

      if (!listEquals(_labels, _labelOrder)) {
        throw AudioProcessingFailure(
          'Model labels must be ordered as $_labelOrder; received $_labels',
        );
      }
      if (AppConstants.sampleRate != 16000 ||
          AppConstants.audioChannels != 1 ||
          AppConstants.expectedSampleCount < 400 ||
          AppConstants.expectedSampleCount > 224000) {
        throw const AudioProcessingFailure(
          'The mixed model requires mono 16 kHz PCM and 400..224000 samples.',
        );
      }
      try {
        _interpreter = _interpreterFactory(
          resolvedModelBytes,
          flexDelegateAddress,
        );
      } on Object catch (error) {
        throw AudioProcessingFailure(
          'Unable to create the TensorFlow Lite interpreter. '
          'The model bytes are present, but the runtime could not initialize them. '
          'Cause: $error',
        );
      }

      final inputs = _interpreter!.getInputTensors();
      final outputs = _interpreter!.getOutputTensors();
      if (inputs.length != 2 || outputs.length != 1) {
        throw const AudioProcessingFailure(
          'The mixed model requires two inputs (pcm, valid_samples) and one probability output.',
        );
      }
      String inputName(Tensor tensor) => tensor.name
          .split(':')
          .first
          .replaceFirst(RegExp(r'^serving_default_'), '');
      _pcmInputIndex = inputs.indexWhere((t) => inputName(t) == 'pcm');
      _lengthInputIndex = inputs.indexWhere(
        (t) => inputName(t) == 'valid_samples',
      );
      if (_pcmInputIndex < 0 ||
          _lengthInputIndex < 0 ||
          inputs[_pcmInputIndex].type != TensorType.float32 ||
          inputs[_lengthInputIndex].type != TensorType.int32 ||
          outputs.single.type != TensorType.float32 ||
          inputs[_pcmInputIndex].shape.length != 2 ||
          inputs[_lengthInputIndex].shape.length != 1) {
        throw const AudioProcessingFailure(
          'Expected pcm float32 [batch,samples], valid_samples int32 [batch], '
          'and float32 probabilities. Check the exported mobile contract.',
        );
      }
      // The asset starts at [1,1]. Configure BOTH dynamic inputs before
      // reallocating; inference uses one complete five-second window per batch.
      _interpreter!.resizeInputTensor(_pcmInputIndex, [
        1,
        AppConstants.expectedSampleCount,
      ]);
      _interpreter!.resizeInputTensor(_lengthInputIndex, [1]);
      _interpreter!.allocateTensors();
      final pcmShape = _interpreter!.getInputTensor(_pcmInputIndex).shape;
      final lengthShape = _interpreter!.getInputTensor(_lengthInputIndex).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      if (!listEquals(pcmShape, [1, AppConstants.expectedSampleCount]) ||
          !listEquals(lengthShape, [1]) ||
          !listEquals(outputShape, [1, _labelOrder.length])) {
        throw AudioProcessingFailure(
          'Unexpected allocated model shapes: pcm=$pcmShape, '
          'valid_samples=$lengthShape, probabilities=$outputShape',
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

  InferenceResult predict(Float32List pcmSamples) {
    if (!_isInitialized || _interpreter == null) {
      throw const AudioProcessingFailure('TFLite engine not initialized');
    }
    if (pcmSamples.length != AppConstants.expectedSampleCount) {
      throw AudioProcessingFailure(
        'Expected ${AppConstants.expectedSampleCount} audio samples, '
        'received ${pcmSamples.length}',
      );
    }

    try {
      if (pcmSamples.any(
        (sample) => !sample.isFinite || sample < -1 || sample > 1,
      )) {
        throw const AudioProcessingFailure(
          'PCM must be finite float32 samples in [-1,1].',
        );
      }
      // Only PCM16 scaling is applied in the app. Statistical normalization and
      // softmax are already embedded in the exported model.
      final inputs = List<Object>.filled(2, const <int>[]);
      inputs[_pcmInputIndex] = [pcmSamples];
      inputs[_lengthInputIndex] = Int32List.fromList([pcmSamples.length]);
      final output = [List<double>.filled(_labels.length, 0)];
      _interpreter!.runForMultipleInputs(inputs, {0: output});
      final probabilities = List<double>.from(output.single);
      final sum = probabilities.fold<double>(0, (sum, value) => sum + value);
      if (probabilities.length != _labels.length ||
          probabilities.any((p) => !p.isFinite || p < 0 || p > 1) ||
          (sum - 1).abs() > 1e-3) {
        throw const AudioProcessingFailure(
          'Model output must be finite softmax probabilities summing to one.',
        );
      }

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

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _pcmInputIndex = -1;
    _lengthInputIndex = -1;
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
