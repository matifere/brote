import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AuthService _authService = AuthService();

  // Active tab index (0: Login, 1: Register)
  int _activeTabIndex = 0;

  // Login form controllers
  final _loginFormKey = GlobalKey<FormState>();
  final _loginUsernameController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  bool _loginObscurePassword = true;

  // Register form controllers
  final _registerFormKey = GlobalKey<FormState>();
  final _registerNameController = TextEditingController();
  final _registerUsernameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerConfirmPasswordController = TextEditingController();
  bool _registerObscurePassword = true;
  bool _registerObscureConfirm = true;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || _tabController.index != _activeTabIndex) {
        setState(() {
          _activeTabIndex = _tabController.index;
          _errorMessage = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    _registerNameController.dispose();
    _registerUsernameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmPasswordController.dispose();
    super.dispose();
  }

  String _cleanErrorMessage(String rawError) {
    if (rawError.contains('Connection refused') ||
        rawError.contains('SocketException') ||
        rawError.contains('errno = 111')) {
      return 'No se pudo conectar al servidor backend (conexión rechazada). Verificá que el servidor esté encendido.';
    }
    if (rawError.contains('Failed host lookup')) {
      return 'No se pudo encontrar la dirección del servidor. Verificá tu conexión.';
    }
    return rawError;
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    // Dismiss keyboard before submitting
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await _authService.login(
      username: _loginUsernameController.text.trim(),
      password: _loginPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res.success && res.profile != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(profile: res.profile!)),
      );
    } else {
      setState(() {
        _errorMessage = _cleanErrorMessage(res.error ?? 'Credenciales inválidas.');
      });
    }
  }

  Future<void> _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;

    // Dismiss keyboard before submitting
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await _authService.register(
      displayName: _registerNameController.text.trim(),
      username: _registerUsernameController.text.trim().toLowerCase(),
      email: _registerEmailController.text.trim().isEmpty ? null : _registerEmailController.text.trim(),
      password: _registerPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res.success && res.profile != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡Bienvenido a Brote, @${res.profile!.username}!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(profile: res.profile!)),
      );
    } else {
      setState(() {
        _errorMessage = _cleanErrorMessage(res.error ?? 'No se pudo crear la cuenta.');
      });
    }
  }

  void _showServerConfigDialog() {
    final textController = TextEditingController(text: _authService.baseUrl);
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Configurar Servidor',
          style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'URL del Backend Brote:',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: textController,
              decoration: InputDecoration(
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                hintText: 'http://10.0.2.2:3333',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '• Emulador Android: http://10.0.2.2:3333\n• Dispositivo físico: http://<tu-ip-local>:3333\n• Web/Desktop/iOS: http://localhost:3333',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: Text('Cancelar', style: TextStyle(color: colorScheme.onSurfaceVariant)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: const Text('Guardar'),
            onPressed: () {
              setState(() {
                _authService.baseUrl = textController.text.trim();
              });
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Configuración de servidor API',
            icon: Icon(Icons.settings_outlined, color: colorScheme.onSurfaceVariant),
            onPressed: _showServerConfigDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          // Bottom padding includes keyboard insets + generous margin for clear typing visibility
          padding: EdgeInsets.fromLTRB(
            20.0,
            isKeyboardOpen ? 4.0 : 12.0,
            20.0,
            mediaQuery.viewInsets.bottom + (isKeyboardOpen ? 60.0 : 32.0),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header (Collapses when keyboard is open to preserve vertical space)
                  if (!isKeyboardOpen) ...[
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.eco_rounded,
                        size: 38,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'brote',
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tu comunidad en tiempo real',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    // Compact header when keyboard is active
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.eco_rounded, color: colorScheme.primary, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'brote',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Error message banner
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colorScheme.error),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(Icons.error_outline_rounded, color: colorScheme.onErrorContainer, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: colorScheme.onErrorContainer,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.close_rounded, size: 18, color: colorScheme.onErrorContainer),
                            onPressed: () => setState(() => _errorMessage = null),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Form Container Card (Fluid height that naturally wraps contents)
                  Card(
                    color: colorScheme.surfaceContainerLow,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 22.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Tab Bar
                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              indicator: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              labelColor: colorScheme.onPrimary,
                              unselectedLabelColor: colorScheme.onSurfaceVariant,
                              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              dividerColor: Colors.transparent,
                              tabs: const [
                                Tab(text: 'Iniciar Sesión'),
                                Tab(text: 'Registrarse'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),

                          // Form content animated cross-fade
                          AnimatedCrossFade(
                            firstChild: _buildLoginForm(colorScheme),
                            secondChild: _buildRegisterForm(colorScheme),
                            crossFadeState: _activeTabIndex == 0
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                            duration: const Duration(milliseconds: 220),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(ColorScheme colorScheme) {
    // scrollPadding of 140 ensures the software keyboard never obscures the field
    const fieldScrollPadding = EdgeInsets.only(bottom: 140);

    return Form(
      key: _loginFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _loginUsernameController,
            scrollPadding: fieldScrollPadding,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Usuario o Correo',
              prefixIcon: Icon(Icons.person_outline_rounded, color: colorScheme.primary),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Ingresá tu usuario o correo';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _loginPasswordController,
            obscureText: _loginObscurePassword,
            scrollPadding: fieldScrollPadding,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleLogin(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: Icon(Icons.lock_outline_rounded, color: colorScheme.primary),
              suffixIcon: IconButton(
                icon: Icon(
                  _loginObscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  setState(() => _loginObscurePassword = !_loginObscurePassword);
                },
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Ingresá tu contraseña';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isLoading ? null : _handleLogin,
              child: _isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: colorScheme.onPrimary),
                    )
                  : const Text('Ingresar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm(ColorScheme colorScheme) {
    const fieldScrollPadding = EdgeInsets.only(bottom: 140);

    return Form(
      key: _registerFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _registerNameController,
            scrollPadding: fieldScrollPadding,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Nombre Completo',
              prefixIcon: Icon(Icons.badge_outlined, color: colorScheme.primary),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Ingresá tu nombre';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _registerUsernameController,
            scrollPadding: fieldScrollPadding,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Nombre de Usuario (@usuario)',
              prefixIcon: Icon(Icons.alternate_email_rounded, color: colorScheme.primary),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Elige un nombre de usuario';
              }
              if (val.trim().length < 3) {
                return 'Mínimo 3 caracteres';
              }
              if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(val.trim())) {
                return 'Solo letras, números y guión bajo';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _registerEmailController,
            keyboardType: TextInputType.emailAddress,
            scrollPadding: fieldScrollPadding,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Correo Electrónico (opcional)',
              prefixIcon: Icon(Icons.mail_outline_rounded, color: colorScheme.primary),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: (val) {
              if (val != null && val.trim().isNotEmpty && !val.contains('@')) {
                return 'Ingresá un correo válido';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _registerPasswordController,
            obscureText: _registerObscurePassword,
            scrollPadding: fieldScrollPadding,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: Icon(Icons.lock_outline_rounded, color: colorScheme.primary),
              suffixIcon: IconButton(
                icon: Icon(
                  _registerObscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  setState(() => _registerObscurePassword = !_registerObscurePassword);
                },
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Ingresá una contraseña';
              }
              if (val.length < 6) {
                return 'Mínimo 6 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _registerConfirmPasswordController,
            obscureText: _registerObscureConfirm,
            scrollPadding: fieldScrollPadding,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleRegister(),
            decoration: InputDecoration(
              labelText: 'Confirmar Contraseña',
              prefixIcon: Icon(Icons.lock_clock_outlined, color: colorScheme.primary),
              suffixIcon: IconButton(
                icon: Icon(
                  _registerObscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  setState(() => _registerObscureConfirm = !_registerObscureConfirm);
                },
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: (val) {
              if (val != _registerPasswordController.text) {
                return 'Las contraseñas no coinciden';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isLoading ? null : _handleRegister,
              child: _isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: colorScheme.onPrimary),
                    )
                  : const Text('Crear Cuenta', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
