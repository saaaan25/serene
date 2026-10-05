import 'dart:async';
import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:record/record.dart';

import '../constants/hive_constants.dart';

abstract class RecorderLeakGuard {
  static const String _idsKey = 'recorder_ids';
  static Box<dynamic>? _box;

  static Future<void> install() async {
    try {
      _box = Hive.isBoxOpen(HiveConstants.recorderRegistryBox)
          ? Hive.box<dynamic>(HiveConstants.recorderRegistryBox)
          : await Hive.openBox<dynamic>(HiveConstants.recorderRegistryBox);
    } catch (_) {
      _box = null;
      return;
    }

    await releaseOrphanedRecorders();

    final delegate = RecordPlatform.instance;
    if (delegate is _TrackingRecordPlatform) return;
    RecordPlatform.instance = _TrackingRecordPlatform(delegate);
  }

  static Future<void> releaseOrphanedRecorders() async {
    final box = _box;
    if (box == null) return;

    final ids = _read(box);
    await box.put(_idsKey, <String>[]);
    if (ids.isEmpty) return;

    for (final recorderId in ids) {
      try {
        await RecordPlatform.instance.dispose(recorderId);
      } catch (_) {}
    }
  }

  static List<String> _read(Box<dynamic> box) {
    final raw = box.get(_idsKey);
    if (raw is! List) return <String>[];
    return raw.whereType<String>().toList();
  }

  static Future<void> _remember(String recorderId) async {
    final box = _box;
    if (box == null) return;
    try {
      final ids = _read(box);
      if (ids.contains(recorderId)) return;
      ids.add(recorderId);
      await box.put(_idsKey, ids);
    } catch (_) {}
  }

  static Future<void> _forget(String recorderId) async {
    final box = _box;
    if (box == null) return;
    try {
      final ids = _read(box);
      if (!ids.remove(recorderId)) return;
      await box.put(_idsKey, ids);
    } catch (_) {}
  }
}

class _TrackingRecordPlatform extends RecordPlatform {
  _TrackingRecordPlatform(this._delegate);

  final RecordPlatform _delegate;

  @override
  Future<void> create(String recorderId) async {
    await RecorderLeakGuard._remember(recorderId);
    await _delegate.create(recorderId);
  }

  @override
  Future<void> dispose(String recorderId) async {
    try {
      await _delegate.dispose(recorderId);
    } finally {
      await RecorderLeakGuard._forget(recorderId);
    }
  }

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) => _delegate.start(recorderId, config, path: path);

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) => _delegate.startStream(recorderId, config);

  @override
  Future<String?> stop(String recorderId) => _delegate.stop(recorderId);

  @override
  Future<void> pause(String recorderId) => _delegate.pause(recorderId);

  @override
  Future<void> resume(String recorderId) => _delegate.resume(recorderId);

  @override
  Future<bool> isRecording(String recorderId) =>
      _delegate.isRecording(recorderId);

  @override
  Future<bool> isPaused(String recorderId) => _delegate.isPaused(recorderId);

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) =>
      _delegate.hasPermission(recorderId, request: request);

  @override
  Future<Amplitude> getAmplitude(String recorderId) =>
      _delegate.getAmplitude(recorderId);

  @override
  Future<bool> isEncoderSupported(String recorderId, AudioEncoder encoder) =>
      _delegate.isEncoderSupported(recorderId, encoder);

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) =>
      _delegate.listInputDevices(recorderId);

  @override
  Future<void> cancel(String recorderId) => _delegate.cancel(recorderId);

  @override
  RecordIos? getIos(String recorderId) => _delegate.getIos(recorderId);

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      _delegate.onStateChanged(recorderId);
}