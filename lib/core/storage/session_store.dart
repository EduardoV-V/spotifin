import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../jellyfin/models.dart';

/// Token do Jellyfin no cofre seguro da plataforma (RNF-004).
class SessionStore {
  static const _s = FlutterSecureStorage();

  static Future<String> deviceId() async {
    var id = await _s.read(key: 'device_id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _s.write(key: 'device_id', value: id);
    }
    return id;
  }

  static Future<void> save(JellyfinSession s) async {
    await _s.write(key: 'server_url', value: s.serverUrl);
    await _s.write(key: 'user_id', value: s.userId);
    await _s.write(key: 'token', value: s.token);
  }

  static Future<JellyfinSession?> load() async {
    final url = await _s.read(key: 'server_url');
    final uid = await _s.read(key: 'user_id');
    final tok = await _s.read(key: 'token');
    if (url == null || uid == null || tok == null) return null;
    return JellyfinSession(
        serverUrl: url, userId: uid, token: tok, deviceId: await deviceId());
  }

  static Future<void> clear() async {
    await _s.delete(key: 'server_url');
    await _s.delete(key: 'user_id');
    await _s.delete(key: 'token');
  }
}
