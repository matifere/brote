import 'dart:async';
import 'package:flutter/material.dart';
import '../models/rating.dart';
import '../services/catalog_service.dart';

/// Opens a full-screen search to choose the movie, song or album to review.
/// Returns null if the user backs out.
Future<CatalogItem?> showReviewItemPicker(
  BuildContext context, {
  RatingCategory initialCategory = RatingCategory.movie,
}) {
  return Navigator.of(context).push<CatalogItem>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ReviewItemPickerScreen(initialCategory: initialCategory),
    ),
  );
}

class ReviewItemPickerScreen extends StatefulWidget {
  final RatingCategory initialCategory;

  const ReviewItemPickerScreen({super.key, this.initialCategory = RatingCategory.movie});

  @override
  State<ReviewItemPickerScreen> createState() => _ReviewItemPickerScreenState();
}

class _ReviewItemPickerScreenState extends State<ReviewItemPickerScreen> {
  static const List<(String, MusicKind?)> _musicFilters = [
    ('Todo', null),
    ('Temas', MusicKind.song),
    ('Álbumes', MusicKind.album),
  ];

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  late RatingCategory _category = widget.initialCategory;
  MusicKind? _musicKind;
  List<CatalogItem> _results = [];
  bool _isSearching = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim();

  void _onQueryChanged() {
    _debounce?.cancel();
    if (_query.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _hasError = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 400), _runSearch);
  }

  Future<void> _runSearch() async {
    final query = _query;
    if (query.isEmpty) return;
    final category = _category;
    final musicKind = _musicKind;

    setState(() => _isSearching = true);
    final results = await CatalogService().search(category, query, musicKind: musicKind);

    // Ignore answers for a query, category or filter the user already changed.
    if (!mounted || _query != query || _category != category || _musicKind != musicKind) return;
    setState(() {
      _results = results ?? [];
      _hasError = results == null;
      _isSearching = false;
    });
  }

  void _setCategory(RatingCategory category) {
    if (category == _category) return;
    setState(() {
      _category = category;
      _results = [];
      _hasError = false;
    });
    if (_query.isNotEmpty) _runSearch();
  }

  void _setMusicKind(MusicKind? kind) {
    if (kind == _musicKind) return;
    setState(() => _musicKind = kind);
    if (_query.isNotEmpty) _runSearch();
  }

  /// Lets the user review something the catalog doesn't know about.
  void _useTypedTitle() {
    Navigator.of(context).pop(CatalogItem(category: _category, title: _query));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMovie = _category == RatingCategory.movie;
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '¿Qué querés reseñar?',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<RatingCategory>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: RatingCategory.movie,
                          icon: Icon(Icons.movie_outlined, size: 18),
                          label: Text('Película'),
                        ),
                        ButtonSegment(
                          value: RatingCategory.music,
                          icon: Icon(Icons.music_note_outlined, size: 18),
                          label: Text('Música'),
                        ),
                      ],
                      selected: {_category},
                      onSelectionChanged: (selection) => _setCategory(selection.first),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: isMovie ? 'Buscar una película o serie...' : 'Buscar un tema, álbum o artista...',
                      prefixIcon: Icon(
                        isMovie ? Icons.movie_outlined : Icons.music_note_outlined,
                        color: colorScheme.primary,
                      ),
                      suffixIcon: _query.isNotEmpty
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
                if (!isMovie)
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
                Expanded(child: _buildBody(colorScheme)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final isMovie = _category == RatingCategory.movie;

    if (_query.isEmpty) {
      return _buildMessage(
        icon: Icons.rate_review_outlined,
        title: isMovie ? 'Buscá la película' : 'Buscá el tema o el álbum',
        body: 'Elegila de la lista, ponele estrellas y escribí tu opinión.',
      );
    }
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) {
      return _buildMessage(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudo buscar',
        body: 'Revisá tu conexión e intentá de nuevo.',
        action: Column(
          children: [
            FilledButton.tonal(onPressed: _runSearch, child: const Text('Reintentar')),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text('Reseñar "$_query"'),
              onPressed: _useTypedTitle,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final item in _results) _buildResultTile(item, colorScheme, textTheme),
        if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              isMovie ? 'No encontramos esa película.' : 'No encontramos esa música.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ListTile(
          leading: Icon(Icons.edit_outlined, color: colorScheme.primary),
          title: Text('Reseñar "$_query"'),
          subtitle: const Text('Usar el título tal como lo escribiste'),
          onTap: _useTypedTitle,
        ),
      ],
    );
  }

  Widget _buildResultTile(CatalogItem item, ColorScheme colorScheme, TextTheme textTheme) {
    final subtitle = item.subtitle ?? (item.category == RatingCategory.movie ? item.year?.toString() : item.artist);
    return ListTile(
      leading: ReviewCover(item: item, size: 48),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle != null
          ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
      onTap: () => Navigator.of(context).pop(item),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          children: [
            Icon(icon, size: 56, color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }
}

/// Poster or cover art of a catalog item, with an icon when there is none.
class ReviewCover extends StatelessWidget {
  final CatalogItem item;
  final double size;

  const ReviewCover({super.key, required this.item, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        item.category == RatingCategory.movie ? Icons.movie_outlined : Icons.music_note_outlined,
        color: colorScheme.primary,
      ),
    );

    final imageUrl = item.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// The review being written in the composer: what is reviewed, tappable
/// stars, and actions to change or remove it.
class ReviewDraftCard extends StatelessWidget {
  static const List<String> starLabels = ['Mala', 'Regular', 'Buena', 'Muy buena', 'Excelente'];

  final CatalogItem item;
  final int stars;
  final ValueChanged<int> onStarsChanged;
  final VoidCallback onChange;
  final VoidCallback onRemove;

  const ReviewDraftCard({
    super.key,
    required this.item,
    required this.stars,
    required this.onStarsChanged,
    required this.onChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMovie = item.category == RatingCategory.movie;
    final detail = item.subtitle ?? (isMovie ? item.year?.toString() : item.artist);
    final starColor = colorScheme.tertiary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReviewCover(item: item, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMovie ? 'Reseña de película' : 'Reseña de música',
                      style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (detail != null)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cambiar',
                icon: const Icon(Icons.swap_horiz_rounded),
                onPressed: onChange,
              ),
              IconButton(
                tooltip: 'Quitar reseña',
                icon: const Icon(Icons.close_rounded),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var value = 1; value <= 5; value++)
                IconButton(
                  tooltip: '$value ${value == 1 ? "estrella" : "estrellas"}',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onStarsChanged(value),
                  icon: Icon(
                    value <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 30,
                    color: value <= stars ? starColor : starColor.withValues(alpha: 0.45),
                  ),
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  stars > 0 ? starLabels[stars - 1] : 'Tocá las estrellas',
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: stars > 0 ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                    fontWeight: stars > 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
