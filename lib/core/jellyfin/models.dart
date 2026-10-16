class JellyfinSession {
  final String serverUrl; // sem barra final
  final String userId;
  final String token;
  final String deviceId;
  const JellyfinSession({
    required this.serverUrl,
    required this.userId,
    required this.token,
    required this.deviceId,
  });
}

/// Informações do arquivo de áudio original, vindas de MediaSources.
class AudioFileInfo {
  final String? container; // ex.: flac
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
  final String id; // ID estável do Jellyfin (identificador externo da faixa)
  final String title;
  final String artist;
  final String album;
  final Duration? duration;
  final AudioFileInfo file;
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.file,
  });

  factory Track.fromJson(Map<String, dynamic> j) {
    final ticks = j['RunTimeTicks'] as int?; // 10.000 ticks = 1 ms
    final artists = (j['Artists'] as List?)?.cast<String>() ?? const [];
    return Track(
      id: j['Id'] as String,
      title: (j['Name'] as String?) ?? 'Sem título',
      artist: artists.isNotEmpty
          ? artists.join(', ')
          : (j['AlbumArtist'] as String?) ?? 'Artista desconhecido',
      album: (j['Album'] as String?) ?? 'Álbum desconhecido',
      duration: ticks == null ? null : Duration(microseconds: ticks ~/ 10),
      file: AudioFileInfo.fromItemJson(j),
    );
  }
}

class TrackPage {
  final List<Track> items;
  final int total;
  const TrackPage(this.items, this.total);
}

/// Resultado do teste "o servidor entregou o original?".
class StreamProbe {
  final int statusCode;
  final String? contentType;
  final int? contentLength;
  final bool matchesOriginalSize;
  const StreamProbe(
      this.statusCode, this.contentType, this.contentLength, this.matchesOriginalSize);
}
