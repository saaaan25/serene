import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:serene/core/constants/evidence_policy.dart';
import 'package:serene/core/errors/failures.dart';
import 'package:serene/core/services/evidence_storage_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native capacity uses the actual directory and converts MiB to bytes',
    () async {
      const channel = MethodChannel('disk_space_2');
      final path = Directory.systemTemp.path;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getFreeDiskSpaceForPath');
            expect((call.arguments as Map)['path'], path);
            return 105.5;
          });
      try {
        final guard = EvidenceStorageGuard();
        expect(await guard.freeBytes(path), (105.5 * 1024 * 1024).floor());
        await guard.ensureWrite(path, (5.5 * 1024 * 1024).floor());
        await expectLater(
          guard.ensureWrite(path, (5.5 * 1024 * 1024).floor() + 1),
          throwsA(isA<StorageCapacityFailure>()),
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );
  test(
    'admission preserves the configured reserve plus estimated write bytes',
    () async {
      final guard = EvidenceStorageGuard(
        freeBytes: (_) async => EvidencePolicy.minimumFreeBytes + 100,
      );
      await guard.ensureWrite('path', 100);
      await expectLater(
        guard.ensureWrite('path', 101),
        throwsA(isA<StorageCapacityFailure>()),
      );
    },
  );
  test('manual deletion remains allowed below the admission reserve', () async {
    final guard = EvidenceStorageGuard(freeBytes: (_) async => 128 * 1024);
    await guard.ensureWrite('path', 64 * 1024, deletion: true);
    await expectLater(
      guard.ensureWrite('path', 64 * 1024),
      throwsA(isA<StorageCapacityFailure>()),
    );
  });
  test(
    'unknown capacity fails safely rather than assuming unlimited space',
    () async {
      for (final guard in [
        EvidenceStorageGuard(freeBytes: (_) async => null),
        EvidenceStorageGuard(
          freeBytes: (_) async => throw StateError('unavailable'),
        ),
      ]) {
        await expectLater(
          guard.ensureWrite('path', 1),
          throwsA(isA<StorageCapacityFailure>()),
        );
      }
    },
  );
  test(
    'compaction is deferred if there is no room for a live-file copy',
    () async {
      final guard = EvidenceStorageGuard(
        freeBytes: (_) async => 2 * 1024 * 1024,
      );
      expect(await guard.canCompact('path', 1024 * 1024), isTrue);
      expect(await guard.canCompact('path', 2 * 1024 * 1024), isFalse);
    },
  );
  test('only disk-full OS errors are translated to capacity failures', () {
    final error = FileSystemException(
      'full',
      'path',
      OSError('full', Platform.isWindows ? 112 : 28),
    );
    expect(
      EvidenceStorageGuard.classifyWriteError(error),
      isA<StorageCapacityFailure>(),
    );
    const unrelated = FileSystemException(
      'permission denied',
      'path',
      OSError('denied', 13),
    );
    expect(EvidenceStorageGuard.classifyWriteError(unrelated), same(unrelated));
  });
}
