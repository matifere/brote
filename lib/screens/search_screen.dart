import 'dart:async';
import 'package:flutter/material.dart';
import '../models/rating.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart';
import 'rating_search_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchMode { people, movies, music }

class _SearchScreenState extends State<SearchScreen> {
  _SearchMode _mode = _SearchMode.people;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  List<UserProfile> _searchResults = [];
  List<UserProfile> _suggestedProfiles = [];
  bool _isSearching = false;
  bool _isLoadingSuggested = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadSuggestedProfiles();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestedProfiles() async {
    setState(() => _isLoadingSuggested = true);
    final list = await AuthService().getSuggestedProfiles();
    if (mounted) {
      setState(() {
        _suggestedProfiles = list;
        _isLoadingSuggested = false;
      });
    }
  }

  void _onSearchChanged() {
    final text = _searchController.text.trim();
    _debounceTimer?.cancel();

    if (text.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await AuthService().searchProfiles(text);
      // Ignore responses for queries the user already changed
      if (mounted && _searchController.text.trim() == text) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  void _openProfile(UserProfile profile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(profile: profile),
      ),
    );
  }

  Widget _buildProfileTile(UserProfile profile, ColorScheme colorScheme, TextTheme textTheme) {
    final initials = profile.displayName.isNotEmpty
        ? profile.displayName[0].toUpperCase()
        : profile.username[0].toUpperCase();

    final hasAvatar = profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty;
    final bioPreview = ProfileBio.parse(profile.bio).preview;

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
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: colorScheme.primaryContainer,
          backgroundImage: hasAvatar ? NetworkImage(profile.avatarUrl!) : null,
          onBackgroundImageError: hasAvatar ? (_, _) {} : null,
          child: !hasAvatar
              ? Text(
                  initials,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                )
              : null,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                profile.displayName,
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (profile.isPrivate) ...[
              const SizedBox(width: 4),
              Icon(Icons.lock_rounded, size: 14, color: colorScheme.onSurfaceVariant),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '@${profile.username}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (bioPreview.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                bioPreview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        trailing: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          onPressed: () => _openProfile(profile),
          child: const Text('Ver perfil', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        onTap: () => _openProfile(profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_SearchMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _SearchMode.people,
                      icon: Icon(Icons.people_outline_rounded),
                      label: Text('Personas'),
                    ),
                    ButtonSegment(
                      value: _SearchMode.movies,
                      icon: Icon(Icons.movie_outlined),
                      label: Text('Películas'),
                    ),
                    ButtonSegment(
                      value: _SearchMode.music,
                      icon: Icon(Icons.music_note_outlined),
                      label: Text('Música'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) => setState(() => _mode = selection.first),
                ),
              ),
            ),

            if (_mode != _SearchMode.people)
              Expanded(
                child: RatingSearchView(
                  key: ValueKey(_mode),
                  category: _mode == _SearchMode.movies ? RatingCategory.movie : RatingCategory.music,
                ),
              )
            else ...[
              // Search Input Field
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre o @usuario...',
                    prefixIcon: Icon(Icons.search_rounded, color: colorScheme.primary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                                _isSearching = false;
                              });
                            },
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

              // Main Content Area
              Expanded(
                child: hasQuery
                    ? _buildSearchResults(colorScheme, textTheme)
                    : _buildSuggestedSection(colorScheme, textTheme),
              ),
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
              'Buscando perfiles...',
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_search_rounded,
                size: 64,
                color: colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No se encontraron perfiles',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Probá buscando con otro nombre de usuario o nombre completo.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _searchResults.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(
              'Perfiles encontrados (${_searchResults.length})',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final profile = _searchResults[index - 1];
        return _buildProfileTile(profile, colorScheme, textTheme);
      },
    );
  }

  Widget _buildSuggestedSection(ColorScheme colorScheme, TextTheme textTheme) {
    if (_isLoadingSuggested) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    if (_suggestedProfiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_rounded,
                size: 64,
                color: colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Buscá perfiles en Brote',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Escribí un nombre o @usuario arriba para encontrar personas en la comunidad.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSuggestedProfiles,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _suggestedProfiles.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Row(
                children: [
                  Icon(Icons.people_outline_rounded, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Perfiles en la comunidad',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            );
          }
          final profile = _suggestedProfiles[index - 1];
          return _buildProfileTile(profile, colorScheme, textTheme);
        },
      ),
    );
  }
}
