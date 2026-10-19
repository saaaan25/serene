import 'dart:io';

import 'package:disk_space_2/disk_space_2.dart';

import '../constants/evidence_policy.dart';
import '../errors/failures.dart';

/// Space estimates are conservative preflight checks, not OS reservations.
class EvidenceStorageGuard {
  final Future<int?> Function(String path) freeBytes;
  EvidenceStorageGuard({Future<int?> Function(String path)? freeBytes})
    : freeBytes = freeBytes ?? _freeBytes;

  static Future<int?> _freeBytes(String path) async {
    final mib = await DiskSpace.getFreeDiskSpaceForPath(path);
    return mib == null || !mib.isFinite || mib < 0
        ? null
        : (mib * 1024 * 1024).floor();
  }

  Future<void> ensureWrite(
    String path,
    int additionalBytes, {
    bool deletion = false,
  }) async {
    int? available;
    try {
      available = await freeBytes(path);
    } catch (_) {
      throw const StorageCapacityFailure(
        'No se pudo comprobar el espacio disponible. Libera espacio y vuelve a intentar.',
      );
    }
    if (available == null) {
      throw const StorageCapacityFailure(
        'No se pudo comprobar el espacio disponible. Libera espacio y vuelve a intentar.',
      );
    }
    final reserve = deletion ? 0 : EvidencePolicy.minimumFreeBytes;
    if (available < reserve + additionalBytes) {
      throw const StorageCapacityFailure(
        'Espacio insuficiente para guardar audio de forma segura. Las evidencias guardadas se conservan. Libera espacio y reinicia el monitoreo.',
      );
    }
  }

  Future<bool> canCompact(String path, int currentFileBytes) async {
    try {
      final available = await freeBytes(path);
      return available != null && available >= currentFileBytes + 1024 * 1024;
    } catch (_) {
      return false;
    }
  }

  static Object classifyWriteError(Object error) {
    if (error is FileSystemException &&
        (Platform.isWindows ? [112, 39] : [28]).contains(
          error.osError?.errorCode,
        )) {
      return const StorageCapacityFailure(
        'El almacenamiento se agotó durante el guardado. Se conservan los guardados confirmados; libera espacio para recuperar la escritura pendiente.',
      );
    }
    return error;
  }
}
