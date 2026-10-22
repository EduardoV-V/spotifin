import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cache local de metadados (JSON com validade). Não toca em downloads,
/// playlists nem favoritos.
class MetaCache {
  static const _p = 'mc_';

  static Future<dynamic> get(String key, Duration ttl) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('$_p$key');
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
      if (DateTime.now().difference(at) > ttl) return null;
      return j['v'];
    } catch (_) {
      return null;
    }
  }

  static Future<void> put(String key, dynamic value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('$_p$key',
          jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'v': value}));
    } catch (_) {}
  }

  /// Limpa só o cache de metadados (RF-012).
  static Future<void> clearAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final k in sp.getKeys().toList()) {
        if (k.startsWith(_p) || k.startsWith('ai2_') || k.startsWith('ai2n_')) {
          await sp.remove(k);
        }
      }
    } catch (_) {}
  }
}
