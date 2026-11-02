import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:serene/core/crypto/cipher_manager.dart';
import 'package:serene/core/errors/failures.dart';
import 'package:serene/core/services/evaluation_metrics.dart';

/// Host evaluation only. Never imports application storage or production keys.
Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    stdout.writeln(
      'dart run tool/evaluate_crypto.dart '
      '[--dataset DIRECTORY] [--repetitions 10] [--skip-tests]\n'
      'Writes evaluation_results/<UTC run>/; dataset: .wav/.pcm/.raw, '
      'whole-file bytes, recursively, no symlinks, maximum 16 MiB/file.',
    );
    return;
  }
  String? dataset;
  var repetitions = 10;
  var runTests = true;
  try {
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--dataset':
          dataset = args[++i];
        case '--repetitions':
          repetitions = int.parse(args[++i]);
        case '--skip-tests':
          runTests = false;
        default:
          throw const FormatException('Unknown option');
      }
    }
    if (repetitions < 1 || repetitions > 1000) {
      throw const FormatException('Repetitions must be 1..1000');
    }
    if (dataset != null && !Directory(dataset).existsSync()) {
      throw const FormatException('Dataset directory does not exist');
    }
  } catch (_) {
    stderr.writeln('Invalid arguments. Use --help.');
    exitCode = 64;
    return;
  }
  final id = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final output = Directory('evaluation_results/$id')
    ..createSync(recursive: true);
  final log = File('${output.path}/run.log').openWrite();
  void note(String message) {
    final line = '${DateTime.now().toUtc().toIso8601String()} $message';
    stdout.writeln(line);
    log.writeln(line);
  }

  final rows = <Map<String, Object?>>[];
  final skipped = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'schema_version': 1,
    'started_at_utc': DateTime.now().toUtc().toIso8601String(),
    'status': 'running',
    'environment': {
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'processors': Platform.numberOfProcessors,
      'execution': 'host Dart VM; not Android/iOS; not mobile latency',
    },
    'configuration': {
      'repetitions': repetitions,
      'warmups_per_input': 2,
      'max_file_bytes': 16 * 1024 * 1024,
      'dataset_representation':
          'whole file bytes; WAV headers included; no decoding',
      'timing':
          'elapsed inside worker isolate around CipherManager.encryptInMemory; '
          'excludes file I/O, key creation, isolate messaging, decryption and storage',
    },
    'cases': rows,
    'skipped': skipped,
    'evaluation_metrics': pendingEvaluationMetrics(),
  };
  void save() => File(
    '${output.path}/results.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  save();
  try {
    final commit = await Process.run('git', ['rev-parse', 'HEAD']);
    final dirty = await Process.run('git', ['status', '--porcelain']);
    report['source'] = {
      'commit': commit.exitCode == 0 ? commit.stdout.toString().trim() : null,
      'working_tree_dirty': dirty.exitCode == 0
          ? dirty.stdout.toString().trim().isNotEmpty
          : null,
      'cipher_source_sha256': sha256
          .convert(
            File('lib/core/crypto/cipher_manager.dart').readAsBytesSync(),
          )
          .toString(),
      'pubspec_lock_sha256': sha256
          .convert(File('pubspec.lock').readAsBytesSync())
          .toString(),
    };
    note('Starting host cryptographic evaluation.');
    final random = Random(7132026);
    final inputs = <({String id, Uint8List? bytes, File? file})>[];
    if (dataset == null) {
      for (final seconds in [1, 5, 30]) {
        inputs.add((
          id: 'synthetic_${seconds}s_16k_mono_pcm16',
          bytes: Uint8List.fromList(
            List.generate(seconds * 32000, (_) => random.nextInt(256)),
          ),
          file: null,
        ));
      }
    } else {
      final files =
          Directory(dataset)
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where(
                (file) => RegExp(
                  r'\.(wav|pcm|raw)$',
                  caseSensitive: false,
                ).hasMatch(file.path),
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (var i = 0; i < files.length; i++) {
        inputs.add((
          id: 'dataset_${(i + 1).toString().padLeft(5, '0')}',
          bytes: null,
          file: files[i],
        ));
      }
      if (inputs.isEmpty) throw StateError('No supported inputs');
    }
    for (final input in inputs) {
      final size = input.file?.lengthSync() ?? input.bytes!.length;
      if (size == 0 || size > 16 * 1024 * 1024) {
        skipped.add({
          'input': input.id,
          'bytes': size,
          'reason': 'empty_or_over_limit',
        });
        note('Skipped ${input.id}: empty or over size limit.');
        save();
        continue;
      }
      final bytes = input.bytes ?? await input.file!.readAsBytes();
      final result = await evaluateInWorker(bytes, repetitions);
      rows.add({
        'input': input.id,
        'input_sha256': sha256.convert(bytes).toString(),
        ...result,
      });
      save();
      note(
        '${input.id}: ${result['passed'] == true ? 'PASS' : 'FAIL'} ($size bytes)',
      );
    }
    if (runTests) {
      note(
        'Running application crypto, persistence, integrity and retention tests.',
      );
      final process = await Process.start('flutter', [
        'test',
        '--no-pub',
        '--reporter',
        'json',
        'test/core/crypto',
        'test/core/services/evidence_storage_guard_test.dart',
        'test/features/evidence_vault/data',
        'test/features/evidence_vault/domain',
      ], runInShell: Platform.isWindows);
      final out = File('${output.path}/flutter-tests.jsonl').openWrite();
      final err = File('${output.path}/flutter-tests.stderr.log').openWrite();
      final streams = Future.wait([
        process.stdout.pipe(out),
        process.stderr.pipe(err),
      ]);
      final code = await process.exitCode;
      await streams;
      report['application_tests'] = {
        'exit_code': code,
        'status': code == 0 ? 'passed' : 'failed',
      };
      note('Application tests exit code: $code.');
    } else {
      report['application_tests'] = {'status': 'not_run'};
    }
    final total = rows.fold<int>(
      0,
      (sum, row) => sum + (row['roundtrip_attempts'] as int),
    );
    final successes = rows.fold<int>(
      0,
      (sum, row) => sum + (row['roundtrip_successes'] as int),
    );
    report['summary'] = {
      'inputs_evaluated': rows.length,
      'inputs_skipped': skipped.length,
      'valid_roundtrip_attempts': total,
      'exact_roundtrip_successes': successes,
      'successful_decryption_percent': total == 0
          ? null
          : successes / total * 100,
      'all_crypto_cases_passed':
          rows.isNotEmpty && rows.every((row) => row['passed'] == true),
    };
    final failed =
        rows.isEmpty ||
        rows.any((row) => row['passed'] != true) ||
        (report['application_tests'] as Map)['status'] == 'failed';
    report['status'] = failed
        ? 'failed'
        : skipped.isNotEmpty || !runTests
        ? 'partial'
        : 'passed';
    exitCode = failed
        ? 1
        : report['status'] == 'partial'
        ? 2
        : 0;
  } catch (error) {
    report['status'] = 'error';
    report['error_type'] = error.runtimeType.toString();
    note(
      'Evaluation interrupted (${error.runtimeType}); inspect saved partial results.',
    );
    exitCode = 1;
  } finally {
    report['ended_at_utc'] = DateTime.now().toUtc().toIso8601String();
    save();
    final csv = StringBuffer('input,bytes,iteration,encryption_elapsed_ms\n');
    for (final row in rows) {
      final times = row['encryption_ms'] as List;
      for (var i = 0; i < times.length; i++) {
        csv.writeln('${row['input']},${row['bytes']},${i + 1},${times[i]}');
      }
    }
    File(
      '${output.path}/encryption_samples.csv',
    ).writeAsStringSync(csv.toString());
    note('Finished: ${report['status']}. Results: ${output.path}');
    await log.close();
  }
}

// Keep the isolate closure away from main's file sinks and process handles.
Future<Map<String, Object?>> evaluateInWorker(
  Uint8List bytes,
  int repetitions,
) => Isolate.run(() => evaluateBytes(bytes, repetitions));

Future<Map<String, Object?>> evaluateBytes(
  Uint8List bytes,
  int repetitions,
) async {
  final cipher = CipherManager();
  final key = await AesGcm.with256bits().newSecretKey();
  final wrongKey = await AesGcm.with256bits().newSecretKey();
  final aad = utf8.encode('serene-evaluation-aad-v1');
  final times = <double>[];
  final nonces = <String>{};
  var successes = 0;
  var unique = true;
  EncryptedPayload? last;
  for (var i = -2; i < repetitions; i++) {
    final clock = Stopwatch()..start();
    final encrypted = await cipher.encryptInMemory(
      rawAudioBytes: bytes,
      secretKey: key,
      aad: aad,
    );
    clock.stop();
    unique = nonces.add(base64Encode(encrypted.ivBytes)) && unique;
    if (i < 0) continue;
    times.add(clock.elapsedMicroseconds / 1000);
    final recovered = await cipher.decryptInMemory(
      cipherBytes: encrypted.cipherBytes,
      ivBytes: encrypted.ivBytes,
      authTag: encrypted.authTag,
      secretKey: key,
      aad: aad,
    );
    if (sameBytes(bytes, recovered)) successes++;
    last = encrypted;
  }
  final payload = last!;
  Uint8List changed(List<int> source) => Uint8List.fromList(source)..[0] ^= 1;
  final checks = <String, bool>{};
  for (final target in ['ciphertext', 'nonce', 'tag', 'aad', 'wrong_key']) {
    try {
      await cipher.decryptInMemory(
        cipherBytes: target == 'ciphertext'
            ? changed(payload.cipherBytes)
            : payload.cipherBytes,
        ivBytes: target == 'nonce' ? changed(payload.ivBytes) : payload.ivBytes,
        authTag: target == 'tag' ? changed(payload.authTag) : payload.authTag,
        secretKey: target == 'wrong_key' ? wrongKey : key,
        aad: target == 'aad' ? changed(aad) : aad,
      );
      checks[target] = false;
    } on CryptoFailure {
      checks[target] = true;
    }
  }
  final sorted = [...times]..sort();
  final mid = sorted.length ~/ 2;
  return {
    'bytes': bytes.length,
    'roundtrip_attempts': repetitions,
    'roundtrip_successes': successes,
    'tamper_and_wrong_key_rejected': checks,
    'nonces_unique_in_this_run': unique,
    'encryption_ms': times,
    'encryption_median_ms': sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2,
    'encryption_p95_ms': sorted[(sorted.length * .95).ceil() - 1],
    'passed':
        successes == repetitions &&
        unique &&
        checks.values.every((value) => value),
  };
}

bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
