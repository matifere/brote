import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  final AuthService _authService = AuthService();
  List<FollowRequest> _requests = [];
  bool _isLoading = true;
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    final reqs = await _authService.getFollowRequests();
    if (mounted) {
      setState(() {
        _requests = reqs;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleAccept(FollowRequest req) async {
    setState(() => _processingIds.add(req.id));
    final success = await _authService.acceptFollowRequest(req.id);
    if (!mounted) return;

    setState(() => _processingIds.remove(req.id));
    if (success) {
      setState(() {
        _requests.removeWhere((r) => r.id == req.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aceptaste la solicitud de @${req.username}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo aceptar la solicitud. Intentá de nuevo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleReject(FollowRequest req) async {
    setState(() => _processingIds.add(req.id));
    final success = await _authService.rejectFollowRequest(req.id);
    if (!mounted) return;

    setState(() => _processingIds.remove(req.id));
    if (success) {
      setState(() {
        _requests.removeWhere((r) => r.id == req.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Eliminaste la solicitud de @${req.username}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo rechazar la solicitud. Intentá de nuevo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openUserProfile(FollowRequest req) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          profile: UserProfile(
            id: req.id,
            username: req.username,
            displayName: req.displayName,
            avatarUrl: req.avatarUrl,
            bio: req.bio,
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (diff.inDays >= 1) {
      return 'hace ${diff.inDays} ${diff.inDays == 1 ? 'día' : 'días'}';
    } else if (diff.inHours >= 1) {
      return 'hace ${diff.inHours} ${diff.inHours == 1 ? 'hora' : 'horas'}';
    } else if (diff.inMinutes >= 1) {
      return 'hace ${diff.inMinutes} min';
    } else {
      return 'recién';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        title: const Text(
          'Solicitudes de seguimiento',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRequests,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _requests.isEmpty
                ? _buildEmptyState(colorScheme, textTheme)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _requests.length + 1,
                    separatorBuilder: (context, index) {
                      if (index == 0) return const SizedBox(height: 12);
                      return Divider(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                        height: 24,
                      );
                    },
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildHeaderNotice(colorScheme, textTheme);
                      }
                      final req = _requests[index - 1];
                      final isBusy = _processingIds.contains(req.id);
                      final timeString = _formatTimeAgo(req.createdAt);

                      return InkWell(
                        onTap: () => _openUserProfile(req),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Avatar
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: colorScheme.primaryFixedDim,
                                    backgroundImage: (req.avatarUrl != null && req.avatarUrl!.isNotEmpty)
                                        ? NetworkImage(req.avatarUrl!)
                                        : null,
                                    onBackgroundImageError: (req.avatarUrl != null && req.avatarUrl!.isNotEmpty)
                                        ? (exception, stackTrace) {}
                                        : null,
                                    child: (req.avatarUrl == null || req.avatarUrl!.isEmpty)
                                        ? Text(
                                            req.displayName.isNotEmpty
                                                ? req.displayName[0].toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 20,
                                              color: colorScheme.onPrimaryContainer,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 14),

                                  // Name & Username
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          req.displayName,
                                          style: textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '@${req.username}',
                                                style: textTheme.bodySmall?.copyWith(
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (timeString.isNotEmpty)
                                              Text(
                                                '· $timeString',
                                                style: textTheme.labelSmall?.copyWith(
                                                  color: colorScheme.outline,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              if (req.bio != null && req.bio!.trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Padding(
                                  padding: const EdgeInsets.only(left: 66),
                                  child: Text(
                                    req.bio!.trim(),
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],

                              const SizedBox(height: 12),
                              // Action Buttons
                              Padding(
                                padding: const EdgeInsets.only(left: 66),
                                child: isBusy
                                    ? const SizedBox(
                                        height: 36,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        ),
                                      )
                                    : Row(
                                        children: [
                                          FilledButton(
                                            onPressed: () => _handleAccept(req),
                                            style: FilledButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 8,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: const Text(
                                              'Confirmar',
                                              style: TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          OutlinedButton(
                                            onPressed: () => _handleReject(req),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                              side: BorderSide(
                                                color: colorScheme.outlineVariant,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: Text(
                                              'Eliminar',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildHeaderNotice(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_person_outlined,
            size: 22,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tenés tu cuenta privada',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Solo las personas que confirmes podrán ver tus fotos, publicaciones y perfil completo.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline_rounded,
                size: 64,
                color: colorScheme.primary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No tenés solicitudes pendientes',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando otras personas soliciten seguir tu cuenta privada, vas a poder aceptarlas o rechazarlas acá.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
