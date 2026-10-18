import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_scope.dart';

/// Playlists marcadas para baixar: novas faixas entram na fila sozinhas.
class AutoDownload extends ChangeNotifier {
  AutoDownload._();
  static final instance = AutoDownload._();

  final Set<String> _ids = {};
  AppScope? _scope;
  Timer? _timer;
  bool _busy = false;

  bool enabled(String id) => _ids.contains(id);

  Future<void> start(AppScope scope) async {
    if (_scope != null) return;
    _scope = scope;
    try {
      final sp = await SharedPreferences.getInstance();
      _ids.addAll(sp.getStringList('auto_dl') ?? const []);
      notifyListeners();
    } catch (_) {}
    scope.reload.addListener(sync);
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => sync());
    unawaited(sync());
  }

  Future<void> toggle(String id) async {
    _ids.contains(id) ? _ids.remove(id) : _ids.add(id);
    notifyListeners();
    try {
      (await SharedPreferences.getInstance())
          .setStringList('auto_dl', _ids.toList());
    } catch (_) {}
    if (_ids.contains(id)) unawaited(sync());
  }

  Future<void> sync() async {
    final sc = _scope;
    if (sc == null || _busy || _ids.isEmpty || sc.client.session == null) return;
    _busy = true;
    try {
      for (final id in _ids.toList()) {
        try {
          final l = await sc.client.playlistTracks(id);
          sc.downloads.enqueue(l);
        } catch (_) {}
      }
    } finally {
      _busy = false;
    }
  }
}
