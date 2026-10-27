import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../errors/failures.dart';

class SecureKeyStorage {
  final FlutterSecureStorage _secureStorage;
  static const String _masterKeyAlias = 'MASTER_KEY_256';
  static Future<void> _keyWork = Future.value();

  SecureKeyStorage({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  /// The OS protects the persisted key. Base64 is serialization, not encryption.
  /// Plain key bytes exist transiently in process memory for crypto operations;
  /// managed runtimes cannot guarantee erasure of every internal copy.
  Future<SecretKey> getOrCreateMasterKey() {
    final task = _keyWork.then((_) => _getOrCreateMasterKey());
    _keyWork = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<SecretKey> _getOrCreateMasterKey() async {
    try {
      final existingKeyHex = await _secureStorage.read(key: _masterKeyAlias);

      if (existingKeyHex != null) {
        final keyBytes = base64Decode(existingKeyHex);
        if (keyBytes.length != 32) {
          keyBytes.fillRange(0, keyBytes.length, 0);
          throw const SecureStorageFailure('Invalid AES-256 master key length');
        }
        try {
          return SecretKey(List<int>.from(keyBytes));
        } finally {
          keyBytes.fillRange(0, keyBytes.length, 0);
        }
      }

      // Cryptographic key 256 bits
      final algorithm = AesGcm.with256bits();
      final newSecretKey = await algorithm.newSecretKey();
      final secretKeyBytes = Uint8List.fromList(
        await newSecretKey.extractBytes(),
      );

      try {
        await _secureStorage.write(
          key: _masterKeyAlias,
          value: base64Encode(secretKeyBytes),
        );
      } finally {
        secretKeyBytes.fillRange(0, secretKeyBytes.length, 0);
      }

      return newSecretKey;
    } catch (e) {
      throw SecureStorageFailure('Error: $e');
    }
  }

  /// Protected audit head and recovery marker, stored separately from Hive.
  Future<String?> readAuditState() =>
      _secureStorage.read(key: 'EVIDENCE_AUDIT_STATE_V2');

  Future<void> writeAuditState(String state) =>
      _secureStorage.write(key: 'EVIDENCE_AUDIT_STATE_V2', value: state);

  /// Clean the master key in case of system reset.
  Future<void> clearMasterKey() async {
    try {
      await _secureStorage.delete(key: _masterKeyAlias);
    } catch (e) {
      throw SecureStorageFailure('Error: $e');
    }
  }
}
