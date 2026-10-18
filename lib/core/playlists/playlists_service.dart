import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/models.dart';

class PlaylistsService extends ChangeNotifier {
  PlaylistsService(this._client);

  final JellyfinClient _client;
  List<PlaylistInfo> _lists = [];
  String? _uid;
  bool _busy = false;
  Timer? _debounce;

  List<PlaylistInfo> get playlists => List.unmodifiable(_lists);
  String get _key => 'playlists_$_uid';

  Future<void> switchUser() async {
    _debounce?.cancel();
    _uid = _client.session?.userId;
    _lists = [];
    if (_uid != null) {
      try {
        final raw = (await SharedPreferences.getInstance()).getString(_key);
        if (raw != null) {
          _lists = (jsonDecode(raw) as List)
              .map((e) => PlaylistInfo.fromStored(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }
    notifyListeners();
    unawaited(refresh());
  }

  void scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), refresh);
  }

  Future<void> refresh() async {
    if (_client.session == null || _uid != _client.session!.userId || _busy) {
      return;
    }
    _busy = true;
    try {
      _lists = await _client.playlists();
      notifyListeners();
      (await SharedPreferences.getInstance()).setString(
          _key, jsonEncode(_lists.map((e) => e.toJson()).toList()));
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<String?> _run(Future<void> Function() op) async {
    try {
      await op();
      await refresh();
      return null;
    } on JellyfinException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sem conexão com o servidor.';
    }
  }

  Future<String?> create(String name, List<Track> tracks) => _run(() async {
        await _client.createPlaylist(name.trim(), tracks.map((t) => t.id).toList());
      });

  Future<String?> add(String playlistId, List<Track> tracks) => _run(
      () => _client.addToPlaylist(playlistId, tracks.map((t) => t.id).toList()));

  Future<String?> removeEntry(String playlistId, Track t) =>
      _run(() => _client.removeFromPlaylist(playlistId, [t.playlistItemId!]));

  Future<String?> move(String playlistId, Track t, int index) =>
      _run(() => _client.movePlaylistItem(playlistId, t.playlistItemId!, index));

  Future<String?> rename(String playlistId, String name) =>
      _run(() => _client.renamePlaylist(playlistId, name.trim()));

  Future<String?> delete(String playlistId) =>
      _run(() => _client.deletePlaylist(playlistId));
}
