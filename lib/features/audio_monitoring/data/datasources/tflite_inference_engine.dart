import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/inference_result.dart';

class TfliteInferenceEngine {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    try {
      // Load labels from assets/labels/labels.txt
      final labelsRaw = await rootBundle.loadString('assets/labels/labels.txt');
      _labels = labelsRaw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // Configure the TFLite interpreter with 2 threads for better performance
      final options = InterpreterOptions()..threads = 2;

      _interpreter = await Interpreter.fromAsset(
        'assets/models/model.tflite',
        options: options,
      );

      _isInitialized = true;
    } catch (e) {
      throw AudioProcessingFailure('Error: $e');
    }
  }

  InferenceResult predict(Float32List normalizedSamples) {
    if (!_isInitialized || _interpreter == null) {
      throw const AudioProcessingFailure('TFLite engine not initialized');
    }

    try {
      // Input tensor: shape [1, 80000] for a single audio window
      final input = [normalizedSamples];

      // Output tensor: shape [1, number_of_labels], initialized to zeros
      final output = List<double>.filled(_labels.length, 0.0).reshape([1, _labels.length]);

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
      final isViolence = (maxScore >= AppConstants.classificationThreshold) &&
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