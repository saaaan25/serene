import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serene/core/crypto/cipher_manager.dart';
import 'package:serene/core/errors/failures.dart';

void main() {
  late CipherManager cipherManager;
  late AesGcm algorithm;
  late SecretKey secretKey;

  setUp(() async {
    cipherManager = CipherManager();
    algorithm = AesGcm.with256bits();
    secretKey = await algorithm.newSecretKey();
  });

  test('It should encrypt and decrypt data correctly (Roundtrip)', () async {
    final originalData = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);

    final payload = await cipherManager.encryptInMemory(
      rawAudioBytes: originalData,
      secretKey: secretKey,
    );
    final decryptedData = await cipherManager.decryptInMemory(
      cipherBytes: payload.cipherBytes,
      ivBytes: payload.ivBytes,
      authTag: payload.authTag,
      secretKey: secretKey,
    );

    expect(decryptedData, equals(originalData));
  });

  test('It should generate distinct cryptographic IVs for the same content (No IV Reuse)', () async {
    final originalData = Uint8List.fromList([1, 2, 3, 4, 5]);

    final p1 = await cipherManager.encryptInMemory(rawAudioBytes: originalData, secretKey: secretKey);
    final p2 = await cipherManager.encryptInMemory(rawAudioBytes: originalData, secretKey: secretKey);

    expect(p1.ivBytes, isNot(equals(p2.ivBytes)));
    expect(p1.cipherBytes, isNot(equals(p2.cipherBytes)));
  });

  test('It should throw a CryptoFailure if the encrypted text is tampered with (Tampering / Authentication MAC Failure)', () async {
    final originalData = Uint8List.fromList([1, 2, 3, 4]);

    final payload = await cipherManager.encryptInMemory(rawAudioBytes: originalData, secretKey: secretKey);
    // Alteración maliciosa de 1 byte
    payload.cipherBytes[0] = payload.cipherBytes[0] ^ 0xFF;

    expect(
      () async => await cipherManager.decryptInMemory(
        cipherBytes: payload.cipherBytes,
        ivBytes: payload.ivBytes,
        authTag: payload.authTag,
        secretKey: secretKey,
      ),
      throwsA(isA<CryptoFailure>()),
    );
  });

  test('It should throw a CryptoFailure if the encrypted text is decrypted with an unauthorized key', () async {
    final originalData = Uint8List.fromList([5, 6, 7, 8]);
    final unauthorizedKey = await algorithm.newSecretKey();

    final payload = await cipherManager.encryptInMemory(rawAudioBytes: originalData, secretKey: secretKey);

    expect(
      () async => await cipherManager.decryptInMemory(
        cipherBytes: payload.cipherBytes,
        ivBytes: payload.ivBytes,
        authTag: payload.authTag,
        secretKey: unauthorizedKey,
      ),
      throwsA(isA<CryptoFailure>()),
    );
  });
}