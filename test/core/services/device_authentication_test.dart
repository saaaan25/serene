import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/core/services/device_authentication.dart';
import 'package:serene/core/services/session_manager.dart';

class LocalAuthMock extends Mock implements LocalAuthentication {}

void main() {
  setUpAll(() => registerFallbackValue(const AuthenticationOptions()));
  late LocalAuthMock native;
  late DeviceAuthentication authentication;
  late SessionManager session;
  setUp(() {
    native = LocalAuthMock();
    authentication = DeviceAuthentication(localAuth: native);
    session = SessionManager()..markAuthenticated();
    when(() => native.isDeviceSupported()).thenAnswer((_) async => true);
  });
  tearDown(() => session.dispose());

  test(
    'native prompts protect the session and allow device credentials',
    () async {
      final pending = Completer<bool>();
      when(
        () => native.authenticate(
          localizedReason: any(named: 'localizedReason'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((invocation) {
        final options =
            invocation.namedArguments[#options] as AuthenticationOptions;
        expect(options.biometricOnly, isFalse);
        expect(session.isAuthenticationPromptActive, isTrue);
        return pending.future;
      });
      final result = authentication.authenticate('reason', session);
      await Future<void>.delayed(Duration.zero);
      expect(session.isAuthenticationPromptActive, isTrue);
      expect(await authentication.authenticate('duplicate', session), isFalse);
      pending.complete(true);
      expect(await result, isTrue);
      expect(session.isAuthenticationPromptActive, isFalse);
      expect(session.isAuthenticated, isTrue);
    },
  );

  test(
    'native failures leave the area locked and clear prompt state',
    () async {
      when(
        () => native.authenticate(
          localizedReason: any(named: 'localizedReason'),
          options: any(named: 'options'),
        ),
      ).thenThrow(StateError('native auth unavailable'));
      expect(await authentication.authenticate('reason', session), isFalse);
      expect(session.isAuthenticationPromptActive, isFalse);
    },
  );

  test('logged out sessions cannot authorize changes', () async {
    session.logout();
    expect(await authentication.authenticate('reason', session), isFalse);
    verifyNever(() => native.isDeviceSupported());
  });
}
