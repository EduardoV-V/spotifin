import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../jellyfin/models.dart';

class SessionStore {
  static const _s = FlutterSecureStorage();

  static Future<String> deviceId() async {
    var id = await _s.read(key: 'device_id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(
          16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _s.write(key: 'device_id', value: id);
    }
    return id;
  }

  static Future<List<JellyfinSession>> accounts() async {
    await _migrateLegacy();
    final raw = await _s.read(key: 'accounts');
    if (raw == null) return [];
    final dev = await deviceId();
    try {
      return (jsonDecode(raw) as List)
          .map((e) => JellyfinSession.fromJson(e as Map<String, dynamic>, dev))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<JellyfinSession> list) =>
      _s.write(key: 'accounts', value: jsonEncode(list.map((e) => e.toJson()).toList()));

  static Future<void> _migrateLegacy() async {
    final url = await _s.read(key: 'server_url');
    final uid = await _s.read(key: 'user_id');
    final tok = await _s.read(key: 'token');
    if (url == null || uid == null || tok == null) return;
    if (await _s.read(key: 'accounts') == null) {
      final dev = await deviceId();
      await _write([
        JellyfinSession(serverUrl: url, userId: uid, token: tok, deviceId: dev)
      ]);
      await _s.write(key: 'active_user', value: uid);
    }
    await _s.delete(key: 'server_url');
    await _s.delete(key: 'user_id');
    await _s.delete(key: 'token');
  }

  /// Insere ou atualiza a conta e a torna ativa.
  static Future<void> save(JellyfinSession s) async {
    final list = await accounts();
    final i = list.indexWhere((a) => a.userId == s.userId);
    if (i >= 0) {
      list[i] = s;
    } else {
      list.add(s);
    }
    await _write(list);
    await _s.write(key: 'active_user', value: s.userId);
  }

  static Future<JellyfinSession?> load() async {
    final list = await accounts();
    if (list.isEmpty) return null;
    final active = await _s.read(key: 'active_user');
    return list.firstWhere((a) => a.userId == active, orElse: () => list.first);
  }

  static Future<void> setActive(String userId) =>
      _s.write(key: 'active_user', value: userId);

  static Future<void> replaceServerUrl(String from, String to) async {
    final list = await accounts();
    await _write([
      for (final a in list)
        a.serverUrl == from
            ? JellyfinSession(
                serverUrl: to,
                userId: a.userId,
                token: a.token,
                deviceId: a.deviceId,
                username: a.username)
            : a
    ]);
  }

  /// Remove a conta e devolve a restante (se houver) já marcada como ativa.
  static Future<JellyfinSession?> remove(String userId) async {
    final wasActive = (await load())?.userId == userId;
    final list = await accounts()
      ..removeWhere((a) => a.userId == userId);
    await _write(list);
    if (!wasActive) return load();
    if (list.isEmpty) {
      await _s.delete(key: 'active_user');
      return null;
    }
    await setActive(list.first.userId);
    return list.first;
  }
}
