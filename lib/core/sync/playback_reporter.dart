import 'dart:async';
import 'dart:math';

import '../audio/player_service.dart';
import '../jellyfin/jellyfin_client.dart';

class PlaybackReporter {
  PlaybackReporter(this._player, this._client);

  final PlayerService _player;
  final JellyfinClient _client;
  Timer? _timer;
  String? _itemId;
  bool _started = false;
  bool _lastPlaying = false;
  int _lastMs = 0;
  int _ticks = 0;
  String _sessionId = _newId();

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void attach() {
    _player.addListener(_sync);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_started && _player.localLoaded && _player.localTrack?.id == _itemId) {
        _lastMs = _player.localPosition.inMilliseconds;
      }
      if (++_ticks % 3 == 0 && _started && _player.localPlaying) {
        _send('progress');
      }
      _sync();
    });
  }

  void _send(String kind, {String? itemId, int? ms}) {
    if (_client.session == null) return;
    _client.reportPlayback(kind,
        itemId: itemId ?? _itemId!,
        positionMs: ms ?? _player.localPosition.inMilliseconds,
        sessionId: _sessionId,
        paused: !_player.localPlaying,
        transcoded: _player.useTranscoded);
  }

  // Reporta SEMPRE o estado do player local, mesmo quando este aparelho está
  // espelhando outro. Antes, ao virar espelho o reporter parava de enviar e o
  // servidor ficava com "tocando" preso para este aparelho.
  void _sync() {
    final t = _player.localTrack;
    if (t?.id != _itemId) {
      if (_started && _itemId != null) {
        final dur = _player.localDuration.inMilliseconds;
        var ms = _lastMs;
        if (dur > 0 && dur - ms < 3000) ms = dur;
        _send('stop', itemId: _itemId, ms: ms);
      }
      _started = false;
      _itemId = t?.id;
      _lastMs = 0;
      _sessionId = _newId();
    }
    if (t == null) {
      _lastPlaying = false;
      return;
    }
    final playing = _player.localPlaying && _player.localLoaded;
    if (!_started && playing) {
      _started = true;
      _lastPlaying = true;
      _send('start');
      return;
    }
    if (_started && playing != _lastPlaying) {
      _lastPlaying = playing;
      _send('progress');
    }
  }
}
