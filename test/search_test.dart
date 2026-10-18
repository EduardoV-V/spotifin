import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/core/jellyfin/jellyfin_client.dart';
import '../lib/core/jellyfin/models.dart';

http.Response _json(Object o) => http.Response(jsonEncode(o), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _item(String id) => {'Id': id, 'Name': 'T$id'};

void main() {
  test('busca inclui músicas do artista e do álbum sem duplicar', () async {
    final mock = MockClient((req) async {
      final q = req.url.queryParameters;
      if (req.url.path == '/Artists') {
        return _json({'Items': [{'Id': 'art1'}]});
      }
      if (q['includeItemTypes'] == 'MusicAlbum') {
        return _json({'Items': [{'Id': 'alb1'}]});
      }
      if (q['artistIds'] == 'art1') {
        return _json({'Items': [_item('a'), _item('b')]});
      }
      if (q['albumIds'] == 'alb1') {
        return _json({'Items': [_item('b'), _item('c')]});
      }
      return _json({'Items': [_item('a')]});
    });
    final c = JellyfinClient(httpClient: mock)
      ..session = const JellyfinSession(
          serverUrl: 'http://s', userId: 'u', token: 't', deviceId: 'd');
    final r = await c.searchTracks('metallica');
    expect(r.map((t) => t.id).toList(), ['a', 'b', 'c']);
  });
}
