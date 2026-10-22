import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../cache/meta_cache.dart';
import 'lyrics.dart';
import 'models.dart';

class JellyfinException implements Exception {
  final String message;
  JellyfinException(this.message);
  @override
  String toString() => message; // nunca inclua token/senha aqui (RNF-004)
}

class JellyfinClient {
  static const clientName = 'Spotifin';
  static const clientVersion = '0.1.0';

  final http.Client _http;
  final String deviceName;
  JellyfinSession? session;

  JellyfinClient({http.Client? httpClient, this.deviceName = 'Device'})
      : _http = httpClient ?? http.Client();

  static String normalizeUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// Sem http:// ou https:// no endereço, descobre qual dos dois responde
  /// (tenta https primeiro). Com esquema explícito, só normaliza.
  Future<String> resolveServerUrl(String input) async {
    final t = input.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) {
      return normalizeUrl(t);
    }
    final bare = normalizeUrl(t).substring('http://'.length);
    for (final scheme in const ['https', 'http']) {
      if (await _pingBase('$scheme://$bare', const Duration(seconds: 4))) {
        return '$scheme://$bare';
      }
    }
    return 'http://$bare';
  }

  Future<bool> _pingBase(String base, Duration t) async {
    try {
      final res =
          await _http.get(Uri.parse('$base/System/Info/Public')).timeout(t);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Servidor da sessão atual responde? (usado para detectar offline)
  Future<bool> pingSession() async {
    final s = session;
    if (s == null) return false;
    return _pingBase(s.serverUrl, const Duration(seconds: 3));
  }

  Future<bool> ping(String url) async {
    try {
      final res = await _http
          .get(Uri.parse('${normalizeUrl(url)}/System/Info/Public'))
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  JellyfinSession updateServerUrl(String url) {
    final s = _requireSession();
    return session = JellyfinSession(
        serverUrl: normalizeUrl(url),
        userId: s.userId,
        token: s.token,
        deviceId: s.deviceId,
        username: s.username);
  }

  String _authHeader(String deviceId, [String? token]) =>
      'MediaBrowser Client="$clientName", Device="$deviceName", '
      'DeviceId="$deviceId", Version="$clientVersion"'
      '${token != null ? ', Token="$token"' : ''}';

  /// Cabeçalhos para qualquer requisição autenticada (inclusive streaming e downloads).
  /// Preferimos cabeçalho a `api_key` na URL para o token não vazar em logs.
  Map<String, String> get authHeaders {
    final s = _requireSession();
    return {'Authorization': _authHeader(s.deviceId, s.token)};
  }

  JellyfinSession _requireSession() =>
      session ?? (throw JellyfinException('Não autenticado no Jellyfin.'));

  Future<JellyfinSession> login({
    required String serverUrl,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final base = normalizeUrl(serverUrl);
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$base/Users/AuthenticateByName'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': _authHeader(deviceId),
            },
            body: jsonEncode({'Username': username, 'Pw': password}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw JellyfinException('Não foi possível conectar a $base.');
    }
    if (res.statusCode == 401) {
      throw JellyfinException('Usuário ou senha do Jellyfin inválidos.');
    }
    if (res.statusCode != 200) {
      throw JellyfinException('Jellyfin respondeu HTTP ${res.statusCode}.');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final user = json['User'] as Map<String, dynamic>;
    return session = JellyfinSession(
      serverUrl: base,
      userId: user['Id'] as String,
      token: json['AccessToken'] as String,
      deviceId: deviceId,
      username: (user['Name'] as String?) ?? username,
    );
  }

  Future<bool?> tokenValid(JellyfinSession s) async {
    try {
      final res = await _http
          .get(Uri.parse('${s.serverUrl}/Users/Me'), headers: {
        'Authorization': _authHeader(s.deviceId, s.token)
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return true;
      if (res.statusCode == 401) return false;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Lista paginada de músicas. [searchTerm] usa a busca do servidor.
  Future<TrackPage> getTracks({
    int startIndex = 0,
    int limit = 100,
    String? searchTerm,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    String? filters,
    String? genre,
  }) async {
    final s = _requireSession();
    final uri = Uri.parse('${s.serverUrl}/Items').replace(queryParameters: {
      if (filters != null) 'filters': filters,
      if (genre != null) 'genres': genre,
      'userId': s.userId,
      'includeItemTypes': 'Audio',
      'recursive': 'true',
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      'fields': 'MediaSources',
      'startIndex': '$startIndex',
      'limit': '$limit',
      if (searchTerm != null && searchTerm.trim().isNotEmpty)
        'searchTerm': searchTerm.trim(),
    });
    final res = await _http.get(uri, headers: authHeaders);
    if (res.statusCode != 200) {
      throw JellyfinException('Falha ao listar músicas (HTTP ${res.statusCode}).');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final items = (json['Items'] as List)
        .cast<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList();
    return TrackPage(items, (json['TotalRecordCount'] as int?) ?? items.length);
  }

  /// Chamado quando uma requisição falha por rede (para marcar modo offline).
  void Function()? onNetworkError;

  /// Faixas disponíveis offline (baixadas + favoritas em cache), para a busca.
  List<Track> Function()? offlineTracks;

  /// Playlists com alterações ainda na fila de envio (não sobrescrever com o servidor).
  bool Function(String playlistId)? playlistPending;

  static bool isNetworkError(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is http.ClientException;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      if (isNetworkError(e)) onNetworkError?.call();
      rethrow;
    }
  }

  Future<List<dynamic>> _items(String path, Map<String, String> query) async {
    if (offlineForced) throw TimeoutException('modo offline');
    final s = _requireSession();
    final uri = Uri.parse('${s.serverUrl}$path').replace(queryParameters: {
      'userId': s.userId,
      'recursive': 'true',
      'fields': 'MediaSources',
      ...query,
    });
    final res = await _guard(
        () => _http.get(uri, headers: authHeaders).timeout(const Duration(seconds: 12)));
    if (res.statusCode != 200) {
      throw JellyfinException('Falha na busca (HTTP ${res.statusCode}).');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (json['Items'] as List?) ?? const [];
  }

  /// Busca por título, artista e álbum. Ordem: título, artista, álbum.
  List<LibItem>? _albumsCache;
  List<LibItem>? _artistsCache;
  String? _libUser;

  List<LibItem>? get albumsCache => _albumsCache;
  List<LibItem>? get artistsCache => _artistsCache;

  void _libCheck() {
    if (_libUser != session?.userId) {
      _libUser = session?.userId;
      _albumsCache = null;
      _artistsCache = null;
    }
  }

  Future<List<LibItem>> libraryAlbums({bool force = false}) async {
    _libCheck();
    if (!force && _albumsCache != null) return _albumsCache!;
    final ck = 'libalbums_${session?.userId}';
    try {
      final l = await _items('/Items', {
        'includeItemTypes': 'MusicAlbum',
        'sortBy': 'SortName',
        'fields': 'AlbumArtist',
      });
      final out = [
        for (final e in l.cast<Map<String, dynamic>>())
          LibItem(e['Id'] as String, (e['Name'] as String?) ?? '?',
              (e['AlbumArtist'] as String?) ?? ''),
      ];
      MetaCache.put(ck, [for (final i in out) [i.id, i.name, i.sub]]);
      return _albumsCache = out;
    } catch (_) {
      final c = await MetaCache.get(ck, const Duration(days: 3650));
      if (c == null) rethrow;
      return _albumsCache = [
        for (final e in (c as List)) LibItem(e[0] as String, e[1] as String, e[2] as String)
      ];
    }
  }

  Future<List<LibItem>> libraryArtists({bool force = false}) async {
    _libCheck();
    if (!force && _artistsCache != null) return _artistsCache!;
    final ck = 'libartists_${session?.userId}';
    try {
      final l = await _items('/Artists', {'sortBy': 'SortName', 'fields': ''});
      final out = [
        for (final e in l.cast<Map<String, dynamic>>())
          LibItem(e['Id'] as String, (e['Name'] as String?) ?? '?', ''),
      ];
      MetaCache.put(ck, [for (final i in out) [i.id, i.name, i.sub]]);
      return _artistsCache = out;
    } catch (_) {
      final c = await MetaCache.get(ck, const Duration(days: 3650));
      if (c == null) rethrow;
      return _artistsCache = [
        for (final e in (c as List)) LibItem(e[0] as String, e[1] as String, e[2] as String)
      ];
    }
  }

  HomeFeed? _feed;
  String? _feedUser;

  /// Três consultas, em cache por 5 min: tudo da Home vem daqui.
  Future<HomeFeed> homeFeed({bool force = false}) async {
    final f = _feed;
    if (!force &&
        f != null &&
        _feedUser == session?.userId &&
        DateTime.now().difference(f.at).inMinutes < 5) {
      return f;
    }
    final fk = 'feed_${session?.userId}';
    HomeFeed? parse(dynamic c) {
      try {
        List<Track> l(String k) => [
              for (final e in (c[k] as List))
                Track.fromStored(e as Map<String, dynamic>)
            ];
        return HomeFeed(l('r'), l('a'), l('t'));
      } catch (_) {
        return null;
      }
    }

    if (!force && f == null) {
      final c = await MetaCache.get(fk, const Duration(minutes: 10));
      final h = c == null ? null : parse(c);
      if (h != null) {
        _feedUser = session?.userId;
        return _feed = h;
      }
    }
    try {
      final r = await Future.wait([
        getTracks(
            limit: 60,
            sortBy: 'DatePlayed',
            sortOrder: 'Descending',
            filters: 'IsPlayed'),
        getTracks(limit: 30, sortBy: 'DateCreated', sortOrder: 'Descending'),
        getTracks(
            limit: 60,
            sortBy: 'PlayCount',
            sortOrder: 'Descending',
            filters: 'IsPlayed'),
      ]);
      _feedUser = session?.userId;
      MetaCache.put(fk, {
        'r': r[0].items.map((t) => t.toJson()).toList(),
        'a': r[1].items.map((t) => t.toJson()).toList(),
        't': r[2].items.map((t) => t.toJson()).toList(),
      });
      return _feed = HomeFeed(r[0].items, r[1].items, r[2].items);
    } catch (_) {
      // Offline: usa o último que foi guardado, de qualquer idade.
      final c = await MetaCache.get(fk, const Duration(days: 3650));
      final h = c == null ? null : parse(c);
      if (h == null) rethrow;
      _feedUser = session?.userId;
      return _feed = h;
    }
  }

  Future<List<Track>> recentlyPlayed({int limit = 40}) async {
    final p = await getTracks(
        limit: limit,
        sortBy: 'DatePlayed',
        sortOrder: 'Descending',
        filters: 'IsPlayed');
    return p.items;
  }

  String _fold(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    var r = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      r = r.replaceAll(from[i], to[i]);
    }
    return r;
  }

  List<Track> _searchOffline(String term, int limit) {
    final q = _fold(term.trim());
    final all = offlineTracks?.call() ?? const <Track>[];
    if (q.isEmpty) return all.take(limit).toList();
    return all
        .where((t) =>
            _fold(t.title).contains(q) ||
            _fold(t.artist).contains(q) ||
            _fold(t.album).contains(q))
        .take(limit)
        .toList();
  }

  Future<List<Track>> searchTracks(String term, {int limit = 100}) async {
    try {
      return await _searchOnline(term, limit);
    } catch (e) {
      if (isNetworkError(e) || offlineForced) return _searchOffline(term, limit);
      rethrow;
    }
  }

  /// True quando o usuário ligou o modo offline manual.
  bool offlineForced = false;

  Future<List<Track>> _searchOnline(String term, int limit) async {
    if (offlineForced) throw TimeoutException('offline');
    final found = await Future.wait([
      _items('/Items', {
        'includeItemTypes': 'Audio',
        'searchTerm': term,
        'limit': '$limit',
        'sortBy': 'SortName',
      }),
      _items('/Artists', {'searchTerm': term, 'limit': '5'}),
      _items('/Items', {
        'includeItemTypes': 'MusicAlbum',
        'searchTerm': term,
        'limit': '5',
      }),
    ]);
    String idOf(dynamic e) => (e as Map<String, dynamic>)['Id'] as String;

    final byArtist = await Future.wait(found[1].map((a) => _items('/Items', {
          'includeItemTypes': 'Audio',
          'artistIds': idOf(a),
          'limit': '$limit',
          'sortBy': 'Album,ParentIndexNumber,IndexNumber,SortName',
        })));
    final byAlbum = await Future.wait(found[2].map((a) => _items('/Items', {
          'includeItemTypes': 'Audio',
          'albumIds': idOf(a),
          'limit': '$limit',
          'sortBy': 'ParentIndexNumber,IndexNumber,SortName',
        })));

    final seen = <String>{};
    final out = <Track>[];
    for (final e in [
      ...found[0],
      for (final l in byArtist) ...l,
      for (final l in byAlbum) ...l,
    ]) {
      final m = e as Map<String, dynamic>;
      if (seen.add(m['Id'] as String)) out.add(Track.fromJson(m));
    }
    return out;
  }

  Future<List<Track>> favoriteTracks() async {
    final items = await _items('/Items', {
      'includeItemTypes': 'Audio',
      'filters': 'IsFavorite',
      'sortBy': 'SortName',
    });
    return items.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Retorna o código HTTP final.
  Future<int> setFavorite(String itemId, bool favorite) async {
    final s = _requireSession();
    Future<http.Response> call(Uri u) => favorite
        ? _http.post(u, headers: authHeaders)
        : _http.delete(u, headers: authHeaders);
    final res = await call(Uri.parse('${s.serverUrl}/UserFavoriteItems/$itemId')
            .replace(queryParameters: {'userId': s.userId}))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 404 && res.statusCode != 405) return res.statusCode;
    final old = await call(
            Uri.parse('${s.serverUrl}/Users/${s.userId}/FavoriteItems/$itemId'))
        .timeout(const Duration(seconds: 10));
    return old.statusCode;
  }

  Future<http.Response> _send(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    if (offlineForced) throw TimeoutException('modo offline');
    final s = _requireSession();
    final uri = Uri.parse('${s.serverUrl}$path')
        .replace(queryParameters: {'userId': s.userId, ...?query});
    final req = http.Request(method, uri)..headers.addAll(authHeaders);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _guard(() async => http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 15))));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var detail = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
      if (detail.length > 200) detail = detail.substring(0, 200);
      throw JellyfinException(
          '$method $path → HTTP ${res.statusCode}${detail.isEmpty ? '' : ': $detail'}');
    }
    return res;
  }

  Future<List<PlaylistInfo>> playlists() async {
    final items = await _items('/Items', {
      'includeItemTypes': 'Playlist',
      'mediaTypes': 'Audio',
      'sortBy': 'SortName',
      'fields': 'ChildCount',
    });
    return items
        .map((e) => PlaylistInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Track>> playlistTracks(String id) async {
    final ck = 'pltracks_${session?.userId}_$id';
    Future<List<Track>?> fromCache() async {
      final c = await MetaCache.get(ck, const Duration(days: 3650));
      if (c == null) return null;
      try {
        return [
          for (final e in (c as List)) Track.fromStored(e as Map<String, dynamic>)
        ];
      } catch (_) {
        return null;
      }
    }

    // Alterações pendentes: o cache local é a verdade até o envio terminar.
    if (offlineForced || (playlistPending?.call(id) ?? false)) {
      final c = await fromCache();
      if (c != null) return c;
    }
    try {
      final items = await _items('/Playlists/$id/Items', {});
      final out =
          items.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
      MetaCache.put(ck, out.map((t) => t.toJson()).toList());
      return out;
    } catch (e) {
      final c = await fromCache();
      if (c != null) return c;
      rethrow;
    }
  }

  /// Faixas da playlist direto do servidor (sem cache), com os IDs de entrada.
  Future<List<Track>> playlistTracksRemote(String id) async {
    final items = await _items('/Playlists/$id/Items', {});
    return items.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Track>?> cachedPlaylistTracks(String id) async {
    final c = await MetaCache.get(
        'pltracks_${session?.userId}_$id', const Duration(days: 3650));
    if (c == null) return null;
    try {
      return [
        for (final e in (c as List)) Track.fromStored(e as Map<String, dynamic>)
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> putPlaylistTracks(String id, List<Track> l) => MetaCache.put(
      'pltracks_${session?.userId}_$id', l.map((t) => t.toJson()).toList());

  Future<String> createPlaylist(String name, List<String> ids) async {
    final s = _requireSession();
    final res = await _send('POST', '/Playlists', body: {
      'Name': name,
      'Ids': ids,
      'UserId': s.userId,
      'MediaType': 'Audio',
    });
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return json['Id'] as String;
  }

  Future<void> addToPlaylist(String id, List<String> ids) =>
      _send('POST', '/Playlists/$id/Items', query: {'ids': ids.join(',')});

  Future<void> removeFromPlaylist(String id, List<String> entryIds) => _send(
      'DELETE', '/Playlists/$id/Items',
      query: {'entryIds': entryIds.join(',')});

  Future<void> movePlaylistItem(String id, String entryId, int index) =>
      _send('POST', '/Playlists/$id/Items/$entryId/Move/$index');

  List<String>? _genres;

  Future<List<String>> genres() async {
    if (_genres != null) return _genres!;
    final l = await _items('/MusicGenres', {'sortBy': 'SortName', 'fields': ''});
    return _genres = [
      for (final e in l) (e as Map<String, dynamic>)['Name'] as String
    ];
  }

  Future<List<Track>> instantMix(String id, {int limit = 100}) async {
    final items = await _items('/Items/$id/InstantMix', {'limit': '$limit'});
    return items.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
  }

  final _avatar = <String, Uint8List?>{};

  /// Foto de perfil do usuário atual (null se não houver).
  Future<Uint8List?> userAvatar() async {
    final s = session;
    if (s == null) return null;
    if (_avatar.containsKey(s.userId)) return _avatar[s.userId];
    try {
      final res = await _http.get(
          Uri.parse('${s.serverUrl}/Users/${s.userId}/Images/Primary')
              .replace(queryParameters: {'maxWidth': '160'}),
          headers: authHeaders);
      final ct = res.headers['content-type'] ?? '';
      if (res.statusCode == 200 && ct.startsWith('image/') && res.bodyBytes.isNotEmpty) {
        return _avatar[s.userId] = res.bodyBytes;
      }
      return _avatar[s.userId] = null;
    } catch (_) {
      return null;
    }
  }

  final _lyricsCache = <String, List<LyricLine>>{};

  /// Letra da faixa (vazia se o servidor não tiver). Start em ticks de 100ns.
  Future<List<LyricLine>> lyrics(String id) async {
    final c = _lyricsCache[id];
    if (c != null) return c;
    var out = <LyricLine>[];
    try {
      final s = _requireSession();
      final res = await _http.get(Uri.parse('${s.serverUrl}/Audio/$id/Lyrics'),
          headers: authHeaders);
      if (res.statusCode == 200) {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        for (final e in (j['Lyrics'] as List? ?? const [])) {
          final m = e as Map<String, dynamic>;
          final st = m['Start'];
          out.add(LyricLine(
              st is num ? (st / 10000).round() : null, (m['Text'] ?? '') as String));
        }
      }
    } catch (_) {}
    return _lyricsCache[id] = out;
  }

  final _artistImg = <String, String?>{};

  /// Foto do artista no próprio Jellyfin (se o servidor tiver); cache.
  Future<String?> artistImage(String name) async {
    if (_artistImg.containsKey(name)) return _artistImg[name];
    final uid = session?.userId ?? '';
    final ck = 'jfart_${uid}_${name.toLowerCase()}';
    final hit = await MetaCache.get(ck, const Duration(days: 7));
    if (hit != null) {
      final v = hit as String;
      return _artistImg[name] = v.isEmpty ? null : v;
    }
    try {
      final s = _requireSession();
      final res = await _http.get(
          Uri.parse('${s.serverUrl}/Artists/${Uri.encodeComponent(name)}')
              .replace(queryParameters: {'userId': s.userId}),
          headers: authHeaders);
      if (res.statusCode == 200) {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final tags = (j['ImageTags'] as Map?) ?? const {};
        if (tags.containsKey('Primary')) {
          final u = imageUri(j['Id'] as String, maxWidth: 600).toString();
          MetaCache.put(ck, u);
          return _artistImg[name] = u;
        }
      }
    } catch (_) {
      return null;
    }
    MetaCache.put(ck, '');
    return _artistImg[name] = null;
  }

  final _previews = <String, List<Track>>{};

  /// 4 primeiras faixas (mosaico da capa padrão); cache em memória.
  Future<List<Track>> playlistPreview(String id) async {
    final c = _previews[id];
    if (c != null) return c;
    final items = await _items('/Playlists/$id/Items', {'limit': '80'});
    final seen = <String>{};
    final out = <Track>[];
    for (final e in items) {
      final t = Track.fromJson(e as Map<String, dynamic>);
      if (seen.add(t.albumId ?? t.id)) out.add(t);
      if (out.length == 4) break;
    }
    return _previews[id] = out;
  }

  void clearPreview(String id) => _previews.remove(id);

  Future<String> playlistOverview(String id) async {
    final res = await _send('GET', '/Items/$id');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (j['Overview'] as String?) ?? '';
  }

  Future<bool> playlistHasImage(String id) async {
    final res = await _send('GET', '/Items/$id');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return ((j['ImageTags'] as Map?) ?? const {}).containsKey('Primary');
  }

  Future<void> setPlaylistOverview(String id, String overview) async {
    final res = await _send('GET', '/Items/$id');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    j['Overview'] = overview;
    await _send('POST', '/Items/$id', body: j);
  }

  static const apiKeyPref = 'jellyfin_api_key';

  Future<void> uploadPlaylistImage(
      String id, List<int> bytes, String mime) async {
    final s = _requireSession();
    final uri = Uri.parse('${s.serverUrl}/Items/$id/Images/Primary');
    Future<http.Response> send(Map<String, String> h) async {
      final req = http.Request('POST', uri)
        ..headers.addAll(h)
        ..headers['Content-Type'] = mime
        ..body = base64Encode(bytes);
      return http.Response.fromStream(
          await _http.send(req).timeout(const Duration(seconds: 60)));
    }

    var res = await send(authHeaders);
    if (res.statusCode == 403) {
      // Só administradores podem enviar imagens; uma chave de API do
      // Jellyfin (Painel > Chaves de API) tem essa permissão.
      String? key;
      try {
        key = (await SharedPreferences.getInstance())
            .getString(apiKeyPref)
            ?.trim();
      } catch (_) {}
      if (key != null && key.isNotEmpty) {
        res = await send({'Authorization': _authHeader(s.deviceId, key)});
      }
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw JellyfinException('Upload da imagem falhou (HTTP ${res.statusCode}).');
    }
  }

  Future<List<Track>> artistTracks(String name) async {
    final s = _requireSession();
    final res = await _http.get(
        Uri.parse('${s.serverUrl}/Artists/${Uri.encodeComponent(name)}')
            .replace(queryParameters: {'userId': s.userId}),
        headers: authHeaders);
    if (res.statusCode != 200) return const [];
    final id = (jsonDecode(utf8.decode(res.bodyBytes))
        as Map<String, dynamic>)['Id'] as String;
    final items = await _items('/Items', {
      'includeItemTypes': 'Audio',
      'artistIds': id,
      'sortBy': 'SortName',
      'limit': '1500',
    });
    return items.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> renamePlaylist(String id, String name) =>
      _send('POST', '/Playlists/$id', body: {'Name': name});

  Future<void> deletePlaylist(String id) => _send('DELETE', '/Items/$id');

  static const _prefsPath = '/DisplayPreferences/spotifin';

  Map<String, dynamic>? _prefsCache;
  String? _prefsCacheUser;

  Future<Map<String, dynamic>> _displayPrefs() async {
    final res =
        await _send('GET', _prefsPath, query: {'client': clientName});
    _prefsCacheUser = session?.userId;
    return _prefsCache =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<String?> readPlayState() async {
    final j = await _displayPrefs();
    final cp = j['CustomPrefs'];
    return cp is Map ? cp['ps_state'] as String? : null;
  }

  Future<void> writePlayState(String value) async {
    final j = (_prefsCache != null && _prefsCacheUser == session?.userId)
        ? _prefsCache!
        : await _displayPrefs();
    final cp = <String, dynamic>{};
    ((j['CustomPrefs'] as Map?) ?? {}).forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) cp[k as String] = v.toString();
    });
    cp['ps_state'] = value;
    j['CustomPrefs'] = cp;
    await _send('POST', _prefsPath, query: {'client': clientName}, body: j);
  }

  Future<List<Map<String, dynamic>>> sessions() async {
    final s = _requireSession();
    final res = await _send('GET', '/Sessions',
        query: {'controllableByUserId': s.userId});
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> postCapabilities() => _send('POST', '/Sessions/Capabilities/Full',
      body: {
        'PlayableMediaTypes': ['Audio'],
        'SupportedCommands': <String>[],
        'SupportsMediaControl': true,
        'SupportsPersistentIdentifier': true,
      });

  Future<void> sendPlay(String sessionId, List<String> ids, int startMs) =>
      _send('POST', '/Sessions/$sessionId/Playing', query: {
        'playCommand': 'PlayNow',
        'itemIds': ids.join(','),
        'startIndex': '0',
        'startPositionTicks': '${startMs * 10000}',
      });

  Future<void> sendPlaystate(String sessionId, String command) =>
      _send('POST', '/Sessions/$sessionId/Playing/$command');

  Future<List<Track>> tracksByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final missing = [
      for (final id in ids)
        if (Track.cache[Track.key(id)] == null) id
    ];
    if (missing.isNotEmpty) {
      final items = await _items('/Items', {
        'ids': missing.join(','),
        'includeItemTypes': 'Audio',
      });
      for (final e in items) {
        Track.fromJson(e as Map<String, dynamic>);
      }
    }
    return [
      for (final id in ids)
        if (Track.cache[Track.key(id)] != null) Track.cache[Track.key(id)]!
    ];
  }

  Future<void> reportPlayback(String kind,
      {required String itemId,
      required int positionMs,
      required String sessionId,
      bool paused = false,
      bool transcoded = false}) async {
    final path = switch (kind) {
      'start' => '/Sessions/Playing',
      'stop' => '/Sessions/Playing/Stopped',
      _ => '/Sessions/Playing/Progress',
    };
    try {
      await _send('POST', path, body: {
        'ItemId': itemId,
        'MediaSourceId': itemId,
        'PositionTicks': positionMs * 10000,
        'IsPaused': paused,
        'CanSeek': true,
        'PlayMethod': transcoded ? 'Transcode' : 'DirectPlay',
        'PlaySessionId': sessionId,
      });
    } catch (_) {}
  }

  Future<int> trackCount() async {
    final s = _requireSession();
    final uri = Uri.parse('${s.serverUrl}/Items').replace(queryParameters: {
      'userId': s.userId,
      'includeItemTypes': 'Audio',
      'recursive': 'true',
      'limit': '0',
    });
    final res = await _http.get(uri, headers: authHeaders);
    if (res.statusCode != 200) {
      throw JellyfinException('Falha ao consultar a biblioteca (HTTP ${res.statusCode}).');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (json['TotalRecordCount'] as int?) ?? 0;
  }

  Future<http.StreamedResponse> openStream(Uri uri, {int rangeStart = 0}) {
    final req = http.Request('GET', uri)..headers.addAll(authHeaders);
    if (rangeStart > 0) req.headers['Range'] = 'bytes=$rangeStart-';
    return _http.send(req);
  }

  Future<List<Track>> albumTracks(String albumId) async {
    final items = await _items('/Items', {
      'includeItemTypes': 'Audio',
      'albumIds': albumId,
      'sortBy': 'ParentIndexNumber,IndexNumber,SortName',
    });
    return items.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Arquivo ORIGINAL, sem transcodificação (`static=true`).
  Uri originalStreamUri(String itemId) {
    final s = _requireSession();
    return Uri.parse('${s.serverUrl}/Audio/$itemId/stream')
        .replace(queryParameters: {'static': 'true'});
  }

  /// Versão transcodificada pelo servidor (qualidade comprimida).
  Uri transcodedStreamUri(String itemId, {int bitrate = 192000}) {
    final s = _requireSession();
    return Uri.parse('${s.serverUrl}/Audio/$itemId/stream.mp3').replace(
      queryParameters: {
        'audioCodec': 'mp3',
        'audioBitRate': '$bitrate',
        'maxAudioChannels': '2',
        'deviceId': s.deviceId,
      },
    );
  }

  Uri imageUri(String itemId, {int maxWidth = 300}) {
    final s = _requireSession();
    return Uri.parse('${s.serverUrl}/Items/$itemId/Images/Primary')
        .replace(queryParameters: {'maxWidth': '$maxWidth'});
  }

  /// Pede só o primeiro byte (Range) e compara o tamanho total com o do arquivo
  /// original. Se bater, o servidor entregou o original sem transcodificar.
  Future<StreamProbe> probeStream(Uri uri, {int? originalSize}) async {
    final res = await _http.get(uri, headers: {
      ...authHeaders,
      'Range': 'bytes=0-0',
    });
    int? total;
    final range = res.headers['content-range']; // "bytes 0-0/12345678"
    if (range != null && range.contains('/')) {
      total = int.tryParse(range.split('/').last);
    }
    total ??= int.tryParse(res.headers['content-length'] ?? '');
    return StreamProbe(
      res.statusCode,
      res.headers['content-type'],
      total,
      originalSize != null && total == originalSize,
    );
  }
}

class HomeFeed {
  final List<Track> recent;
  final List<Track> added;
  final List<Track> top;
  final DateTime at = DateTime.now();
  HomeFeed(this.recent, this.added, this.top);
}

class LibItem {
  final String id;
  final String name;
  final String sub;
  const LibItem(this.id, this.name, this.sub);
}
