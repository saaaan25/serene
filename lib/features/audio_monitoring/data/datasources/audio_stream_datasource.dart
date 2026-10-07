import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';

abstract class AudioStreamDataSource {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startStream();
  Future<void> stopStream();
}

class AudioStreamDataSourceImpl implements AudioStreamDataSource {
  static const RecordConfig _recordConfig = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: AppConstants.sampleRate,
    numChannels: AppConstants.audioChannels,
    audioInterruption: AudioInterruptionMode.pauseResume,
    iosConfig: IosRecordConfig(
      categoryOptions: [IosAudioCategoryOption.mixWithOthers],
    ),
  );

  final AudioRecorder Function() _recorderFactory;
  final bool _canRecreateRecorder;
  AudioRecorder _audioRecorder;

  AudioStreamDataSourceImpl({
    AudioRecorder? audioRecorder,
    AudioRecorder Function()? recorderFactory,
  }) : _recorderFactory = recorderFactory ?? AudioRecorder.new,
       _canRecreateRecorder = audioRecorder == null || recorderFactory != null,
       _audioRecorder =
           audioRecorder ?? (recorderFactory ?? AudioRecorder.new)();

  @override
  Future<bool> hasPermission() => _audioRecorder.hasPermission(request: false);

  @override
  Future<Stream<Uint8List>> startStream() async {
    try {
      if (!await hasPermission()) {
        throw const AudioProcessingFailure('Access to microphone denied');
      }
    } on AudioProcessingFailure {
      rethrow;
    } catch (error) {
      throw AudioProcessingFailure(
        'Could not check microphone permission: $error',
      );
    }

    try {
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }

      return await _audioRecorder.startStream(_recordConfig);
    } catch (e) {
      if (!_canRecreateRecorder) {
        throw AudioProcessingFailure('Could not start audio stream: $e');
      }

      try {
        await _audioRecorder.dispose();
      } catch (disposeError) {
        throw AudioProcessingFailure(
          'Could not start audio stream: $e. '
          'Could not release the previous recorder: $disposeError',
        );
      }

      _audioRecorder = _recorderFactory();
      try {
        if (!await hasPermission()) {
          throw const AudioProcessingFailure('Access to microphone denied');
        }
        return await _audioRecorder.startStream(_recordConfig);
      } catch (retryError) {
        try {
          await _audioRecorder.dispose();
        } catch (disposeError) {
          throw AudioProcessingFailure(
            'Could not start audio stream after recreating the recorder: '
            '$retryError. Could not release it: $disposeError '
            '(initial error: $e)',
          );
        }
        throw AudioProcessingFailure(
          'Could not start audio stream after recreating the recorder: '
          '$retryError (initial error: $e)',
        );
      }
    }
  }

  @override
  Future<void> stopStream() async {
    try {
      await _audioRecorder.stop();
    } catch (e) {
      throw AudioProcessingFailure('Error: $e');
    } finally {
      await _disposeRecorder();
    }
  }

  Future<void> _disposeRecorder() async {
    final recorder = _audioRecorder;
    if (_canRecreateRecorder) {
      _audioRecorder = _recorderFactory();
    }
    try {
      await recorder.dispose();
    } catch (_) {}
  }
}
