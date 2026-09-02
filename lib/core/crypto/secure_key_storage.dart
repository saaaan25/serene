import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';
import '../errors/failures.dart';

class SecureKeyStorage {
  final FlutterSecureStorage _secureStorage;
  static const String _masterKeyAlias = 'MASTER_KEY_256';

  SecureKeyStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  /// Get or create a master key for AES encryption
  Future<SecretKey> getOrCreateMasterKey() async {
    try {
      final existingKeyHex = await _secureStorage.read(key: _masterKeyAlias);

      if (existingKeyHex != null) {
        final keyBytes = base64Decode(existingKeyHex);
        return SecretKey(keyBytes);
      }

      // Cryptographic key 256 bits
      final algorithm = AesGcm.with256bits();
      final newSecretKey = await algorithm.newSecretKey();
      final secretKeyBytes = await newSecretKey.extractBytes();

      await _secureStorage.write(
        key: _masterKeyAlias,
        value: base64Encode(secretKeyBytes),
      );

      return newSecretKey;
    } catch (e) {
      throw SecureStorageFailure('Error: $e');
    }
  }

  /// Clean the master key in case of system reset
  Future<void> clearMasterKey() async {
    try {
      await _secureStorage.delete(key: _masterKeyAlias);
    } catch (e) {
      throw SecureStorageFailure('Error: $e');
    }
  }
}