import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/services/evidence_storage_guard.dart';
import '../models/evidence_envelope.dart';
import '../models/evidence_record_model.dart';
import 'evidence_local_datasource.dart';

/// Immutable encrypted staging. Only the UI isolate writes Hive/audit.
/// A claimed file survives a crash until its authenticated import is committed.
class BackgroundEvidenceJournal implements EvidenceLocalDataSource {
  static Future<void>? _importing;
  Future<void> _writing = Future.value();
  final Future<Directory> Function() _directoryProvider;
  final Future<void> Function()? afterStagingFlush;
  final EvidenceStorageGuard storageGuard;
  BackgroundEvidenceJournal({
    Future<Directory> Function()? directoryProvider,
    this.afterStagingFlush,
    EvidenceStorageGuard? storageGuard,
  }) : _directoryProvider = directoryProvider ?? _directory,
       storageGuard = storageGuard ?? EvidenceStorageGuard();

  static Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory(
      '${root.path}/background_evidence',
    ).create(recursive: true);
  }

  static void _checkId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const CryptoFailure('Invalid evidence staging identifier');
    }
  }

  @override
  Future<void> insertRecord(EvidenceRecordModel record) {
    final task = _writing.then((_) async {
      try {
        await _stage(record);
      } catch (error) {
        throw EvidenceStorageGuard.classifyWriteError(error);
      }
    });
    _writing = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> _stage(EvidenceRecordModel record) async {
    _checkId(record.id);
    EvidenceEnvelope.requireSealed(record);
    if (record.schemaVersion != 2) {
      throw const CryptoFailure(
        'New staging records require an encrypted metadata envelope',
      );
    }
    final directory = await _directoryProvider();
    final destination = File('${directory.path}/${record.id}.json');
    final encoded = canonicalJson(EvidenceEnvelope.encode(record));
    if (await destination.exists()) {
      if (await destination.readAsString() == encoded) return;
      throw const CryptoFailure('Cannot overwrite an immutable staged version');
    }
    final temporary = File('${destination.path}.${const Uuid().v4()}.tmp');
    // Include headroom for the later audited import while this staging file
    // remains present. JSON/base64 and the encrypted WAL require extra bytes.
    await storageGuard.ensureWrite(
      directory.path,
      utf8.encode(encoded).length * 5 + 256 * 1024,
    );
    // Keep a flushed .tmp on interruption: import can recover complete envelopes.
    await temporary.writeAsString(encoded, flush: true);
    await afterStagingFlush?.call();
    await temporary.rename(destination.path);
  }

  static Future<void> importInto(
    Box<EvidenceRecordModel> box, {
    Directory? directory,
    required Future<void> Function(EvidenceRecordModel) importer,
    Future<DateTime> Function(EvidenceRecordModel)? ordering,
  }) async {
    if (!Platform.isAndroid && directory == null) return;
    if (_importing != null) return _importing;
    final future = _import(directory, importer, ordering);
    _importing = future;
    try {
      await future;
    } finally {
      _importing = null;
    }
  }

  static Future<void> _import(
    Directory? overrideDirectory,
    Future<void> Function(EvidenceRecordModel) importer,
    Future<DateTime> Function(EvidenceRecordModel)? ordering,
  ) async {
    final directory = overrideDirectory ?? await _directory();
    final entries = await directory.list().toList();
    final pending =
        <({File file, EvidenceRecordModel record, DateTime order})>[];
    for (final entry in entries) {
      if (entry is! File ||
          (!entry.path.endsWith('.json') && !entry.path.endsWith('.tmp'))) {
        continue;
      }
      Map<String, dynamic> data;
      try {
        data = jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
      } on FormatException {
        if (!entry.path.endsWith('.tmp')) rethrow;
        // A partial temporary write was never committed by the service.
        await entry.delete();
        continue;
      }
      final record = EvidenceEnvelope.decode(data);
      _checkId(record.id);
      final order = ordering == null
          ? record.timestamp
          : await ordering(record);
      pending.add((file: entry, record: record, order: order));
    }
    pending.sort((a, b) {
      final order = a.order.compareTo(b.order);
      return order == 0 ? a.record.id.compareTo(b.record.id) : order;
    });
    for (final item in pending) {
      final claimed = item.file.path.endsWith('.claimed.json')
          ? item.file
          : await item.file.rename(
              '${directory.path}/${const Uuid().v4()}.claimed.json',
            );
      await importer(item.record);
      // Removal only follows the durable audit+record commit. Retries are harmless.
      await claimed.delete();
    }
  }

  @override
  Future<List<EvidenceRecordModel>> fetchAllRecords() async => [];

  @override
  Future<void> removeRecord(String id) async {
    throw UnsupportedError(
      'Evidence deletion is handled by the UI audit writer',
    );
  }
}
