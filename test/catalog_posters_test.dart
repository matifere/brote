import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:brote/models/rating.dart';
import 'package:brote/services/catalog_service.dart';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('Wikipedia posters go to the right movie when a result is skipped', () async {
    final client = MockClient((request) async {
      final params = request.url.queryParameters;
      if (request.url.host == 'es.wikipedia.org') {
        return _json({
          'query': {
            'pages': {
              '1': {'title': 'Zzpeli Uno', 'thumbnail': {'source': 'https://img.test/uno.jpg'}},
              '2': {'title': 'Zzpeli Dos', 'thumbnail': {'source': 'https://img.test/dos.jpg'}},
            },
          },
        });
      }
      if (params['list'] == 'search') {
        return _json({
          'query': {
            'search': [
              {'title': 'Q1'},
              {'title': 'Q2'},
              {'title': 'Q3'},
            ],
          },
        });
      }
      if (params['action'] == 'wbgetentities') {
        return _json({
          'entities': {
            // No Spanish label, so it's left out of the results
            'Q1': {'labels': {}},
            'Q2': {
              'labels': {'es': {'value': 'Zzpeli Uno'}},
              'descriptions': {'es': {'value': 'película de 2001'}},
              'sitelinks': {'eswiki': {'title': 'Zzpeli Uno'}},
            },
            'Q3': {
              'labels': {'es': {'value': 'Zzpeli Dos'}},
              'descriptions': {'es': {'value': 'película de 2005'}},
              'sitelinks': {'eswiki': {'title': 'Zzpeli Dos'}},
            },
          },
        });
      }
      // Wikidata pageimages: nothing, so posters come from Wikipedia
      return _json({'query': {'pages': {}}});
    });

    final items = await http.runWithClient(
      () => CatalogService().search(RatingCategory.movie, 'zzpeli'),
      () => client,
    );

    expect(items, isNotNull);
    expect(items!.map((it) => it.title), ['Zzpeli Uno', 'Zzpeli Dos']);
    expect(items[0].imageUrl, 'https://img.test/uno.jpg');
    expect(items[1].imageUrl, 'https://img.test/dos.jpg');
    expect(items[1].year, 2005);
  });
}
