import 'package:flutter/material.dart';
import '../models/report_item.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';

class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ReportItem> _pendingReports = [];
  List<ReportItem> _allReports = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadReports();
      }
    });
    _loadReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_tabController.index == 0) {
        final reports = await AuthService().getAdminReports(status: 'pending');
        if (mounted) {
          setState(() {
            _pendingReports = reports;
            _isLoading = false;
          });
        }
      } else {
        final reports = await AuthService().getAdminReports(status: 'all');
        if (mounted) {
          setState(() {
            _allReports = reports;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleAction(ReportItem report, String action, String actionLabel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$actionLabel reporte'),
        content: Text('¿Confirmás que querés aplicar la acción "$actionLabel" a este reporte?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: action == 'dismiss'
                  ? Theme.of(ctx).colorScheme.primary
                  : Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final ok = await AuthService().takeAdminReportAction(report.id, action);
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Acción "$actionLabel" aplicada correctamente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadReports();
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Error al procesar la acción de moderación.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 48),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700),
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
            child: AppBar(
              title: Row(
                children: [
                  Icon(Icons.shield_rounded, color: colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  const Text('Panel de Moderación'),
                ],
              ),
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: colorScheme.surface,
              actions: [
                IconButton(
                  tooltip: 'Refrescar',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loadReports,
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: colorScheme.primary,
                labelColor: colorScheme.primary,
                unselectedLabelColor: colorScheme.onSurfaceVariant,
                tabs: const [
                  Tab(text: 'Pendientes', icon: Icon(Icons.pending_actions_rounded, size: 20)),
                  Tab(text: 'Historial', icon: Icon(Icons.history_rounded, size: 20)),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
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
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                          const SizedBox(height: 12),
                          Text(_errorMessage!, style: textTheme.bodyMedium),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _loadReports, child: const Text('Reintentar')),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildReportList(_pendingReports, colorScheme, textTheme),
                        _buildReportList(_allReports, colorScheme, textTheme),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildReportList(List<ReportItem> reports, ColorScheme colorScheme, TextTheme textTheme) {
    if (reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 54, color: colorScheme.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 12),
              Text(
                'Sin reportes pendientes',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'La comunidad está segura y no hay contenido pendiente de revisión.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        itemCount: reports.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => _buildReportCard(reports[i], colorScheme, textTheme),
      ),
    );
  }

  Widget _buildReportCard(ReportItem report, ColorScheme colorScheme, TextTheme textTheme) {
    final isPending = report.status == 'pending';

    Color reasonColor;
    IconData reasonIcon;
    switch (report.reason.toLowerCase()) {
      case 'spam':
        reasonColor = Colors.blue;
        reasonIcon = Icons.campaign_rounded;
        break;
      case 'explicit':
        reasonColor = Colors.orange;
        reasonIcon = Icons.visibility_off_rounded;
        break;
      case 'harassment':
        reasonColor = Colors.purple;
        reasonIcon = Icons.sentiment_very_dissatisfied_rounded;
        break;
      case 'violence':
        reasonColor = Colors.red;
        reasonIcon = Icons.warning_amber_rounded;
        break;
      default:
        reasonColor = Colors.grey;
        reasonIcon = Icons.info_outline_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? reasonColor.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Reason badge & Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: reasonColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: reasonColor.withValues(alpha: 0.3), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(reasonIcon, size: 14, color: reasonColor),
                    const SizedBox(width: 5),
                    Text(
                      report.reasonLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: reasonColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPending
                      ? Colors.amber.withValues(alpha: 0.15)
                      : Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  report.status == 'pending'
                      ? 'Pendiente'
                      : (report.status == 'dismissed' ? 'Desestimado' : 'Resuelto'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isPending ? Colors.amber[800] : Colors.green[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Reporter info
          if (report.reporter != null)
            Text(
              'Reportado por @${report.reporter!.username}',
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),

          if (report.details != null && report.details!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Nota: "${report.details}"',
              style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Target Content Preview
          if (report.post != null) _buildPostPreview(report.post!, colorScheme, textTheme),
          if (report.comment != null) _buildCommentPreview(report.comment!, colorScheme, textTheme),
          if (report.user != null) _buildUserPreview(report.user!, colorScheme, textTheme),

          if (isPending) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Desestimar'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => _handleAction(report, 'dismiss', 'Desestimar'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_off_rounded, size: 16),
                  label: const Text('Ocultar'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.orangeAccent,
                  ),
                  onPressed: () => _handleAction(report, 'hide', 'Ocultar'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Eliminar'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: colorScheme.error,
                  ),
                  onPressed: () => _handleAction(report, 'delete', 'Eliminar'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.person_off_rounded, size: 16),
                  label: const Text('Suspender usuario'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.red[900],
                  ),
                  onPressed: () => _handleAction(report, 'suspend', 'Suspender'),
                ),
              ],
            ),
          ] else if (report.actionTaken != null) ...[
            const SizedBox(height: 8),
            Text(
              'Acción tomada: ${report.actionTaken}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPostPreview(ReportedPostPreview post, ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.feed_rounded, size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Publicación de @${post.authorUsername}',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (post.isHidden)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Oculto por auto-filtro (3+ reportes)',
                    style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          if (post.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(post.content, maxLines: 3, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium),
          ],
          if (post.imageUrl != null && post.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                post.imageUrl!,
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox(),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Total reportes: ${post.reportsCount}',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentPreview(ReportedCommentPreview comment, ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.comment_rounded, size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Comentario de @${comment.authorUsername}',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (comment.isHidden)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Oculto (3+ reportes)',
                    style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(comment.content, style: textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            'Total reportes: ${comment.reportsCount}',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildUserPreview(UserProfile user, ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
            child: user.avatarUrl == null
                ? Text(user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?')
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text('@${user.username}', style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (user.isSuspended)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Suspendido',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
