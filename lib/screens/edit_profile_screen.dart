import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late bool _isPrivate;

  final ImagePicker _picker = ImagePicker();
  Uint8List? _newImageBytes;
  String? _newImageFilename;
  bool _removeAvatar = false;

  Uint8List? _newBannerBytes;
  String? _newBannerFilename;
  bool _removeBanner = false;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio ?? '');
    _isPrivate = widget.profile.isPrivate;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _newImageBytes = bytes;
          _newImageFilename = file.name;
          _removeAvatar = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al seleccionar imagen: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _pickBanner(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _newBannerBytes = bytes;
          _newBannerFilename = file.name;
          _removeBanner = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al seleccionar portada: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showImageSourcePicker() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final hasActiveAvatar = (_newImageBytes != null ||
            (widget.profile.avatarUrl != null &&
                widget.profile.avatarUrl!.isNotEmpty &&
                !_removeAvatar));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Foto de perfil',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Elegí una foto de tu dispositivo para subirla a tu perfil.',
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),

                // Option: Gallery
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.photo_library_rounded, color: colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Elegir de la galería', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Seleccionar una foto guardada en tu teléfono'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 8),

                // Option: Camera
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.camera_alt_rounded, color: colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Tomar foto', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Abrir la cámara para sacar una nueva foto'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
                  },
                ),

                // Option: Remove current photo
                if (hasActiveAvatar) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                    ),
                    title: Text(
                      'Eliminar foto de perfil',
                      style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.error),
                    ),
                    subtitle: const Text('Restablecer a las iniciales de tu cuenta'),
                    onTap: () {
                      setState(() {
                        _newImageBytes = null;
                        _newImageFilename = null;
                        _removeAvatar = true;
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBannerSourcePicker() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final hasActiveBanner = (_newBannerBytes != null ||
            (widget.profile.bannerUrl != null &&
                widget.profile.bannerUrl!.isNotEmpty &&
                !_removeBanner));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Banner de portada',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Elegí una imagen de tu dispositivo para personalizar tu portada.',
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),

                // Option: Gallery
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.image_rounded, color: colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Elegir de la galería', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Seleccionar una imagen horizontal de tu galería'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickBanner(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 8),

                // Option: Camera
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.camera_alt_rounded, color: colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Tomar foto', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Abrir la cámara para sacar una nueva portada'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickBanner(ImageSource.camera);
                  },
                ),

                // Option: Remove current banner
                if (hasActiveBanner) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                    ),
                    title: Text(
                      'Eliminar banner de portada',
                      style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.error),
                    ),
                    subtitle: const Text('Restablecer a la portada predeterminada'),
                    onTap: () {
                      setState(() {
                        _newBannerBytes = null;
                        _newBannerFilename = null;
                        _removeBanner = true;
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final newDisplayName = _displayNameController.text.trim();
    final newBio = _bioController.text.trim();

    setState(() => _isLoading = true);

    try {
      String? finalAvatarUrl = widget.profile.avatarUrl;
      String? finalBannerUrl = widget.profile.bannerUrl;

      // 1. Upload new avatar from device if selected
      if (_newImageBytes != null) {
        final uploadResponse = await AuthService().uploadAvatar(
          _newImageBytes!,
          filename: _newImageFilename ?? 'avatar.jpg',
        );

        if (!uploadResponse.success) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(uploadResponse.error ?? 'Error al subir la imagen de perfil al servidor'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }

        finalAvatarUrl = uploadResponse.profile?.avatarUrl;
      } else if (_removeAvatar) {
        finalAvatarUrl = null;
      }

      // 2. Upload new banner from device if selected
      if (_newBannerBytes != null) {
        final bannerUploadResponse = await AuthService().uploadBanner(
          _newBannerBytes!,
          filename: _newBannerFilename ?? 'banner.jpg',
        );

        if (!bannerUploadResponse.success) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(bannerUploadResponse.error ?? 'Error al subir el banner de portada al servidor'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }

        finalBannerUrl = bannerUploadResponse.profile?.bannerUrl;
      } else if (_removeBanner) {
        finalBannerUrl = null;
      }

      // 3. Update display name, bio, avatar, banner and privacy on Neon
      final updateResponse = await AuthService().updateProfile(
        displayName: newDisplayName,
        bio: newBio.isNotEmpty ? newBio : null,
        avatarUrl: _removeAvatar ? '' : finalAvatarUrl,
        bannerUrl: _removeBanner ? '' : finalBannerUrl,
        isPrivate: _isPrivate,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (updateResponse.success && updateResponse.profile != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil actualizado con éxito'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(updateResponse.profile);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(updateResponse.error ?? 'Error al actualizar el perfil'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar cambios: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  ImageProvider? _getAvatarImageProvider() {
    if (_removeAvatar) return null;
    if (_newImageBytes != null) {
      return MemoryImage(_newImageBytes!);
    }
    if (widget.profile.avatarUrl != null && widget.profile.avatarUrl!.isNotEmpty) {
      return NetworkImage(widget.profile.avatarUrl!);
    }
    return null;
  }

  Widget _buildBannerContent(ColorScheme colorScheme) {
    if (_newBannerBytes != null) {
      return Image.memory(
        _newBannerBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 130,
      );
    }
    if (!_removeBanner && widget.profile.bannerUrl != null && widget.profile.bannerUrl!.isNotEmpty) {
      return Image.network(
        widget.profile.bannerUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 130,
        errorBuilder: (context, error, stackTrace) => _buildDefaultBannerArt(colorScheme),
      );
    }
    if (!_removeBanner) {
      return Image.network(
        'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=1200&q=80',
        fit: BoxFit.cover,
        width: double.infinity,
        height: 130,
        errorBuilder: (context, error, stackTrace) => _buildDefaultBannerArt(colorScheme),
      );
    }
    return _buildDefaultBannerArt(colorScheme);
  }

  Widget _buildDefaultBannerArt(ColorScheme colorScheme) {
    return Container(
      height: 130,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E2230),
            colorScheme.primary.withValues(alpha: 0.15),
            const Color(0xFF12131A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initials = widget.profile.displayName.isNotEmpty
        ? widget.profile.displayName[0].toUpperCase()
        : widget.profile.username[0].toUpperCase();

    final avatarImage = _getAvatarImageProvider();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Editar perfil',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : FilledButton(
                    onPressed: _handleSave,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Guardar'),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Banner & Overlapping Avatar Preview
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Modern Banner background with tap handler
                GestureDetector(
                  onTap: _showBannerSourcePicker,
                  child: Container(
                    height: 130,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1E2230),
                          colorScheme.primary.withValues(alpha: 0.15),
                          const Color(0xFF12131A),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: _buildBannerContent(colorScheme),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.2),
                            Colors.black.withValues(alpha: 0.6),
                            colorScheme.surface,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // Edit Banner Pill Button on Top Right
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _showBannerSourcePicker,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt_outlined, size: 15, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Editar portada',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Avatar positioned overlapping banner
                Positioned(
                  left: 20,
                  bottom: -40,
                  child: GestureDetector(
                    onTap: _showImageSourcePicker,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: colorScheme.surface, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 44,
                            backgroundColor: colorScheme.primary,
                            backgroundImage: avatarImage,
                            onBackgroundImageError: avatarImage != null
                                ? (exception, stackTrace) {}
                                : null,
                            child: avatarImage == null
                                ? Text(
                                    initials,
                                    style: TextStyle(
                                      color: colorScheme.onPrimary,
                                      fontSize: 34,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        // Camera overlay badge
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: colorScheme.surface, width: 2.5),
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 52),

            // Form Fields
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Change photo and change banner buttons
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.person_outline_rounded, size: 18),
                          label: const Text('Cambiar foto'),
                          onPressed: _showImageSourcePicker,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: const Text('Cambiar portada'),
                          onPressed: _showBannerSourcePicker,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Display Name
                    TextFormField(
                      controller: _displayNameController,
                      maxLength: 60,
                      decoration: InputDecoration(
                        labelText: 'Nombre',
                        hintText: 'Tu nombre o apodo',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresá tu nombre';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Username (Read-only)
                    TextFormField(
                      initialValue: '@${widget.profile.username}',
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Nombre de usuario',
                        helperText: 'El nombre de usuario identifica tu cuenta de forma única.',
                        prefixIcon: const Icon(Icons.alternate_email_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Bio
                    TextFormField(
                      controller: _bioController,
                      maxLength: 300,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Biografía / Descripción',
                        hintText: 'Contale a la comunidad sobre tus intereses, proyectos o gustos...',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 50),
                          child: Icon(Icons.notes_rounded),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Privacy Settings Toggle
                    Material(
                      color: colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        value: _isPrivate,
                        onChanged: (val) => setState(() => _isPrivate = val),
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _isPrivate ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isPrivate ? Icons.lock_rounded : Icons.lock_open_rounded,
                            color: _isPrivate ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        title: const Text('Cuenta privada', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          _isPrivate
                              ? 'Solo las personas que apruebes podrán ver tus publicaciones.'
                              : 'Cualquier persona puede ver tu perfil y publicaciones.',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
