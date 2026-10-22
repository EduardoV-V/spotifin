import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Cache permanente de imagens em disco (capas, fotos de artistas), para o
/// modo offline e para não pedir a mesma imagem de novo à rede/Jellyfin.
class ImageStore {
  static final _mem = <String, File>{};
  static final _inflight = <String, Future<File?>>{};
  static final _failedAt = <String, DateTime>{};
  static Directory? _dir;
  static final _client = http.Client();
  static int _running = 0;
  static final _waiters = <Completer<void>>[];
  static int _bgRunning = 0;
  static final _bgWaiters = <Completer<void>>[];
  static bool _trimmed = false;
  static const _maxBytes = 500 * 1024 * 1024;
  static const _targetBytes = 350 * 1024 * 1024;

  static String _key(String url) {
    var h = 0xcbf29ce484222325;
    for (final c in url.codeUnits) {
      h = (h ^ c) * 0x100000001b3;
    }
    return (h & 0x7fffffffffffffff).toRadixString(16);
  }

  static Future<Directory> _root() async {
    final d = _dir;
    if (d != null) return d;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}img_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _dir = dir;
  }

  static Future<void> _acquire(bool bg) async {
    if (bg) {
      if (_bgRunning < 2) {
        _bgRunning++;
        return;
      }
      final c = Completer<void>();
      _bgWaiters.add(c);
      await c.future;
      return;
    }
    if (_running < 10) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  static void _release(bool bg) {
    if (bg) {
      if (_bgWaiters.isNotEmpty) {
        _bgWaiters.removeAt(0).complete();
      } else {
        _bgRunning--;
      }
      return;
    }
    if (_waiters.isNotEmpty) {
      _waiters.removeLast().complete(); // as últimas pedidas (tela atual) primeiro
    } else {
      _running--;
    }
  }

  /// Arquivo local da imagem (baixa e guarda na primeira vez).
  /// [background]: pré-carregamento; usa uma fila própria para não atrasar
  /// as imagens que a tela está pedindo.
  static Future<File?> get(String url,
      {Map<String, String>? headers, bool background = false}) {
    final m = _mem[url];
    if (m != null) return Future.value(m);
    return _inflight[url] ??=
        _load(url, headers, background).whenComplete(() => _inflight.remove(url));
  }

  static Future<File?> _load(
      String url, Map<String, String>? headers, bool bg) async {
    try {
      final dir = await _root();
      final f = File('${dir.path}${Platform.pathSeparator}${_key(url)}.img');
      final have = f.existsSync() && f.lengthSync() > 0;
      // Fresca (< 14 dias): usa direto. Velha: tenta renovar, mas mantém a
      // antiga se a rede falhar (modo offline).
      if (have &&
          DateTime.now().difference(f.statSync().modified).inDays < 14) {
        return _mem[url] = f;
      }
      final fa = _failedAt[url];
      if (fa != null && DateTime.now().difference(fa).inSeconds < 60) {
        return have ? (_mem[url] = f) : null;
      }
      await _acquire(bg);
      try {
        final res = await _client
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 20));
        final ct = res.headers['content-type'] ?? '';
        if (res.statusCode != 200 ||
            res.bodyBytes.isEmpty ||
            !ct.startsWith('image/')) {
          _failedAt[url] = DateTime.now();
          debugPrint('ImageStore: ${res.statusCode} $ct $url');
          return have ? (_mem[url] = f) : null;
        }
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(res.bodyBytes, flush: true);
        await tmp.rename(f.path);
        _trim(dir);
        return _mem[url] = f;
      } finally {
        _release(bg);
      }
    } catch (e) {
      debugPrint('ImageStore: erro $e $url');
      _failedAt[url] = DateTime.now();
      try {
        final dir = await _root();
        final f = File('${dir.path}${Platform.pathSeparator}${_key(url)}.img');
        if (f.existsSync() && f.lengthSync() > 0) return _mem[url] = f;
      } catch (_) {}
      return null;
    }
  }

  /// Remove arquivos corrompidos (a imagem não decodificou).
  static Future<void> evict(String url) async {
    final f = _mem.remove(url);
    try {
      await f?.delete();
    } catch (_) {}
  }

  static Future<void> _trim(Directory dir) async {
    if (_trimmed) return;
    _trimmed = true;
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.img'))
          .toList();
      var total = 0;
      final info = <(File, int, DateTime)>[];
      for (final f in files) {
        final s = f.statSync();
        total += s.size;
        info.add((f, s.size, s.modified));
      }
      if (total <= _maxBytes) return;
      info.sort((a, b) => a.$3.compareTo(b.$3));
      for (final e in info) {
        if (total <= _targetBytes) break;
        try {
          e.$1.deleteSync();
          total -= e.$2;
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final dir = await _root();
      for (final f in dir.listSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
      _mem.clear();
    } catch (_) {}
  }
}
