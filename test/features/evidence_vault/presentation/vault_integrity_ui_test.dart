import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:serene/app/controllers/app_settings_controller.dart';
import 'package:serene/core/errors/failures.dart';
import 'package:serene/core/constants/hive_constants.dart';
import 'package:serene/core/models/app_settings.dart';
import 'package:serene/features/evidence_vault/data/datasources/evidence_local_datasource.dart';
import 'package:serene/features/evidence_vault/data/models/evidence_record_model.dart';
import 'package:serene/features/evidence_vault/domain/entities/evidence_record.dart';
import 'package:serene/features/evidence_vault/domain/repositories/evidence_repository.dart';
import 'package:serene/features/evidence_vault/presentation/screens/vault_screen.dart';

import '../../../support/evidence_fixtures.dart';
import '../../../support/memory_evidence_keys.dart';

class MockVaultRepository extends Mock implements EvidenceRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppSettingsController settings;
  late MockVaultRepository repository;
  late List<EvidenceRecord> records;
  GoRouter? router;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('serene_vault_ui_');
    Hive.init(root.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(EvidenceRecordModelAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
    settings = AppSettingsController(
      box: await Hive.openBox<AppSettings>('appSettings'),
    );
    final keys = MemoryEvidenceKeys();
    final source = EvidenceLocalDataSourceImpl(
      storageGuard: ampleStorage(),
      keyStorage: keys,
    );
    await source.insertRecord(await sealedFixture(keys));
    await source.insertRecord(
      await sealedFixture(
        keys,
        id: 'version-2',
        second: 2,
        previous: 'version-1',
      ),
    );
    records = await testRepository(source, keys).getAllEvidenceRecords();
    repository = MockVaultRepository();
    when(
      () => repository.getAllEvidenceRecords(),
    ).thenAnswer((_) async => records);
  });
  tearDown(() async {
    router?.dispose();
    settings.dispose();
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<void> render(WidgetTester tester, {bool settle = true}) async {
    router = GoRouter(
      initialLocation: '/vault',
      routes: [GoRoute(path: '/vault', builder: (_, _) => const VaultScreen())],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsController>.value(value: settings),
          Provider<EvidenceRepository>.value(value: repository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets(
    'vault uses authenticated repository metadata and shows one incident',
    (tester) async {
      await render(tester);
      expect(find.text('1 items'), findsOneWidget);
      expect(find.textContaining('sensitive-label'), findsOneWidget);
      expect(find.textContaining('Registro antiguo'), findsNothing);
      verify(() => repository.getAllEvidenceRecords()).called(1);
    },
  );

  testWidgets(
    'an incoming change during loading triggers another repository read',
    (tester) async {
      final pending = Completer<List<EvidenceRecord>>();
      var calls = 0;
      when(() => repository.getAllEvidenceRecords()).thenAnswer((_) {
        calls++;
        return calls == 1 ? pending.future : Future.value([]);
      });
      await render(tester, settle: false);
      await tester.pump();
      expect(calls, 1);
      await tester.runAsync(() async {
        final box = Hive.box<EvidenceRecordModel>(
          HiveConstants.encryptedEvidenceBox,
        );
        await box.put('version-2', box.get('version-2')!);
      });
      await tester.pump();
      pending.complete(records);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('0 items'), findsOneWidget);
      expect(find.textContaining('sensitive-label'), findsNothing);
    },
  );

  testWidgets('legacy recordings are visibly marked', (tester) async {
    final record = records.single;
    records = [
      EvidenceRecord(
        id: 'legacy',
        timestamp: record.timestamp,
        predictionLabel: 'old-label',
        confidenceScore: .9,
        gpsCoordinates: const {},
        encryptedAudioBlob: record.encryptedAudioBlob,
        ivBytes: record.ivBytes,
        authTag: record.authTag,
        integrityHash: 'legacy-hash',
      ),
    ];
    await render(tester);
    expect(
      find.textContaining('Registro antiguo: sin metadatos autenticados'),
      findsOneWidget,
    );
  });

  testWidgets(
    'failed integrity check hides evidence and shows a verification error',
    (tester) async {
      when(
        () => repository.getAllEvidenceRecords(),
      ).thenThrow(const CryptoFailure('changed audit'));
      await render(tester);
      expect(
        find.textContaining('No se pudo verificar la integridad'),
        findsOneWidget,
      );
      expect(find.textContaining('sensitive-label'), findsNothing);
    },
  );
}
