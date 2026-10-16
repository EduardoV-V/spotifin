import 'dart:convert';

import 'package:http/http.dart' as http;

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
        deviceId: s.deviceId);
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
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return session = JellyfinSession(
      serverUrl: base,
      userId: (json['User'] as Map<String, dynamic>)['Id'] as String,
      token: json['AccessToken'] as String,
      deviceId: deviceId,
    );
  }

  /// Lista paginada de músicas. [searchTerm] usa a busca do servidor.
  Future<TrackPage> getTracks({
    int startIndex = 0,
    int limit = 100,
    String? searchTerm,
  }) async {
    final s = _requireSession();
    final uri = Uri.parse('${s.serverUrl}/Items').replace(queryParameters: {
      'userId': s.userId,
      'includeItemTypes': 'Audio',
      'recursive': 'true',
      'sortBy': 'SortName',
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

  /// Arquivo ORIGINAL, sem transcodificação (`static=true`).
  Uri originalStreamUri(String itemId) {
    final s = _requireSession();
    return Uri.parse('${s.serverUrl}/Audio/$itemId/stream')
        .replace(queryParameters: {'static': 'true'});
  }

  /// Versão transcodificada pelo servidor (para comparação / qualidade comprimida).
  Uri transcodedStreamUri(String itemId,
      {String container = 'mp3', int bitrate = 192000}) {
    final s = _requireSession();
    return Uri.parse('${s.serverUrl}/Audio/$itemId/universal').replace(
      queryParameters: {
        'userId': s.userId,
        'deviceId': s.deviceId,
        'container': container,
        'audioCodec': container,
        'maxStreamingBitrate': '$bitrate',
        'transcodingContainer': container,
        'transcodingProtocol': 'http',
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
