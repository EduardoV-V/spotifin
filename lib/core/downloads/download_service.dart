import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/models.dart';

enum DownloadState { queued, downloading, completed, error, cancelled, missing }

enum DownloadQuality { original, mp3 }

class DownloadItem {
  final Track track;
  DownloadState state;
  int bytesReceived;
  int? totalBytes;
  final String localPath;
  final DownloadQuality quality;
  DateTime? completedAt;
  String? error;

  DownloadItem({
    required this.track,
    required this.localPath,
    required this.quality,
    this.state = DownloadState.queued,
    this.bytesReceived = 0,
    this.totalBytes,
    this.completedAt,
    this.error,
  });

  double? get progress => (totalBytes == null || totalBytes == 0)
      ? null
      : (bytesReceived / totalBytes!).clamp(0.0, 1.0).toDouble();

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'state': state.index,
        'bytes': bytesReceived,
        'total': totalBytes,
        'path': localPath,
        'quality': quality.index,
        'completedAt': completedAt?.millisecondsSinceEpoch,
        'error': error,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
        track: Track.fromStored(j['track'] as Map<String, dynamic>),
        state: DownloadState.values[j['state'] as int],
        bytesReceived: j['bytes'] as int,
        totalBytes: j['total'] as int?,
        localPath: j['path'] as String,
        quality: DownloadQuality.values[j['quality'] as int],
        completedAt: j['completedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['completedAt'] as int),
        error: j['error'] as String?,
      );
}

class DownloadService extends ChangeNotifier {
  /// [baseDir] é usado em testes para evitar o path_provider.
  DownloadService(this._client, {Directory? baseDir}) : _baseDir = baseDir;

  static const _kDir = 'download_dir';
  static const _kQuality = 'download_quality';
  static const _maxParallel = 2;
  static final _sep = Platform.pathSeparator;

  final JellyfinClient _client;
  final Directory? _baseDir;
  final Map<String, DownloadItem> _items = {};
  final Set<String> _active = {};
  final Set<String> _cancelRequested = {};
  final Set<String> _removeAfter = {};

  late Directory _dir;
  late File _indexFile;
  late Directory _support;
  String? _userId;
  DownloadQuality _quality = DownloadQuality.original;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  DownloadQuality get quality => _quality;
  String get directoryPath => _dir.path;

  List<DownloadItem> get items => _items.values.toList()
    ..sort((a, b) =>
        a.track.title.toLowerCase().compareTo(b.track.title.toLowerCase()));

  List<Track> get completedTracks => items
      .where((i) => i.state == DownloadState.completed)
      .map((i) => i.track)
      .toList();

  int get usedBytes => _items.values
      .where((i) => i.state == DownloadState.completed)
      .fold(0, (sum, i) => sum + i.bytesReceived);

  DownloadItem? itemFor(String id) => _items[id];

  int get pendingCount => _items.values
      .where((i) =>
          i.state == DownloadState.queued ||
          i.state == DownloadState.downloading)
      .length;

  DownloadItem? get currentItem {
    for (final i in _items.values) {
      if (i.state == DownloadState.downloading) return i;
    }
    return null;
  }

  /// Cancela tudo que está na fila ou baixando (mantém os arquivos parciais).
  void cancelPending() {
    for (final i in _items.values.toList()) {
      if (i.state == DownloadState.queued ||
          i.state == DownloadState.downloading) {
        cancel(i.track.id);
      }
    }
  }

  /// Caminho do arquivo local se a faixa estiver baixada e o arquivo existir.
  String? localPath(String id) {
    final it = _items[id];
    if (it == null || it.state != DownloadState.completed) return null;
    if (File(it.localPath).existsSync()) return it.localPath;
    it.state = DownloadState.missing;
    _changed(force: true);
    return null;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _quality =
        DownloadQuality.values[(prefs.getInt(_kQuality) ?? 0).clamp(0, 1)];
    _support = _baseDir ?? await getApplicationSupportDirectory();
    final custom = prefs.getString(_kDir);
    _dir = Directory(custom ?? await _defaultDir());
    try {
      await _dir.create(recursive: true);
    } catch (_) {
      _dir = Directory(await _defaultDir());
      await _dir.create(recursive: true);
    }
    await _openIndex();
  }

  File _indexOf(String? userId) => File(userId == null
      ? '${_support.path}${_sep}downloads_index.json'
      : '${_support.path}${_sep}downloads_index_$userId.json');

  Future<void> _openIndex() async {
    _userId = _client.session?.userId;
    _indexFile = _indexOf(_userId);
    final legacy = _indexOf(null);
    if (_userId != null && !_indexFile.existsSync() && legacy.existsSync()) {
      try {
        await legacy.rename(_indexFile.path);
      } catch (_) {}
    }
    _items.clear();
    await _loadIndex();
    for (final it in _items.values) {
      if (it.state == DownloadState.completed) {
        if (!File(it.localPath).existsSync()) it.state = DownloadState.missing;
      } else if (it.state == DownloadState.downloading) {
        it.state = DownloadState.queued;
      }
      if (it.state != DownloadState.completed) {
        final part = File('${it.localPath}.part');
        if (part.existsSync()) it.bytesReceived = part.lengthSync();
      }
    }
    _changed(force: true);
    _pump();
  }

  Future<void> _settle() async {
    for (var i = 0; i < 30 && _active.isNotEmpty; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Chamar depois de trocar `client.session`.
  Future<void> switchUser() async {
    cancelPending();
    await _settle();
    await _writeIndex();
    await _openIndex();
  }

  /// Apaga downloads e índice de uma conta (a ativa ou outra).
  Future<void> purgeUser(String userId) async {
    if (userId == _userId) {
      cancelPending();
      await _settle();
      for (final it in _items.values.toList()) {
        await _deleteFiles(it);
      }
      _items.clear();
      try {
        if (_indexFile.existsSync()) await _indexFile.delete();
      } catch (_) {}
      notifyListeners();
      return;
    }
    final f = _indexOf(userId);
    try {
      if (f.existsSync()) {
        for (final e in jsonDecode(await f.readAsString()) as List) {
          try {
            await _deleteFiles(DownloadItem.fromJson(e as Map<String, dynamic>));
          } catch (_) {}
        }
        await f.delete();
      }
    } catch (_) {}
  }

  Future<String> _defaultDir() async {
    if (_baseDir != null) return '${_baseDir.path}${_sep}downloads';
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return '${ext.path}${_sep}downloads';
    }
    if (Platform.isWindows || Platform.isLinux) {
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}${_sep}Spotifin${_sep}downloads';
    }
    final support = await getApplicationSupportDirectory();
    return '${support.path}${_sep}downloads';
  }

  /// Retorna uma mensagem de erro, ou null se a pasta foi aceita.
  Future<String?> setDirectory(String path) async {
    if (path.isEmpty) return 'Informe uma pasta.';
    try {
      final d = Directory(path);
      await d.create(recursive: true);
      final probe = File('${d.path}${_sep}.write_test');
      await probe.writeAsString('ok');
      await probe.delete();
      _dir = d;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDir, d.path);
      notifyListeners();
      return null;
    } catch (_) {
      return 'Não foi possível gravar nessa pasta.';
    }
  }

  Future<void> setQuality(DownloadQuality q) async {
    _quality = q;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kQuality, q.index);
  }

  String _targetPath(Track t, DownloadQuality q) {
    final raw = q == DownloadQuality.mp3
        ? 'mp3'
        : (t.file.container ?? t.file.codec ?? 'audio');
    final ext = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final base = _userId == null ? _dir.path : '${_dir.path}$_sep$_userId';
    return '$base$_sep${t.id}.${ext.isEmpty ? 'audio' : ext}';
  }

  void enqueue(Iterable<Track> tracks) {
    for (final t in tracks) {
      final cur = _items[t.id];
      if (cur != null &&
          (cur.state == DownloadState.completed ||
              cur.state == DownloadState.queued ||
              cur.state == DownloadState.downloading)) {
        continue;
      }
      if (cur != null &&
          (cur.state == DownloadState.error ||
              cur.state == DownloadState.cancelled) &&
          cur.quality == _quality) {
        cur.state = DownloadState.queued;
        cur.error = null;
      } else {
        _items[t.id] = DownloadItem(
          track: t,
          localPath: _targetPath(t, _quality),
          quality: _quality,
        );
      }
    }
    _changed(force: true);
    _pump();
  }

  void cancel(String id) {
    final it = _items[id];
    if (it == null) return;
    if (_active.contains(id)) {
      _cancelRequested.add(id);
    } else if (it.state == DownloadState.queued) {
      it.state = DownloadState.cancelled;
      _changed(force: true);
    }
  }

  void retry(String id) {
    final it = _items[id];
    if (it != null) enqueue([it.track]);
  }

  Future<void> remove(String id) async {
    final it = _items[id];
    if (it == null) return;
    if (_active.contains(id)) {
      _cancelRequested.add(id);
      _removeAfter.add(id);
    } else {
      _items.remove(id);
      await _deleteFiles(it);
    }
    _changed(force: true);
  }

  Future<void> removeAll() async {
    for (final id in _items.keys.toList()) {
      await remove(id);
    }
  }

  Future<void> _deleteFiles(DownloadItem it) async {
    for (final p in [it.localPath, '${it.localPath}.part']) {
      try {
        final f = File(p);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }

  void _pump() {
    if (_client.session == null) return;
    for (final it in _items.values.toList()) {
      if (_active.length >= _maxParallel) break;
      if (it.state == DownloadState.queued && !_active.contains(it.track.id)) {
        final id = it.track.id;
        _active.add(id);
        unawaited(_run(it).whenComplete(() {
          _active.remove(id);
          _pump();
        }));
      }
    }
  }

  Future<void> _run(DownloadItem it) async {
    final id = it.track.id;
    final part = File('${it.localPath}.part');
    it.state = DownloadState.downloading;
    it.error = null;
    _changed(force: true);
    IOSink? sink;
    try {
      await part.parent.create(recursive: true);
      final resumable = it.quality == DownloadQuality.original;
      var start = (resumable && part.existsSync()) ? part.lengthSync() : 0;
      final uri = resumable
          ? _client.originalStreamUri(id)
          : _client.transcodedStreamUri(id);
      final resp = await _client
          .openStream(uri, rangeStart: start)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 416) {
        if (part.existsSync()) await part.delete();
        throw const FormatException('Arquivo parcial inválido; tente de novo.');
      }
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw HttpException('Servidor respondeu HTTP ${resp.statusCode}');
      }
      int? total;
      if (resp.statusCode == 206) {
        final cr = resp.headers['content-range'];
        total = cr != null ? int.tryParse(cr.split('/').last) : null;
      } else {
        start = 0;
        total = resp.contentLength;
      }
      total ??= resumable ? it.track.file.sizeBytes : null;
      it.totalBytes = total;
      it.bytesReceived = start;
      sink = part.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);
      await for (final chunk
          in resp.stream.timeout(const Duration(seconds: 30))) {
        if (_cancelRequested.contains(id)) break;
        sink.add(chunk);
        it.bytesReceived += chunk.length;
        _changed();
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (_cancelRequested.remove(id)) {
        if (_removeAfter.remove(id)) {
          _items.remove(id);
          await _deleteFiles(it);
        } else {
          it.state = DownloadState.cancelled;
        }
      } else {
        final len = await part.length();
        final expected = it.totalBytes;
        if (len == 0 || (expected != null && len != expected)) {
          throw const FormatException('Download incompleto.');
        }
        final target = File(it.localPath);
        if (target.existsSync()) await target.delete();
        await part.rename(it.localPath);
        it.bytesReceived = len;
        it.totalBytes = len;
        it.state = DownloadState.completed;
        it.completedAt = DateTime.now();
      }
    } catch (e) {
      it.state = DownloadState.error;
      it.error = _describe(e);
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
    }
    _changed(force: true);
  }

  String _describe(Object e) {
    if (e is TimeoutException) return 'Tempo esgotado.';
    if (e is SocketException) return 'Sem conexão com o servidor.';
    if (e is FormatException) return e.message;
    if (e is HttpException) return e.message;
    return 'Erro inesperado no download.';
  }

  Future<void> _loadIndex() async {
    try {
      if (!_indexFile.existsSync()) return;
      final list = jsonDecode(await _indexFile.readAsString()) as List;
      for (final e in list) {
        try {
          final it = DownloadItem.fromJson(e as Map<String, dynamic>);
          _items[it.track.id] = it;
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _writeIndex() async {
    try {
      final tmp = File('${_indexFile.path}.tmp');
      await tmp.writeAsString(
          jsonEncode(_items.values.map((e) => e.toJson()).toList()));
      await tmp.rename(_indexFile.path);
    } catch (_) {}
  }

  void _changed({bool force = false}) {
    final now = DateTime.now();
    if (force || now.difference(_lastNotify) > const Duration(milliseconds: 250)) {
      _lastNotify = now;
      notifyListeners();
    }
    if (force) unawaited(_writeIndex());
  }
}
