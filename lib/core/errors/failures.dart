abstract class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class CryptoFailure extends Failure {
  const CryptoFailure(super.message);
}

class SecureStorageFailure extends Failure {
  const SecureStorageFailure(super.message);
}

class AudioProcessingFailure extends Failure {
  const AudioProcessingFailure(super.message);
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}