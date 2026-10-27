import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:serene/app/controllers/app_settings_controller.dart';
import 'package:serene/core/models/app_settings.dart';
import 'package:serene/core/services/device_authentication.dart';
import 'package:serene/core/services/session_manager.dart';
import 'package:serene/features/evidence_vault/domain/entities/evidence_record.dart';
import 'package:serene/features/evidence_vault/domain/repositories/evidence_repository.dart';
import 'package:serene/features/evidence_vault/presentation/screens/audio_playback_screen.dart';
import 'package:serene/features/evidence_vault/presentation/widgets/in_memory_audio_player.dart';

class AuthMock extends Mock implements DeviceAuthentication {}

class RepositoryMock extends Mock implements EvidenceRepository {}

void main() {
  late Directory root;
  late AppSettingsController settings;
  late SessionManager session;
  late AuthMock auth;
  late RepositoryMock repository;
  late EvidenceRecord record;
  late Uint8List pcm;
  Uint8List? wav;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('serene_playback_');
    Hive.init(root.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
    settings = AppSettingsController(
      box: await Hive.openBox<AppSettings>('appSettings'),
    );
    session = SessionManager()..markAuthenticated();
    auth = AuthMock();
    repository = RepositoryMock();
    record = EvidenceRecord(
      id: 'audio-record',
      timestamp: DateTime.utc(2026),
      predictionLabel: 'verbal_violence',
      confidenceScore: .9,
      gpsCoordinates: const {},
      encryptedAudioBlob: Uint8List.fromList([7, 8]),
      ivBytes: Uint8List(12),
      authTag: Uint8List(16),
      integrityHash: 'checksum',
    );
    pcm = Uint8List.fromList([1, 2, 3, 4]);
    wav = null;
    when(() => auth.authenticate(any(), session)).thenAnswer((_) async => true);
    when(
      () => repository.getDecryptedAudioBytes(record),
    ).thenAnswer((_) async => pcm);
  });
  tearDown(() async {
    settings.dispose();
    session.dispose();
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<void> render(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsController>.value(value: settings),
          ChangeNotifierProvider<SessionManager>.value(value: session),
          Provider<DeviceAuthentication>.value(value: auth),
          Provider<EvidenceRepository>.value(value: repository),
        ],
        child: MaterialApp(
          home: AudioPlaybackScreen(
            record: record,
            playerBuilder: (bytes) {
              wav = bytes;
              return const Text('memory player');
            },
          ),
        ),
      ),
    );
  }

  testWidgets(
    'audio is not decrypted before its own authentication completes',
    (tester) async {
      final pending = Completer<bool>();
      when(
        () => auth.authenticate(any(), session),
      ).thenAnswer((_) => pending.future);
      await render(tester);
      await tester.pump();
      verifyNever(() => repository.getDecryptedAudioBytes(record));
      expect(wav, isNull);
      pending.complete(true);
      await tester.pumpAndSettle();
      verify(() => repository.getDecryptedAudioBytes(record)).called(1);
      expect(find.text('memory player'), findsOneWidget);
      expect(wav!.sublist(44), [1, 2, 3, 4]);
      expect(pcm, everyElement(0));
      // The player receives the owned WAV buffer, which is cleared on exit.
      final playbackBuffer = wav!;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(playbackBuffer, everyElement(0));
    },
  );

  testWidgets(
    'cancelled audio authentication never decrypts or mounts player',
    (tester) async {
      when(
        () => auth.authenticate(any(), session),
      ).thenAnswer((_) async => false);
      await render(tester);
      await tester.pumpAndSettle();
      verifyNever(() => repository.getDecryptedAudioBytes(record));
      expect(wav, isNull);
      expect(find.text('memory player'), findsNothing);
    },
  );

  testWidgets('a new audio screen requests a fresh authentication', (
    tester,
  ) async {
    await render(tester);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    pcm = Uint8List.fromList([5, 6]);
    await render(tester);
    await tester.pumpAndSettle();
    verify(() => auth.authenticate(any(), session)).called(2);
    expect(wav!.sublist(44), [5, 6]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('decryption finishing after screen exit clears the result', (
    tester,
  ) async {
    final pending = Completer<Uint8List>();
    when(
      () => repository.getDecryptedAudioBytes(record),
    ).thenAnswer((_) => pending.future);
    await render(tester);
    await tester.pump();
    verify(() => repository.getDecryptedAudioBytes(record)).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(pcm);
    await tester.pumpAndSettle();
    expect(pcm, everyElement(0));
    expect(wav, isNull);
  });

  test(
    'in-memory source serves byte ranges as views of the volatile buffer',
    () async {
      final bytes = Uint8List.fromList([10, 20, 30, 40]);
      final source = InMemoryAudioSource(audioData: bytes);
      final response = await source.request(1, 3);
      expect(response.contentType, 'audio/wav');
      expect(response.contentLength, 2);
      expect(response.sourceLength, 4);
      final view = await response.stream.first;
      expect(view, [20, 30]);
      bytes.fillRange(0, bytes.length, 0);
      expect(view, [0, 0]);
    },
  );
}
