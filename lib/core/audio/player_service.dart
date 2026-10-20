import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/models.dart';

enum QueueRepeat { off, all, one }

class MirrorState {
  final String sessionId;
  final String deviceId;
  final String deviceName;
  final Track track;
  final int durationMs;
  final int positionMs;
  final bool paused;
  final DateTime at;
  const MirrorState({
    required this.sessionId,
    required this.deviceId,
    required this.deviceName,
    required this.track,
    required this.durationMs,
    required this.positionMs,
    required this.paused,
    required this.at,
  });

  MirrorState copyWith({int? positionMs, bool? paused, DateTime? at}) =>
      MirrorState(
        sessionId: sessionId,
        deviceId: deviceId,
        deviceName: deviceName,
        track: track,
        durationMs: durationMs,
        positionMs: positionMs ?? this.positionMs,
        paused: paused ?? this.paused,
        at: at ?? this.at,
      );

  Duration get position {
    var ms = positionMs;
    if (!paused) ms += DateTime.now().difference(at).inMilliseconds;
    if (durationMs > 0 && ms > durationMs) ms = durationMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }
}

class PlayerService extends ChangeNotifier {
  PlayerService(this._client) {
    _player.playerStateStream.listen(_onPlayerState);
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_player.playing) _persistPosition();
    });
    _player.positionStream.listen((p) {
      if (_mirror == null) _posCtl.add(p);
    });
    Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_mirror != null) _posCtl.add(_mirror!.position);
    });
    unawaited(_loadVolume());
    unawaited(restoreQuality());
  }

  static const _kQueue = 'player_queue';
  static const _kPos = 'player_position';
  static const _kVolume = 'player_volume';

  final JellyfinClient _client;
  final AudioPlayer _player = AudioPlayer();
  final Random _rng = Random();
  late final Timer _ticker;

  List<Track> _queue = [];
  List<int> _order = [];
  // Índices de _queue adicionados manualmente ("fila do usuário").
  Set<int> _manual = {};
  int _pos = -1;
  bool _shuffle = false;
  QueueRepeat _repeat = QueueRepeat.off;
  int _kbps = 0;
  bool get _useTranscoded => _kbps > 0;
  int get streamKbps => _kbps;
  bool _advanced = false;
  bool get advanced => _advanced;
  Future<void> setAdvanced(bool v) async {
    _advanced = v;
    try {
      (await SharedPreferences.getInstance()).setBool('advanced_opts', v);
    } catch (_) {}
    notifyListeners();
  }
  bool _playingLocal = false;
  String? Function(String id)? localPathResolver;
  double _volume = 1.0;
  double _volumeBeforeMute = 1.0;
  bool _loaded = false;
  bool _completionHandled = false;
  Duration _pendingStart = Duration.zero;
  int _loadId = 0;
  StreamProbe? _probe;
  String? _playerError;

  MirrorState? _mirror;
  bool _busyLoading = false;
  final StreamController<Duration> _posCtl = StreamController.broadcast();
  Future<void> Function(String cmd, Duration? seek)? onMirrorControl;

  MirrorState? get mirror => _mirror;
  bool get isMirror => _mirror != null;
  bool get localPlaying => _player.playing;
  bool get localActive => _player.playing || _busyLoading;

  void setMirror(MirrorState? m) {
    _mirror = m;
    notifyListeners();
  }

  /// Atualiza o espelho com o estado do servidor sem fazer a barra pular.
  void updateMirror(MirrorState n) {
    final o = _mirror;
    if (o != null && o.sessionId == n.sessionId && o.track.id == n.track.id) {
      if (n.paused) {
        if (o.paused && (o.positionMs - n.positionMs).abs() < 300) return;
        _mirror = n;
      } else if (!o.paused) {
        final server = n.positionMs + 1500;
        if ((server - o.position.inMilliseconds).abs() < 3000) return;
        _mirror = n.copyWith(positionMs: server);
      } else {
        _mirror = n.copyWith(positionMs: n.positionMs + 1500);
      }
    } else {
      _mirror = n;
    }
    notifyListeners();
  }

  Future<void> _ctl(String cmd, [Duration? d]) =>
      onMirrorControl?.call(cmd, d) ?? Future.value();

  Track? get _cur =>
      _pos >= 0 && _pos < _order.length ? _queue[_order[_pos]] : null;
  Track? get current => _mirror?.track ?? _cur;
  bool _wantPlay = false;
  bool get playing => _mirror != null
      ? !_mirror!.paused
      : (_player.playing && _player.processingState != ProcessingState.completed) ||
          (_busyLoading && _wantPlay);
  bool get shuffle => _shuffle;
  QueueRepeat get repeat => _repeat;
  bool get useTranscoded => _useTranscoded;
  String? get playerError => _playerError;
  Stream<Duration> get positionStream => Stream.multi((c) {
        c.add(position);
        final sub = _posCtl.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });
  Duration get duration {
    if (_mirror != null) return Duration(milliseconds: _mirror!.durationMs);
    final meta = _cur?.duration;
    if (_useTranscoded) return meta ?? _player.duration ?? Duration.zero;
    return _player.duration ?? meta ?? Duration.zero;
  }

  Duration get position =>
      _mirror != null ? _mirror!.position : (_loaded ? _player.position : _pendingStart);
  ProcessingState get processingState =>
      _mirror != null ? ProcessingState.ready : _player.processingState;
  bool get isLoaded => _mirror != null || _loaded;
  bool get localLoaded => _loaded;
  Track? get localTrack => _cur;
  Duration get localPosition => _loaded ? _player.position : _pendingStart;
  Duration get localDuration {
    final meta = _cur?.duration;
    if (_useTranscoded) return meta ?? _player.duration ?? Duration.zero;
    return _player.duration ?? meta ?? Duration.zero;
  }
  double get volume => _volume;
  Duration displayPosition(Duration streamPos) => _mirror != null
      ? _mirror!.position
      : (_loaded ? streamPos : _pendingStart);

  List<Track> get orderedTracks => [for (final i in _order) _queue[i]];

  Future<void> loadRemote(List<Track> tracks, int index, Duration start,
      {required bool shuffle, required QueueRepeat repeat}) async {
    _mirror = null;
    _loadId++;
    await _player.stop();
    _queue = List.of(tracks);
    _manual = {};
    _order = List<int>.generate(tracks.length, (i) => i);
    _pos = index.clamp(0, tracks.length - 1);
    _shuffle = shuffle;
    _repeat = repeat;
    _pendingStart = start;
    _loaded = false;
    _persistQueue();
    notifyListeners();
  }

  int get queueLength => _order.length;
  int get orderPos => _pos;
  Track trackAtOrder(int p) => _queue[_order[p]];
  int keyAtOrder(int p) => _order[p];
  bool isManualAt(int p) => p >= 0 && p < _order.length && _manual.contains(_order[p]);

  String get verdict {
    if (_playingLocal) return 'Reproduzindo arquivo baixado (offline).';
    if (_useTranscoded) return 'Transcodificado (MP3 $_kbps kbps).';
    final p = _probe;
    if (p == null) return 'Verificando entrega do servidor…';
    if (p.statusCode >= 400) return 'Servidor respondeu HTTP ${p.statusCode}.';
    return p.matchesOriginalSize
        ? 'Original entregue (${p.contentType}).'
        : 'Tamanho diferente do original — possível transcodificação.';
  }

  void _rebuildOrder(int currentQueueIndex) {
    final pending = <int>[
      if (_pos >= 0)
        for (var i = _pos + 1; i < _order.length; i++)
          if (_manual.contains(_order[i]) && _order[i] != currentQueueIndex)
            _order[i]
    ];
    final idx = List<int>.generate(_queue.length, (i) => i);
    if (_shuffle) {
      if (currentQueueIndex >= 0) idx.remove(currentQueueIndex);
      idx.shuffle(_rng);
      if (currentQueueIndex >= 0) idx.insert(0, currentQueueIndex);
      _pos = currentQueueIndex >= 0 ? 0 : -1;
    } else {
      _pos = currentQueueIndex;
    }
    if (pending.isNotEmpty && _pos >= 0) {
      idx.removeWhere(pending.contains);
      final at = idx.indexOf(currentQueueIndex);
      idx.insertAll(at + 1, pending);
    }
    _order = idx;
  }

  void _restartOrder() {
    _order = List<int>.generate(_queue.length, (i) => i);
    if (_shuffle) _order.shuffle(_rng);
    _pos = 0;
  }

  String? queueSource;

  Future<void> playQueue(List<Track> tracks, int startIndex,
      {String? source}) async {
    if (tracks.isEmpty) return;
    queueSource = source;
    _mirror = null;
    _queue = List.of(tracks);
    _manual = {};
    _pos = -1;
    _rebuildOrder(startIndex);
    await _playCurrent();
    _persistQueue();
  }

  Future<void> _playCurrent({Duration? start, bool autoplay = true}) async {
    _busyLoading = true;
    try {
      await _playCurrentInner(start: start, autoplay: autoplay);
    } finally {
      _busyLoading = false;
    }
  }

  Future<void> _playCurrentInner(
      {Duration? start, bool autoplay = true}) async {
    final t = _cur;
    if (t == null) return;
    _wantPlay = autoplay;
    final id = ++_loadId;
    _completionHandled = false;
    _loaded = false;
    _probe = null;
    _playerError = null;
    _pendingStart = start ?? Duration.zero;
    notifyListeners();
    final local = localPathResolver?.call(t.id);
    _playingLocal = local != null;
    final uri = local != null
        ? Uri.file(local)
        : (_useTranscoded
            ? _client.transcodedStreamUri(t.id, bitrate: _kbps * 1000)
            : _client.originalStreamUri(t.id));
    try {
      await _player.setAudioSource(
        AudioSource.uri(uri, headers: local == null ? _client.authHeaders : null),
        initialPosition: start,
      );
      if (id != _loadId) return;
      if (start != null &&
          start.inSeconds >= 1 &&
          (_player.position - start).abs() > const Duration(milliseconds: 1500)) {
        try {
          await _player.seek(start);
        } catch (_) {}
        if (id != _loadId) return;
      }
      _loaded = true;
      if (autoplay && _wantPlay) unawaited(_player.play());
      notifyListeners();
      if (local == null && !_useTranscoded) {
        Future.delayed(const Duration(seconds: 4), () {
          if (id != _loadId) return;
          _client
              .probeStream(uri, originalSize: t.file.sizeBytes)
              .then((p) {
            if (id == _loadId) {
              _probe = p;
              notifyListeners();
            }
          }).catchError((_) {});
        });
      }
    } on PlayerInterruptedException {
      return;
    } catch (e) {
      if (id == _loadId) {
        _playerError = 'Falha ao reproduzir: $e';
        notifyListeners();
      }
    }
  }

  void _onPlayerState(PlayerState s) {
    notifyListeners();
    if (!s.playing) _persistPosition();
    if (s.processingState == ProcessingState.completed && !_completionHandled) {
      _completionHandled = true;
      _onCompleted();
    }
  }

  Future<void> _onCompleted() async {
    if (_repeat == QueueRepeat.one) {
      await _player.seek(Duration.zero);
      _completionHandled = false;
      unawaited(_player.play());
      return;
    }
    await next(auto: true);
  }

  Future<void> play() async {
    if (_mirror != null) return _ctl('play');
    if (_cur == null) return;
    if (!_loaded) {
      await _playCurrent(start: _pendingStart);
      return;
    }
    _completionHandled = false;
    unawaited(_player.play());
  }

  Future<void> ensurePlaying() async {
    if (_mirror != null || _cur == null || !_wantPlay || _busyLoading) return;
    if (_playerError != null || !_loaded || !_player.playing) {
      await _playCurrent(start: _loaded ? _player.position : _pendingStart);
    }
  }

  Future<void> pause() {
    if (_mirror != null) return _ctl('pause');
    _wantPlay = false;
    notifyListeners();
    return _player.pause();
  }

  Future<void> togglePlay() {
    if (_mirror != null) return _ctl('toggle');
    if (_busyLoading && _wantPlay) {
      _wantPlay = false;
      notifyListeners();
      return Future.value();
    }
    return (_loaded && _player.playing) ? pause() : play();
  }

  Future<void> setVolume(double v, {bool persist = true}) async {
    _volume = v.clamp(0.0, 1.0).toDouble();
    await _player.setVolume(_volume);
    notifyListeners();
    if (persist) commitVolume();
  }

  Future<void> toggleMute() async {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      await setVolume(0);
    } else {
      await setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 1.0);
    }
  }

  Future<void> commitVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kVolume, _volume);
    } catch (_) {}
  }

  Future<void> _loadVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_kVolume);
      if (v == null) return;
      _volume = v;
      await _player.setVolume(v);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> next({bool auto = false}) async {
    if (_mirror != null) return _ctl('next');
    if (_order.isEmpty) return;
    if (_pos + 1 < _order.length) {
      _pos++;
      await _playCurrent();
    } else if (_repeat == QueueRepeat.all) {
      _restartOrder();
      await _playCurrent();
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
      _completionHandled = false;
    }
    _persistQueue();
  }

  Future<void> previous() async {
    if (_mirror != null) return _ctl('previous');
    if (_order.isEmpty) return;
    if (_player.position > const Duration(seconds: 3) || _pos <= 0) {
      if (_loaded) await _player.seek(Duration.zero);
      return;
    }
    _pos--;
    await _playCurrent();
    _persistQueue();
  }

  Future<void> seek(Duration d) async {
    if (_mirror != null) return _ctl('seek', d);
    if (_cur == null) return;
    if (!_loaded) {
      await _playCurrent(start: d, autoplay: false);
      return;
    }
    await _player.seek(d);
    _persistPosition();
    notifyListeners();
  }

  Future<void> stop() async {
    if (_loaded) _pendingStart = _player.position;
    await _player.stop();
    _loaded = false;
    notifyListeners();
  }

  Future<void> setTranscoded(bool v) => setStreamKbps(v ? 192 : 0);

  Future<void> restoreQuality() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final k = sp.getInt('stream_kbps');
      if (k != null) _kbps = k;
      _advanced = sp.getBool('advanced_opts') ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setStreamKbps(int kbps) async {
    if (kbps == _kbps) return;
    _kbps = kbps;
    try {
      (await SharedPreferences.getInstance()).setInt('stream_kbps', kbps);
    } catch (_) {}
    notifyListeners();
    if (_cur != null && _loaded && !_playingLocal) {
      await _playCurrent(start: _player.position, autoplay: _player.playing);
    }
  }

  void toggleShuffle() {
    if (_mirror != null) return;
    _shuffle = !_shuffle;
    _rebuildOrder(_pos >= 0 ? _order[_pos] : -1);
    _persistQueue();
    notifyListeners();
  }

  void cycleRepeat() {
    if (_mirror != null) return;
    _repeat = QueueRepeat.values[(_repeat.index + 1) % QueueRepeat.values.length];
    _persistQueue();
    notifyListeners();
  }

  Future<void> jumpToOrder(int p) async {
    if (p < 0 || p >= _order.length) return;
    _pos = p;
    await _playCurrent();
    _persistQueue();
  }

  Future<void> addToQueue(Track t) async {
    if (_queue.isEmpty) return playQueue([t], 0);
    _queue.add(t);
    _manual.add(_queue.length - 1);
    var at = _pos + 1;
    while (at < _order.length && _manual.contains(_order[at])) {
      at++;
    }
    _order.insert(at, _queue.length - 1);
    _persistQueue();
    notifyListeners();
  }

  Future<void> addAllToQueue(List<Track> ts) async {
    if (ts.isEmpty) return;
    if (_queue.isEmpty) return playQueue(ts, 0);
    var at = _pos + 1;
    while (at < _order.length && _manual.contains(_order[at])) {
      at++;
    }
    for (final t in ts) {
      _queue.add(t);
      _manual.add(_queue.length - 1);
      _order.insert(at++, _queue.length - 1);
    }
    _persistQueue(); // uma gravação só, em vez de uma por faixa
    notifyListeners();
  }

  void fillAround(Track current, List<Track> before, List<Track> after){
    if (_queue.length !=1 || _queue[0].id != current.id) return;
    _queue = [...before, _queue[0], ...after];
    _manual = {};
    _order = List<int>.generate(_queue.length, (i) => i);
    _pos = before.length;
    _persistQueue();
    notifyListeners();
  }

  Future<void> playNext(Track t) async {
    if (_queue.isEmpty) return playQueue([t], 0);
    _queue.add(t);
    _manual.add(_queue.length - 1);
    _order.insert(_pos + 1, _queue.length - 1);
    _persistQueue();
    notifyListeners();
  }

  Future<void> removeAt(int p) async {
    if (p < 0 || p >= _order.length) return;
    final qIdx = _order[p];
    final wasCurrent = p == _pos;
    _queue.removeAt(qIdx);
    _manual = {
      for (final m in _manual)
        if (m != qIdx) m > qIdx ? m - 1 : m
    };
    _order.removeAt(p);
    for (var i = 0; i < _order.length; i++) {
      if (_order[i] > qIdx) _order[i]--;
    }
    if (p < _pos) _pos--;
    if (wasCurrent) {
      if (_pos < _order.length) {
        await _playCurrent();
      } else {
        _pos = -1;
        await stop();
      }
    }
    _persistQueue();
    notifyListeners();
  }

  void reorder(int oldP, int newP) {
    if (newP > oldP) newP--;
    final item = _order.removeAt(oldP);
    _order.insert(newP, item);
    if (oldP == _pos) {
      _pos = newP;
    } else if (oldP < _pos && newP >= _pos) {
      _pos--;
    } else if (oldP > _pos && newP <= _pos) {
      _pos++;
    }
    _persistQueue();
    notifyListeners();
  }

  void clearUpcoming() {
    final cur = _cur;
    if (cur == null) return;
    _queue = [cur];
    _manual = {};
    _order = [0];
    _pos = 0;
    _persistQueue();
    notifyListeners();
  }

  Future<void> reset() async {
    _mirror = null;
    await _player.stop();
    _queue = [];
    _manual = {};
    _order = [];
    _pos = -1;
    _loaded = false;
    _pendingStart = Duration.zero;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kQueue);
      await prefs.remove(_kPos);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kQueue);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final queue = (j['queue'] as List)
          .cast<Map<String, dynamic>>()
          .map(Track.fromStored)
          .toList();
      final order = (j['order'] as List).cast<int>();
      final pos = j['pos'] as int;
      if (order.length != queue.length || pos >= order.length) {
        throw StateError('estado inválido');
      }
      _queue = queue;
      _manual = {...((j['manual'] as List?) ?? const []).cast<int>()};
      _order = order;
      _pos = pos;
      _shuffle = j['shuffle'] as bool;
      _repeat = QueueRepeat.values[j['repeat'] as int];
      _pendingStart = Duration(milliseconds: prefs.getInt(_kPos) ?? 0);
      _loaded = false;
      notifyListeners();
    } catch (_) {
      _queue = [];
      _order = [];
      _pos = -1;
    }
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kQueue,
        jsonEncode({
          'queue': _queue.map((t) => t.toJson()).toList(),
          'order': _order,
          'manual': _manual.toList(),
          'pos': _pos,
          'shuffle': _shuffle,
          'repeat': _repeat.index,
        }),
      );
    } catch (_) {}
  }

  Future<void> _persistPosition() async {
    if (!_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kPos, _player.position.inMilliseconds);
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker.cancel();
    _player.dispose();
    super.dispose();
  }
}
