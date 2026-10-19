import 'package:cryptography/cryptography.dart';
import 'package:serene/core/crypto/secure_key_storage.dart';
import 'package:serene/core/services/evidence_storage_guard.dart';

EvidenceStorageGuard ampleStorage() =>
    EvidenceStorageGuard(freeBytes: (_) async => 10 * 1024 * 1024 * 1024);

/// Models the secure-storage boundary while retaining state across Hive reopen.
class MemoryEvidenceKeys extends SecureKeyStorage {
  final SecretKey secret = SecretKey(List.generate(32, (i) => i));
  String? anchor;
  @override
  Future<SecretKey> getOrCreateMasterKey() async => secret;
  @override
  Future<String?> readAuditState() async => anchor;
  @override
  Future<void> writeAuditState(String state) async {
    anchor = state;
  }
}
