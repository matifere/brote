import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/models/post_content.dart';
import 'package:brote/models/post_item.dart';
import 'package:brote/models/rating.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/create_post_screen.dart';
import 'package:brote/screens/edit_profile_screen.dart';
import 'package:brote/screens/profile_screen.dart';
import 'package:brote/screens/search_screen.dart';
import 'package:brote/services/catalog_service.dart';
import 'package:brote/widgets/post_card.dart';

RatedItem movie(String title, {int? year, int stars = 1}) =>
    RatedItem.create(category: RatingCategory.movie, title: title, year: year, stars: stars);

RatedItem song(String title, {String? artist, int stars = 1}) =>
    RatedItem.create(category: RatingCategory.music, title: title, artist: artist, stars: stars);

void main() {
  group('ProfileBio', () {
    test('parses empty and plain bios', () {
      expect(ProfileBio.parse(null).text, '');
      expect(ProfileBio.parse(null).ratings, isEmpty);
      expect(ProfileBio.parse(null).compose(), isNull);

      final plain = ProfileBio.parse('Me gusta el cine.');
      expect(plain.text, 'Me gusta el cine.');
      expect(plain.ratings, isEmpty);
      expect(plain.compose(), 'Me gusta el cine.');
    });

    test('round-trips free text and movie ratings', () {
      final bio = const ProfileBio(text: 'Cinéfila.\nPorteña.')
          .withRating(movie('Dune', year: 2021, stars: 4))
          .withRating(movie('Relatos salvajes', year: 2014, stars: 5));

      final stored = bio.compose()!;
      expect(stored, 'Cinéfila.\nPorteña.\n\n🎬 Relatos salvajes (2014) ★★★★★ · Dune (2021) ★★★★☆');

      final parsed = ProfileBio.parse(stored);
      expect(parsed.text, 'Cinéfila.\nPorteña.');
      expect(parsed.of(RatingCategory.movie).map((m) => m.title), ['Relatos salvajes', 'Dune']);
      expect(parsed.of(RatingCategory.movie).map((m) => m.year), [2014, 2021]);
      expect(parsed.of(RatingCategory.movie).map((m) => m.stars), [5, 4]);
    });

    test('keeps movies and music on separate lines', () {
      final bio = const ProfileBio(text: 'Hola')
          .withRating(song('Abbey Road', artist: 'The Beatles', stars: 5))
          .withRating(movie('Dune', year: 2021, stars: 4))
          .withRating(song('Bohemian Rhapsody', artist: 'Queen', stars: 4));

      final stored = bio.compose()!;
      expect(
        stored,
        'Hola\n\n'
        '🎬 Dune (2021) ★★★★☆\n'
        '🎵 Bohemian Rhapsody — Queen ★★★★☆ · Abbey Road — The Beatles ★★★★★',
      );

      final parsed = ProfileBio.parse(stored);
      expect(parsed.text, 'Hola');
      expect(parsed.of(RatingCategory.movie).single.title, 'Dune');
      expect(parsed.of(RatingCategory.music).map((m) => m.artist), ['Queen', 'The Beatles']);
      expect(parsed.ratedTopics, 'películas y música');
      expect(ProfileBio(ratings: parsed.ratings).preview, '3 calificaciones de películas y música');
    });

    test('stores ratings alone when there is no free text', () {
      final bio = const ProfileBio().withRating(movie('Matrix', stars: 3));
      expect(bio.compose(), '🎬 Matrix ★★★☆☆');

      final parsed = ProfileBio.parse(bio.compose());
      expect(parsed.text, '');
      expect(parsed.ratings.single.year, isNull);
      expect(parsed.preview, '1 calificación de películas');
    });

    test('re-rating moves the item first and removing drops it', () {
      var bio = const ProfileBio()
          .withRating(movie('Dune', year: 2021, stars: 4))
          .withRating(movie('Dune', year: 1984, stars: 2))
          .withRating(movie('Dune', year: 2021, stars: 5));

      expect(bio.ratings.length, 2);
      expect(bio.ratings.first.year, 2021);
      expect(bio.ratings.first.stars, 5);
      expect(bio.find(movie('dune', year: 1984))?.stars, 2);

      bio = bio.without(movie('Dune', year: 2021));
      expect(bio.ratings.single.year, 1984);
    });

    test('keeps titles with years or reserved characters intact', () {
      final bio = const ProfileBio()
          .withRating(movie('Blade Runner 2049', year: 2017, stars: 5))
          .withRating(movie('Amor · Odio', year: 2001, stars: 2))
          .withRating(song('Tema — Remix', artist: 'Dúo · Banda', stars: 3));

      final parsed = ProfileBio.parse(bio.compose());
      expect(parsed.of(RatingCategory.movie).map((m) => m.title), ['Amor - Odio', 'Blade Runner 2049']);
      expect(parsed.of(RatingCategory.movie).last.year, 2017);
      expect(parsed.of(RatingCategory.music).single.title, 'Tema - Remix');
      expect(parsed.of(RatingCategory.music).single.artist, 'Dúo - Banda');
    });

    test('shortens long titles and still matches them', () {
      const longTitle = 'Dr. Strangelove or: How I Learned to Stop Worrying and Love the Bomb';
      final rating = movie(longTitle, year: 1964, stars: 5);
      expect(rating.title.length, RatedItem.maxTitleLength);
      expect(rating.title.endsWith('…'), isTrue);

      final parsed = ProfileBio.parse(const ProfileBio().withRating(rating).compose());
      expect(parsed.find(movie(longTitle, year: 1964))?.stars, 5);
    });

    test('treats free-form emoji lines as regular text', () {
      final parsed = ProfileBio.parse('Hola\n🎬 me encanta el cine\n🎵 y la música');
      expect(parsed.ratings, isEmpty);
      expect(parsed.text, 'Hola\n🎬 me encanta el cine\n🎵 y la música');
    });

    test('reports when the bio exceeds the server limit', () {
      var bio = ProfileBio(text: 'a' * 250);
      expect(bio.fits, isTrue);

      bio = bio.withRating(movie('El secreto de sus ojos', year: 2009, stars: 5));
      expect(bio.fits, isTrue);

      bio = bio.withRating(song('Nueve reinas', artist: 'Banda', stars: 4));
      expect(bio.fits, isFalse);
      expect(bio.maxTextLength, ProfileBio.maxLength - bio.ratingsBlock.length - 2);
    });
  });

  group('PostContent', () {
    test('leaves regular posts untouched', () {
      final parsed = PostContent.parse('Hola **mundo**\n\nSegundo párrafo');
      expect(parsed.body, 'Hola **mundo**\n\nSegundo párrafo');
      expect(parsed.review, isNull);
      expect(parsed.isEphemeral, isFalse);
    });

    test('round-trips a 24-hour review', () {
      final content = PostContent(
        review: song('Abbey Road', artist: 'The Beatles', stars: 5),
        body: 'Un discazo.',
        isEphemeral: true,
      ).compose();
      expect(content, '🎵 Abbey Road — The Beatles ★★★★★\n\nUn discazo.\n\n⏳ 24 h');

      final parsed = PostContent.parse(content);
      expect(parsed.review?.title, 'Abbey Road');
      expect(parsed.review?.artist, 'The Beatles');
      expect(parsed.body, 'Un discazo.');
      expect(parsed.isEphemeral, isTrue);
    });

    test('marks image-only posts as 24-hour posts', () {
      final content = const PostContent(isEphemeral: true).compose();
      expect(content, PostContent.ephemeralTag);
      final parsed = PostContent.parse(content);
      expect(parsed.isEphemeral, isTrue);
      expect(parsed.body, '');
    });

    test('expires 24-hour posts after a day', () {
      PostItem post(String content, Duration age) => PostItem(
            id: 'p',
            authorId: 'a',
            authorName: 'Ana',
            authorUsername: 'ana',
            content: content,
            createdAt: DateTime.now().subtract(age),
          );

      expect(post('Hola\n\n⏳ 24 h', const Duration(hours: 25)).isExpired, isTrue);
      expect(post('Hola\n\n⏳ 24 h', const Duration(hours: 1)).isExpired, isFalse);
      expect(post('Hola\n\n⏳ 24 h', const Duration(hours: 1)).timeLeft, startsWith('quedan'));
      expect(post('Hola', const Duration(days: 30)).isExpired, isFalse);
      expect(post('Hola', const Duration(days: 30)).timeLeft, isNull);
    });
  });

  test('cleans store edition tags from music titles', () {
    expect(CatalogService.cleanMusicTitle('Abbey Road (Remastered)'), 'Abbey Road');
    expect(
      CatalogService.cleanMusicTitle('Abbey Road (Super Deluxe Edition) [2019 Remix & Remaster]'),
      'Abbey Road',
    );
    expect(CatalogService.cleanMusicTitle('un x100to - Single'), 'un x100to');
    expect(CatalogService.cleanMusicTitle('Bohemian Rhapsody - Remastered 2011'), 'Bohemian Rhapsody');
    expect(CatalogService.cleanMusicTitle('Soltera (Remix)'), 'Soltera (Remix)');
    expect(CatalogService.cleanMusicTitle('Come Together (2019 Mix)'), 'Come Together (2019 Mix)');
  });

  group('Ratings UI', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    const profileWithRatings = UserProfile(
      id: 'test-uuid-ratings',
      username: 'cinefila',
      displayName: 'Cinéfila',
      bio: 'Fan del cine argentino.\n\n'
          '🎬 Relatos salvajes (2014) ★★★★★ · Dune (2021) ★★★★☆\n'
          '🎵 Abbey Road — The Beatles ★★★★★',
    );

    void useView(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    testWidgets('ProfileScreen shows movies and music apart from the bio text', (WidgetTester tester) async {
      useView(tester, const Size(1080, 2400));

      await tester.pumpWidget(const MaterialApp(home: ProfileScreen(profile: profileWithRatings)));
      await tester.pumpAndSettle();

      expect(find.text('Fan del cine argentino.'), findsOneWidget);
      expect(find.text('Películas'), findsOneWidget);
      expect(find.text('Música'), findsOneWidget);
      expect(find.textContaining('Relatos salvajes', findRichText: true), findsOneWidget);
      expect(find.textContaining('Abbey Road · The Beatles', findRichText: true), findsOneWidget);
      expect(find.textContaining('🎬', findRichText: true), findsNothing);
      expect(find.textContaining('🎵', findRichText: true), findsNothing);
      expect(find.text('Calificar'), findsNWidgets(2));
      expect(find.text('Expandir'), findsOneWidget);
    });

    testWidgets('ProfileScreen expands and compresses ratings row when tapping the toggle button', (WidgetTester tester) async {
      useView(tester, const Size(1080, 2400));

      await tester.pumpWidget(const MaterialApp(home: ProfileScreen(profile: profileWithRatings)));
      await tester.pumpAndSettle();

      // Initially collapsed: shows single horizontal row with "Expandir" and "Ver todas"
      expect(find.text('Expandir'), findsOneWidget);
      expect(find.text('Ver todas'), findsOneWidget);

      // Tap "Expandir"
      await tester.tap(find.text('Expandir'));
      await tester.pumpAndSettle();

      // Now expanded: shows "Comprimir" in header and chip
      expect(find.text('Comprimir'), findsNWidgets(2));
      expect(find.text('Expandir'), findsNothing);

      // Tap "Comprimir" in the header
      await tester.tap(find.widgetWithText(TextButton, 'Comprimir'));
      await tester.pumpAndSettle();

      // Compressed back to horizontal row
      expect(find.text('Expandir'), findsOneWidget);
      expect(find.text('Ver todas'), findsOneWidget);
    });

    testWidgets('EditProfileScreen edits only the free text of the bio', (WidgetTester tester) async {
      useView(tester, const Size(1080, 2400));

      await tester.pumpWidget(const MaterialApp(home: EditProfileScreen(profile: profileWithRatings)));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Fan del cine argentino.'), findsOneWidget);
      expect(find.textContaining('🎬'), findsNothing);
      expect(
        find.text('Tus calificaciones de películas y música se muestran debajo de la descripción.'),
        findsOneWidget,
      );
    });

    testWidgets('SearchScreen switches between people, movies and music on a phone', (WidgetTester tester) async {
      useView(tester, const Size(360, 780));

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Buscar por nombre o @usuario...'), findsOneWidget);

      await tester.tap(find.text('Películas'));
      await tester.pumpAndSettle();
      expect(find.text('Buscar una película o serie...'), findsOneWidget);
      expect(find.text('Calificá tus películas y series'), findsOneWidget);

      expect(find.text('Álbumes'), findsNothing);

      await tester.tap(find.text('Música'));
      await tester.pumpAndSettle();
      expect(find.text('Buscar un tema, álbum o artista...'), findsOneWidget);
      expect(find.text('Calificá tu música'), findsOneWidget);
      expect(find.text('Buscar por nombre o @usuario...'), findsNothing);

      ChoiceChip chip(String label) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
      expect(chip('Todo').selected, isTrue);
      await tester.tap(find.text('Álbumes'));
      await tester.pumpAndSettle();
      expect(chip('Álbumes').selected, isTrue);
      expect(chip('Todo').selected, isFalse);
      expect(chip('Temas').selected, isFalse);
    });

    testWidgets('PostCard shows reviews and the time left of 24-hour posts', (WidgetTester tester) async {
      useView(tester, const Size(360, 780));

      final post = PostItem(
        id: 'review-1',
        authorId: 'author-1',
        authorName: 'Ana',
        authorUsername: 'ana',
        content: '🎵 Abbey Road — The Beatles ★★★★☆\n\nUn discazo.\n\n⏳ 24 h',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PostCard(post: post))));
      await tester.pumpAndSettle();

      expect(find.text('Reseña de música'), findsOneWidget);
      expect(find.text('Abbey Road'), findsOneWidget);
      expect(find.text('The Beatles'), findsOneWidget);
      expect(find.textContaining('Un discazo.', findRichText: true), findsOneWidget);
      expect(find.textContaining('quedan', findRichText: true), findsOneWidget);
      expect(find.textContaining('⏳', findRichText: true), findsNothing);
      expect(find.textContaining('★', findRichText: true), findsNothing);
    });

    testWidgets('PostCard renders movie review and loads poster', (WidgetTester tester) async {
      useView(tester, const Size(360, 780));

      final post = PostItem(
        id: 'review-movie-1',
        authorId: 'author-1',
        authorName: 'Matias',
        authorUsername: 'mati',
        imageUrl: 'https://commons.wikimedia.org/wiki/Special:FilePath/Inception_poster.jpg',
        content: '🎬 Inception (2010) ★★★★★\n\nIncreíble película de Nolan.',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PostCard(post: post))));
      await tester.pumpAndSettle();

      expect(find.text('Reseña de película'), findsOneWidget);
      expect(find.text('Inception'), findsOneWidget);
      expect(find.text('2010'), findsOneWidget);
      expect(find.textContaining('Increíble película de Nolan.', findRichText: true), findsOneWidget);
      // Hero tag for the poster in review
      expect(find.byType(Hero), findsOneWidget);
    });

    test('CatalogService caches poster correctly', () {
      final service = CatalogService();
      expect(service.getCachedPoster('Test Movie', year: 2020), isNull);
    });

    testWidgets('CreatePostScreen lets you pick a 24-hour duration', (WidgetTester tester) async {
      useView(tester, const Size(360, 780));

      await tester.pumpWidget(const MaterialApp(home: CreatePostScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Duración'), findsOneWidget);
      expect(find.text('Permanente'), findsOneWidget);
      expect(find.text('Queda en tu perfil y en el feed.'), findsOneWidget);

      await tester.tap(find.text('24 horas'));
      await tester.pumpAndSettle();
      expect(find.text('Se deja de mostrar en Brote 24 horas después de publicarla.'), findsOneWidget);
    });
  });
}
