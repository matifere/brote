import 'package:flutter/material.dart';
import '../services/chat_crypto.dart';

enum ChatPasswordMode { create, unlock, reset }

/// What the chat password dialog returns: a password, or the user's choice to
/// create new keys because they forgot it.
class ChatPasswordResult {
  final String? password;
  final bool forgotPassword;

  const ChatPasswordResult.password(String this.password) : forgotPassword = false;
  const ChatPasswordResult.forgot()
      : password = null,
        forgotPassword = true;
}

Future<ChatPasswordResult?> showChatPasswordDialog(BuildContext context, {required ChatPasswordMode mode}) {
  return showDialog<ChatPasswordResult>(
    context: context,
    builder: (_) => _ChatPasswordDialog(mode: mode),
  );
}

class _ChatPasswordDialog extends StatefulWidget {
  final ChatPasswordMode mode;

  const _ChatPasswordDialog({required this.mode});

  @override
  State<_ChatPasswordDialog> createState() => _ChatPasswordDialogState();
}

class _ChatPasswordDialogState extends State<_ChatPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  bool get _isUnlock => widget.mode == ChatPasswordMode.unlock;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(ChatPasswordResult.password(_passwordController.text));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final title = switch (widget.mode) {
      ChatPasswordMode.create => 'Activar cifrado',
      ChatPasswordMode.unlock => 'Desbloquear chats cifrados',
      ChatPasswordMode.reset => 'Crear claves nuevas',
    };
    final explanation = switch (widget.mode) {
      ChatPasswordMode.create =>
        'Elegí una contraseña de chat. La vas a necesitar para leer tus mensajes en otros dispositivos. '
            'No es la contraseña de tu cuenta y, si la olvidás, no se puede recuperar.',
      ChatPasswordMode.unlock => 'Ingresá tu contraseña de chat para leer y enviar mensajes cifrados en este dispositivo.',
      ChatPasswordMode.reset =>
        'Vas a tener claves nuevas: los mensajes cifrados que ya tenías no se van a poder leer más. '
            'Elegí una contraseña de chat nueva.',
    };

    return AlertDialog(
      icon: Icon(
        widget.mode == ChatPasswordMode.reset ? Icons.warning_amber_rounded : Icons.lock_rounded,
        color: widget.mode == ChatPasswordMode.reset ? colorScheme.error : colorScheme.primary,
      ),
      title: Text(title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(explanation, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscure,
                autofocus: true,
                textInputAction: _isUnlock ? TextInputAction.done : TextInputAction.next,
                onFieldSubmitted: _isUnlock ? (_) => _submit() : null,
                decoration: InputDecoration(
                  labelText: 'Contraseña de chat',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Ingresá la contraseña.';
                  if (!_isUnlock && value.length < ChatCrypto.minPasswordLength) {
                    return 'Usá al menos ${ChatCrypto.minPasswordLength} caracteres.';
                  }
                  return null;
                },
              ),
              if (!_isUnlock) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Repetí la contraseña',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value != _passwordController.text ? 'Las contraseñas no coinciden.' : null,
                ),
              ],
              if (_isUnlock) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(const ChatPasswordResult.forgot()),
                  child: const Text('¿La olvidaste?'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          style: widget.mode == ChatPasswordMode.reset
              ? FilledButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError)
              : null,
          child: Text(switch (widget.mode) {
            ChatPasswordMode.create => 'Activar',
            ChatPasswordMode.unlock => 'Desbloquear',
            ChatPasswordMode.reset => 'Crear claves nuevas',
          }),
        ),
      ],
    );
  }
}
