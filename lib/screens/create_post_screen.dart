import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';
import '../models/post_content.dart';
import '../models/rating.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/catalog_service.dart';
import '../widgets/review_picker.dart';

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
  final ImagePicker _picker = ImagePicker();

  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _isPublishing = false;
  bool _showPreview = false;
  bool _isEphemeral = false;

  /// Movie, song or album being reviewed, and its stars (0 = not chosen yet).
  CatalogItem? _reviewItem;
  int _reviewStars = 0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickReviewItem() async {
    final item = await showReviewItemPicker(
      context,
      initialCategory: _reviewItem?.category ?? RatingCategory.movie,
    );
    if (item == null || !mounted) return;
    setState(() {
      // Keep the stars when swapping the item; a fresh review starts unrated.
      if (_reviewItem == null) _reviewStars = 0;
      _reviewItem = item;
    });
  }

  void _removeReview() {
    setState(() {
      _reviewItem = null;
      _reviewStars = 0;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = picked.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo seleccionar la imagen: $e')),
        );
      }
    }
  }

  void _showImageSourcePicker() {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Elegir de la galería'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded),
                  title: const Text('Tomar foto con la cámara'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _removeSelectedImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
    });
  }

  Future<void> _handlePublish() async {
    final text = _textController.text.trim();
    final reviewItem = _reviewItem;
    if (reviewItem != null && _reviewStars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elegí de 1 a 5 estrellas para tu reseña.')),
      );
      return;
    }
    if (text.isEmpty && _selectedImageBytes == null && reviewItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribí algo o seleccioná una imagen para publicar.')),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      String? uploadedImageUrl;

      // Upload image to Neon Object Storage if selected
      if (_selectedImageBytes != null) {
        uploadedImageUrl = await AuthService().uploadPostImage(
          _selectedImageBytes!,
          filename: _selectedImageName ?? 'post.jpg',
        );
        if (uploadedImageUrl == null) {
          if (!mounted) return;
          setState(() => _isPublishing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al subir la imagen. Intentá de nuevo.')),
          );
          return;
        }
      }

      // Create post on Neon backend (the review header and 24 h mark travel in the text)
      final rating = reviewItem?.toRating(_reviewStars);
      final content = PostContent(body: text, review: rating, isEphemeral: _isEphemeral).compose();
      final post = await AuthService().createPost(
        content: content.isNotEmpty ? content : null,
        imageUrl: uploadedImageUrl,
      );

      // Like rating from the profile, a published review also lands in the
      // user's ratings; the post stays published even if that part fails.
      String? bioError;
      if (post != null && rating != null) {
        final bioResponse = await AuthService().updateBioRatings((bio) => bio.withRating(rating));
        if (!bioResponse.success) {
          bioError = bioResponse.error ?? 'No se pudo guardar la calificación en tu perfil.';
        }
      }

      if (!mounted) return;
      setState(() => _isPublishing = false);

      if (post != null) {
        final wasEphemeral = _isEphemeral;
        _textController.clear();
        setState(() {
          _selectedImageBytes = null;
          _selectedImageName = null;
          _showPreview = false;
          _isEphemeral = false;
          _reviewItem = null;
          _reviewStars = 0;
        });

        final String message;
        if (rating == null) {
          message = '¡Publicación creada con éxito!';
        } else if (bioError == null) {
          message = '¡Publicaste tu reseña de "${rating.title}"!';
        } else {
          message = 'Publicaste tu reseña, pero no se guardó en tu descripción. $bioError';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasEphemeral ? '$message Se deja de mostrar en 24 horas.' : message),
            behavior: SnackBarBehavior.floating,
          ),
        );

        widget.onPublished?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo crear la publicación. Intentá de nuevo.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final current = AuthService().currentUser ?? widget.profile;
    final displayName = current?.displayName ?? 'Usuario';
    final username = current?.username ?? 'usuario';
    final avatarUrl = current?.avatarUrl;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

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
          // Preview Toggle button
          if (_textController.text.trim().isNotEmpty)
            TextButton.icon(
              icon: Icon(
                _showPreview ? Icons.edit_note_rounded : Icons.visibility_outlined,
                size: 18,
              ),
              label: Text(_showPreview ? 'Editar' : 'Vista previa'),
              onPressed: () {
                setState(() => _showPreview = !_showPreview);
              },
            ),
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
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          decoration: isDesktop
              ? BoxDecoration(
                  color: colorScheme.surface,
                  border: Border.symmetric(
                    vertical: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                )
              : null,
          child: SingleChildScrollView(
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

            // Review of a movie or music (shown above the opinion, like in the feed)
            if (_reviewItem != null) ...[
              ReviewDraftCard(
                item: _reviewItem!,
                stars: _reviewStars,
                onStarsChanged: (value) => setState(() => _reviewStars = value),
                onChange: _pickReviewItem,
                onRemove: _removeReview,
              ),
              const SizedBox(height: 12),
            ],

            // Content textfield or Markdown Preview
            if (_showPreview)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Vista previa de Markdown',
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    MarkdownBody(
                      data: _textController.text,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        p: textTheme.bodyMedium?.copyWith(height: 1.45, fontSize: 15),
                        code: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          backgroundColor:
                              colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                          color: colorScheme.primary,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                          ),
                        ),
                        codeblockPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              )
            else
              TextField(
                controller: _textController,
                maxLines: 7,
                minLines: 4,
                onChanged: (_) => setState(() {}),
                style: textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: _reviewItem != null
                      ? '¿Qué te pareció "${_reviewItem!.title}"? (opcional)'
                      : '¿Qué estás pensando?\nPodés usar Markdown, listas o bloques de código con ``` ...',
                  hintStyle: textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                  ),
                  border: InputBorder.none,
                  filled: false,
                ),
              ),

            // Image Preview if selected
            if (_selectedImageBytes != null) ...[
              const SizedBox(height: 16),
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 280),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Image.memory(
                        _selectedImageBytes!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: _removeSelectedImage,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 12),

            // Attachments: photo and movie/music review
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
                  label: Text(_selectedImageBytes == null ? 'Agregar foto' : 'Cambiar foto'),
                  onPressed: _showImageSourcePicker,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.rate_review_outlined, size: 20),
                  label: Text(_reviewItem == null ? 'Reseña' : 'Cambiar reseña'),
                  onPressed: _pickReviewItem,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                if (_selectedImageBytes != null)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                    label: const Text('Quitar foto', style: TextStyle(color: Colors.redAccent)),
                    onPressed: _removeSelectedImage,
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Duration: permanent or 24 hours
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Duración',
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.all_inclusive_rounded, size: 18),
                    label: Text('Permanente'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.timelapse_rounded, size: 18),
                    label: Text('24 horas'),
                  ),
                ],
                selected: {_isEphemeral},
                onSelectionChanged: (selection) => setState(() => _isEphemeral = selection.first),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isEphemeral
                  ? 'Se deja de mostrar en Brote 24 horas después de publicarla.'
                  : 'Queda en tu perfil y en el feed.',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ),
  ),
);
  }
}
