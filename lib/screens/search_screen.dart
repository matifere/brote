import 'package:flutter/material.dart';

class RecommendedAccount {
  final String name;
  final String username;
  final String bio;
  bool isFollowing;

  RecommendedAccount({
    required this.name,
    required this.username,
    required this.bio,
    this.isFollowing = false,
  });
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedFilterIndex = 0;

  final List<String> _filters = ['Todo', 'Tendencias', 'Personas', 'Multimedia'];

  final List<Map<String, String>> _trends = [
    {'tag': '#Permacultura', 'category': 'Agricultura regenerativa', 'posts': '1.4k brotes'},
    {'tag': '#HuertaUrbana', 'category': 'Comunidad sustentable', 'posts': '2.8k brotes'},
    {'tag': '#SemillasNativas', 'category': 'Biodiversidad local', 'posts': '890 brotes'},
    {'tag': '#CompostajeCasero', 'category': 'Suelos vivos', 'posts': '650 brotes'},
    {'tag': '#PlantasNativas', 'category': 'Flora autóctona', 'posts': '1.2k brotes'},
  ];

  final List<RecommendedAccount> _accounts = [
    RecommendedAccount(
      name: 'Lucía Benítez',
      username: 'lucia_agro',
      bio: 'Ingeniera agrónoma | Cultivo sin pesticidas y bioconstrucción.',
      isFollowing: false,
    ),
    RecommendedAccount(
      name: 'Semillero Abierto',
      username: 'semillero_la',
      bio: 'Red comunitaria de rescate de semillas criollas en Latinoamérica.',
      isFollowing: true,
    ),
    RecommendedAccount(
      name: 'Diego Almada',
      username: 'diego_botanica',
      bio: 'Investigador de hongos y micorrizas en ecosistemas pampeanos.',
      isFollowing: false,
    ),
  ];

  final List<String> _mediaThumbnails = [
    'https://images.unsplash.com/photo-1530836369250-ef72a3f5cda8?auto=format&fit=crop&w=600&q=80',
    'https://images.unsplash.com/photo-1587334274328-64186a80aeee?auto=format&fit=crop&w=600&q=80',
    'https://images.unsplash.com/photo-1592417817098-8f3d69102553?auto=format&fit=crop&w=600&q=80',
    'https://images.unsplash.com/photo-1509316975850-ff9c5deb0cd9?auto=format&fit=crop&w=600&q=80',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Search Input
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar en Brote (temas, personas, etiquetas)...',
                prefixIcon: Icon(Icons.search_rounded, color: colorScheme.primary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          setState(() => _searchController.clear());
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Filter Chips
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final isSelected = _selectedFilterIndex == index;
                  return ChoiceChip(
                    label: Text(_filters[index]),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedFilterIndex = index),
                    selectedColor: colorScheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                    backgroundColor: colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Section: Tendencias para ti
            Text(
              'Tendencias para ti',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: _trends.map((t) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    title: Text(
                      t['tag']!,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    subtitle: Text(
                      '${t['category']} · ${t['posts']}',
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    trailing: Icon(Icons.trending_up_rounded, color: colorScheme.primaryContainer, size: 20),
                    onTap: () {},
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Section: Cuentas recomendadas
            Text(
              'Cuentas recomendadas',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: _accounts.map((acc) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        child: Text(
                          acc.name[0],
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        acc.name,
                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('@${acc.username}', style: textTheme.bodySmall),
                          const SizedBox(height: 2),
                          Text(
                            acc.bio,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      trailing: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              acc.isFollowing ? colorScheme.surfaceContainerHighest : colorScheme.primary,
                          foregroundColor:
                              acc.isFollowing ? colorScheme.onSurface : colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          acc.isFollowing ? 'Siguiendo' : 'Seguir',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          setState(() => acc.isFollowing = !acc.isFollowing);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Section: Multimedia popular
            Text(
              'Multimedia popular',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _mediaThumbnails.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.1,
              ),
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        _mediaThumbnails[index],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: colorScheme.surfaceContainerHigh,
                          child: Icon(Icons.image_outlined, color: colorScheme.outline),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.favorite_rounded, color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text('128', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
