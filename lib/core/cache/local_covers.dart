import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Capas de playlist guardadas só neste aparelho (usadas quando o usuário do
/// Jellyfin não tem permissão para enviar imagens ao servidor).
class LocalCovers {
  static final _files = <String, File>{};
  static final rev = ValueNotifier<int>(0);
  static Directory? _dir;

  static Future<Directory> _root() async {
    final d = _dir;
    if (d != null) return d;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}covers');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _dir = dir;
  }

  static Future<void> init() async {
    try {
      final dir = await _root();
      for (final f in dir.listSync().whereType<File>()) {
        final n = f.uri.pathSegments.last;
        if (n.endsWith('.img')) _files[n.substring(0, n.length - 4)] = f;
      }
    } catch (_) {}
  }

  static File? file(String id) => _files[id];

  static Future<void> save(String id, List<int> bytes) async {
    final dir = await _root();
    final f = File('${dir.path}${Platform.pathSeparator}$id.img');
    await f.writeAsBytes(bytes, flush: true);
    await FileImage(f).evict();
    _files[id] = f;
    rev.value++;
  }

  static Future<void> remove(String id) async {
    final f = _files.remove(id);
    try {
      await f?.delete();
    } catch (_) {}
    rev.value++;
  }
}
