import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:serene/core/crypto/secure_key_storage.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late SecureKeyStorage keyStorage;
  const masterKeyAlias = 'MASTER_KEY_256';

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    keyStorage = SecureKeyStorage(secureStorage: mockStorage);
  });

  test('It should retrieve the existing key if it is already stored in the secure hardware', () async {
    final existingBytes = List<int>.generate(32, (i) => i);
    final base64Key = base64Encode(existingBytes);

    when(() => mockStorage.read(key: masterKeyAlias))
        .thenAnswer((_) async => base64Key);

    final key = await keyStorage.getOrCreateMasterKey();
    final extractedBytes = await key.extractBytes();

    expect(extractedBytes, equals(existingBytes));
    verify(() => mockStorage.read(key: masterKeyAlias)).called(1);
    verifyNever(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value')));
  });

  test('It should generate a new 256-bit (32-byte) key and persist it if it does not exist', () async {
    when(() => mockStorage.read(key: masterKeyAlias)).thenAnswer((_) async => null);
    when(() => mockStorage.write(key: masterKeyAlias, value: any(named: 'value')))
        .thenAnswer((_) async {});

    final key = await keyStorage.getOrCreateMasterKey();
    final extractedBytes = await key.extractBytes();

    expect(extractedBytes.length, equals(32));
    verify(() => mockStorage.write(key: masterKeyAlias, value: any(named: 'value'))).called(1);
  });

  test('It should clear the master key from the secure hardware when invoking clearMasterKey', () async {
    when(() => mockStorage.delete(key: masterKeyAlias)).thenAnswer((_) async {});

    await keyStorage.clearMasterKey();

    verify(() => mockStorage.delete(key: masterKeyAlias)).called(1);
  });
}