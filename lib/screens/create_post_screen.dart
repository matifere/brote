import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';

class CreatePostScreen extends StatefulWidget {
  final UserProfile? profile;
  final VoidCallback? onPublished;

  const CreatePostScreen({
    super.key,
    this.profile,
    this.onPublished,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isPublishing = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _handlePublish() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribí algo antes de publicar.')),
      );
      return;
    }

    setState(() => _isPublishing = true);
    // Placeholder feedback before publications backend implementation
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      _textController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publicación creada con éxito'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onPublished?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final current = AuthService().currentUser ?? widget.profile;
    final displayName = current?.displayName ?? 'Usuario';
    final username = current?.username ?? 'usuario';
    final avatarUrl = current?.avatarUrl;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        title: const Text(
          'Nueva publicación',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _isPublishing ? null : _handlePublish,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: _isPublishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Publicar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User header
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? NetworkImage(avatarUrl)
                      : null,
                  onBackgroundImageError: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? (exception, stackTrace) {}
                      : null,
                  child: (avatarUrl == null || avatarUrl.isEmpty)
                      ? Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '@$username',
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content textfield
            TextField(
              controller: _textController,
              maxLines: 7,
              minLines: 4,
              style: textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: '¿Qué estás pensando? Compartí fotos, novedades o ideas...',
                hintStyle: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                border: InputBorder.none,
                filled: false,
              ),
            ),
            const SizedBox(height: 24),

            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 12),

            // Media attachment options
            Text(
              'Agregar a tu publicación',
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildAttachmentButton(
                  icon: Icons.image_rounded,
                  label: 'Foto / Video',
                  colorScheme: colorScheme,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Selección de fotos en la siguiente sección.')),
                    );
                  },
                ),
                const SizedBox(width: 8),
                _buildAttachmentButton(
                  icon: Icons.tag_rounded,
                  label: 'Tema',
                  colorScheme: colorScheme,
                  onTap: () {},
                ),
                const SizedBox(width: 8),
                _buildAttachmentButton(
                  icon: Icons.location_on_outlined,
                  label: 'Ubicación',
                  colorScheme: colorScheme,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentButton({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
