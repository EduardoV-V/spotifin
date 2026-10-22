import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/models.dart';
import '../net/connectivity_service.dart';
import '../sync/outbox.dart';

class PlaylistsService extends ChangeNotifier {
  PlaylistsService(this._client, {OutboxService? outbox, ConnectivityService? conn})
      : _outbox = outbox,
        _conn = conn;

  final JellyfinClient _client;
  final OutboxService? _outbox;
  final ConnectivityService? _conn;
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
      if (_outbox != null && _outbox!.pending > 0 && _online) {
        await _outbox!.flush();
      }
      final remote = await _client.playlists();
      // Playlists criadas offline e ainda não enviadas continuam na lista.
      _lists = [...remote, ...?_outbox?.pendingCreates()];
      notifyListeners();
      await _saveLists();
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  bool get _online => _conn == null || _conn!.online;

  Future<void> _saveLists() async {
    try {
      (await SharedPreferences.getInstance()).setString(
          _key, jsonEncode(_lists.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// Executa [op] no servidor; sem conexão (ou falha de rede) aplica [local]
  /// no cache, enfileira [type]/[data] no outbox e devolve null (sucesso).
  Future<String?> _run(
    Future<void> Function() op,
    String type,
    Map<String, dynamic> data,
    Future<void> Function() local,
  ) async {
    final pid = data['pid'] as String?;
    final queued = _outbox != null &&
        pid != null &&
        (pid.startsWith('local-') || _outbox!.hasPendingFor(pid));
    if ((_online || _outbox == null) && !queued) {
      try {
        await op();
        await refresh();
        return null;
      } on JellyfinException catch (e) {
        return e.message;
      } catch (e) {
        if (_outbox == null || !JellyfinClient.isNetworkError(e)) {
          return 'Sem conexão com o servidor.';
        }
      }
    }
    await local();
    await _outbox!.enqueue(type, data);
    notifyListeners();
    if (_online) unawaited(_outbox!.flush().then((_) => refresh()));
    return null;
  }

  Future<List<Track>> _cached(String pid) async =>
      (await _client.cachedPlaylistTracks(pid)) ?? <Track>[];

  void _setCount(String pid, int count) {
    _lists = [
      for (final p in _lists)
        p.id == pid ? PlaylistInfo(p.id, p.name, count) : p
    ];
  }

  Future<String?> create(String name, List<Track> tracks) async {
    final n = name.trim();
    final ids = tracks.map((t) => t.id).toList();
    if (_online || _outbox == null) {
      try {
        await _client.createPlaylist(n, ids);
        await refresh();
        return null;
      } on JellyfinException catch (e) {
        return e.message;
      } catch (e) {
        if (_outbox == null || !JellyfinClient.isNetworkError(e)) {
          return 'Sem conexão com o servidor.';
        }
      }
    }
    final temp = 'local-${DateTime.now().millisecondsSinceEpoch}';
    _lists = [..._lists, PlaylistInfo(temp, n, tracks.length)];
    await _saveLists();
    await _client.putPlaylistTracks(temp, tracks);
    await _outbox!
        .enqueue('pl_create', {'tempId': temp, 'name': n, 'trackIds': ids});
    notifyListeners();
    return null;
  }

  Future<String?> add(String playlistId, List<Track> tracks) => _run(
        () => _client.addToPlaylist(playlistId, tracks.map((t) => t.id).toList()),
        'pl_add',
        {'pid': playlistId, 'trackIds': tracks.map((t) => t.id).toList()},
        () async {
          final cur = await _cached(playlistId);
          final next = [...cur, ...tracks];
          await _client.putPlaylistTracks(playlistId, next);
          _setCount(playlistId, next.length);
          await _saveLists();
        },
      );

  /// Alguns servidores Jellyfin apagam todas as cópias de uma faixa repetida;
  /// aqui as cópias que sobraram são recolocadas nas posições originais.
  Future<void> _removeKeepingDuplicates(String pid, Track t) async {
    List<Track>? before;
    try {
      before = await _client.playlistTracksRemote(pid);
    } catch (_) {}
    var id = t.playlistItemId;
    id ??= before
        ?.where((x) => Track.key(x.id) == Track.key(t.id))
        .firstOrNull
        ?.playlistItemId;
    if (id == null) return;
    await _client.removeFromPlaylist(pid, [id]);
    if (before == null) return;
    final idx = before.indexWhere((x) => x.playlistItemId == id);
    if (idx < 0) return;
    final key = Track.key(before[idx].id);
    final rest = [...before]..removeAt(idx);
    final pos = <int>[
      for (var i = 0; i < rest.length; i++)
        if (Track.key(rest[i].id) == key) i
    ];
    if (pos.isEmpty) return;
    final after = await _client.playlistTracksRemote(pid);
    if (after.any((x) => Track.key(x.id) == key)) return;
    await _client.addToPlaylist(pid, List.filled(pos.length, before[idx].id));
    final now = await _client.playlistTracksRemote(pid);
    if (now.length < pos.length) return;
    final fresh = now.sublist(now.length - pos.length);
    for (var i = 0; i < pos.length; i++) {
      final e = fresh[i].playlistItemId;
      if (e != null) await _client.movePlaylistItem(pid, e, pos[i]);
    }
  }

  Future<String?> removeEntry(String playlistId, Track t) => _run(
        () => _removeKeepingDuplicates(playlistId, t),
        'pl_remove',
        {'pid': playlistId, 'itemId': t.playlistItemId, 'trackId': t.id},
        () async {
          final cur = await _cached(playlistId);
          final next = [
            for (final x in cur)
              if (!(t.playlistItemId != null
                  ? x.playlistItemId == t.playlistItemId
                  : x.id == t.id))
                x
          ];
          await _client.putPlaylistTracks(playlistId, next);
          _setCount(playlistId, next.length);
          await _saveLists();
        },
      );

  Future<String?> move(String playlistId, Track t, int index) => _run(
        () => _client.movePlaylistItem(playlistId, t.playlistItemId!, index),
        'pl_move',
        {
          'pid': playlistId,
          'itemId': t.playlistItemId,
          'trackId': t.id,
          'index': index
        },
        () async {
          final cur = await _cached(playlistId);
          final i = cur.indexWhere((x) => t.playlistItemId != null
              ? x.playlistItemId == t.playlistItemId
              : x.id == t.id);
          if (i < 0) return;
          final item = cur.removeAt(i);
          cur.insert(index.clamp(0, cur.length), item);
          await _client.putPlaylistTracks(playlistId, cur);
        },
      );

  Future<String?> rename(String playlistId, String name) => _run(
        () => _client.renamePlaylist(playlistId, name.trim()),
        'pl_rename',
        {'pid': playlistId, 'name': name.trim()},
        () async {
          _lists = [
            for (final p in _lists)
              p.id == playlistId ? PlaylistInfo(p.id, name.trim(), p.count) : p
          ];
          await _saveLists();
        },
      );

  Future<String?> delete(String playlistId) => _run(
        () => _client.deletePlaylist(playlistId),
        'pl_delete',
        {'pid': playlistId},
        () async {
          _lists = _lists.where((p) => p.id != playlistId).toList();
          await _saveLists();
        },
      );
}
