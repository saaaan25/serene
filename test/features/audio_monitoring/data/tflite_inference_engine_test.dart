import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:serene/core/constants/app_constants.dart';
import 'package:serene/core/errors/failures.dart';
import 'package:serene/features/audio_monitoring/data/datasources/tflite_inference_engine.dart';

class InterpreterMock extends Mock implements Interpreter {}

class TensorMock extends Mock implements Tensor {}

void main() {
  setUpAll(() {
    registerFallbackValue(<int>[]);
    registerFallbackValue(<Object>[]);
    registerFallbackValue(<int, Object>{});
  });
  late InterpreterMock interpreter;
  late TensorMock pcm;
  late TensorMock lengths;
  late TensorMock output;
  late TfliteInferenceEngine engine;
  late List<int> pcmShape;
  late List<int> lengthShape;
  late List<double> probabilities;
  List<Object>? sentInputs;
  const labels = 'no_violence\nphysical_violence\nverbal_violence';

  setUp(() {
    interpreter = InterpreterMock();
    pcm = TensorMock();
    lengths = TensorMock();
    output = TensorMock();
    pcmShape = [1, 1];
    lengthShape = [1];
    probabilities = [.05, .9, .05];
    sentInputs = null;
    when(() => pcm.name).thenReturn('serving_default_pcm:0');
    when(() => pcm.type).thenReturn(TensorType.float32);
    when(() => pcm.shape).thenAnswer((_) => pcmShape);
    when(() => lengths.name).thenReturn('serving_default_valid_samples:0');
    when(() => lengths.type).thenReturn(TensorType.int32);
    when(() => lengths.shape).thenAnswer((_) => lengthShape);
    when(() => output.type).thenReturn(TensorType.float32);
    when(() => output.shape).thenReturn([1, 3]);
    when(() => interpreter.getInputTensors()).thenReturn([pcm, lengths]);
    when(() => interpreter.getOutputTensors()).thenReturn([output]);
    when(() => interpreter.getInputTensor(0)).thenReturn(pcm);
    when(() => interpreter.getInputTensor(1)).thenReturn(lengths);
    when(() => interpreter.getOutputTensor(0)).thenReturn(output);
    when(() => interpreter.resizeInputTensor(any(), any())).thenAnswer((call) {
      final index = call.positionalArguments[0] as int;
      final shape = call.positionalArguments[1] as List<int>;
      if (index == 0) {
        pcmShape = shape;
      } else {
        lengthShape = shape;
      }
    });
    when(() => interpreter.runForMultipleInputs(any(), any())).thenAnswer((
      call,
    ) {
      sentInputs = call.positionalArguments[0] as List<Object>;
      final destinations = call.positionalArguments[1] as Map<int, Object>;
      (destinations[0] as List<List<double>>)[0] = List<double>.from(
        probabilities,
      );
    });
    engine = TfliteInferenceEngine(interpreterFactory: (_, _) => interpreter);
  });
  tearDown(() => engine.close());
  Future<void> initialize() =>
      engine.initialize(modelBytes: Uint8List.fromList([1]), labelsRaw: labels);

  test(
    'dynamic PCM and valid_samples are resized before reallocation',
    () async {
      await initialize();
      expect(engine.isInitialized, isTrue);
      verifyInOrder([
        () => interpreter.resizeInputTensor(0, [1, 80000]),
        () => interpreter.resizeInputTensor(1, [1]),
        () => interpreter.allocateTensors(),
      ]);
    },
  );

  test('sends scaled PCM unchanged and an int32 full-window length', () async {
    await initialize();
    final samples = Float32List(80000);
    samples[0] = -.5;
    samples[1] = .25;
    final result = engine.predict(samples);
    expect((sentInputs![0] as List).single, same(samples));
    expect(sentInputs![1], isA<Int32List>());
    expect(sentInputs![1], [80000]);
    expect(result.label, AppConstants.classPhysicalViolence);
    expect(result.confidence, .9); // No second softmax.
    expect(result.allScores, {
      'no_violence': .05,
      'physical_violence': .9,
      'verbal_violence': .05,
    });
    expect(result.isViolenceDetected, isTrue);
    verifyNever(() => interpreter.run(any(), any()));
  });

  test(
    'input positions are resolved by name rather than graph tensor IDs',
    () async {
      when(() => interpreter.getInputTensors()).thenReturn([lengths, pcm]);
      when(() => interpreter.getInputTensor(0)).thenReturn(lengths);
      when(() => interpreter.getInputTensor(1)).thenReturn(pcm);
      when(() => interpreter.resizeInputTensor(any(), any())).thenAnswer((
        call,
      ) {
        final shape = call.positionalArguments[1] as List<int>;
        if (call.positionalArguments[0] == 0) {
          lengthShape = shape;
        } else {
          pcmShape = shape;
        }
      });
      await initialize();
      engine.predict(Float32List(80000));
      expect(sentInputs![0], isA<Int32List>());
      expect((sentInputs![1] as List).single, isA<Float32List>());
    },
  );

  test(
    'probabilities retain class order, threshold and no_violence exclusion',
    () async {
      await initialize();
      final samples = Float32List(80000);
      probabilities = [.95, .03, .02];
      expect(engine.predict(samples).isViolenceDetected, isFalse);
      probabilities = [.1, .2, .7];
      expect(engine.predict(samples).label, 'verbal_violence');
      expect(engine.predict(samples).isViolenceDetected, isTrue);
      probabilities = [.25, .25, .5];
      expect(engine.predict(samples).isViolenceDetected, isFalse);
    },
  );

  test('wrong labels cannot silently remap predictions', () async {
    await expectLater(
      engine.initialize(
        modelBytes: Uint8List(1),
        labelsRaw: 'physical_violence\nno_violence\nverbal_violence',
      ),
      throwsA(isA<AudioProcessingFailure>()),
    );
    expect(engine.isInitialized, isFalse);
  });

  test('wrong length dtype is rejected and releases the interpreter', () async {
    when(() => lengths.type).thenReturn(TensorType.float32);
    await expectLater(initialize(), throwsA(isA<AudioProcessingFailure>()));
    verify(() => interpreter.close()).called(1);
    expect(engine.isInitialized, isFalse);
  });

  test('missing valid_samples input rejects incompatible old models', () async {
    when(() => interpreter.getInputTensors()).thenReturn([pcm]);
    await expectLater(initialize(), throwsA(isA<AudioProcessingFailure>()));
    expect(engine.isInitialized, isFalse);
  });

  test('resize failure does not leave a ready engine', () async {
    when(
      () => interpreter.resizeInputTensor(0, any()),
    ).thenThrow(StateError('resize failed'));
    await expectLater(initialize(), throwsA(isA<AudioProcessingFailure>()));
    verify(() => interpreter.close()).called(1);
    expect(engine.isInitialized, isFalse);
  });

  test(
    'invalid samples and incomplete windows do not invoke the model',
    () async {
      await initialize();
      for (final samples in [
        Float32List(400),
        Float32List(80000)..[0] = double.nan,
        Float32List(80000)..[0] = 2,
      ]) {
        expect(
          () => engine.predict(samples),
          throwsA(isA<AudioProcessingFailure>()),
        );
      }
      verifyNever(() => interpreter.runForMultipleInputs(any(), any()));
    },
  );

  test(
    'logits and invalid outputs are rejected instead of masked by softmax',
    () async {
      await initialize();
      for (final values in [
        [1.2, 3.8, .5],
        [0.0, 0.0, 0.0],
        [double.nan, .9, .1],
        [.1, .2],
      ]) {
        probabilities = values;
        expect(
          () => engine.predict(Float32List(80000)),
          throwsA(isA<AudioProcessingFailure>()),
        );
      }
    },
  );
}
