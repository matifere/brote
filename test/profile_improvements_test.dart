import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brote/main.dart';
import 'package:brote/models/chat_item.dart';
import 'package:brote/models/rating.dart';
import 'package:brote/models/user_profile.dart';
import 'package:brote/screens/main_navigation_screen.dart';
import 'package:brote/screens/profile_screen.dart';
import 'package:brote/services/auth_service.dart';
import 'package:brote/services/chat_unread_service.dart';
import 'package:brote/services/theme_service.dart';
import 'package:brote/widgets/taste_affinity.dart';

RatedItem _movie(String title, int year, int stars) =>
    RatedItem.create(category: RatingCategory.movie, title: title, year: year, stars: stars);

RatedItem _music(String title, String artist, int stars) =>
    RatedItem.create(category: RatingCategory.music, title: title, artist: artist, stars: stars);

const _me = UserProfile(id: 'me-1', username: 'thiago', displayName: 'Thiago');

/// Restores a signed-in session for [_me] with [bio], like a returning user.
Future<void> _signIn({String? bio}) async {
  SharedPreferences.setMockInitialValues({
    'brote_session_token': 'test-token',
    'brote_user_profile': jsonEncode({..._me.toJson(), 'bio': bio}),
  });
  await AuthService().tryAutoLogin();
}

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().logout();
    ThemeService().mode.value = ThemeMode.system;
    ChatUnreadService().clear();
  });

  group('TasteAffinity', () {
    test('finds the ratings both profiles share and how much they agree', () {
      final mine = ProfileBio(ratings: [
        _movie('Dune', 2021, 4),
        _movie('Relatos salvajes', 2014, 5),
        _music('Abbey Road', 'The Beatles', 5),
      ]);
      final theirs = ProfileBio(ratings: [
        _movie('dune', 2021, 5), // same movie, different case
        _movie('Dune', 1984, 2), // same title, different movie
        _music('Abbey Road', 'The Beatles', 5),
      ]);

      final affinity = TasteAffinity.compare(mine, theirs)!;

      expect(affinity.matches, hasLength(2));
      expect(affinity.summary, 'Coinciden en 1 película y 1 tema o álbum');
      // (0.75 + 1) / 2
      expect(affinity.agreementPercent, 88);
    });

    test('is null when nothing is in common', () {
      final mine = ProfileBio(ratings: [_movie('Dune', 2021, 4)]);
      final theirs = ProfileBio(ratings: [_movie('Alien', 1979, 5)]);
      expect(TasteAffinity.compare(mine, theirs), isNull);
      expect(TasteAffinity.compare(const ProfileBio(), theirs), isNull);
    });
  });

  group('Appearance', () {
    test('the chosen mode is saved and restored', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      await ThemeService().load();
      expect(ThemeService().mode.value, ThemeMode.dark);

      await ThemeService().setMode(ThemeMode.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'light');
    });

    testWidgets('the app follows the chosen mode', (tester) async {
      await tester.pumpWidget(const BroteApp());
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.system);

      ThemeService().mode.value = ThemeMode.dark;
      await tester.pump();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    });
  });

  testWidgets('own profile: no made-up bio, no verified badge, and the appearance menu', (tester) async {
    _useTallView(tester);
    await _signIn();

    await tester.pumpWidget(const MaterialApp(home: ProfileScreen(profile: _me)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Creador de contenido'), findsNothing);
    expect(find.text('Agregá una descripción'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsNothing);

    await tester.tap(find.byTooltip('Apariencia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();

    expect(ThemeService().mode.value, ThemeMode.dark);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
  });

  testWidgets('someone else\'s profile: tastes in common, real verified badge and share', (tester) async {
    _useTallView(tester);
    final myBio = ProfileBio(ratings: [_movie('Dune', 2021, 4), _music('Abbey Road', 'The Beatles', 5)]).compose();
    await _signIn(bio: myBio);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final other = UserProfile(
      id: 'ana-1',
      username: 'ana',
      displayName: 'Ana',
      isVerified: true,
      bio: ProfileBio(ratings: [_movie('Dune', 2021, 4), _movie('Alien', 1979, 5)]).compose(),
    );
    await tester.pumpWidget(MaterialApp(home: ProfileScreen(profile: other)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.verified), findsOneWidget);
    expect(find.text('Gustos en común'), findsOneWidget);
    expect(find.text('Coinciden en 1 película'), findsOneWidget);
    expect(find.text('100% de acuerdo'), findsOneWidget);

    await tester.tap(find.byTooltip('Compartir perfil'));
    await tester.pump();
    expect(copied, 'Seguí a Ana (@ana) en brote');
    expect(find.textContaining('brote.app'), findsNothing);
  });

  testWidgets('own profile fits a narrow phone with every action shown', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _signIn();

    final me = _me.copyWith(isPrivate: true, pendingRequestsCount: 2);
    await tester.pumpWidget(MaterialApp(home: ProfileScreen(profile: me)));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Apariencia'), findsOneWidget);
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a public account that isn\'t verified shows no badge', (tester) async {
    _useTallView(tester);
    await _signIn();

    const other = UserProfile(id: 'leo-1', username: 'leo', displayName: 'Leo');
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen(profile: other)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.verified), findsNothing);
    expect(find.text('Gustos en común'), findsNothing);
  });

  testWidgets('the Chats tab shows how many conversations are unread', (tester) async {
    _useTallView(tester);

    ChatUnreadService().update([
      ChatItem(id: 'c1', lastMessage: 'hola', unreadCount: 3),
      ChatItem(id: 'c2', lastMessage: 'chau', unreadCount: 0),
      ChatItem(id: 'c3', lastMessage: '¿vamos?', unreadCount: 1),
    ]);
    expect(ChatUnreadService().unreadChats.value, 2);

    await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen(profile: _me)));
    // Signed out, the inbox load resets the badge; report a fresh load after it
    await tester.pump();
    ChatUnreadService().update([ChatItem(id: 'c1', lastMessage: 'hola', unreadCount: 3)]);
    await tester.pump();

    final badge = find.ancestor(of: find.text('1'), matching: find.byType(Badge));
    expect(badge, findsWidgets);
    expect(find.byTooltip('Chats: 1 conversación sin leer'), findsOneWidget);

    ChatUnreadService().clear();
    await tester.pump();
    expect(find.byTooltip('Chats: 1 conversación sin leer'), findsNothing);
  });
}
