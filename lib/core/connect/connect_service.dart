import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../audio/player_service.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/models.dart';

class RemoteDevice {
  final String id;
  final String deviceId;
  final String name;
  final Track? track;
  final bool paused;
  final int posMs;
  final int durMs;
  final DateTime activity;
  const RemoteDevice({
    required this.activity,
    required this.id,
    required this.deviceId,
    required this.name,
    required this.track,
    required this.paused,
    required this.posMs,
    required this.durMs,
  });

  bool get playing => track != null && !paused;
}

class _Source {
  final List<String> ids;
  final int index;
  final int posMs;
  final bool shuffle;
  final int repeat;
  const _Source(this.ids, this.index, this.posMs, this.shuffle, this.repeat);
}

class ConnectService extends ChangeNotifier with WidgetsBindingObserver {
  ConnectService(this._client, this._player);

  final JellyfinClient _client;
  final PlayerService _player;
  void Function(String)? onNotice;
  void Function(bool on)? onSessionsPush;
  String _devSig = '';

  List<RemoteDevice> devices = [];
  bool online = true;
  bool offlineMode = false;

  Timer? _timer;
  bool _fg = true;
  bool _busy = false;
  bool _sw = false;
  bool get _switching => _sw;
  set _switching(bool v) {
    if (_sw == v) return;
    _sw = v;
    notifyListeners();
  }

  bool get transferring => _sw;
  bool _lastLocalPlaying = false;
  int _fails = 0;
  int _n = 0;
  DateTime _grace = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastIngest = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCaps = DateTime.fromMillisecondsSinceEpoch(0);

  void _ensureCaps({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastCaps).inSeconds < 20) return;
    _lastCaps = now;
    unawaited(_client.postCapabilities().catchError((_) {}));
  }

  bool get canConnect => online && !offlineMode && _client.session != null;
  String get myName => _client.deviceName;

  static String _norm(String? s) => (s ?? '').replaceAll('-', '').toLowerCase();

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _player.addListener(_onPlayer);
    _player.onMirrorControl = _control;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _n++;
      final every = _player.isMirror ? 2 : 4;
      final fresh =
          DateTime.now().difference(_lastIngest).inSeconds < every;
      if ((_fg || _player.localPlaying) && !fresh) unawaited(poll());
    });
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_onPlayer);
    _timer?.cancel();
  }

  void reset() {
    devices = [];
    online = true;
    _player.setMirror(null);
    notifyListeners();
    unawaited(poll());
  }

  void announce() {
    if (_client.session == null) return;
    _ensureCaps(force: true);
    unawaited(poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _fg = state == AppLifecycleState.resumed;
    onSessionsPush?.call(_fg || _player.localPlaying);
    if (_fg) {
      _ensureCaps(force: true);
      unawaited(poll());
    }
  }

  void _onPlayer() {
    final lp = _player.localPlaying;
    if (lp && !_lastLocalPlaying && !_switching && !_player.isMirror) {
      for (final d in devices.where((d) => d.playing)) {
        unawaited(_client.sendPlaystate(d.id, 'Pause').catchError((_) {}));
      }
    }
    _lastLocalPlaying = lp;
  }

  Future<void> poll() async {
    if (_client.session == null || _busy || _switching || offlineMode) return;
    _busy = true;
    try {
      final raw = await _client.sessions();
      online = true;
      _fails = 0;
      _ingest(raw);
    } catch (_) {
      if (++_fails >= 3 && online) {
        online = false;
        if (_player.isMirror) _player.setMirror(null);
        notifyListeners();
      }
    } finally {
      _busy = false;
    }
  }

  void ingestPush(List<Map<String, dynamic>> raw) {
    if (_switching || offlineMode || _client.session == null) return;
    online = true;
    _fails = 0;
    _ingest(raw);
  }

  void _ingest(List<Map<String, dynamic>> raw) {
    final me = _client.session;
    if (me == null) return;
    _lastIngest = DateTime.now();
    final byDevice = <String, RemoteDevice>{};
    final mine = raw.where((m) => m['DeviceId'] == me.deviceId).toList();
    if (mine.isEmpty ||
        mine.any((m) => m['SupportsRemoteControl'] != true)) {
      _ensureCaps();
    } else if (DateTime.now().difference(_lastCaps).inSeconds > 90) {
      _ensureCaps();
    }
    for (final m in raw) {
      if (m['DeviceId'] == me.deviceId) continue;
      if (m['SupportsRemoteControl'] != true) continue;
      if (_norm(m['UserId'] as String?) != _norm(me.userId)) continue;
      final item = m['NowPlayingItem'];
      final ps = m['PlayState'];
      final dev = RemoteDevice(
        activity: DateTime.tryParse((m['LastPlaybackCheckIn'] ??
                    m['LastActivityDate'] ??
                    '')
                .toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        id: m['Id'] as String,
        deviceId: m['DeviceId'] as String,
        name: (m['DeviceName'] as String?) ?? (m['Client'] as String?) ?? '?',
        track: item is Map<String, dynamic> ? Track.fromJson(item) : null,
        paused: !(ps is Map && ps['IsPaused'] == false),
        posMs:
            (ps is Map ? (ps['PositionTicks'] as num?)?.toInt() ?? 0 : 0) ~/ 10000,
        durMs: (item is Map ? (item['RunTimeTicks'] as num?)?.toInt() ?? 0 : 0) ~/ 10000,
      );
      final prev = byDevice[dev.deviceId];
      if (prev == null || dev.activity.isAfter(prev.activity)) {
        byDevice[dev.deviceId] = dev;
      }
    }
    devices = byDevice.values.toList();
    final sig = devices
        .map((d) => '${d.id}|${d.name}|${d.track?.id}|${d.paused}')
        .join(',');
    final changed = sig != _devSig;
    _devSig = sig;
    _updateMirror();
    if (changed) notifyListeners();
  }

  MirrorState _mirrorOf(RemoteDevice d) => MirrorState(
        sessionId: d.id,
        deviceId: d.deviceId,
        deviceName: d.name,
        track: d.track!,
        durationMs: d.durMs > 0
            ? d.durMs
            : (d.track!.duration?.inMilliseconds ?? 0),
        positionMs: d.posMs,
        paused: d.paused,
        at: DateTime.now(),
      );

  void _updateMirror() {
    final m = _player.mirror;
    if (_player.localActive) {
      if (m != null) _player.setMirror(null);
      return;
    }
    final playingNow = devices.where((d) => d.playing).toList()
      ..sort((a, b) => b.activity.compareTo(a.activity));
    RemoteDevice? cur;
    if (m != null) {
      cur = devices.where((d) => d.id == m.sessionId).firstOrNull;
      if (DateTime.now().isBefore(_grace)) {
        if (cur != null && cur.playing && cur.track!.id == m.track.id) {
          _grace = DateTime.fromMillisecondsSinceEpoch(0);
          _player.updateMirror(_mirrorOf(cur));
        }
        return;
      }
    }
    RemoteDevice? target;
    if (cur != null && cur.track != null && (cur.playing || playingNow.isEmpty)) {
      target = cur;
    } else if (playingNow.isNotEmpty) {
      target = playingNow.first;
    }
    if (target == null) {
      if (m != null) _player.setMirror(null);
      return;
    }
    _player.updateMirror(_mirrorOf(target));
  }

  Future<_Source> _sourceFromMirror(MirrorState m) async {
    var ids = [m.track.id];
    var idx = 0;
    var shuffle = false;
    var repeat = 0;
    try {
      final raw = await _client.readPlayState();
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        {
          final l = (j['ids'] as List).cast<String>();
          final i = l.indexWhere((e) => _norm(e) == _norm(m.track.id));
          if (i >= 0) {
            ids = l;
            idx = i;
            shuffle = (j['shuffle'] as bool?) ?? false;
            repeat = (j['repeat'] as int?) ?? 0;
          }
        }
      }
    } catch (_) {}
    return _Source(ids, idx, m.position.inMilliseconds, shuffle, repeat);
  }

  _Source _sourceFromLocal() {
    final tracks = _player.orderedTracks;
    final pos = _player.orderPos < 0 ? 0 : _player.orderPos;
    final ids = tracks.skip(pos).take(150).map((t) => t.id).toList();
    return _Source(ids, 0, _player.position.inMilliseconds, _player.shuffle,
        _player.repeat.index);
  }

  Future<void> _startProgressive(List<String> ids, int idx, int posMs, {bool shuffle = false, QueueRepeat repeat = QueueRepeat.off}) async {
    final first = await _client.tracksByIds([ids[idx]]);
    if (first.isEmpty) throw JellyfinException('Faixas não encontradas.');
    _player.setMirror(null);
    await _player.loadRemote(first, 0, Duration(milliseconds: posMs), shuffle: shuffle, repeat: repeat);
    await _player.play();
    unawaited(() async {
      try {
        final before = await _client.tracksByIds(ids.sublist(0, idx));
        final after = await _client.tracksByIds(ids.sublist(idx + 1));
        _player.fillAround(first.first, before, after);
      } catch (_) {}
    }());
  }

  Future<void> _fillFromState(MirrorState m) async {
    try {
      var src = await _sourceFromMirror(m);
      if (src.ids.length < 2) {
        await Future.delayed(const Duration(milliseconds: 1500));
        src = await _sourceFromMirror(m);
      }
      if (src.ids.length < 2) return;
      final before = await _client.tracksByIds(src.ids.sublist(0, src.index));
      final after = await _client.tracksByIds(src.ids.sublist(src.index + 1));
      _player.fillAround(m.track, before, after);
    } catch (_) {}
  }

  Future<void> _takeLocal(MirrorState m, String cmd, Duration? seek) async {
    if (cmd != 'next' && cmd != 'previous') {
      final pos = cmd == 'seek'
          ? (seek?.inMilliseconds ?? m.position.inMilliseconds)
          : m.position.inMilliseconds;
      unawaited(_client.sendPlaystate(m.sessionId, 'Pause').catchError((_) {}));
      _player.setMirror(null);
      await _player.loadRemote([m.track], 0, Duration(milliseconds: pos),
          shuffle: false, repeat: QueueRepeat.off);
      await _player.play();
      unawaited(_fillFromState(m));
      return;
    }
    final src = await _sourceFromMirror(m);
    var idx = src.index;
    var pos = src.posMs;
    switch (cmd) {
      case 'next':
        if (idx + 1 < src.ids.length) idx++;
        pos = 0;
      case 'previous':
        if (pos > 3000 || idx <= 0) {
          pos = 0;
        } else {
          idx--;
          pos = 0;
        }
      case 'seek':
        pos = seek?.inMilliseconds ?? pos;
    }
    await _startProgressive(src.ids, idx, pos,
        shuffle: src.shuffle,
        repeat: QueueRepeat.values[src.repeat.clamp(0, 2)]);
    unawaited(_client.sendPlaystate(m.sessionId, 'Pause').catchError((_) {}));
  }

  Future<void> _control(String cmd, Duration? seek) async {
    final m = _player.mirror;
    if (m == null) return;
    _switching = true;
    try {
      _player.setMirror(m.copyWith(
          paused: false, positionMs: m.position.inMilliseconds, at: DateTime.now()));
      await _takeLocal(m, cmd, seek);
    } catch (_) {
      onNotice?.call('Não foi possível assumir a reprodução.');
    } finally {
      _switching = false;
    }
  }

  Future<String?> transferTo(RemoteDevice? target) async {
    if (!canConnect) return 'Sem conexão com o servidor.';
    final m = _player.mirror;
    _switching = true;
    try {
      if (target == null) {
        if (m != null) await _takeLocal(m, 'play', null);
        return null;
      }
      if (m != null && m.sessionId == target.id) return null;
      final cur = _player.current;
      if (cur == null) return 'Nada para transferir.';
      if (m==null) await _player.pause();
      final src = m == null ? _sourceFromLocal() : await _sourceFromMirror(m);
      final ids = src.ids.sublist(src.index);
      try{
        await _client.sendPlay(target.id, ids, src.posMs);
      } catch(_){
        if (m == null) unawaited(_player.play());
        rethrow;
      }
      if (m != null){
        unawaited(_client.sendPlaystate(m.sessionId, 'Pause').catchError((_){}));
      }
      _grace = DateTime.now().add(const Duration(seconds: 8));
      for (final ms in const [800,1600,3000]) {
        Future.delayed(Duration(milliseconds: ms), () => unawaited(poll()));
      }
      _player.setMirror(MirrorState(
        sessionId: target.id,
        deviceId: target.deviceId,
        deviceName: target.name,
        track: cur,
        durationMs: cur.duration?.inMilliseconds ?? 0,
        positionMs: src.posMs,
        paused: false,
        at: DateTime.now(),
      ));
      return null;
    } on JellyfinException catch (e) {
      return e.message;
    } catch (_) {
      return 'Falha ao transferir a reprodução.';
    } finally {
      _switching = false;
    }
  }

  Future<void> handlePlay(Map<String, dynamic> d) async {
    final ids = (d['ItemIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (ids.isEmpty) return;
    final cmd = (d['PlayCommand'] ?? 'PlayNow').toString();
    final startIdx = (d['StartIndex'] as num?)?.toInt() ?? 0;
    final posMs = ((d['StartPositionTicks'] as num?)?.toInt() ?? 0) ~/ 10000;
    try {
      if (cmd == 'PlayNext' || cmd == 'PlayLast') {
        final tracks = await _client.tracksByIds(ids);
        if (tracks.isEmpty) return;
        if (cmd == 'PlayNext') {
          for (final t in tracks.reversed) {
            await _player.playNext(t);
          }
        } else {
          await _player.addAllToQueue(tracks);
        }
        return;
      }
      _switching = true;
      await _startProgressive(ids, startIdx.clamp(0, ids.length - 1), posMs);
    } catch (_) {
    } finally {
      _switching = false;
    }
  }
  Future<void> handlePlaystate(Map<String, dynamic> d) async {
    if (_player.isMirror) return;
    switch (d['Command']) {
      case 'Pause':
        await _player.pause();
      case 'Unpause':
        await _player.play();
      case 'PlayPause':
        await _player.togglePlay();
      case 'Stop':
        await _player.stop();
      case 'NextTrack':
        await _player.next();
      case 'PreviousTrack':
        await _player.previous();
      case 'Seek':
        final t = (d['SeekPositionTicks'] as num?)?.toInt();
        if (t != null) await _player.seek(Duration(microseconds: t ~/ 10));
    }
  }
}
