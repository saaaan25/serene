import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:serene/core/dsp/audio_buffer_manager.dart';

void main() {
  test('It should store samples sequentially when the capacity is not filled', () {
    final buffer = AudioBufferManager(bufferSize: 5);
    buffer.appendSamples(Float32List.fromList([1.0, 2.0, 3.0]));

    final snapshot = buffer.getOrderedSnapshot();

    expect(snapshot, equals([1.0, 2.0, 3.0, 0.0, 0.0]));
  });

  test('It should overwrite the oldest samples while maintaining strict chronological order (FIFO)', () {
    final buffer = AudioBufferManager(bufferSize: 4);
    // Insert 4 samples to fill the buffer
    buffer.appendSamples(Float32List.fromList([1.0, 2.0, 3.0, 4.0]));
    // Overwrite the oldest 2 samples with new data
    buffer.appendSamples(Float32List.fromList([5.0, 6.0]));

    final snapshot = buffer.getOrderedSnapshot();

    // The oldest samples (1.0 and 2.0) were replaced by 5.0 and 6.0
    expect(snapshot, equals([3.0, 4.0, 5.0, 6.0]));
  });

  test('It should clear all data from RAM when purge() is called', () {
    final buffer = AudioBufferManager(bufferSize: 3);
    buffer.appendSamples(Float32List.fromList([0.9, 0.8, 0.7]));

    buffer.purge();
    final snapshot = buffer.getOrderedSnapshot();

    expect(snapshot, equals([0.0, 0.0, 0.0]));
  });
}