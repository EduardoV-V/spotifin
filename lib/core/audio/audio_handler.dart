import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import '../cache/image_store.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/models.dart';
import 'player_service.dart';

/// Liga o PlayerService à notificação, tela de bloqueio e botões de mídia
/// (fones, Bluetooth, teclas de volume longas) no Android.
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
        _publish(t);
      }
    }
    final playing = _p.sessionPlaying;
    var state = switch (_p.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    // Entre faixas (ou retomando de uma falha) a sessão continua "ativa".
    if (playing &&
        (state == AudioProcessingState.completed ||
            state == AudioProcessingState.idle)) {
      state = AudioProcessingState.buffering;
    }
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: state,
      playing: playing,
      updatePosition: _p.position,
      bufferedPosition: _p.position,
      speed: 1.0,
    ));
  }

  /// A capa da notificação vem do cache local do app (não do servidor).
  void _publish(Track t) {
    String? big, small;
    try {
      final id = t.albumId ?? t.id;
      big = _client.imageUri(id, maxWidth: 1000).toString();
      small = _client.imageUri(id, maxWidth: 400).toString();
    } catch (_) {}
    final f = big == null ? null : (ImageStore.peek(big) ?? ImageStore.peek(small!));
    final item = MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: t.duration,
      artUri: f == null ? null : Uri.file(f.path),
    );
    mediaItem.add(item);
    if (f == null && big != null) {
      ImageStore.get(big, headers: _client.authHeaders).then((file) {
        if (file == null || _lastId != t.id) return;
        mediaItem.add(item.copyWith(artUri: Uri.file(file.path)));
      }).catchError((_) {});
    }
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
