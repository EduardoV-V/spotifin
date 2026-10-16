import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/core/jellyfin/jellyfin_client.dart';
import '../lib/core/jellyfin/models.dart';

void main() {
  test('normalizeUrl adiciona esquema e remove barra final', () {
    expect(JellyfinClient.normalizeUrl('jellyfin.home:8096/'),
        'http://jellyfin.home:8096');
    expect(JellyfinClient.normalizeUrl('https://x.com//'), 'https://x.com');
  });

  test('login e listagem de faixas FLAC Hi-Res', () async {
    final mock = MockClient((req) async {
      if (req.url.path == '/Users/AuthenticateByName') {
        return http.Response(
            jsonEncode({'AccessToken': 'tok', 'User': {'Id': 'u1'}}), 200);
      }
      if (req.url.path == '/Items') {
        expect(req.headers['Authorization'], contains('Token="tok"'));
        return http.Response(
            jsonEncode({
              'TotalRecordCount': 1,
              'Items': [
                {
                  'Id': 'a1',
                  'Name': 'Faixa',
                  'Artists': ['Artista'],
                  'Album': 'Álbum',
                  'RunTimeTicks': 2400000000,
                  'MediaSources': [
                    {
                      'Container': 'flac',
                      'Size': 1000,
                      'MediaStreams': [
                        {
                          'Type': 'Audio',
                          'Codec': 'flac',
                          'SampleRate': 96000,
                          'BitDepth': 24,
                          'BitRate': 2800000
                        }
                      ]
                    }
                  ]
                }
              ]
            }),
            200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('', 404);
    });
    final c = JellyfinClient(httpClient: mock);
    await c.login(
        serverUrl: 'srv', username: 'a', password: 'b', deviceId: 'd');
    final page = await c.getTracks();
    final t = page.items.single;
    expect(t.duration, const Duration(minutes: 4));
    expect(t.file.label, 'FLAC • 24 bit / 96 kHz • 2800 kbps');
    expect(c.originalStreamUri('a1').queryParameters['static'], 'true');
  });

  test('probe detecta original pelo tamanho total', () async {
    final mock = MockClient((req) async => http.Response('x', 206, headers: {
          'content-range': 'bytes 0-0/1000',
          'content-type': 'audio/flac'
        }));
    final c = JellyfinClient(httpClient: mock)
      ..session = const JellyfinSession(
          serverUrl: 'http://s', userId: 'u', token: 't', deviceId: 'd');
    final p = await c.probeStream(Uri.parse('http://s/x'), originalSize: 1000);
    expect(p.matchesOriginalSize, isTrue);
  });
}