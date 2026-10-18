import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/strings.dart';

/// Dados de artista vindos de APIs públicas (não do Jellyfin):
/// Deezer (foto, fãs) e TheAudioDB (banner/fanart, biografia por idioma).
class ArtistInfo {
  final String name;
  final String? picture;
  final String? hero;
  final int? fans;
  final String? genre;
  final String? country;
  final Map<String, String> bio;
  const ArtistInfo(
      {required this.name,
      this.picture,
      this.hero,
      this.fans,
      this.genre,
      this.country,
      this.bio = const {}});

  String? get heroOrPicture => hero ?? picture;

  String? bioFor(String lang) =>
      (bio[lang]?.isNotEmpty ?? false) ? bio[lang] : bio['en'];

  Map<String, dynamic> toJson() => {
        'name': name,
        'picture': picture,
        'hero': hero,
        'fans': fans,
        'genre': genre,
        'country': country,
        'bio': bio,
      };

  factory ArtistInfo.fromJson(Map<String, dynamic> j) => ArtistInfo(
        name: j['name'] as String,
        picture: j['picture'] as String?,
        hero: j['hero'] as String?,
        fans: j['fans'] as int?,
        genre: j['genre'] as String?,
        country: j['country'] as String?,
        bio: ((j['bio'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v')),
      );
}

class ArtistInfoService {
  ArtistInfoService._();
  static final instance = ArtistInfoService._();

  /// Chave de teste pública do TheAudioDB; troque por uma própria se precisar.
  static const audioDbDefault = '2'; // chave pública de teste
  static const audioDbPref = 'meta_audiodb';

  Future<String> audioDbKey() async {
    final v = (await SharedPreferences.getInstance()).getString(audioDbPref);
    return (v == null || v.trim().isEmpty) ? audioDbDefault : v.trim();
  }
  static const _ttl = Duration(days: 14);
  static const _bioFields = {
    'en': 'EN',
    'pt': 'PT',
    'es': 'ES',
    'fr': 'FR',
    'de': 'DE',
    'it': 'IT',
    'ja': 'JP',
    'ru': 'RU',
    'zh': 'CN',
    'nl': 'NL',
    'pl': 'PL',
  };

  final _mem = <String, ArtistInfo?>{};
  final _pending = <String, Future<ArtistInfo?>>{};
  final _http = http.Client();

  static String primary(String artist) => artist.split(RegExp(r',\s*|;\s*')).first.trim();
  static String _key(String n) => n.toLowerCase().trim();
  static String _fold(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    var r = s.toLowerCase().trim();
    for (var i = 0; i < from.length; i++) {
      r = r.replaceAll(from[i], to[i]);
    }
    return r.replaceAll(RegExp(r'^the '), '').replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  ArtistInfo? cached(String name) => _mem[_key(primary(name))];

  Future<ArtistInfo?> get(String artist) {
    final name = primary(artist);
    final k = _key(name);
    if (_mem.containsKey(k)) return Future.value(_mem[k]);
    return _pending[k] ??= _load(name, k).whenComplete(() => _pending.remove(k));
  }

  Future<ArtistInfo?> _load(String name, String k) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('ai2_$k');
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
        if (DateTime.now().difference(at) < _ttl) {
          final c = ArtistInfo.fromJson(j['info'] as Map<String, dynamic>);
          if (c.picture != null || c.hero != null) return _mem[k] = c;
        }
      } catch (_) {}
    }
    final r = await Future.wait([_deezer(name), _audioDb(name)]);
    final dz = r[0];
    final adb = r[1];
    var picture = dz?['picture'] as String?;
    var hero = adb?['hero'] as String?;
    final bio = Map<String, String>.from(
        (adb?['bio'] as Map<String, String>?) ?? const {});
    if (picture == null || hero == null || !bio.containsKey(S.lang)) {
      final wk = await _wiki(name, S.lang);
      if (wk != null) {
        picture ??= wk['image'] as String?;
        hero ??= wk['image'] as String?;
        final ex = wk['bio'] as String?;
        if (ex != null && !bio.containsKey(S.lang)) bio[S.lang] = ex;
      }
    }
    if (dz == null && adb == null && picture == null) {
      return null; // falha: tenta de novo depois
    }
    final info = ArtistInfo(
      name: name,
      picture: picture,
      fans: dz?['fans'] as int?,
      hero: hero,
      genre: adb?['genre'] as String?,
      country: adb?['country'] as String?,
      bio: bio,
    );
    try {
      if (info.picture == null && info.hero == null) return _mem[k] = info;
      await sp.setString(
          'ai2_$k',
          jsonEncode({
            'at': DateTime.now().millisecondsSinceEpoch,
            'info': info.toJson(),
          }));
    } catch (_) {}
    return _mem[k] = info;
  }

  /// Wikipedia (sem chave, no idioma do app): foto e resumo.
  Future<Map<String, dynamic>?> _wiki(String name, String lang) async {
    final host = '${lang.isEmpty ? 'en' : lang}.wikipedia.org';
    try {
      final q = await _http
          .get(Uri.https(host, '/w/api.php', {
            'action': 'query',
            'list': 'search',
            'srsearch': '$name musician OR band OR singer',
            'srlimit': '1',
            'format': 'json',
          }), headers: const {'User-Agent': 'Spotifin/0.1 (personal use)'})
          .timeout(const Duration(seconds: 8));
      if (q.statusCode != 200) return null;
      final hits = (jsonDecode(utf8.decode(q.bodyBytes))['query']?['search']
              as List?) ??
          const [];
      if (hits.isEmpty) return null;
      final title = (hits.first as Map)['title'] as String;
      if (_fold(title).contains(_fold(name)) == false) return null;
      final r = await _http
          .get(Uri.https(host,
              '/api/rest_v1/page/summary/${Uri.encodeComponent(title.replaceAll(' ', '_'))}'),
              headers: const {'User-Agent': 'Spotifin/0.1 (personal use)'})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final img = ((j['originalimage'] ?? j['thumbnail']) as Map?)?['source']
          as String?;
      return {'image': img, 'bio': j['extract'] as String?};
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _deezer(String name) async {
    try {
      final res = await _http
          .get(Uri.https('api.deezer.com', '/search/artist',
              {'q': name, 'limit': '5'}))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = ((jsonDecode(res.body)['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      if (data.isEmpty) return null;
      final a = data.firstWhere(
          (e) => _fold(e['name'] as String? ?? '') == _fold(name),
          orElse: () => data.first);
      return {
        'picture': (a['picture_xl'] ?? a['picture_big']) as String?,
        'fans': a['nb_fan'] as int?,
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _audioDb(String name) async {
    try {
      final key = await audioDbKey();
      final res = await _http
          .get(Uri.https('www.theaudiodb.com',
              '/api/v1/json/$key/search.php', {'s': name}))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final list = (jsonDecode(res.body)['artists'] as List?) ?? const [];
      if (list.isEmpty) return null;
      final a = list.first as Map<String, dynamic>;
      String? s(String f) {
        final v = a[f];
        return v is String && v.isNotEmpty ? v : null;
      }

      final bio = <String, String>{};
      _bioFields.forEach((code, suffix) {
        final b = s('strBiography$suffix');
        if (b != null) bio[code] = b;
      });
      return {
        'hero': s('strArtistFanart') ??
            s('strArtistWideThumb') ??
            s('strArtistFanart2') ??
            s('strArtistThumb'),
        'genre': s('strGenre'),
        'country': s('strCountry'),
        'bio': bio,
      };
    } catch (_) {
      return null;
    }
  }
}

/// Reproduções globais por faixa via Last.fm (precisa de chave gratuita).
class LastFmService {
  LastFmService._();
  static final instance = LastFmService._();

  static const prefKey = 'lastfm_key';
  static const lbPref = 'meta_lb_token';
  final _http = http.Client();
  final _mem = <String, Map<String, int>>{};

  static String norm(String t) => t
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
      .replaceAll(RegExp(r'\s-\s.*$'), '')
      .replaceAll(RegExp(r'[^a-z0-9à-ÿ ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<String> key() async =>
      (await SharedPreferences.getInstance()).getString(prefKey) ?? '';

  static const _ua = {'User-Agent': 'Spotifin/0.1 (personal use)'};

  Future<Map<String, String>> _lbHeaders() async {
    final t = (await SharedPreferences.getInstance()).getString(lbPref) ?? '';
    return {..._ua, if (t.trim().isNotEmpty) 'Authorization': 'Token ${t.trim()}'};
  }

  /// título normalizado -> reproduções globais.
  /// Last.fm (se houver chave); senão ListenBrainz (sem chave).
  Future<Map<String, int>?> topTracks(String artist) async {
    final k = artist.toLowerCase();
    if (_mem.containsKey(k)) return _mem[k];
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('gp_$k');
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (DateTime.now().millisecondsSinceEpoch - (j['at'] as int) <
            const Duration(days: 7).inMilliseconds) {
          return _mem[k] = (j['m'] as Map)
              .map((a, b) => MapEntry('$a', (b as num).toInt()));
        }
      } catch (_) {}
    }
    final apiKey = await key();
    var m = apiKey.isEmpty ? null : await _lastFm(artist, apiKey);
    if (m == null || m.isEmpty) m = await _listenBrainz(artist);
    if (m == null || m.isEmpty) return null;
    await sp.setString('gp_$k',
        jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'm': m}));
    return _mem[k] = m;
  }

  Future<Map<String, int>?> _lastFm(String artist, String apiKey) async {
    try {
      final res = await _http
          .get(Uri.https('ws.audioscrobbler.com', '/2.0/', {
            'method': 'artist.gettoptracks',
            'artist': artist,
            'api_key': apiKey,
            'format': 'json',
            'limit': '100',
            'autocorrect': '1',
          }))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final list =
          ((jsonDecode(res.body)['toptracks']?['track']) as List?) ?? const [];
      final m = <String, int>{};
      for (final t in list.cast<Map<String, dynamic>>()) {
        final n = norm((t['name'] as String?) ?? '');
        final c = int.tryParse('${t['playcount']}') ?? 0;
        if (n.isNotEmpty && c > (m[n] ?? 0)) m[n] = c;
      }
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, int>?> _listenBrainz(String artist) async {
    try {
      final mb = await _http
          .get(
              Uri.https('musicbrainz.org', '/ws/2/artist/', {
                'query': 'artist:"$artist"',
                'fmt': 'json',
                'limit': '1',
              }),
              headers: _ua)
          .timeout(const Duration(seconds: 10));
      if (mb.statusCode != 200) return null;
      final arts = (jsonDecode(mb.body)['artists'] as List?) ?? const [];
      if (arts.isEmpty) return null;
      final mbid = (arts.first as Map<String, dynamic>)['id'] as String;
      final res = await _http
          .get(
              Uri.https('api.listenbrainz.org',
                  '/1/popularity/top-recordings-for-artist',
                  {'artist_mbid': mbid}),
              headers: await _lbHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body);
      final m = <String, int>{};
      for (final t in (list as List).cast<Map<String, dynamic>>()) {
        final n = norm((t['recording_name'] as String?) ?? '');
        final c = (t['total_listen_count'] as num?)?.toInt() ?? 0;
        if (n.isNotEmpty && c > (m[n] ?? 0)) m[n] = c;
      }
      return m;
    } catch (_) {
      return null;
    }
  }
}

/// Testa cada fonte de metadados e devolve um relatório curto.
Future<String> diagnoseMetadata() async {
  final c = http.Client();
  const ua = {'User-Agent': 'Spotifin/0.1 (personal use)'};
  Future<String> t(String label, Uri u, [Map<String, String>? h]) async {
    try {
      final r = await c.get(u, headers: h).timeout(const Duration(seconds: 10));
      return '$label: HTTP ${r.statusCode}';
    } catch (e) {
      return '$label: ERRO $e';
    }
  }

  final ak = await ArtistInfoService.instance.audioDbKey();
  final lk = await LastFmService.instance.key();
  final out = <String>[
    await t('Deezer', Uri.https('api.deezer.com', '/search/artist', {'q': 'Coldplay', 'limit': '1'})),
    await t('Wikipedia', Uri.https('en.wikipedia.org', '/api/rest_v1/page/summary/Coldplay'), ua),
    await t('TheAudioDB', Uri.https('www.theaudiodb.com', '/api/v1/json/$ak/search.php', {'s': 'Coldplay'})),
    await t('MusicBrainz', Uri.https('musicbrainz.org', '/ws/2/artist/', {'query': 'artist:"Coldplay"', 'fmt': 'json', 'limit': '1'}), ua),
    await t('ListenBrainz', Uri.https('api.listenbrainz.org', '/1/popularity/top-recordings-for-artist', {'artist_mbid': 'cc197bad-dc9c-440d-a5b5-d52ba2e14234'}), ua),
    if (lk.isNotEmpty)
      await t('Last.fm', Uri.https('ws.audioscrobbler.com', '/2.0/', {'method': 'artist.gettoptracks', 'artist': 'Coldplay', 'api_key': lk, 'format': 'json', 'limit': '1'})),
  ];
  c.close();
  return out.join('\n');
}
