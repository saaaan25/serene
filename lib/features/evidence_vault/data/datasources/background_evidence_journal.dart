import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/evidence_record_model.dart';
import 'evidence_local_datasource.dart';

/// Service writes encrypted records here; only the UI isolate opens Hive.
/// Atomic claims keep a new checkpoint safe while the UI imports an older one.
class BackgroundEvidenceJournal implements EvidenceLocalDataSource {
  static Future<void>? _importing;
  final Future<Directory> Function() _directoryProvider;
  BackgroundEvidenceJournal({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? _directory;

  static Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory(
      '${root.path}/background_evidence',
    ).create(recursive: true);
  }

  @override
  Future<void> insertRecord(EvidenceRecordModel record) async {
    final directory = await _directoryProvider();
    final destination = File('${directory.path}/${record.id}.json');
    final temporary = File('${destination.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'id': record.id,
          'timestamp': record.timestamp.toIso8601String(),
          'label': record.predictionLabel,
          'confidence': record.confidenceScore,
          'gps': record.gpsCoordinates,
          'audio': base64Encode(record.encryptedAudioBlob),
          'iv': base64Encode(record.ivBytes),
          'tag': base64Encode(record.authTag),
          'hash': record.integrityHash,
        }),
        flush: true,
      );
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<void> importInto(
    Box<EvidenceRecordModel> box, {
    Directory? directory,
  }) async {
    if (!Platform.isAndroid && directory == null) return;
    if (_importing != null) return _importing;
    final future = _import(box, directory);
    _importing = future;
    try {
      await future;
    } finally {
      _importing = null;
    }
  }

  static Future<void> _import(
    Box<EvidenceRecordModel> box,
    Directory? overrideDirectory,
  ) async {
    final directory = overrideDirectory ?? await _directory();
    final entries = await directory.list().toList();
    for (final entry in entries) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final claimed = entry.path.endsWith('.claimed.json')
          ? entry
          : await entry.rename(
              '${directory.path}/${const Uuid().v4()}.claimed.json',
            );
      final data =
          jsonDecode(await claimed.readAsString()) as Map<String, dynamic>;
      final record = EvidenceRecordModel(
        id: data['id'] as String,
        timestamp: DateTime.parse(data['timestamp'] as String),
        predictionLabel: data['label'] as String,
        confidenceScore: (data['confidence'] as num).toDouble(),
        gpsCoordinates: (data['gps'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        encryptedAudioBlob: base64Decode(data['audio'] as String),
        ivBytes: base64Decode(data['iv'] as String),
        authTag: base64Decode(data['tag'] as String),
        integrityHash: data['hash'] as String,
      );
      final existing = box.get(record.id);
      if (existing == null ||
          record.encryptedAudioBlob.length >=
              existing.encryptedAudioBlob.length) {
        await box.put(record.id, record);
        await box.flush();
      }
      await claimed.delete();
    }
  }

  @override
  Future<List<EvidenceRecordModel>> fetchAllRecords() async => [];
  @override
  Future<void> removeRecord(String id) async {
    final directory = await _directoryProvider();
    final file = File('${directory.path}/$id.json');
    if (await file.exists()) await file.delete();
  }
}
