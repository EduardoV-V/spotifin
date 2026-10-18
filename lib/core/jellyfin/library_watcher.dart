import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/io.dart';

import 'jellyfin_client.dart';

/// Avisa via [reload] quando a biblioteca do Jellyfin muda.
/// Usa WebSocket; se não conectar (ex.: proxy sem suporte), consulta a cada 90 s.
class LibraryWatcher with WidgetsBindingObserver {
  LibraryWatcher(this._client, this._reload);

  final JellyfinClient _client;
  final ValueNotifier<int> _reload;
  void Function(List<Map<String, dynamic>> changes)? onUserDataChanged;
  void Function(Map<String, dynamic> data)? onRemotePlay;
  void Function(Map<String, dynamic> data)? onRemotePlaystate;
  VoidCallback? onConnected;
  void Function(List<Map<String, dynamic>> sessions)? onSessions;
  bool _sessionsOn = true;

  void setSessionsPush(bool on) {
    if (_sessionsOn == on) return;
    _sessionsOn = on;
    if (_connected) {
      _send({'MessageType': on ? 'SessionsStart' : 'SessionsStop', if (on) 'Data': '0,2000'});
    }
  }

  IOWebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _keepAlive;
  Timer? _retry;
  Timer? _debounce;
  Timer? _poll;
  int _attempt = 0;
  int? _lastCount;
  bool _running = false;
  bool _connected = false;
  DateTime? _pausedAt;

  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _connect();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 90), (_) => _pollOnce());
  }

  void stop() {
    _running = false;
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    _debounce?.cancel();
    _poll?.cancel();
    _close();
  }

  void restart() {
    _close();
    _attempt = 0;
    _lastCount = null;
    if (_running) {
      _connect();
    } else {
      start();
    }
  }

  void _connect() {
    final s = _client.session;
    if (s == null) return;
    final u = Uri.parse(s.serverUrl);
    final uri = Uri(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      host: u.host,
      port: u.port,
      path: '${u.path}/socket',
      queryParameters: {'deviceId': s.deviceId},
    );
    try {
      final ch = IOWebSocketChannel.connect(uri, headers: _client.authHeaders);
      _ch = ch;
      ch.ready.then((_) {}, onError: (_) {
        if (_ch == ch) _scheduleRetry();
      });
      _sub = ch.stream.listen(
        _onMessage,
        onError: (_) {
          if (_ch == ch) _scheduleRetry();
        },
        onDone: () {
          if (_ch == ch) _scheduleRetry();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onMessage(dynamic raw) {
    _connected = true;
    _attempt = 0;
    _lastCount = null;
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (j['MessageType']) {
        case 'ForceKeepAlive':
          final sec = (j['Data'] as num?)?.toInt() ?? 60;
          _keepAlive?.cancel();
          _keepAlive = Timer.periodic(
              Duration(seconds: (sec ~/ 2).clamp(5, 60).toInt()),
              (_) => _send({'MessageType': 'KeepAlive'}));
          _send({'MessageType': 'KeepAlive'});
          if (_sessionsOn) _send({'MessageType': 'SessionsStart', 'Data': '0,2000'});
          onConnected?.call();
        case 'Sessions':
          final d = j['Data'];
          if (d is List) {
            onSessions?.call(d.whereType<Map<String, dynamic>>().toList());
          }
        case 'Play':
          final d = j['Data'];
          if (d is Map<String, dynamic>) onRemotePlay?.call(d);
        case 'Playstate':
          final d = j['Data'];
          if (d is Map<String, dynamic>) onRemotePlaystate?.call(d);
        case 'UserDataChanged':
          final data = j['Data'];
          final list = data is Map ? data['UserDataList'] : null;
          onUserDataChanged?.call(list is List
              ? list.whereType<Map<String, dynamic>>().toList()
              : const []);
        case 'LibraryChanged':
          _debounce?.cancel();
          _debounce = Timer(const Duration(seconds: 4), () => _reload.value++);
      }
    } catch (_) {}
  }

  void _send(Map<String, dynamic> m) {
    try {
      _ch?.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  void _close() {
    _connected = false;
    _keepAlive?.cancel();
    _sub?.cancel();
    _sub = null;
    final ch = _ch;
    _ch = null;
    try {
      ch?.sink.close();
    } catch (_) {}
  }

  void _scheduleRetry() {
    if (!_running) return;
    _close();
    _retry?.cancel();
    final delay = Duration(seconds: 2 << _attempt.clamp(0, 5));
    _attempt++;
    _retry = Timer(delay, _connect);
  }

  Future<void> _pollOnce() async {
    if (_connected || _client.session == null) return;
    onUserDataChanged?.call(const []);
    try {
      final n = await _client.trackCount();
      if (_lastCount != null && n != _lastCount) _reload.value++;
      _lastCount = n;
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _running) {
      final away = _pausedAt == null
          ? Duration.zero
          : DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (!_connected || away > const Duration(seconds:30)) restart();
      if (away > const Duration(minutes: 1)) _reload.value++;
    }
  }
}
