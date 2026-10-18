import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/player_service.dart';
import '../jellyfin/jellyfin_client.dart';

class PlayStateSync extends ChangeNotifier with WidgetsBindingObserver {
  PlayStateSync(this._player, this._client);

  static const _kStamp = 'ps_stamp';

  final PlayerService _player;
  final JellyfinClient _client;
  void Function(String)? onNotice;

  Timer? _debounce;
  Timer? _tick;
  String? _lastSig;
  int _localStamp = 0;
  int _n = 0;
  bool _running = false;
  bool _foreground = true;
  bool _busy = false;
  int _applying = 0;

  String? lastError;
  String remoteInfo = '';
  DateTime? lastOk;

  String get _me => _client.session?.deviceId ?? '';

  String _sig() => Object.hash(
        _player.current?.id,
        _player.queueLength,
        _player.playing,
        _player.shuffle,
        _player.repeat,
        Object.hashAll(_player.orderedTracks.map((t) => t.id)),
      ).toString();

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      _localStamp =
          (await SharedPreferences.getInstance()).getInt(_kStamp) ?? 0;
    } catch (_) {}
    _lastSig = _sig();
    WidgetsBinding.instance.addObserver(this);
    _player.addListener(_onChange);
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _onTick());
    unawaited(pull());
  }

  void stop() {
    _running = false;
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_onChange);
    _tick?.cancel();
    _debounce?.cancel();
  }

  Future<void> switchUser() async {
    _debounce?.cancel();
    _lastSig = _sig();
    _localStamp = 0;
    await _saveStamp();
    if (_running) await pull();
  }

  void _onTick() {
    _n++;
    if (_player.playing && !_player.isMirror && _n % 3 == 0) unawaited(_push());
  }

  void _onChange() {
    if (_applying > 0 || _player.isMirror) return;
    final sig = _sig();
    if (sig == _lastSig) return;
    _lastSig = sig;
    _localStamp = DateTime.now().millisecondsSinceEpoch;
    _saveStamp();
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), _push);
  }

  Future<void> _saveStamp() async {
    try {
      (await SharedPreferences.getInstance()).setInt(_kStamp, _localStamp);
    } catch (_) {}
  }

  void _ok() {
    lastError = null;
    lastOk = DateTime.now();
    notifyListeners();
  }

  void _fail(Object e) {
    lastError = e is JellyfinException ? e.message : 'Sem conexão com o servidor.';
    debugPrint('sync: $e');
    notifyListeners();
  }

  Future<Map<String, dynamic>?> _readRemote() async {
    final raw = await _client.readPlayState();
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _push() async {
    if (_client.session == null ||
        _player.queueLength == 0 ||
        _player.isMirror ||
        _busy) {
      return;
    }
    _busy = true;
    try {
      final tracks = _player.orderedTracks;
      final idx = _player.orderPos;
      final start = max(0, idx - 10);
      final now = DateTime.now().millisecondsSinceEpoch;
      await _client.writePlayState(jsonEncode({
        'ids': tracks.skip(start).take(200).map((t) => t.id).toList(),
        'index': idx - start,
        'posMs': _player.position.inMilliseconds,
        'playing': _player.playing,
        'shuffle': _player.shuffle,
        'repeat': _player.repeat.index,
        'updatedAt': now,
        'device': _me,
        'name': _client.deviceName,
      }));
      _localStamp = now;
      await _saveStamp();
      _ok();
    } catch (e) {
      _fail(e);
    } finally {
      _busy = false;
    }
  }

  Future<void> _apply(Map<String, dynamic> j, {bool force = false}) async {
    final ids = (j['ids'] as List).cast<String>();
    final tracks = await _client.tracksByIds(ids);
    if (tracks.isEmpty) return;
    // Durante o await, outra troca (Play remoto, takeover) pode ter começado.
    if (_player.isMirror || _player.localActive) return;
    if (_player.queueLength > 0 && !force) return;
    final want = ids[((j['index'] as int?) ?? 0).clamp(0, ids.length - 1)];
    var idx = tracks.indexWhere((t) => t.id == want);
    final exact = idx >= 0;
    if (!exact) idx = 0;
    var pos = exact ? ((j['posMs'] as int?) ?? 0) : 0;
    final stamp = (j['updatedAt'] as int?) ?? 0;
    if (exact && j['playing'] == true) {
      pos += max(0, DateTime.now().millisecondsSinceEpoch - stamp);
    }
    _applying++;
    try {
      await _player.loadRemote(tracks, idx, Duration(milliseconds: pos),
          shuffle: (j['shuffle'] as bool?) ?? false,
          repeat:
              QueueRepeat.values[((j['repeat'] as int?) ?? 0).clamp(0, 2)]);
    } finally {
      _applying--;
    }
    _lastSig = _sig();
    _localStamp = stamp;
    await _saveStamp();
  }

  /// Retorna mensagem de erro ou null.
  Future<String?> pullNow() async {
    await pull(force: true);
    return lastError;
  }

  Future<void> pull({bool force = false}) async {
    if (_client.session == null || _busy) return;
    _busy = true;
    try {
      final j = await _readRemote();
      remoteInfo = j == null
          ? 'Nada salvo no servidor ainda.'
          : 'Salvo por ${j['name']} há ${((DateTime.now().millisecondsSinceEpoch - ((j['updatedAt'] as int?) ?? 0)) / 1000).round()} s'
              '${j['device'] == _me ? ' (este aparelho)' : ''}';
      _ok();
      if (j == null) return;
      if (_player.isMirror || _player.localActive) return;
      if (_player.queueLength > 0 && !force) return;
      await _apply(j, force: force);
      if (j['device'] != _me) {
        onNotice?.call('Retomado de ${j['name'] ?? 'outro dispositivo'}');
      }
    } catch (e) {
      _fail(e);
    } finally {
      _busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    if (state == AppLifecycleState.paused) {
      _foreground = false;
      _debounce?.cancel();
      if (_player.queueLength > 0 && _player.playing) unawaited(_push());
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
    }
  }
}
