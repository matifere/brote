import 'package:flutter/material.dart';
import '../services/auth_service.dart';

Future<void> showReportContentDialog(
  BuildContext context, {
  String? postId,
  String? commentId,
  String? userId,
  String targetTitle = 'este contenido',
}) async {
  String selectedReason = 'spam';
  final detailsController = TextEditingController();

  final reasons = [
    ('spam', 'Spam o contenido comercial no deseado', Icons.campaign_outlined),
    ('explicit', 'Contenido explícito (+18) sin marcar', Icons.visibility_off_outlined),
    ('harassment', 'Acoso, insultos o mensajes de odio', Icons.sentiment_very_dissatisfied_outlined),
    ('violence', 'Incitación a la violencia o daño físico', Icons.warning_amber_rounded),
    ('other', 'Otro motivo', Icons.more_horiz_rounded),
  ];

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final colorScheme = Theme.of(ctx).colorScheme;
          final textTheme = Theme.of(ctx).textTheme;

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.flag_rounded, color: colorScheme.error, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reportar $targetTitle',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seleccioná el motivo del reporte:',
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  ...reasons.map((r) {
                    final isSelected = selectedReason == r.$1;
                    return InkWell(
                      onTap: () => setState(() => selectedReason = r.$1),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 18,
                              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Icon(r.$3, size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                r.$2,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailsController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Detalles adicionales (opcional)',
                      hintText: 'Añadí información relevante para los moderadores',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Enviar reporte'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == true && context.mounted) {
    final messenger = ScaffoldMessenger.of(context);
    final res = await AuthService().reportContent(
      postId: postId,
      commentId: commentId,
      userId: userId,
      reason: selectedReason,
      details: detailsController.text.trim().isNotEmpty ? detailsController.text.trim() : null,
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(res.success ? res.message : (res.error ?? 'Error al enviar reporte')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  detailsController.dispose();
}
