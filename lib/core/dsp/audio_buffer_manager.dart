import 'dart:typed_data';
import '../constants/app_constants.dart';

class AudioBufferManager {
  final int capacityInSamples;
  final Float32List _buffer;
  int _writeIndex = 0;
  bool _isFull = false;

  bool get isFull => _isFull;

  AudioBufferManager({int? bufferSize})
      : capacityInSamples = bufferSize ?? AppConstants.expectedSampleCount,
        _buffer = Float32List(bufferSize ?? AppConstants.expectedSampleCount);

  /// Adds new audio samples to the circular buffer, overwriting old samples if necessary
  void appendSamples(Float32List samples) {
    for (int i = 0; i < samples.length; i++) {
      _buffer[_writeIndex] = samples[i];
      _writeIndex = (_writeIndex + 1) % capacityInSamples;
      if (_writeIndex == 0) {
        _isFull = true;
      }
    }
  }

  /// Extracts a snapshot of the current buffer in the correct order, handling wrap-around if necessary
  Float32List getOrderedSnapshot() {
    final snapshot = Float32List(capacityInSamples);
    if (!_isFull) {
      snapshot.setRange(0, _writeIndex, _buffer.sublist(0, _writeIndex));
      return snapshot;
    }

    // If the buffer is full, we need to handle wrap-around
    final tailLength = capacityInSamples - _writeIndex;
    snapshot.setRange(0, tailLength, _buffer.sublist(_writeIndex));
    snapshot.setRange(tailLength, capacityInSamples, _buffer.sublist(0, _writeIndex));

    return snapshot;
  }

  /// Clears the buffer and resets the write index
  void purge() {
    _buffer.fillRange(0, capacityInSamples, 0.0);
    _writeIndex = 0;
    _isFull = false;
  }
}