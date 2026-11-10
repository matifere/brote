import 'package:flutter/material.dart';
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
  late final TextEditingController _avatarUrlController;

  bool _isLoading = false;
  String? _selectedAvatarUrl;

  static const List<String> _avatarPresets = [
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=400&q=80',
  ];

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio ?? '');
    _avatarUrlController = TextEditingController(text: widget.profile.avatarUrl ?? '');
    _selectedAvatarUrl = widget.profile.avatarUrl;

    _avatarUrlController.addListener(() {
      final text = _avatarUrlController.text.trim();
      if (text != _selectedAvatarUrl) {
        setState(() {
          _selectedAvatarUrl = text.isNotEmpty ? text : null;
        });
      }
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final newDisplayName = _displayNameController.text.trim();
    final newBio = _bioController.text.trim();
    final newAvatar = _selectedAvatarUrl?.trim();

    setState(() => _isLoading = true);

    final response = await AuthService().updateProfile(
      displayName: newDisplayName,
      bio: newBio.isNotEmpty ? newBio : null,
      avatarUrl: newAvatar != null && newAvatar.isNotEmpty ? newAvatar : null,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (response.success && response.profile != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil actualizado con éxito'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(response.profile);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.error ?? 'Error al actualizar perfil'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showAvatarPickerSheet() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
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
                  'Elegí una imagen prediseñada o ingresá la URL de tu foto.',
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),

                // Avatar Presets Grid
                Text(
                  'Avatares destacados',
                  style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _avatarPresets.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final url = _avatarPresets[index];
                      final isSelected = _selectedAvatarUrl == url;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedAvatarUrl = url;
                            _avatarUrlController.text = url;
                          });
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? colorScheme.primary : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 30,
                            backgroundImage: NetworkImage(url),
                            onBackgroundImageError: (exception, stackTrace) {},
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // Action to clear avatar
                if (_selectedAvatarUrl != null) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                    ),
                    title: const Text('Quitar foto de perfil'),
                    subtitle: const Text('Volver a la inicial predeterminada'),
                    onTap: () {
                      setState(() {
                        _selectedAvatarUrl = null;
                        _avatarUrlController.clear();
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 8),
                ],

                // Action to enter custom URL
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.link_rounded, color: colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Ingresar URL personalizada'),
                  subtitle: const Text('Pegá el enlace directo a tu imagen (JPG, PNG)'),
                  onTap: () {
                    Navigator.pop(ctx);
                    // Scroll to URL field or focus it
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initials = widget.profile.displayName.isNotEmpty
        ? widget.profile.displayName[0].toUpperCase()
        : widget.profile.username[0].toUpperCase();

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
                // Banner background
                Container(
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
                  child: Image.network(
                    'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?auto=format&fit=crop&w=1200&q=80',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const SizedBox(),
                  ),
                ),
                Positioned.fill(
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

                // Avatar positioned overlapping banner
                Positioned(
                  left: 20,
                  bottom: -40,
                  child: GestureDetector(
                    onTap: _showAvatarPickerSheet,
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
                            backgroundImage: _selectedAvatarUrl != null
                                ? NetworkImage(_selectedAvatarUrl!)
                                : null,
                            onBackgroundImageError: _selectedAvatarUrl != null
                                ? (exception, stackTrace) {}
                                : null,
                            child: _selectedAvatarUrl == null
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
                        // Camera icon overlay
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

            // Form Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar change trigger button
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Cambiar foto de perfil'),
                      onPressed: _showAvatarPickerSheet,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Display Name Field
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

                    // Username Field (Read-only)
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

                    // Bio Field
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
                    const SizedBox(height: 16),

                    // Avatar URL Field (Direct link input)
                    TextFormField(
                      controller: _avatarUrlController,
                      decoration: InputDecoration(
                        labelText: 'URL de imagen de perfil (opcional)',
                        hintText: 'https://...',
                        prefixIcon: const Icon(Icons.link_rounded),
                        suffixIcon: _avatarUrlController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _avatarUrlController.clear();
                                  setState(() => _selectedAvatarUrl = null);
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      ),
                    ),
                    const SizedBox(height: 40),
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
