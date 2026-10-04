class VaultStats {
  final int totalCount;
  final int totalBytes;

  const VaultStats({
    required this.totalCount,
    required this.totalBytes,
  });

  /// Formatea la suma de bytes a una cadena legible (ej: "1.4 MB", "320 KB", "0 B")
  String get formattedSpace {
    if (totalBytes <= 0) return '0 B';
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}