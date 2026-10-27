import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:serene/app/controllers/app_settings_controller.dart';
import 'package:serene/core/models/app_settings.dart';
import 'package:serene/core/services/device_authentication.dart';
import 'package:serene/core/services/session_manager.dart';
import 'package:serene/features/evidence_vault/presentation/widgets/vault_access_gate.dart';

class AuthMock extends Mock implements DeviceAuthentication {}

void main() {
  late Directory root;
  late AppSettingsController settings;
  late SessionManager session;
  late AuthMock auth;
  late GoRouter router;
  int loads = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('serene_vault_gate_');
    Hive.init(root.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AppSettingsAdapter());
    }
    settings = AppSettingsController(
      box: await Hive.openBox<AppSettings>('appSettings'),
    );
    session = SessionManager()..markAuthenticated();
    auth = AuthMock();
    loads = 0;
    when(() => auth.authenticate(any(), session)).thenAnswer((_) async => true);
    router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/home', builder: (_, _) => const Text('home')),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/vault',
                  builder: (_, _) => VaultAccessGate(
                    builder: (_) => _RecordList(onLoad: () => loads++),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (_, _) => const Text('settings'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  });
  tearDown(() async {
    router.dispose();
    session.dispose();
    settings.dispose();
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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'every reentry to a retained vault branch authenticates and reloads',
    (tester) async {
      await render(tester);
      router.go('/vault');
      await tester.pumpAndSettle();
      expect(find.text('sensitive recordings'), findsOneWidget);
      expect(loads, 1);
      router.go('/settings');
      await tester.pumpAndSettle();
      router.go('/vault');
      await tester.pumpAndSettle();
      expect(loads, 2);
      verify(() => auth.authenticate(any(), session)).called(2);
    },
  );

  testWidgets('cancelled authentication does not mount or load recordings', (
    tester,
  ) async {
    when(
      () => auth.authenticate(any(), session),
    ).thenAnswer((_) async => false);
    await render(tester);
    router.go('/vault');
    await tester.pumpAndSettle();
    expect(loads, 0);
    expect(find.text('sensitive recordings'), findsNothing);
    expect(find.text('Desbloquear grabaciones'), findsOneWidget);
  });

  testWidgets('leaving during an auth prompt cannot unlock the hidden branch', (
    tester,
  ) async {
    final pending = Completer<bool>();
    when(
      () => auth.authenticate(any(), session),
    ).thenAnswer((_) => pending.future);
    await render(tester);
    router.go('/vault');
    await tester.pump();
    await tester.pump();
    expect(loads, 0);
    router.go('/home');
    await tester.pumpAndSettle();
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(loads, 0);
    expect(
      find.text('sensitive recordings', skipOffstage: false),
      findsNothing,
    );
  });
}

class _RecordList extends StatefulWidget {
  const _RecordList({required this.onLoad});
  final VoidCallback onLoad;
  @override
  State<_RecordList> createState() => _RecordListState();
}

class _RecordListState extends State<_RecordList> {
  @override
  void initState() {
    super.initState();
    widget.onLoad();
  }

  @override
  Widget build(BuildContext context) => const Text('sensitive recordings');
}
