import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/models.dart';

class FavoritesService extends ChangeNotifier {
  FavoritesService(this._client);

  final JellyfinClient _client;
  final Set<String> _ids = {};
  final Map<String, bool> _outbox = {};
  List<Track> _tracks = [];
  String? _uid;
  bool _busy = false;
  bool _again = false;
  Timer? _debounce;

  List<Track> get tracks => List.unmodifiable(_tracks);
  static String _n(String id) => id.replaceAll('-', '').toLowerCase();
  bool isFavorite(String id) => _ids.contains(_n(id));

  /// Aplica mudanças vindas do WebSocket sem refazer a lista inteira.
  Future<void> applyUserData(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) {
      scheduleRefresh();
      return;
    }
    final fetch = <String>[];
    var changed = false;
    for (final c in changes) {
      final raw = c['ItemId'] as String?;
      final fav = c['IsFavorite'];
      if (raw == null || fav is! bool) continue;
      final id = _n(raw);
      if (_outbox.keys.any((k) => _n(k) == id)) continue;
      if (fav && !_ids.contains(id)) {
        fetch.add(raw);
      } else if (!fav && _ids.contains(id)) {
        _ids.remove(id);
        _tracks = _tracks.where((t) => _n(t.id) != id).toList();
        changed = true;
      }
    }
    if (fetch.isNotEmpty) {
      try {
        for (final t in await _client.tracksByIds(fetch)) {
          if (_ids.add(_n(t.id))) {
            _tracks = [t, ..._tracks];
            changed = true;
          }
        }
      } catch (_) {}
    }
    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  String get _kTracks => 'fav_tracks_$_uid';
  String get _kOutbox => 'fav_outbox_$_uid';

  Future<void> switchUser() async {
    _debounce?.cancel();
    _uid = _client.session?.userId;
    _ids.clear();
    _outbox.clear();
    _tracks = [];
    if (_uid != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_kTracks);
        if (raw != null) {
          _tracks = (jsonDecode(raw) as List)
              .map((e) => Track.fromStored(e as Map<String, dynamic>))
              .toList();
        }
        final ob = prefs.getString(_kOutbox);
        if (ob != null) {
          (jsonDecode(ob) as Map<String, dynamic>)
              .forEach((k, v) => _outbox[k] = v as bool);
        }
      } catch (_) {}
      _ids.addAll(_tracks.map((t) => _n(t.id)));
    }
    notifyListeners();
    unawaited(refresh());
  }

  void scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), refresh);
  }

  Future<void> toggle(Track t) async {
    final fav = !_ids.contains(_n(t.id));
    _apply(t, fav);
    _outbox[t.id] = fav;
    notifyListeners();
    await _persist();
    await _flush();
    await _persist();
  }

  void _apply(Track t, bool fav) {
    if (fav) {
      if (_ids.add(_n(t.id))) _tracks = [t, ..._tracks];
    } else {
      _ids.remove(_n(t.id));
      _tracks = _tracks.where((x) => x.id != t.id).toList();
    }
  }

  Future<void> _flush() async {
    for (final e in _outbox.entries.toList()) {
      try {
        final code = await _client.setFavorite(e.key, e.value);
        if ((code >= 200 && code < 300) || code == 400 || code == 403 || code == 404) {
          _outbox.remove(e.key);
        } else {
          return;
        }
      } catch (_) {
        return;
      }
    }
  }

  Future<void> refresh() async {
    if (_client.session == null || _uid != _client.session!.userId) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _flush();
        try {
          final server = await _client.favoriteTracks();
          final byId = {for (final t in _tracks) t.id: t};
          final list = <Track>[];
          for (final t in server) {
            if (_outbox[t.id] == false) continue;
            list.add(t);
          }
          for (final e in _outbox.entries) {
            if (e.value && !list.any((t) => t.id == e.key)) {
              final t = byId[e.key];
              if (t != null) list.insert(0, t);
            }
          }
          _tracks = list;
          _ids
            ..clear()
            ..addAll(list.map((t) => _n(t.id)));
          notifyListeners();
        } catch (_) {}
      } while (_again);
    } finally {
      _busy = false;
    }
    await _persist();
  }

  Future<void> _persist() async {
    if (_uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kTracks, jsonEncode(_tracks.map((t) => t.toJson()).toList()));
      await prefs.setString(_kOutbox, jsonEncode(_outbox));
    } catch (_) {}
  }
}
