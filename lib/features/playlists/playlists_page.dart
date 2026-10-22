import '../../widgets/download_badge.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/jellyfin_client.dart';
import '../../core/jellyfin/models.dart';
import '../../core/downloads/auto_download.dart';
import '../../core/recent/recent_store.dart';
import 'package:flutter/services.dart';

import '../../core/cover_color.dart';
import '../../widgets/add_to_playlist.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/playlist_cover.dart';
import '../../widgets/smooth_scroll.dart';
import '../../widgets/playlist_details.dart';
import '../../widgets/track_tile.dart';

Widget _cover(BuildContext context, PlaylistInfo p, double size) =>
    PlaylistCover(id: p.id, size: size);

class PlaylistsView extends StatelessWidget {
  const PlaylistsView({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = AppScope.of(context).playlists;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) => ListView(children: [
        ListTile(
          leading: const Icon(Icons.add_box_outlined),
          title: const Text('Nova playlist'),
          onTap: () async {
            final name = await askName(context);
            if (name == null || name.trim().isEmpty || !context.mounted) return;
            final err = await svc.create(name, const []);
            if (err != null && context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(err)));
            }
          },
        ),
        for (final p in svc.playlists)
          ListTile(
            leading: _cover(context, p, 48),
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${p.count} faixas',
                style: const TextStyle(color: AppColors.textSecondary)),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PlaylistPage(info: p))),
          ),
      ]),
    );
  }
}

/// Pilha das playlists abertas (a do topo é a visível).
final openPlaylists = ValueNotifier<List<String>>(const []);

void openPlaylist(NavigatorState nav, PlaylistInfo p) {
  final st = openPlaylists.value;
  if (st.isNotEmpty && st.last == p.id) return;
  nav.push(MaterialPageRoute(builder: (_) => PlaylistPage(info: p)));
}

class PlaylistPage extends StatefulWidget {
  final PlaylistInfo info;
  const PlaylistPage({super.key, required this.info});
  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  List<Track> _tracks = [];
  bool _loading = true;
  String? _error;
  late String _name = widget.info.name;
  _Sort _sort = _Sort.custom;
  bool _asc = true;
  double _top = 0;
  bool _mobileInit = false;
  double get _searchH => 56 + _top;
  late final _scrollCtl = SmoothScrollController(
      initialScrollOffset: _mobileInit ? _searchH : 0);
  bool _bar = false;
  bool _hid = false;
  String _q = '';
  bool _searching = false;
  int _coverV = 0;
  String _desc = '';
  bool _hasImg = false;

  String get _tintId => _hasImg || _tracks.isEmpty
      ? widget.info.id
      : (_tracks.first.albumId ?? _tracks.first.id);
  final _qCtl = TextEditingController();

  List<Track> get _view {
    final q = _q.trim().toLowerCase();
    final base = q.isEmpty
        ? _tracks
        : _tracks
            .where((t) =>
                t.title.toLowerCase().contains(q) ||
                t.artist.toLowerCase().contains(q) ||
                t.album.toLowerCase().contains(q))
            .toList();
    if (_sort == _Sort.custom) return base;
    final l = List.of(base);
    int c(Track a, Track b) {
      switch (_sort) {
        case _Sort.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case _Sort.artist:
          return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
        case _Sort.album:
          return a.album.toLowerCase().compareTo(b.album.toLowerCase());
        case _Sort.added:
          return (a.added ?? DateTime(1970)).compareTo(b.added ?? DateTime(1970));
        case _Sort.duration:
          return (a.duration ?? Duration.zero)
              .compareTo(b.duration ?? Duration.zero);
        case _Sort.custom:
          return 0;
      }
    }
    l.sort(c);
    return _asc ? l : l.reversed.toList();
  }

  void _setSort(_Sort k) => setState(() {
        if (_sort == k && k != _Sort.custom) {
          _asc = !_asc;
        } else {
          _sort = k;
          _asc = k != _Sort.added;
        }
      });

  String get _sortLabel => switch (_sort) {
        _Sort.custom => 'Ordem personalizada',
        _Sort.title => 'Título',
        _Sort.artist => 'Artista',
        _Sort.album => 'Álbum',
        _Sort.added => 'Adicionado recentemente',
        _Sort.duration => 'Duração',
      };
  bool _init = false;
  late final AppScope _scope;

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => openPlaylists.value = [...openPlaylists.value, widget.info.id]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _scope = AppScope.of(context);
    _top = MediaQuery.paddingOf(context).top;
    _mobileInit = MediaQuery.sizeOf(context).width < 700;
    _scope.reload.addListener(_load);
    _scrollCtl.addListener(() {
      final b = _scrollCtl.hasClients && _scrollCtl.offset > 300;
      if (b != _bar) setState(() => _bar = b);
    });
    _load();
    _scope.client.playlistHasImage(widget.info.id).then((v) {
      if (mounted) setState(() => _hasImg = v);
    }).catchError((_) {});
    _scope.client
        .playlistOverview(widget.info.id)
        .then((d) => mounted ? setState(() => _desc = d) : null)
        .catchError((_) => null);
  }

  @override
  void dispose() {
    _scope.reload.removeListener(_load);
    _scrollCtl.dispose();
    _qCtl.dispose();
    final id = widget.info.id;
    Future.microtask(() {
      final l = [...openPlaylists.value];
      final i = l.lastIndexOf(id);
      if (i >= 0) l.removeAt(i);
      openPlaylists.value = l;
    });
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    try {
      final l = await _scope.client.playlistTracks(widget.info.id);
      if (mounted) {
        setState(() {
          _tracks = l;
          _error = null;
        });
      }
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Sem conexão com o servidor.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(Track t) async {
    final err = await _scope.playlists.removeEntry(widget.info.id, t);
    if (err != null && mounted) _toast(err);
    await _load();
  }

  Future<void> _reorder(int from, int to) async {
    if (to > from) to--;
    if (from == to) return;
    final t = _tracks[from];
    setState(() => _tracks.insert(to, _tracks.removeAt(from)));
    final err = await _scope.playlists.move(widget.info.id, t, to);
    if (err != null && mounted) {
      _toast(err);
      await _load();
    }
  }

  Future<void> _rename() async {
    final r =
        await showPlaylistDetails(context, widget.info.id, _name, _coverV);
    if (r == null || !mounted) return;
    if (r.deleted) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _name = r.name;
      _scope.client
          .playlistOverview(widget.info.id)
          .then((d) => mounted ? setState(() => _desc = d) : null)
          .catchError((_) => null);
      if (r.photoChanged) _coverV++;
    });
    if (r.localCover) {
      _toast(
          'Seu usuário não pode enviar imagens ao Jellyfin (HTTP 403). Capa salva só neste aparelho; para enviar ao servidor, crie uma chave de API no Painel do Jellyfin e coloque em Configurações.');
    }
  }

  Widget _circleBtn(IconData i, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          color: _bar ? Colors.transparent : const Color(0x66000000),
          shape: const CircleBorder(),
          child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(i, size: 22)),
        ),
      );

  SliverAppBar _mobileBar(Color tint, List<Track> view) => SliverAppBar(
        pinned: true,
        toolbarHeight: 56,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: _bar
            ? Color.lerp(tint, const Color(0xFF121212), 0.35)
            : Colors.transparent,
        leading: _circleBtn(Icons.arrow_back, () => Navigator.of(context).pop()),
        title: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _bar ? 1 : 0,
          child: Text(_name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        actions: [
          if (_bar)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _PlayButton(
                  playing: false,
                  size: 44,
                  onTap: view.isEmpty ? null : () => _play(List.of(view), 0)),
            ),
          _circleBtn(
              Icons.more_vert,
              () => showPlaylistMenu(
                  context, Offset.zero, PlaylistInfo(widget.info.id, _name, _tracks.length))),
        ],
      );

  Widget _mobileHeader() {
    final owner = _scope.client.session?.username ?? '';
    final total = _tracks.fold<int>(0, (a, t) => a + (t.duration?.inSeconds ?? 0));
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final dur = h > 0 ? '${h}h ${m}min' : '$m min';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            decoration: const BoxDecoration(boxShadow: [
              BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))
            ]),
            child: PlaylistCover(
                id: widget.info.id, size: 208, version: _coverV, radius: 2),
          ),
        ),
        const SizedBox(height: 18),
        Text(_name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 22, height: 1.1, fontWeight: FontWeight.w800)),
        if (_desc.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(_desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.add, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          CircleAvatar(
              radius: 11,
              backgroundColor: const Color(0xFF6A4FC4),
              child: Text(owner.isEmpty ? '?' : owner[0].toUpperCase(),
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Text(owner,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.public, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text('${_tracks.length} músicas • $dur',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary)),
        ]),
      ]),
    );
  }

  int _tries = 0;
  void _hideSearch() {
    if (_hid || !mounted) return;
    if (_scrollCtl.hasClients) {
      final pos = _scrollCtl.position;
      if (pos.maxScrollExtent >= _searchH) {
        _hid = true;
        if (pos.pixels < _searchH) _scrollCtl.jumpTo(_searchH);
        return;
      }
    }
    if (++_tries < 120) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hideSearch());
    }
  }

  bool _snapSearch(ScrollNotification n) {
    if (n is ScrollEndNotification && _scrollCtl.hasClients) {
      final o = _scrollCtl.offset;
      if (o > 0.5 && o < _searchH - 0.5 && _q.isEmpty) {
        _scrollCtl.animateTo(o < _searchH / 2 ? 0 : _searchH,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    }
    return false;
  }

  Widget _mobileSearch() => SizedBox(
        height: _searchH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, _top + 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  const SizedBox(width: 10),
                  const Icon(Icons.search, size: 22),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _qCtl,
                      onChanged: (v) => setState(() => _q = v),
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                          hintText: 'Procurar nesta playlist',
                          hintStyle: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                          border: InputBorder.none,
                          isDense: true),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _sortSheet,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Ordenar',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _mobileActions() {
    final pl = _scope.player;
    return ListenableBuilder(
      listenable: pl,
      builder: (context, _) {
        final here = pl.queueSource == _name;
        return Row(children: [
          ListenableBuilder(
            listenable: AutoDownload.instance,
            builder: (_, __) {
              final on = AutoDownload.instance.enabled(widget.info.id);
              return IconButton(
                iconSize: 26,
                tooltip: 'Baixar',
                color: on ? AppColors.accent : AppColors.textSecondary,
                icon: on
                    ? const DownloadBadge(size: 26)
                    : const Icon(Icons.arrow_circle_down_outlined),
                onPressed: () {
                  AutoDownload.instance.toggle(widget.info.id);
                  _toast(on
                      ? 'Download automático desativado'
                      : 'Baixando e monitorando novas músicas');
                },
              );
            },
          ),
          IconButton(
            iconSize: 24,
            color: AppColors.textSecondary,
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _name));
              _toast('Nome copiado');
            },
          ),
          const Spacer(),
          IconButton(
            iconSize: 28,
            color: pl.shuffle ? AppColors.accent : AppColors.textSecondary,
            icon: const Icon(Icons.shuffle),
            onPressed: _tracks.isEmpty
                ? null
                : () {
                    pl.toggleShuffle();
                  },
          ),
          const SizedBox(width: 4),
          _PlayButton(
            playing: here && pl.playing,
            onTap: _tracks.isEmpty
                ? null
                : () {
                    if (here) {
                      pl.togglePlay();
                    } else {
                      _play(List.of(_view), 0);
                    }
                  },
          ),
        ]);
      },
    );
  }

  Widget _chipsRow() => ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _pill(Icons.add, 'Adicionar',
              () => _toast('Use ⋮ em uma faixa → Adicionar à playlist')),
          const SizedBox(width: 8),
          _pill(Icons.tune, 'Mixar', () {
            final l = List.of(_tracks)..shuffle();
            if (l.isNotEmpty) _play(l, 0);
          }),
          const SizedBox(width: 8),
          _pill(Icons.edit_outlined, 'Nome e detalhes', _rename),
          const SizedBox(width: 8),
          _pill(Icons.swap_vert, 'Classificar', _sortSheet),
        ],
      );

  void _sortSheet() {
    showSheetEntries(
        context,
        const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Classificar por',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
        [
          for (final k in _Sort.values.where((k) => k != _Sort.added))
            MenuEntry(_labelOf(k),
                icon: _sort == k ? Icons.check : null, onTap: () => _setSort(k)),
        ]);
  }

  void _play(List<Track> l, int i) {
    RecentStore.instance.add('playlist', widget.info.id, _name);
    _scope.player.playQueue(l, i, source: _name);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Apagar "$_name"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await _scope.playlists.delete(widget.info.id);
    if (!mounted) return;
    if (err != null) {
      _toast(err);
    } else {
      Navigator.of(context).pop();
    }
  }

  String get _summary {
    final total = _tracks.fold<int>(
        0, (a, t) => a + (t.duration?.inSeconds ?? 0));
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final dur = h > 0 ? '${h}h ${m}min' : '${m} min';
    return '${_tracks.length} músicas, $dur';
  }

  Widget _menu() => PopupMenuButton<String>(
        color: AppColors.elevated,
        icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
        onSelected: (v) {
          switch (v) {
            case 'dl':
              _scope.downloads.enqueue(_tracks);
              _toast('${_tracks.length} faixas na fila de download');
            case 'rename':
              _rename();
            case 'delete':
              _delete();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'dl', child: Text('Baixar playlist')),
          PopupMenuItem(value: 'rename', child: Text('Renomear')),
          PopupMenuItem(value: 'delete', child: Text('Apagar playlist')),
        ],
      );

  Widget _circle(IconData icon, String tip, VoidCallback? onTap,
      {Color? color}) {
    return IconButton(
      iconSize: 32,
      tooltip: tip,
      color: color ?? AppColors.textSecondary,
      icon: Icon(icon),
      onPressed: onTap,
    );
  }

  Widget _actions(bool wide) {
    final pl = _scope.player;
    return ListenableBuilder(
      listenable: pl,
      builder: (context, _) {
        final here = pl.queueSource == _name;
        final playingHere = here && pl.playing;
        return Row(children: [
          _PlayButton(
            playing: playingHere,
            onTap: _tracks.isEmpty
                ? null
                : () {
                    if (here) {
                      pl.togglePlay();
                    } else {
                      _play(List.of(_view), 0);
                    }
                  },
          ),
          const SizedBox(width: 8),
          _circle(Icons.shuffle, 'Aleatório', _tracks.isEmpty
              ? null
              : () {
                  final l = List.of(_tracks)..shuffle();
                  pl.playQueue(l, 0, source: _name);
                },
              color: pl.shuffle ? AppColors.accent : null),
          ListenableBuilder(
            listenable: AutoDownload.instance,
            builder: (_, __) {
              final on = AutoDownload.instance.enabled(widget.info.id);
              return _circle(
                  on ? Icons.arrow_circle_down : Icons.arrow_circle_down_outlined,
                  on ? 'Download automático ativo' : 'Baixar e manter atualizada',
                  () {
                AutoDownload.instance.toggle(widget.info.id);
                _toast(on
                    ? 'Download automático desativado'
                    : 'Baixando e monitorando novas músicas');
              }, color: on ? AppColors.accent : null);
            },
          ),
          _menu(),
          const Spacer(),
          _searchBox(),
          if (wide) _sortMenu(),
        ]);
      },
    );
  }

  Widget _searchBox() => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: _searching ? 200 : 40,
        height: 36,
        decoration: BoxDecoration(
            color: _searching ? const Color(0xFF2A2A2A) : Colors.transparent,
            borderRadius: BorderRadius.circular(4)),
        child: Row(children: [
          IconButton(
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
            color: AppColors.textSecondary,
            icon: const Icon(Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _q = '';
                _qCtl.clear();
              }
            }),
          ),
          if (_searching)
            Expanded(
              child: TextField(
                controller: _qCtl,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Buscar na playlist'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
        ]),
      );

  Widget _chips() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Wrap(spacing: 8, children: [
          _pill(Icons.add, 'Adicionar', () => _toast('Use ⋯ em uma faixa → Adicionar à playlist')),
          _pill(Icons.shuffle, 'Mixar', () {
            final l = List.of(_tracks)..shuffle();
            if (l.isNotEmpty) _scope.player.playQueue(l, 0, source: _name);
          }),
          _pill(Icons.edit_outlined, 'Nome e detalhes', _rename),
        ]),
      );

  Widget _pill(IconData i, String t, VoidCallback onTap) => Material(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 16),
              const SizedBox(width: 6),
              Text(t,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );

  Widget _sortMenu() {
    return PopupMenuButton<_Sort>(
      color: const Color(0xFF282828),
      tooltip: '',
      onSelected: (k) => setState(() {
        _sort = k;
        _asc = k != _Sort.added;
      }),
      itemBuilder: (_) => [
        const PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text('Ordenar por',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary))),
        for (final k in _Sort.values.where((k) => k != _Sort.added))
          PopupMenuItem(
            value: k,
            child: Row(children: [
              Expanded(
                  child: Text(_labelOf(k),
                      style: TextStyle(
                          color: _sort == k ? AppColors.accent : Colors.white))),
              if (_sort == k)
                const Icon(Icons.check, size: 18, color: AppColors.accent),
            ]),
          ),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(_sortLabel,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSecondary)),
        const SizedBox(width: 6),
        const Icon(Icons.format_list_bulleted,
            size: 18, color: AppColors.textSecondary),
      ]),
    );
  }

  String _labelOf(_Sort k) => switch (k) {
        _Sort.title => 'Título',
        _Sort.artist => 'Artista',
        _Sort.album => 'Álbum',
        _Sort.added => 'Adicionado recentemente',
        _Sort.duration => 'Duração',
        _Sort.custom => 'Ordem personalizada',
      };

  Widget _header(bool wide) {
    final client = _scope.client;
    final owner = client.session?.username ?? '';
    final cover = PlaylistCover(
        id: widget.info.id,
        size: wide ? 232 : 200,
        version: _coverV);
    final meta = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            wide ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.accent,
              child: Text(owner.isEmpty ? '?' : owner[0].toUpperCase(),
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
                [if (owner.isNotEmpty) owner, if (_tracks.isNotEmpty) _summary]
                    .join(' • '),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ]);
    final info = Column(
        crossAxisAlignment:
            wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text('Playlist',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          wide
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_name,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 88,
                          height: 1.0,
                          letterSpacing: -2,
                          fontWeight: FontWeight.w900)),
                )
              : Text(_name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 30, height: 1.05, fontWeight: FontWeight.w900)),
          if (_desc.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: wide ? TextAlign.start : TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 14),
          meta,
        ]);
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 24 : 0, 24, 24),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              cover,
              const SizedBox(width: 24),
              Expanded(child: info),
            ])
          : Column(children: [cover, const SizedBox(height: 16), info]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 700;
              const showAdded = false;
              Widget tile(int i) {
                final t = view[i];
                return TrackTile(
                  track: t,
                  wide: wide,
                  showAdded: showAdded,
                  index: i,
                  onTap: () => _play(List.of(view), i),
                  onRemove: () => _remove(t),
                );
              }

              if (!wide && !_hid) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _hideSearch());
              }
              return CoverTint(
                  itemId: _tintId,
                  builder: (context, tint) => Stack(children: [
                AnimatedBuilder(
                  animation: _scrollCtl,
                  builder: (_, child) => Transform.translate(
                      offset: Offset(0,
                          -(_scrollCtl.hasClients ? _scrollCtl.offset : 0.0)),
                      child: child),
                  child: Container(
                    height: 460,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [tint, AppColors.background]),
                    ),
                  ),
                ),
                NotificationListener<ScrollNotification>(
                  onNotification: wide ? null : _snapSearch,
                  child: CustomScrollView(controller: _scrollCtl, slivers: [
                  if (!wide) SliverToBoxAdapter(child: _mobileSearch()),
                  if (!wide) _mobileBar(tint, view) else
                  SliverAppBar(
                    pinned: true,
                    toolbarHeight: 56,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    surfaceTintColor: Colors.transparent,
                    backgroundColor:
                        _bar ? const Color(0xFF3A3A3A) : Colors.transparent,
                    title: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _bar ? 1 : 0,
                      child: Row(children: [
                        _PlayButton(
                            playing: false,
                            size: 40,
                            onTap: view.isEmpty
                                ? null
                                : () => _scope.player.playQueue(
                                    List.of(view), 0,
                                    source: _name)),
                        const SizedBox(width: 12),
                        Text(_name,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                  SliverToBoxAdapter(
                      child: wide
                          ? _header(wide)
                          : AnimatedBuilder(
                              animation: _scrollCtl,
                              builder: (_, child) {
                                final o =
                                    _scrollCtl.hasClients ? _scrollCtl.offset : 0.0;
                                final f = (1 - (o - _searchH) / 280)
                                    .clamp(0.0, 1.0)
                                    .toDouble();
                                return Opacity(
                                    opacity: f,
                                    child: Transform.scale(
                                        scale: 0.85 + 0.15 * f,
                                        alignment: Alignment.topCenter,
                                        child: child));
                              },
                              child: _mobileHeader())),
                  SliverToBoxAdapter(
                    child: wide
                        ? Container(
                            color: const Color(0x66000000),
                            padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
                            child: _actions(wide),
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: _mobileActions(),
                          ),
                  ),
                  if (wide) SliverToBoxAdapter(child: _chips()),
                  if (!wide)
                    SliverPersistentHeader(
                        pinned: true,
                        delegate: _ChipsHeader(
                            child: _chipsRow(), color: const Color(0xF2181818))),
                  if (_error != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ),
                    ),
                  if (wide)
                    SliverPersistentHeader(
                        pinned: true,
                        delegate: _TableHeader(
                            showAdded: showAdded,
                            sort: _sort,
                            asc: _asc,
                            onSort: _setSort)),
                  if (view.isEmpty && _error == null)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                            child: Text('Playlist vazia.',
                                style: TextStyle(
                                    color: AppColors.textSecondary))),
                      ),
                    )
                  else if (_sort == _Sort.custom && _q.trim().isEmpty)
                    SliverReorderableList(
                      itemCount: view.length,
                      onReorder: _reorder,
                      itemBuilder: (_, i) {
                        final t = view[i];
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(t.playlistItemId ?? '${t.id}#$i'),
                          index: i,
                          child: tile(i),
                        );
                      },
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                          (_, i) => KeyedSubtree(
                              key: ValueKey(
                                  view[i].playlistItemId ?? '${view[i].id}#$i'),
                              child: tile(i)),
                          childCount: view.length),
                    ),
                  SliverToBoxAdapter(
                      child: SizedBox(height: bottomReserve(context))),
                ])),
              ]));
            }),
    );
  }
}

enum _Sort { custom, title, artist, album, added, duration }

class _PlayButton extends StatefulWidget {
  final bool playing;
  final double size;
  final VoidCallback? onTap;
  const _PlayButton(
      {required this.playing, required this.onTap, this.size = 56});
  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.06 : 1,
        duration: const Duration(milliseconds: 120),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: const BoxDecoration(
                color: AppColors.accent, shape: BoxShape.circle),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(widget.playing ? Icons.pause : Icons.play_arrow,
                  key: ValueKey(widget.playing),
                  color: Colors.black,
                  size: widget.size * 0.57),
            ),
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends SliverPersistentHeaderDelegate {
  final bool showAdded;
  final _Sort sort;
  final bool asc;
  final void Function(_Sort) onSort;
  _TableHeader(
      {required this.showAdded,
      required this.sort,
      required this.asc,
      required this.onSort});

  @override
  double get minExtent => 36;
  @override
  double get maxExtent => 36;
  @override
  bool shouldRebuild(covariant _TableHeader old) =>
      old.showAdded != showAdded || old.sort != sort || old.asc != asc;

  Widget _col(String label, _Sort k, {int flex = 1, Widget? icon}) {
    final on = sort == k;
    final child = InkWell(
      onTap: () => onSort(k),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) icon else
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: on ? Colors.white : AppColors.textSecondary)),
        if (on) ...[
          const SizedBox(width: 4),
          Icon(asc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 18, color: AppColors.accent),
        ],
      ]),
    );
    return Expanded(flex: flex, child: Align(alignment: Alignment.centerLeft, child: child));
  }

  @override
  Widget build(BuildContext context, double shrink, bool overlaps) {
    final first = sort == _Sort.artist ? _Sort.artist : _Sort.title;
    final firstLabel = sort == _Sort.artist ? 'Artista' : 'Título';
    return Container(
      color: overlaps ? const Color(0xFF181818) : AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        Expanded(
          child: Row(children: [
            const SizedBox(
                width: 32,
                child: Center(
                    child: Text('#',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)))),
            const SizedBox(width: 60),
            _col(firstLabel, first, flex: 5),
            _col('Álbum', _Sort.album, flex: 4),
            if (showAdded) _col('Adicionada em', _Sort.added, flex: 3),
            const SizedBox(width: 40),
            SizedBox(
              width: 48,
              child: InkWell(
                onTap: () => onSort(_Sort.duration),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.schedule,
                      size: 16, color: AppColors.textSecondary),
                  if (sort == _Sort.duration)
                    Icon(asc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        size: 16, color: AppColors.accent),
                ]),
              ),
            ),
            const SizedBox(width: 40),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
      ]),
    );
  }
}

class _ChipsHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final Color color;
  _ChipsHeader({required this.child, required this.color});
  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;
  @override
  bool shouldRebuild(covariant _ChipsHeader old) => true;
  @override
  Widget build(BuildContext context, double shrink, bool overlaps) =>
      Container(color: overlaps ? color : Colors.transparent, child: child);
}
