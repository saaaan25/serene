/// Secret trigger sequence detector for unlocking the vault
/// Uses a numeric pattern to invoke biometric authentication
class SecretTrigger {
  // The secret sequence to trigger vault access
  // Example: "19+1=" becomes "191" then "=" triggers the gate
  static const String triggerSequence = '191=';

  final List<String> _input = [];

  /// Add a digit or operator to the input buffer
  void addInput(String value) {
    _input.add(value);
    _checkForTrigger();
  }

  /// Check if the current input matches the trigger sequence
  bool _checkForTrigger() {
    if (_input.length > triggerSequence.length) {
      _input.removeAt(0);
    }
    return _input.join() == triggerSequence;
  }

  /// Determines if the vault should be triggered
  /// Returns true if trigger sequence is matched
  bool shouldTriggerVault() {
    return _input.length >= triggerSequence.length &&
        _input.join() == triggerSequence;
  }

  /// Reset the trigger detector
  void reset() {
    _input.clear();
  }

  /// Get current input for debugging
  String getInputBuffer() => _input.join();
}
