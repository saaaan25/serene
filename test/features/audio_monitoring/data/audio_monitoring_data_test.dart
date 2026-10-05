import 'dart:typed_data';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:serene/core/constants/app_constants.dart';
import 'package:serene/core/errors/failures.dart';
import 'package:serene/features/audio_monitoring/data/datasources/audio_stream_datasource.dart';

class MockAudioRecorder extends Mock implements AudioRecorder {}

class FakeRecordConfig extends Fake implements RecordConfig {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeRecordConfig());
  });

  group('Microphone Control', () {
    late MockAudioRecorder mockRecorder;
    late AudioStreamDataSourceImpl dataSource;

    setUp(() {
      mockRecorder = MockAudioRecorder();
      dataSource = AudioStreamDataSourceImpl(audioRecorder: mockRecorder);
    });

    test('hasPermission checks without prompting automatically', () async {
      when(
        () => mockRecorder.hasPermission(request: false),
      ).thenAnswer((_) async => true);

      expect(await dataSource.hasPermission(), isTrue);

      verify(() => mockRecorder.hasPermission(request: false)).called(1);
    });

    test('startStream should throw AudioProcessingFailure if microphone permission is denied', () async {
      when(() => mockRecorder.isRecording()).thenAnswer((_) async => false);
      when(
        () => mockRecorder.hasPermission(request: false),
      ).thenAnswer((_) async => false);

      await expectLater(
        () async => await dataSource.startStream(),
        throwsA(isA<AudioProcessingFailure>()),
      );
      verify(() => mockRecorder.hasPermission(request: false)).called(1);
      verifyNever(() => mockRecorder.isRecording());
      verifyNever(() => mockRecorder.startStream(any()));
    });

    test('startStream stops an existing recording before opening a new stream', () async {
      final audioStream = Stream<Uint8List>.empty();
      when(() => mockRecorder.isRecording()).thenAnswer((_) async => true);
      when(() => mockRecorder.stop()).thenAnswer((_) async => null);
      when(
        () => mockRecorder.hasPermission(request: false),
      ).thenAnswer((_) async => true);
      when(() => mockRecorder.startStream(any()))
          .thenAnswer((_) async => audioStream);

      expect(await dataSource.startStream(), same(audioStream));

      verifyInOrder([
        () => mockRecorder.hasPermission(request: false),
        () => mockRecorder.isRecording(),
        () => mockRecorder.stop(),
        () => mockRecorder.startStream(any()),
      ]);
    });

    test('startStream recreates and retries the native recorder after a failure', () async {
      final firstRecorder = MockAudioRecorder();
      final replacementRecorder = MockAudioRecorder();
      final audioStream = Stream<Uint8List>.empty();
      final recoveringDataSource = AudioStreamDataSourceImpl(
        audioRecorder: firstRecorder,
        recorderFactory: () => replacementRecorder,
      );
      when(
        () => firstRecorder.hasPermission(request: false),
      ).thenAnswer((_) async => true);
      when(
        () => firstRecorder.isRecording(),
      ).thenAnswer((_) async => false);
      when(
        () => firstRecorder.startStream(any()),
      ).thenThrow(StateError('Native recorder failed'));
      when(() => firstRecorder.dispose()).thenAnswer((_) async {});
      when(
        () => replacementRecorder.hasPermission(request: false),
      ).thenAnswer((_) async => true);
      when(
        () => replacementRecorder.startStream(any()),
      ).thenAnswer((_) async => audioStream);

      expect(await recoveringDataSource.startStream(), same(audioStream));

      verify(() => firstRecorder.dispose()).called(1);
      verify(() => replacementRecorder.startStream(any())).called(1);
    });

    test('stopStream should delegate the closure to the native hardware', () async {
      // 3. Devolver un String válido en lugar de null para respetar la firma Future<String?>
      when(() => mockRecorder.stop()).thenAnswer((_) async => 'dummy/path.wav');

      await dataSource.stopStream();

      verify(() => mockRecorder.stop()).called(1);
    });
  });

  group('Mathematical Logic', () {
    List<double> applySoftmax(List<double> logits) {
      final maxLogit = logits.reduce(max);
      final expValues = logits.map((v) => exp(v - maxLogit)).toList();
      final sumExp = expValues.reduce((a, b) => a + b);
      return expValues.map((v) => v / sumExp).toList();
    }

    test('Softmax should transform logits to bounded probabilities that sum to 1.0', () {
      final logits = [1.2, 3.8, 0.5];
      final probs = applySoftmax(logits);

      final sum = probs.reduce((a, b) => a + b);
      expect(sum, closeTo(1.0, 0.0001));
      expect(probs[1], greaterThan(probs[0]));
      expect(probs[0], greaterThan(probs[2]));
    });

    test('It should not activate if the predicted label is no_violence, regardless of confidence', () {
      const predictedLabel = AppConstants.classNoViolence;
      const confidence = 0.96;

      final isViolence = (confidence >= AppConstants.classificationThreshold) &&
          (predictedLabel != AppConstants.classNoViolence);

      expect(isViolence, isFalse);
    });

    test('It should activate if the predicted label is physical_violence or verbal_violence, provided the confidence exceeds 0.70', () {
      const predictedLabel = AppConstants.classPhysicalViolence;
      const confidence = 0.85;

      final isViolence = (confidence >= AppConstants.classificationThreshold) &&
          (predictedLabel != AppConstants.classNoViolence);

      expect(isViolence, isTrue);
    });

    test('It should not activate if the predicted label is verbal_violence and the confidence is below the threshold', () {
      const predictedLabel = AppConstants.classVerbalViolence;
      const confidence = 0.52;

      final isViolence = (confidence >= AppConstants.classificationThreshold) &&
          (predictedLabel != AppConstants.classNoViolence);

      expect(isViolence, isFalse);
    });
  });
}
