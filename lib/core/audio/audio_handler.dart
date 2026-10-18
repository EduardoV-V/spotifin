import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import '../jellyfin/jellyfin_client.dart';
import 'player_service.dart';

/// Liga o PlayerService à notificação, tela de bloqueio e botões de mídia (Android).
class SpotifinAudioHandler extends BaseAudioHandler with SeekHandler {
  SpotifinAudioHandler(this._p, this._client) {
    _p.addListener(_sync);
  }

  final PlayerService _p;
  final JellyfinClient _client;
  String? _lastId;

  void _sync() {
    final t = _p.current;
    if (t?.id != _lastId) {
      _lastId = t?.id;
      if (t == null) {
        mediaItem.add(null);
      } else {
        Uri? art;
        Map<String, String>? headers;
        try {
          art = _client.imageUri(t.albumId ?? t.id, maxWidth: 512);
          headers = _client.authHeaders;
        } catch (_) {}
        mediaItem.add(MediaItem(
          id: t.id,
          title: t.title,
          artist: t.artist,
          album: t.album,
          duration: t.duration,
          artUri: art,
          artHeaders: headers,
        ));
      }
    }
    final state = switch (_p.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        _p.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: state,
      playing: _p.playing,
      updatePosition: _p.position,
      bufferedPosition: _p.position,
      speed: 1.0,
    ));
  }

  @override
  Future<void> play() => _p.play();

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> stop() => _p.pause();

  @override
  Future<void> skipToNext() => _p.next();

  @override
  Future<void> skipToPrevious() => _p.previous();

  @override
  Future<void> seek(Duration position) => _p.seek(position);
}
