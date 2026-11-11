import 'dart:async';
import 'package:flutter/material.dart';
import '../models/post_content.dart';
import '../models/rating.dart';
import '../services/auth_service.dart';
import '../services/catalog_service.dart';
import '../widgets/rating_stars.dart';

/// Texts and icon for each rating category.
class _CategoryCopy {
  final String title;
  final String hint;
  final IconData icon;
  final String searching;
  final String emptyTitle;
  final String emptyBody;
  final String noResultsTitle;
  final String noResultsBody;
  final String source;

  const _CategoryCopy({
    required this.title,
    required this.hint,
    required this.icon,
    required this.searching,
    required this.emptyTitle,
    required this.emptyBody,
    required this.noResultsTitle,
    required this.noResultsBody,
    required this.source,
  });

  static _CategoryCopy of(RatingCategory category) => switch (category) {
        RatingCategory.movie => const _CategoryCopy(
            title: 'Películas',
            hint: 'Buscar una película...',
            icon: Icons.movie_outlined,
            searching: 'Buscando películas...',
            emptyTitle: 'Calificá tus películas',
            emptyBody:
                'Buscá una película, ponele de 1 a 5 estrellas y va a aparecer en la descripción de tu perfil. Si le sumás una opinión, se publica en el feed.',
            noResultsTitle: 'No encontramos películas',
            noResultsBody: 'Probá con el título original o con otra forma de escribirlo.',
            source: 'Datos de Wikidata',
          ),
        RatingCategory.music => const _CategoryCopy(
            title: 'Música',
            hint: 'Buscar un tema, álbum o artista...',
            icon: Icons.music_note_outlined,
            searching: 'Buscando música...',
            emptyTitle: 'Calificá tu música',
            emptyBody:
                'Buscá un tema o un álbum, ponele de 1 a 5 estrellas y va a aparecer en la descripción de tu perfil. Si le sumás una opinión, se publica en el feed.',
            noResultsTitle: 'No encontramos música',
            noResultsBody: 'Probá con el nombre del artista o con otra forma de escribirlo.',
            source: 'Datos de iTunes',
          ),
      };
}

/// Standalone screen to search and rate (opened from the profile).
class RatingSearchScreen extends StatelessWidget {
  final RatingCategory category;

  const RatingSearchScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(_CategoryCopy.of(category).title)),
      body: SafeArea(top: false, child: RatingSearchView(category: category, autofocus: true)),
    );
  }
}

/// Search with rating; ratings are saved in the profile bio and opinions are posted to the feed.
class RatingSearchView extends StatefulWidget {
  final RatingCategory category;
  final bool autofocus;

  const RatingSearchView({super.key, required this.category, this.autofocus = false});

  @override
  State<RatingSearchView> createState() => _RatingSearchViewState();
}

class _RatingSearchViewState extends State<RatingSearchView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  List<CatalogItem> _results = [];
  bool _isSearching = false;
  bool _hasError = false;
  bool _isSaving = false;
  ProfileBio _bio = const ProfileBio();
  MusicKind? _musicKind;

  static const List<(String, MusicKind?)> _musicFilters = [
    ('Todo', null),
    ('Temas', MusicKind.song),
    ('Álbumes', MusicKind.album),
  ];

  _CategoryCopy get _copy => _CategoryCopy.of(widget.category);

  @override
  void initState() {
    super.initState();
    _bio = ProfileBio.parse(AuthService().currentUser?.bio);
    AuthService().currentUserNotifier.addListener(_onProfileChanged);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    AuthService().currentUserNotifier.removeListener(_onProfileChanged);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) {
      setState(() => _bio = ProfileBio.parse(AuthService().currentUser?.bio));
    }
  }

  void _onSearchChanged() {
    final text = _searchController.text.trim();
    _debounceTimer?.cancel();

    if (text.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _hasError = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 400), _runSearch);
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    final musicKind = _musicKind;
    final results = await CatalogService().search(widget.category, query, musicKind: musicKind);
    // Ignore responses for queries or filters the user already changed
    if (!mounted || _searchController.text.trim() != query || _musicKind != musicKind) return;
    setState(() {
      _results = results ?? [];
      _hasError = results == null;
      _isSearching = false;
    });
  }

  void _setMusicKind(MusicKind? kind) {
    if (kind == _musicKind) return;
    setState(() => _musicKind = kind);
    if (_searchController.text.trim().isNotEmpty) {
      _debounceTimer?.cancel();
      setState(() => _isSearching = true);
      _runSearch();
    }
  }

  Future<void> _openRatingSheet(RatedItem item, {String? subtitle, String? imageUrl}) async {
    final current = _bio.find(item);
    final result = await showModalBottomSheet<_RatingResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _RatingSheet(
        item: item,
        subtitle: subtitle ?? item.detail,
        imageUrl: imageUrl,
        initialStars: current?.stars,
      ),
    );
    if (result == null || !mounted) return;
    await _save(item, result);
  }

  Future<void> _save(RatedItem item, _RatingResult result) async {
    setState(() => _isSaving = true);

    if (result.stars == 0) {
      final response = await AuthService().updateBioRatings((bio) => bio.without(item));
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showMessage(
        response.success ? 'Quitaste "${item.title}" de tu perfil' : response.error ?? 'No se pudo quitar la calificación',
        isError: !response.success,
      );
      return;
    }

    final rating = item.withStars(result.stars);
    final bioResponse = await AuthService().updateBioRatings((bio) => bio.withRating(rating));

    bool? posted;
    if (result.opinion.isNotEmpty) {
      final post = await AuthService().createPost(
        content: PostContent(review: rating, body: result.opinion).compose(),
      );
      posted = post != null;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    final starsLabel = '${rating.stars} ${rating.stars == 1 ? "estrella" : "estrellas"}';
    if (bioResponse.success) {
      _showMessage(
        switch (posted) {
          null => 'Calificaste "${rating.title}" con $starsLabel',
          true => 'Calificaste "${rating.title}" y publicaste tu opinión en el feed',
          false => 'Calificaste "${rating.title}", pero no se pudo publicar tu opinión',
        },
        isError: posted == false,
      );
    } else {
      final error = bioResponse.error ?? 'No se pudo guardar la calificación';
      _showMessage(
        posted == true ? 'Publicaste tu opinión, pero no se guardó en tu descripción. $error' : error,
        isError: true,
      );
    }
  }

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: _copy.hint,
              prefixIcon: Icon(_copy.icon, color: colorScheme.primary),
              suffixIcon: hasQuery
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Limpiar búsqueda',
                      onPressed: _searchController.clear,
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (widget.category == RatingCategory.music)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (label, kind) in _musicFilters)
                  ChoiceChip(
                    label: Text(label),
                    selected: _musicKind == kind,
                    showCheckmark: false,
                    onSelected: (_) => _setMusicKind(kind),
                  ),
              ],
            ),
          ),
        if (_isSaving) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: hasQuery
              ? _buildSearchResults(colorScheme, textTheme)
              : _buildMyRatings(colorScheme, textTheme),
        ),
      ],
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String body,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    Widget? action,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme colorScheme, TextTheme textTheme) {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 16),
            Text(
              _copy.searching,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return _buildMessage(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudo buscar',
        body: 'Revisá tu conexión e intentá de nuevo.',
        colorScheme: colorScheme,
        textTheme: textTheme,
        action: OutlinedButton.icon(
          onPressed: () {
            setState(() => _isSearching = true);
            _runSearch();
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Reintentar'),
        ),
      );
    }

    if (_results.isEmpty) {
      return _buildMessage(
        icon: Icons.search_off_rounded,
        title: _copy.noResultsTitle,
        body: _copy.noResultsBody,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == _results.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _copy.source,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
          );
        }
        final result = _results[index];
        return _buildTile(
          item: result.toRating(),
          subtitle: result.subtitle,
          imageUrl: result.imageUrl,
          colorScheme: colorScheme,
          textTheme: textTheme,
        );
      },
    );
  }

  Widget _buildMyRatings(ColorScheme colorScheme, TextTheme textTheme) {
    final ratings = _bio.of(widget.category);
    if (ratings.isEmpty) {
      return _buildMessage(
        icon: _copy.icon,
        title: _copy.emptyTitle,
        body: _copy.emptyBody,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    }

    final charsLeft = ProfileBio.maxLength - (_bio.compose()?.length ?? 0);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: ratings.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(
              children: [
                Icon(_copy.icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tus calificaciones (${ratings.length})',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  '$charsLeft caracteres libres',
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }
        return _buildTile(
          item: ratings[index - 1],
          colorScheme: colorScheme,
          textTheme: textTheme,
        );
      },
    );
  }

  Widget _buildTile({
    required RatedItem item,
    String? subtitle,
    String? imageUrl,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    final rating = _bio.find(item);
    final details = subtitle ?? item.detail;
    final iconBox = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(_copy.icon, color: colorScheme.primary),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => iconBox,
                ),
              )
            : iconBox,
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: details != null
            ? Text(
                details,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              )
            : null,
        trailing: rating != null
            ? RatingStars(stars: rating.stars)
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: _isSaving ? null : () => _openRatingSheet(item, subtitle: subtitle, imageUrl: imageUrl),
                child: const Text('Calificar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
        onTap: _isSaving ? null : () => _openRatingSheet(item, subtitle: subtitle, imageUrl: imageUrl),
      ),
    );
  }
}

/// What the rating sheet returns: 1-5 stars (0 removes the rating) and an optional opinion.
class _RatingResult {
  final int stars;
  final String opinion;

  const _RatingResult(this.stars, [this.opinion = '']);
}

class _RatingSheet extends StatefulWidget {
  final RatedItem item;
  final String? subtitle;
  final String? imageUrl;
  final int? initialStars;

  const _RatingSheet({
    required this.item,
    required this.subtitle,
    required this.imageUrl,
    required this.initialStars,
  });

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  static const List<String> _labels = ['Mala', 'Regular', 'Buena', 'Muy buena', 'Obra maestra'];

  final TextEditingController _opinionController = TextEditingController();
  late int _stars = widget.initialStars ?? 0;

  @override
  void dispose() {
    _opinionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasOpinion = _opinionController.text.trim().isNotEmpty;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  widget.imageUrl!,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              widget.item.title,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final value = i + 1;
                return IconButton(
                  tooltip: '$value ${value == 1 ? "estrella" : "estrellas"}',
                  iconSize: 40,
                  onPressed: () => setState(() => _stars = value),
                  icon: Icon(
                    value <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: colorScheme.tertiary,
                  ),
                );
              }),
            ),
            SizedBox(
              height: 24,
              child: Text(
                _stars > 0 ? _labels[_stars - 1] : 'Tocá las estrellas para calificar',
                style: textTheme.bodyMedium?.copyWith(
                  color: _stars > 0 ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                  fontWeight: _stars > 0 ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _opinionController,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Tu opinión (opcional)',
                hintText: '¿Qué te pareció?',
                helperText: 'Si escribís una opinión, se publica en el feed.',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _stars > 0
                    ? () => Navigator.of(context).pop(_RatingResult(_stars, _opinionController.text.trim()))
                    : null,
                child: Text(hasOpinion ? 'Guardar y publicar' : 'Guardar en mi perfil'),
              ),
            ),
            if (widget.initialStars != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(const _RatingResult(0)),
                style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                child: const Text('Quitar calificación'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
