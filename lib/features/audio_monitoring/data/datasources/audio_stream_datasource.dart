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
  final AudioRecorder _audioRecorder;

  AudioStreamDataSourceImpl({AudioRecorder? audioRecorder})
      : _audioRecorder = audioRecorder ?? AudioRecorder();

  @override
  Future<bool> hasPermission() => _audioRecorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream() async {
    if (!await hasPermission()) {
      throw const AudioProcessingFailure('Access to microphone denied');
    }

    try {
      const recordConfig = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AppConstants.sampleRate,
        numChannels: AppConstants.audioChannels,
      );

      return await _audioRecorder.startStream(recordConfig);
    } catch (e) {
      throw AudioProcessingFailure('Error: $e');
    }
  }

  @override
  Future<void> stopStream() async {
    try {
      await _audioRecorder.stop();
    } catch (e) {
      throw AudioProcessingFailure('Error: $e');
    }
  }
}