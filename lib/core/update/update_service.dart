import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/version.dart';
import '../net/net_policy.dart';

const _repo = 'EduardoV-V/spotifin';
const _kSkip = 'update_skip';
const _kLast = 'update_last_check';

class UpdateInfo {
  final String version;
  final String notes;
  final String pageUrl;
  final String? assetName;
  final String? assetUrl;
  final String? shaUrl;
  const UpdateInfo(this.version, this.notes, this.pageUrl,
      {this.assetName, this.assetUrl, this.shaUrl});
}

/// Verifica novos releases publicados no GitHub (só o repositório público,
/// sem servidor próprio). Releases em rascunho não aparecem na API.
class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  bool _busy = false;

  static List<int> _parse(String v) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(v);
    if (m == null) return const [0, 0, 0];
    return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  }

  static bool isNewer(String remote, String local) {
    final a = _parse(remote), b = _parse(local);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  Future<UpdateInfo?> fetchLatest() async {
    if (NetPolicy.offline) throw 'modo offline';
    final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'}).timeout(
        const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw 'GitHub respondeu HTTP ${res.statusCode}.';
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String?) ?? '';
    if (!isNewer(tag, appVersion)) return null;
    final assets = ((j['assets'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    Map<String, dynamic>? pick;
    bool Function(String) test;
    if (Platform.isWindows) {
      test = (n) => n.endsWith('_Setup.exe');
    } else if (Platform.isAndroid) {
      test = (n) => n.startsWith('Spotifin_Android_v') && n.endsWith('.apk');
    } else {
      test = (_) => false;
    }
    for (final a in assets) {
      if (test((a['name'] as String?) ?? '')) {
        pick = a;
        break;
      }
    }
    String? sha;
    if (pick != null) {
      for (final a in assets) {
        if (a['name'] == '${pick['name']}.sha256') {
          sha = a['browser_download_url'] as String?;
        }
      }
    }
    return UpdateInfo(
      tag.replaceFirst(RegExp(r'^v'), ''),
      ((j['body'] as String?) ?? '').trim(),
      (j['html_url'] as String?) ?? 'https://github.com/$_repo/releases',
      assetName: pick?['name'] as String?,
      assetUrl: pick?['browser_download_url'] as String?,
      shaUrl: sha,
    );
  }

  /// Verificação automática (no máximo a cada 6 h) ou manual (`manual: true`).
  Future<void> check(BuildContext Function() ctx, {bool manual = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!manual && now - (sp.getInt(_kLast) ?? 0) < 6 * 3600 * 1000) return;
      UpdateInfo? u;
      try {
        u = await fetchLatest();
        await sp.setInt(_kLast, now);
      } catch (e) {
        if (manual) _snack(ctx, 'Não foi possível verificar: $e');
        return;
      }
      if (u == null) {
        if (manual) _snack(ctx, 'Você já está na versão mais recente.');
        return;
      }
      if (!manual && sp.getString(_kSkip) == u.version) return;
      final c = ctx();
      if (!c.mounted) return;
      await _prompt(c, u, sp);
    } finally {
      _busy = false;
    }
  }

  void _snack(BuildContext Function() ctx, String m) {
    try {
      ScaffoldMessenger.of(ctx())
          .showSnackBar(SnackBar(content: Text(m)));
    } catch (_) {}
  }

  Future<void> _prompt(
      BuildContext context, UpdateInfo u, SharedPreferences sp) async {
    final auto = Platform.isWindows && u.assetUrl != null;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Nova versão ${u.version}'),
        content: SingleChildScrollView(
          child: Text(
              'Você está na versão $appVersion.'
              '${u.notes.isEmpty ? '' : '\n\n${u.notes.length > 600 ? '${u.notes.substring(0, 600)}…' : u.notes}'}'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, 'skip'),
              child: const Text('Ignorar esta versão')),
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Depois')),
          FilledButton(
              onPressed: () => Navigator.pop(c, 'go'),
              child: Text(auto ? 'Atualizar agora' : 'Baixar')),
        ],
      ),
    );
    if (r == 'skip') {
      await sp.setString(_kSkip, u.version);
    } else if (r == 'go' && context.mounted) {
      if (auto) {
        await _installWindows(context, u);
      } else {
        await launchUrl(Uri.parse(u.assetUrl ?? u.pageUrl),
            mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _installWindows(BuildContext context, UpdateInfo u) async {
    final progress = ValueNotifier<double?>(null);
    var cancelled = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Baixando atualização'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, __) => LinearProgressIndicator(value: v),
        ),
        actions: [
          TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.pop(c);
              },
              child: const Text('Cancelar')),
        ],
      ),
    );
    final client = http.Client();
    final file = File('${Directory.systemTemp.path}\\${u.assetName}');
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(u.assetUrl!)));
      if (resp.statusCode != 200) throw 'HTTP ${resp.statusCode}';
      final total = resp.contentLength ?? 0;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        if (cancelled) break;
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) progress.value = got / total;
      }
      await sink.close();
      if (cancelled) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      if (u.shaUrl != null) {
        final txt = (await http.get(Uri.parse(u.shaUrl!))).body.trim();
        final want = txt.split(RegExp(r'\s+')).first.toLowerCase();
        final have = sha256.convert(await file.readAsBytes()).toString();
        if (want != have) {
          file.deleteSync();
          throw 'verificação de integridade falhou';
        }
      }
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await Process.start(file.path, ['/SILENT'],
          mode: ProcessStartMode.detached);
      exit(0);
    } catch (e) {
      debugPrint('update: $e');
      if (!cancelled && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Falha ao atualizar: $e')));
        await launchUrl(Uri.parse(u.pageUrl),
            mode: LaunchMode.externalApplication);
      }
    } finally {
      client.close();
    }
  }
}
