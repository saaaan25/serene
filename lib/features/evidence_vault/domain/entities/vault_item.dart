class VaultItem {
  final String id;
  final String name;
  final DateTime date;
  final bool encrypted;
  final String type; // 'audio' or 'video'

  VaultItem({
    required this.id,
    required this.name,
    required this.date,
    required this.encrypted,
    required this.type,
  });
}
