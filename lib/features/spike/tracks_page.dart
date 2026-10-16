import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/jellyfin/jellyfin_client.dart';
import '../../core/jellyfin/models.dart';
import '../../core/storage/session_store.dart';
import '../settings/settings_page.dart';
import 'login_page.dart';

/// Tela do spike F0: lista faixas, toca, e mostra se o áudio veio do original.
class TracksPage extends StatefulWidget {
  final JellyfinClient client;
  const TracksPage({super.key, required this.client});
  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  final _player = AudioPlayer();
  final _search = TextEditingController();
  Timer? _debounce;

  List<Track> _tracks = [];
  int _total = 0;
  bool _loading = true;
  String? _error;

  Track? _current;
  bool _transcoded = false; // alterna original x MP3 192k
  StreamProbe? _probe;
  String? _playerError;

  @override
  void initState() {
    super.initState();
    _load();
    _player.playerStateStream.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _player.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.client.getTracks(searchTerm: _search.text);
      setState(() {
        _tracks = page.items;
        _total = page.total;
      });
    } on JellyfinException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Erro de rede ao listar músicas.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play(Track t) async {
    setState(() {
      _current = t;
      _probe = null;
      _playerError = null;
    });
    final uri = _transcoded
        ? widget.client.transcodedStreamUri(t.id)
        : widget.client.originalStreamUri(t.id);
    try {
      // Probe em paralelo ao início da reprodução.
      unawaited(widget.client
          .probeStream(uri, originalSize: t.file.sizeBytes)
          .then((p) => mounted ? setState(() => _probe = p) : null)
          .catchError((_) {}));
      await _player.setAudioSource(
          AudioSource.uri(uri, headers: widget.client.authHeaders));
      await _player.play();
    } catch (e) {
      setState(() => _playerError = 'Falha ao reproduzir: $e');
    }
  }

  String get _verdict {
    final p = _probe;
    if (_transcoded) return 'Modo transcodificado (MP3 192 kbps) — comparação.';
    if (p == null) return 'Verificando entrega do servidor…';
    if (p.statusCode >= 400) return 'Servidor respondeu HTTP ${p.statusCode}.';
    return p.matchesOriginalSize
        ? 'Original entregue (tamanho idêntico ao arquivo, ${p.contentType}).'
        : 'Tamanho diferente do original (${p.contentLength} B) — possível transcodificação.';
  }

  Future<void> _logout() async {
    await _player.stop();
    await SessionStore.clear();
    widget.client.session = null;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LoginPage(client: widget.client)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Biblioteca ($_total)'),
        actions: [
          const Text('MP3 192k'),
          Switch(
              value: _transcoded,
              onChanged: (v) => setState(() => _transcoded = v)),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                      builder: (_) => SettingsPage(client: widget.client)));
              if (changed == true) {
                await _player.stop();
                _load();
              }
            },
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar título, artista ou álbum',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _load);
              },
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _tracks.length,
                  itemBuilder: (_, i) {
                    final t = _tracks[i];
                    return ListTile(
                      selected: t.id == _current?.id,
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${t.artist} • ${t.album}\n${t.file.label}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                      onTap: () => _play(t),
                    );
                  },
                ),
      bottomNavigationBar: _current == null ? null : _buildPlayerBar(),
    );
  }

  Widget _buildPlayerBar() {
    final playing = _player.playing;
    return Material(
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_current!.title, style: Theme.of(context).textTheme.titleMedium),
            Text('Origem: ${_current!.file.label}',
                style: Theme.of(context).textTheme.bodySmall),
            Text(_playerError ?? _verdict,
                style: Theme.of(context).textTheme.bodySmall),
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (_, snap) {
                final pos = snap.data ?? Duration.zero;
                final dur = _player.duration ?? _current!.duration ?? Duration.zero;
                final max = dur.inMilliseconds.toDouble();
                return Row(children: [
                  Text(_fmt(pos)),
                  Expanded(
                    child: Slider(
                      value: pos.inMilliseconds.clamp(0, max <= 0 ? 1 : max.toInt()).toDouble(),
                      max: max <= 0 ? 1 : max,
                      onChanged: (v) =>
                          _player.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                  Text(_fmt(dur)),
                ]);
              },
            ),
            IconButton.filled(
              iconSize: 32,
              onPressed: () => playing ? _player.pause() : _player.play(),
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            ),
          ]),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes, s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
