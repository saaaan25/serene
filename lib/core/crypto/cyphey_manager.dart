import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../errors/failures.dart';

class EncryptedPayload {
  final Uint8List cipherBytes;
  final Uint8List ivBytes;
  final Uint8List authTag;

  EncryptedPayload({
    required this.cipherBytes,
    required this.ivBytes,
    required this.authTag,
  });
}

class CipherManager {
  final AesGcm _algorithm;

  CipherManager() : _algorithm = AesGcm.with256bits();

  /// Encrypts raw audio bytes in memory using AES-GCM with a provided secret key
  Future<EncryptedPayload> encryptInMemory({
    required Uint8List rawAudioBytes,
    required SecretKey secretKey,
  }) async {
    try {
      final secretBox = await _algorithm.encrypt(
        rawAudioBytes,
        secretKey: secretKey,
      );

      return EncryptedPayload(
        cipherBytes: Uint8List.fromList(secretBox.cipherText),
        ivBytes: Uint8List.fromList(secretBox.nonce),
        authTag: Uint8List.fromList(secretBox.mac.bytes),
      );
    } catch (e) {
      throw CryptoFailure('Error: $e');
    }
  }

  /// Decrypts the volatile binary blob into reproducible audio
  Future<Uint8List> decryptInMemory({
    required Uint8List cipherBytes,
    required Uint8List ivBytes,
    required Uint8List authTag,
    required SecretKey secretKey,
  }) async {
    try {
      final secretBox = SecretBox(
        cipherBytes,
        nonce: ivBytes,
        mac: Mac(authTag),
      );

      final decryptedBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return Uint8List.fromList(decryptedBytes);
    } catch (e) {
      throw CryptoFailure('Error: $e');
    }
  }
}