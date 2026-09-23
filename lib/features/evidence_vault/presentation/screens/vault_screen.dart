import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/controllers/app_settings_controller.dart';
import '../../../../app/dialogs/confirm_delete_dialog.dart';
import '../../../../core/localization/app_translations.dart';
import '../../domain/entities/vault_item.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  // Mock data for the vault items
  final List<VaultItem> _vaultItems = [
    VaultItem(
      id: '1',
      name: 'Evening_Briefing_0...',
      date: DateTime(2026, 9, 14, 12, 45),
      encrypted: true,
      type: 'audio',
    ),
    VaultItem(
      id: '2',
      name: 'Security_Log_Hom...',
      date: DateTime(2026, 9, 13, 5, 12),
      encrypted: true,
      type: 'video',
    ),
    VaultItem(
      id: '3',
      name: 'Legal_Meeting_Tra...',
      date: DateTime(2026, 9, 11, 16, 10),
      encrypted: true,
      type: 'audio',
    ),
    VaultItem(
      id: '4',
      name: 'Street_Observation...',
      date: DateTime(2026, 9, 10, 2, 30),
      encrypted: true,
      type: 'video',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final tertiaryColor = Theme.of(context).colorScheme.tertiary;

    // Get the current locale from the AppSettingsController
    final settingsController = context.watch<AppSettingsController>();
    final currentLocale = settingsController.locale;
    String t(String key) => AppTranslations.tr(key, currentLocale);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            //Icon(Icons.shield, color: primaryColor, size: 24),
            const SizedBox(width: 12),
            Text(
              'serene',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
            ),
            child: const CircleAvatar(
              child: Icon(Icons.person),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  t('vault_title'),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: primaryColor,
                      ),
                ),

                const SizedBox(height: 8),

                Text(
                  t('vault_subtitle'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7),
                      ),
                ),

                const SizedBox(height: 32),

                // State Badge
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: primaryColor.withValues(alpha: 0.15),
                            ),
                            child: Icon(
                              Icons.verified,
                              color: primaryColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            t('vault_status_badge'),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t('vault_encryption_active'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t('vault_encryption_desc'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7),
                              height: 1.6,
                            ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Import button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(
                      backgroundColor: tertiaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.upload, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          t('vault_import_btn'),
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Recent Assets Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tertiaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          t('vault_recent_assets'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () {},
                      child: Text(
                        t('vault_sort_by_date'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Lista de elementos en el baúl
                ..._vaultItems.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _VaultItemCard(
                        item: item,
                        deleteActionText: t('vault_delete_action'),
                        onDelete: () {
                          showDialog(
                            context: context,
                            builder: (context) => ConfirmDeleteDialog(
                              title: t('vault_delete_title'),
                              message: t('vault_delete_msg'),
                              onConfirm: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(t('vault_delete_success')),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    )),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultItemCard extends StatelessWidget {
  final VaultItem item;
  final String deleteActionText;
  final VoidCallback onDelete;

  const _VaultItemCard({
    required this.item,
    required this.deleteActionText,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final tertiaryColor = Theme.of(context).colorScheme.tertiary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor.withValues(alpha: 0.15),
            ),
            child: Icon(
              item.type == 'audio' ? Icons.mic : Icons.videocam,
              color: primaryColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(item.date)} • ${_formatTime(item.date)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock, color: tertiaryColor, size: 20),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: onDelete,
                child: Text(deleteActionText),
              ),
            ],
            child: Icon(
              Icons.more_vert,
              color: primaryColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}