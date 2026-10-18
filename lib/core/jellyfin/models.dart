class JellyfinSession {
  final String serverUrl;
  final String userId;
  final String token;
  final String deviceId;
  final String username;
  const JellyfinSession({
    required this.serverUrl,
    required this.userId,
    required this.token,
    required this.deviceId,
    this.username = '',
  });

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'userId': userId,
        'token': token,
        'username': username,
      };

  factory JellyfinSession.fromJson(Map<String, dynamic> j, String deviceId) =>
      JellyfinSession(
        serverUrl: j['serverUrl'] as String,
        userId: j['userId'] as String,
        token: j['token'] as String,
        username: (j['username'] as String?) ?? '',
        deviceId: deviceId,
      );
}

class AudioFileInfo {
  final String? container;
  final String? codec;
  final int? sampleRate;
  final int? bitDepth;
  final int? bitrate;
  final int? sizeBytes;
  const AudioFileInfo({
    this.container,
    this.codec,
    this.sampleRate,
    this.bitDepth,
    this.bitrate,
    this.sizeBytes,
  });

  factory AudioFileInfo.fromItemJson(Map<String, dynamic> item) {
    final sources = (item['MediaSources'] as List?) ?? const [];
    if (sources.isEmpty) return const AudioFileInfo();
    final src = sources.first as Map<String, dynamic>;
    final streams = (src['MediaStreams'] as List?) ?? const [];
    final audio = streams
        .cast<Map<String, dynamic>>()
        .where((s) => s['Type'] == 'Audio')
        .firstOrNull;
    return AudioFileInfo(
      container: src['Container'] as String?,
      codec: audio?['Codec'] as String?,
      sampleRate: audio?['SampleRate'] as int?,
      bitDepth: audio?['BitDepth'] as int?,
      bitrate: (audio?['BitRate'] ?? src['Bitrate']) as int?,
      sizeBytes: src['Size'] as int?,
    );
  }

  factory AudioFileInfo.fromStored(Map<String, dynamic> j) => AudioFileInfo(
        container: j['container'] as String?,
        codec: j['codec'] as String?,
        sampleRate: j['sampleRate'] as int?,
        bitDepth: j['bitDepth'] as int?,
        bitrate: j['bitrate'] as int?,
        sizeBytes: j['sizeBytes'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'container': container,
        'codec': codec,
        'sampleRate': sampleRate,
        'bitDepth': bitDepth,
        'bitrate': bitrate,
        'sizeBytes': sizeBytes,
      };

  String get label {
    final parts = <String>[
      (codec ?? container ?? '?').toUpperCase(),
      if (bitDepth != null && sampleRate != null)
        '$bitDepth bit / ${(sampleRate! / 1000).toStringAsFixed(sampleRate! % 1000 == 0 ? 0 : 1)} kHz',
      if (bitrate != null) '${(bitrate! / 1000).round()} kbps',
    ];
    return parts.join(' • ');
  }
}

class Track {
  final String id;
  final String? albumId;
  final String title;
  final String artist;
  final String album;
  final Duration? duration;
  final AudioFileInfo file;
  final String? playlistItemId;
  final DateTime? added;
  final int plays;
  const Track({
    this.playlistItemId,
    this.added,
    this.plays = 0,
    required this.id,
    this.albumId,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.file,
  });

  static final Map<String, Track> cache = {};
  static String key(String id) => id.replaceAll('-', '').toLowerCase();

  factory Track.fromJson(Map<String, dynamic> j) {
    final t = Track._parse(j);
    if (j['MediaSources'] != null && j['PlaylistItemId'] == null) {
      if (cache.length > 600) cache.remove(cache.keys.first);
      cache[key(t.id)] = t;
    }
    return t;
  }

  factory Track._parse(Map<String, dynamic> j) {
    final ticks = (j['RunTimeTicks'] as num?)?.toInt();
    final artists = (j['Artists'] as List?)?.cast<String>() ?? const [];
    return Track(
      id: j['Id'] as String,
      playlistItemId: j['PlaylistItemId'] as String?,
      added: DateTime.tryParse((j['DateCreated'] ?? '').toString())?.toLocal(),
      plays: ((j['UserData'] is Map ? (j['UserData'] as Map)['PlayCount'] : null) as num?)?.toInt() ?? 0,
      albumId: j['AlbumId'] as String?,
      title: (j['Name'] as String?) ?? 'Sem título',
      artist: artists.isNotEmpty
          ? artists.join(', ')
          : (j['AlbumArtist'] as String?) ?? 'Artista desconhecido',
      album: (j['Album'] as String?) ?? 'Álbum desconhecido',
      duration: ticks == null ? null : Duration(microseconds: ticks ~/ 10),
      file: AudioFileInfo.fromItemJson(j),
    );
  }

  factory Track.fromStored(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        albumId: j['albumId'] as String?,
        added: DateTime.tryParse((j['added'] ?? '').toString()),
        title: j['title'] as String,
        artist: j['artist'] as String,
        album: j['album'] as String,
        duration: j['durationMs'] == null
            ? null
            : Duration(milliseconds: j['durationMs'] as int),
        file: AudioFileInfo.fromStored(j['file'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'albumId': albumId,
        'added': added?.toIso8601String(),
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': duration?.inMilliseconds,
        'file': file.toJson(),
      };
}

class PlaylistInfo {
  final String id;
  final String name;
  final int count;
  const PlaylistInfo(this.id, this.name, this.count);

  factory PlaylistInfo.fromJson(Map<String, dynamic> j) => PlaylistInfo(
      j['Id'] as String,
      (j['Name'] as String?) ?? 'Playlist',
      (j['ChildCount'] as int?) ?? 0);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'count': count};
  factory PlaylistInfo.fromStored(Map<String, dynamic> j) =>
      PlaylistInfo(j['id'] as String, j['name'] as String, j['count'] as int);
}

class TrackPage {
  final List<Track> items;
  final int total;
  const TrackPage(this.items, this.total);
}

class StreamProbe {
  final int statusCode;
  final String? contentType;
  final int? contentLength;
  final bool matchesOriginalSize;
  const StreamProbe(
      this.statusCode, this.contentType, this.contentLength, this.matchesOriginalSize);
}
