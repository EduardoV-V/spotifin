import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../jellyfin/jellyfin_client.dart';

/// Estado de conexão com o servidor Jellyfin (sem plugin: testa o servidor
/// periodicamente e reage a falhas de rede reportadas pelo cliente).
class ConnectivityService extends ChangeNotifier {
  ConnectivityService(this._client) {
    _client.onNetworkError = reportFailure;
  }

  static const _kForce = 'offline_forced';
  final JellyfinClient _client;
  bool _reachable = true;
  bool _forced = false;
  bool _checking = false;
  Timer? _timer;

  bool get online => _reachable && !_forced;
  bool get offline => !online;
  bool get forced => _forced;

  Future<void> start() async {
    try {
      _forced = (await SharedPreferences.getInstance()).getBool(_kForce) ?? false;
    } catch (_) {}
    _client.offlineForced = _forced;
    notifyListeners();
    unawaited(check());
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, check);
  }

  Future<void> check() async {
    if (_checking) return;
    if (_client.session == null || _forced) {
      _schedule(const Duration(seconds: 30));
      return;
    }
    _checking = true;
    final ok = await _client.pingSession();
    _checking = false;
    _set(ok);
    _schedule(Duration(seconds: ok ? 20 : 6));
  }

  void _set(bool ok) {
    if (ok == _reachable) return;
    _reachable = ok;
    notifyListeners();
  }

  /// Uma requisição falhou por rede: marca offline e confirma logo.
  void reportFailure() {
    if (_reachable && !_forced) {
      _reachable = false;
      notifyListeners();
    }
    _schedule(const Duration(seconds: 3));
  }

  Future<void> setForced(bool v) async {
    _forced = v;
    _client.offlineForced = v;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_kForce, v);
    } catch (_) {}
    if (!v) {
      _reachable = true;
      unawaited(check());
    }
  }
}
