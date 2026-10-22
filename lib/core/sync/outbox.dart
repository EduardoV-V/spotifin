import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/models.dart';
import '../net/connectivity_service.dart';

class OutboxOp {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final int at;
  int retries;
  OutboxOp(this.id, this.type, this.data, this.at, [this.retries = 0]);

  Map<String, dynamic> toJson() =>
      {'id': id, 't': type, 'd': data, 'at': at, 'r': retries};
  factory OutboxOp.fromJson(Map<String, dynamic> j) => OutboxOp(
      j['id'] as String,
      j['t'] as String,
      Map<String, dynamic>.from(j['d'] as Map),
      j['at'] as int,
      (j['r'] as int?) ?? 0);
}

/// Fila de operações feitas sem conexão (playlists). Persistida por usuário e
/// reenviada em ordem quando o servidor volta. Favoritos têm fila própria.
class OutboxService extends ChangeNotifier {
  OutboxService(this._client, this._conn) {
    _client.playlistPending = hasPendingFor;
  }

  final JellyfinClient _client;
  final ConnectivityService _conn;
  final List<OutboxOp> _ops = [];
  Map<String, String> _idMap = {}; // id temporário -> id real
  String? _uid;
  bool _flushing = false;
  int _seq = 0;

  /// Chamado depois de um envio que mudou algo no servidor.
  VoidCallback? onFlushed;

  int get pending => _ops.length;
  List<OutboxOp> get ops => List.unmodifiable(_ops);

  String _real(String id) => _idMap[id] ?? id;

  bool hasPendingFor(String playlistId) => _ops.any((o) =>
      o.data['pid'] == playlistId ||
      o.data['tempId'] == playlistId ||
      (_idMap[o.data['pid']] == playlistId));

  /// Playlists criadas offline que ainda não existem no servidor.
  List<PlaylistInfo> pendingCreates() => [
        for (final o in _ops)
          if (o.type == 'pl_create')
            PlaylistInfo(o.data['tempId'] as String, o.data['name'] as String,
                (o.data['trackIds'] as List).length)
      ];

  String get _kOps => 'outbox_$_uid';
  String get _kMap => 'outbox_map_$_uid';

  Future<void> switchUser() async {
    _uid = _client.session?.userId;
    _ops.clear();
    _idMap = {};
    if (_uid != null) {
      try {
        final sp = await SharedPreferences.getInstance();
        final raw = sp.getString(_kOps);
        if (raw != null) {
          _ops.addAll((jsonDecode(raw) as List)
              .map((e) => OutboxOp.fromJson(e as Map<String, dynamic>)));
        }
        final m = sp.getString(_kMap);
        if (m != null) {
          _idMap = Map<String, String>.from(jsonDecode(m) as Map);
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kOps, jsonEncode(_ops.map((e) => e.toJson()).toList()));
      await sp.setString(_kMap, jsonEncode(_idMap));
    } catch (_) {}
  }

  Future<void> enqueue(String type, Map<String, dynamic> data) async {
    _ops.add(OutboxOp(
        '${DateTime.now().microsecondsSinceEpoch}_${_seq++}',
        type,
        data,
        DateTime.now().millisecondsSinceEpoch));
    notifyListeners();
    await _persist();
  }

  static int? _httpCode(Object e) {
    final m = RegExp(r'HTTP (\d{3})').firstMatch('$e');
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  Future<void> flush() async {
    if (_flushing || _ops.isEmpty || _conn.offline || _client.session == null) {
      return;
    }
    _flushing = true;
    var changed = false;
    try {
      while (_ops.isNotEmpty) {
        final op = _ops.first;
        try {
          await _exec(op);
          changed = true;
        } catch (e) {
          if (JellyfinClient.isNetworkError(e)) {
            _conn.reportFailure();
            break;
          }
          final code = _httpCode(e);
          // 4xx (exceto timeout/limite): operação inválida, descarta.
          if (code != null && code >= 400 && code < 500 && code != 408 && code != 429) {
            changed = true;
          } else if (++op.retries >= 5) {
            changed = true;
          } else {
            await _persist();
            break;
          }
        }
        _ops.removeAt(0);
        notifyListeners();
        await _persist();
      }
    } finally {
      _flushing = false;
    }
    if (changed) onFlushed?.call();
  }

  Future<String?> _resolveItem(String pid, String? itemId, String trackId) async {
    if (itemId != null) return itemId;
    final l = await _client.playlistTracksRemote(pid);
    final k = Track.key(trackId);
    for (final t in l) {
      if (Track.key(t.id) == k) return t.playlistItemId;
    }
    return null;
  }

  Future<void> _exec(OutboxOp op) async {
    final d = op.data;
    switch (op.type) {
      case 'pl_create':
        final id = await _client.createPlaylist(
            d['name'] as String, (d['trackIds'] as List).cast<String>());
        _idMap[d['tempId'] as String] = id;
        await _persist();
      case 'pl_add':
        final pid = _real(d['pid'] as String);
        if (pid.startsWith('local-')) return;
        await _client.addToPlaylist(pid, (d['trackIds'] as List).cast<String>());
      case 'pl_remove':
        final pid = _real(d['pid'] as String);
        if (pid.startsWith('local-')) return;
        final item = await _resolveItem(
            pid, d['itemId'] as String?, d['trackId'] as String);
        if (item != null) await _client.removeFromPlaylist(pid, [item]);
      case 'pl_move':
        final pid = _real(d['pid'] as String);
        if (pid.startsWith('local-')) return;
        final item = await _resolveItem(
            pid, d['itemId'] as String?, d['trackId'] as String);
        if (item != null) {
          await _client.movePlaylistItem(pid, item, d['index'] as int);
        }
      case 'pl_rename':
        final pid = _real(d['pid'] as String);
        if (pid.startsWith('local-')) return;
        await _client.renamePlaylist(pid, d['name'] as String);
      case 'pl_delete':
        final pid = _real(d['pid'] as String);
        if (pid.startsWith('local-')) return;
        await _client.deletePlaylist(pid);
    }
  }
}
