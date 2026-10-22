import '../widgets/net_image.dart';
import '../widgets/context_menu.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/smooth_scroll.dart';
import 'package:flutter/material.dart';

import '../core/audio/player_service.dart';
import '../core/connect/connect_service.dart';
import '../core/format.dart';
import '../core/i18n/strings.dart';
import '../core/jellyfin/jellyfin_client.dart';
import '../core/jellyfin/models.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/playlists/playlists_page.dart';
import '../features/artists/artist_page.dart';
import '../features/search/desktop_search.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/cover.dart';
import '../widgets/devices_sheet.dart';
import '../widgets/volume_control.dart';
import 'app_scope.dart';
import 'theme.dart';

enum _Right { none, queue, recent, devices }

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});
  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final _nav = GlobalKey<NavigatorState>();
  int _index = 0;
  _Right _right = _Right.queue;
  _Right _last = _Right.queue;
  double _leftRaw = 340;
  double _rightW = 348;
  bool _dragging = false;
  int _lib = 0;

  static const _pages = [HomePage(), SearchPage(), LibraryPage()];

  double get _leftW => _leftRaw < 180 ? 72 : _leftRaw.clamp(180.0, 384.0);

  void _tab(int i) {
    _nav.currentState?.popUntil((r) => r.isFirst);
    setState(() => _index = i);
  }

  void _toggle(_Right r) => setState(() {
        if (_right != _Right.none) _last = _right;
        _right = _right == r ? _Right.none : r;
      });

  void _openArtist(String name) => _nav.currentState?.push(
      MaterialPageRoute(builder: (_) => ArtistPage(name: name)));

  void _search(String q) => _nav.currentState?.push(MaterialPageRoute(
      builder: (_) => SearchResultsPage(query: q, onOpenArtist: _openArtist)));

  BoxDecoration get _panel => BoxDecoration(
      color: AppColors.background, borderRadius: BorderRadius.circular(8));

  @override
  Widget build(BuildContext context) {
    final open = _right != _Right.none;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(children: [
        _TopBar(
          onBack: () => _nav.currentState?.maybePop(),
          onHome: () => _tab(0),
          onSearch: _search,
          onArtist: _openArtist,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Row(children: [
              SizedBox(
                width: _leftW,
                child: Container(
                  decoration: _panel,
                  clipBehavior: Clip.antiAlias,
                  child: _LeftPanel(
                    compact: _leftW <= 100,
                    mode: _lib,
                    onMode: (m) => setState(() => _lib = m),
                    nav: _nav,
                    onAllSongs: () => _tab(2),
                    onArtist: _openArtist,
                  ),
                ),
              ),
              _Resizer(
                onStart: () => setState(() => _dragging = true),
                onEnd: () => setState(() => _dragging = false),
                onDelta: (dx) => setState(() => _leftRaw =
                    (_leftRaw + dx).clamp(60.0, 384.0).toDouble()),
              ),
              Expanded(
                child: Container(
                  decoration: _panel,
                  clipBehavior: Clip.antiAlias,
                  child: Navigator(
                    key: _nav,
                    onGenerateRoute: (_) => MaterialPageRoute(
                        builder: (_) =>
                            IndexedStack(index: _index, children: _pages)),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: open ? _rightW + 8 : 0,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerRight,
                    minWidth: _rightW + 8,
                    maxWidth: _rightW + 8,
                    child: Row(children: [
                      _Resizer(
                        onStart: () => setState(() => _dragging = true),
                        onEnd: () => setState(() => _dragging = false),
                        onDelta: (dx) => setState(() => _rightW =
                            (_rightW - dx).clamp(256.0, 384.0).toDouble()),
                      ),
                      Expanded(
                        child: Container(
                          decoration: _panel,
                          clipBehavior: Clip.antiAlias,
                          child: _RightPanel(
                              mode: open ? _right : _last,
                              onMode: (m) => setState(() => _right = m),
                              onClose: () =>
                                  setState(() => _right = _Right.none)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
        const PlayingOnBar(),
        _BottomBar(right: _right, onToggle: _toggle, onArtist: _openArtist),
      ]),
    );
  }
}

class _Resizer extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final void Function(double dx) onDelta;
  const _Resizer(
      {required this.onStart, required this.onEnd, required this.onDelta});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => onStart(),
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        onHorizontalDragCancel: onEnd,
        child: const SizedBox(width: 8, height: double.infinity),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onHome;
  final void Function(String) onSearch;
  final void Function(String) onArtist;
  const _TopBar(
      {required this.onBack,
      required this.onHome,
      required this.onSearch,
      required this.onArtist});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(children: [
        const SizedBox(width: 8),
        IconButton(
            tooltip: 'Voltar',
            icon: const Icon(Icons.chevron_left),
            onPressed: onBack),
        const Spacer(),
        Material(
          color: AppColors.elevated,
          shape: const CircleBorder(),
          child: IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: onHome,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 420,
          child: DesktopSearchBox(onSubmit: onSearch, onOpenArtist: onArtist),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Configurações',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => openSettings(context),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }
}

class _Entry {
  final String id;
  final String title;
  final String sub;
  final Widget image;
  final bool round;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;
  final void Function(BuildContext, Offset)? onMenu;
  const _Entry(
      {this.onMenu,
      required this.id,
      required this.title,
      required this.sub,
      required this.image,
      required this.onTap,
      this.round = false,
      this.selected = false,
      this.playing = false});
}

class _LeftPanel extends StatelessWidget {
  final bool compact;
  final int mode;
  final ValueChanged<int> onMode;
  final GlobalKey<NavigatorState> nav;
  final VoidCallback onAllSongs;
  final void Function(String) onArtist;
  const _LeftPanel(
      {required this.compact,
      required this.mode,
      required this.onMode,
      required this.nav,
      required this.onAllSongs,
      required this.onArtist});

  Widget _img(AppScope scope, String id, {IconData fallback = Icons.queue_music}) {
    final client = scope.client;
    if (fallback == Icons.queue_music) {
      return PlaylistCover(id: id, size: 48, radius: 0);
    }
    return NetImage(
      client.imageUri(id, maxWidth: 120).toString(),
      headers: client.authHeaders,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
          color: AppColors.elevated,
          child: Icon(fallback, color: AppColors.textSecondary)),
    );
  }

  Widget _chip(String label, int i) {
    final on = mode == i;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onMode(on ? 0 : i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
              color: on ? Colors.white : const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(20)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: on ? Colors.black : Colors.white)),
        ),
      ),
    );
  }

  Widget _row(_Entry e) => Builder(
      builder: (ctx) => MenuTarget(
          onMenu: (p) => e.onMenu?.call(ctx, p), child: _rowInner(e)));

  Widget _rowInner(_Entry e) {
    if (compact) {
      return Tooltip(
        message: e.title,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: InkWell(
            onTap: e.onTap,
            borderRadius: BorderRadius.circular(e.round ? 24 : 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(e.round ? 24 : 4),
              child: SizedBox(width: 48, height: 48, child: e.image),
            ),
          ),
        ),
      );
    }
    return Material(
      color: e.selected ? const Color(0xFF2A2A2A) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: e.onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(e.round ? 24 : 4),
              child: SizedBox(width: 48, height: 48, child: e.image),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color:
                                e.playing ? AppColors.accent : Colors.white)),
                    if (e.sub.isNotEmpty)
                      Text(e.sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final svc = scope.playlists;
    final user = scope.client.session?.username ?? '';

    Future<void> create() async {
      final name = await askName(context);
      if (name == null || name.trim().isEmpty) return;
      await svc.create(name, const []);
    }

    Widget list(List<_Entry> items) => SmoothListView(
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 8),
          children: [for (final e in items) _row(e)],
        );

    Widget body() {
      final player = scope.player;
      if (mode == 1) {
        return FutureBuilder<List<LibItem>>(
          future: scope.client.libraryAlbums(),
          initialData: scope.client.albumsCache,
          builder: (_, s) => ListenableBuilder(
            listenable: player,
            builder: (_, __) => list([
              for (final a in s.data ?? const <LibItem>[])
                _Entry(
                  id: a.id,
                  title: a.name,
                  sub: '${S.t('album')} • ${a.sub}',
                  image: _img(scope, a.id, fallback: Icons.album),
                  playing: player.queueSource == a.name,
                  onMenu: (c, pos) => showAlbumMenu(c, pos,
                      albumId: a.id, name: a.name, artist: a.sub),
                  onTap: () async {
                    final l = await scope.client.albumTracks(a.id);
                    if (l.isNotEmpty) {
                      player.playQueue(l, 0, source: a.name);
                    }
                  },
                ),
            ]),
          ),
        );
      }
      if (mode == 2) {
        return FutureBuilder<List<LibItem>>(
          future: scope.client.libraryArtists(),
          initialData: scope.client.artistsCache,
          builder: (_, s) => ListenableBuilder(
            listenable: player,
            builder: (_, __) => list([
              for (final a in s.data ?? const <LibItem>[])
                _Entry(
                  id: a.id,
                  title: a.name,
                  sub: S.t('artist'),
                  round: true,
                  image: _img(scope, a.id, fallback: Icons.person),
                  playing: player.queueSource == a.name,
                  onTap: () => onArtist(a.name),
                ),
            ]),
          ),
        );
      }
      return ListenableBuilder(
        listenable: Listenable.merge([svc, player, openPlaylists]),
        builder: (_, __) {
          final top = openPlaylists.value.isEmpty ? null : openPlaylists.value.last;
          return list([
            _Entry(
              id: 'liked',
              title: S.t('liked'),
              sub: 'Playlist • $user',
              image: Container(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xFF4A2FD0), Color(0xFF9B8CF0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight)),
                child: const Icon(Icons.favorite, color: Colors.white, size: 22),
              ),
              playing: player.queueSource == S.t('liked'),
              onTap: () => nav.currentState?.push(MaterialPageRoute(
                  builder: (_) => const FavoritesPage())),
            ),
            _Entry(
              id: 'all',
              title: 'Todas as músicas',
              sub: 'Biblioteca',
              image: Container(
                  color: AppColors.elevated,
                  child: const Icon(Icons.library_music,
                      color: AppColors.textSecondary)),
              onTap: onAllSongs,
            ),
            for (final p in svc.playlists)
              _Entry(
                id: p.id,
                title: p.name,
                sub: 'Playlist • $user',
                image: _img(scope, p.id),
                selected: top == p.id,
                playing: player.queueSource == p.name,
                onMenu: (c, pos) => showPlaylistMenu(c, pos, p),
                onTap: () {
                  final n = nav.currentState;
                  if (n != null) openPlaylist(n, p);
                },
              ),
          ]);
        },
      );
    }

    return Column(children: [
      if (compact) ...[
        const SizedBox(height: 12),
        const Icon(Icons.library_music_outlined,
            color: AppColors.textSecondary),
        IconButton(icon: const Icon(Icons.add), onPressed: create),
      ] else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(children: [
            Expanded(
                child: Text(S.t('your_library'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700))),
            TextButton.icon(
              style: TextButton.styleFrom(
                  backgroundColor: AppColors.elevated,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder()),
              icon: const Icon(Icons.add, size: 18),
              label: Text(S.t('create')),
              onPressed: create,
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip(S.t('playlists'), 0),
              _chip(S.t('albums'), 1),
              _chip(S.t('artists'), 2),
            ]),
          ),
        ),
      ],
      Expanded(child: body()),
    ]);
  }
}

class _RightPanel extends StatelessWidget {
  final _Right mode;
  final ValueChanged<_Right> onMode;
  final VoidCallback onClose;
  const _RightPanel(
      {required this.mode, required this.onMode, required this.onClose});

  Widget _tab(String label, _Right m) {
    final on = mode == m;
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: InkWell(
        onTap: () => onMode(m),
        child: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: on ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).player;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
        child: Row(children: [
          if (mode == _Right.devices)
            const Expanded(
                child: Text('Connect',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)))
          else
            Expanded(
                child: Row(children: [
              _tab('Fila', _Right.queue),
              _tab('Tocado recentemente', _Right.recent),
            ])),
          IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ]),
      ),
      Expanded(
        child: switch (mode) {
          _Right.queue => _QueueView(player: p),
          _Right.recent => const _RecentView(),
          _ => const _DevicesView(),
        },
      ),
    ]);
  }
}

class _TrackRow extends StatelessWidget {
  final Track track;
  final bool current;
  final VoidCallback onTap;
  const _TrackRow(
      {required this.track, required this.onTap, this.current = false});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Cover(track: track, size: 44),
      title: Text(track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: FontWeight.w500,
              color: current ? AppColors.accent : Colors.white)),
      subtitle: Text(track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary)),
      onTap: onTap,
    );
  }
}

Widget _section(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
    );

class _QueueView extends StatelessWidget {
  final PlayerService player;
  const _QueueView({required this.player});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final cur = player.current;
        if (cur == null) {
          return const Center(
              child: Text('Nada na fila',
                  style: TextStyle(color: AppColors.textSecondary)));
        }
        final next = <int>[];
        if (!player.isMirror) {
          for (var i = player.orderPos + 1;
              i < player.queueLength && next.length < 100;
              i++) {
            next.add(i);
          }
        }
        return SmoothListView(children: [
          _section('Tocando agora'),
          _TrackRow(track: cur, current: true, onTap: () {}),
          if (next.isNotEmpty)
            _section(player.queueSource == null
                ? 'Próximas'
                : 'Próximas de: ${player.queueSource}'),
          for (final i in next)
            _TrackRow(
                track: player.trackAtOrder(i),
                onTap: () => player.jumpToOrder(i)),
        ]);
      },
    );
  }
}

class _RecentView extends StatefulWidget {
  const _RecentView();
  @override
  State<_RecentView> createState() => _RecentViewState();
}

class _RecentViewState extends State<_RecentView> {
  Future<List<Track>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= AppScope.of(context).client.recentlyPlayed();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).player;
    return FutureBuilder<List<Track>>(
      future: _f,
      builder: (context, s) {
        if (!s.hasData) {
          return Center(
              child: s.hasError
                  ? const Text('Não foi possível carregar.',
                      style: TextStyle(color: AppColors.textSecondary))
                  : const CircularProgressIndicator());
        }
        final l = s.data!;
        return SmoothListView.builder(
          itemCount: l.length,
          itemBuilder: (_, i) =>
              _TrackRow(track: l[i], onTap: () => p.playQueue(l, i)),
        );
      },
    );
  }
}

class _DevicesView extends StatefulWidget {
  const _DevicesView();
  @override
  State<_DevicesView> createState() => _DevicesViewState();
}

class _DevicesViewState extends State<_DevicesView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => AppScope.of(context).connect.poll());
  }

  IconData _icon(String n) {
    final s = n.toLowerCase();
    if (s.contains('android') || s.contains('phone') || s.contains('ios')) {
      return Icons.smartphone;
    }
    if (s.contains('web') || s.contains('chrome')) return Icons.language;
    return Icons.computer;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.connect, scope.player]),
      builder: (context, _) {
        final c = scope.connect;
        final m = scope.player.mirror;
        final ok = c.canConnect && !c.transferring;

        Future<void> pick(RemoteDevice? d) async {
          final err = await c.transferTo(d);
          if (err != null) messenger.showSnackBar(SnackBar(content: Text(err)));
        }

        Widget row(IconData icon, String title, String? sub, bool on,
            VoidCallback? tap) {
          return ListTile(
            leading: Icon(icon, color: on ? AppColors.accent : Colors.white),
            title: Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: on ? AppColors.accent : Colors.white)),
            subtitle: sub == null
                ? null
                : Text(sub,
                    style: const TextStyle(color: AppColors.textSecondary)),
            onTap: tap,
          );
        }

        return SmoothListView(children: [
          Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
                color: AppColors.elevated,
                borderRadius: BorderRadius.circular(8)),
            child: row(
                _icon(c.myName),
                'Este dispositivo',
                c.myName,
                m == null,
                ok ? () => pick(null) : null),
          ),
          if (!c.canConnect)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sem conexão com o servidor.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          for (final d in c.devices)
            row(
                _icon(d.name),
                d.name,
                d.playing
                    ? 'Tocando agora'
                    : (d.track != null ? 'Pausado' : null),
                m?.sessionId == d.id,
                ok ? () => pick(d) : null),
          if (c.devices.isEmpty && c.canConnect)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhum outro dispositivo aberto nesta conta.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
        ]);
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  final _Right right;
  final ValueChanged<_Right> onToggle;
  final void Function(String) onArtist;
  const _BottomBar(
      {required this.right, required this.onToggle, required this.onArtist});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final p = scope.player;
    final fav = scope.favorites;
    return SizedBox(
      height: 84,
      child: ListenableBuilder(
        listenable: Listenable.merge([p, fav]),
        builder: (context, _) {
          final t = p.current;
          return Row(children: [
            Expanded(
              flex: 3,
              child: t == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Cover(key: ValueKey(t.id), track: t, size: 56),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                InkWell(
                                  onTap: () => onArtist(t.artist),
                                  child: Text(t.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                ),
                              ]),
                        ),
                        IconButton(
                          icon: Icon(
                              fav.isFavorite(t.id)
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline,
                              size: 20,
                              color: fav.isFavorite(t.id)
                                  ? AppColors.accent
                                  : AppColors.textSecondary),
                          onPressed: () => fav.toggle(t),
                        ),
                      ]),
                    ),
            ),
            Expanded(
              flex: 4,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: Icon(Icons.shuffle,
                                    size: 20,
                                    color: p.shuffle
                                        ? AppColors.accent
                                        : AppColors.textSecondary),
                                onPressed: p.toggleShuffle,
                              ),
                              IconButton(
                                  icon: const Icon(Icons.skip_previous),
                                  onPressed: () => p.previous()),
                              Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  color: Colors.black,
                                  icon: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 150),
                                    transitionBuilder: (c, a) =>
                                        ScaleTransition(scale: a, child: c),
                                    child: Icon(
                                        p.playing
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        key: ValueKey(p.playing)),
                                  ),
                                  onPressed: () => p.togglePlay(),
                                ),
                              ),
                              IconButton(
                                  icon: const Icon(Icons.skip_next),
                                  onPressed: () => p.next()),
                              IconButton(
                                icon: Icon(
                                    p.repeat == QueueRepeat.one
                                        ? Icons.repeat_one
                                        : Icons.repeat,
                                    size: 20,
                                    color: p.repeat == QueueRepeat.off
                                        ? AppColors.textSecondary
                                        : AppColors.accent),
                                onPressed: p.cycleRepeat,
                              ),
                            ]),
                        _SeekBar(player: p),
                      ]),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                IconButton(
                  tooltip: 'Fila',
                  icon: Icon(Icons.queue_music,
                      color: right == _Right.queue || right == _Right.recent
                          ? AppColors.accent
                          : AppColors.textSecondary),
                  onPressed: () => onToggle(_Right.queue),
                ),
                IconButton(
                  tooltip: 'Dispositivos',
                  icon: Icon(Icons.speaker_group_outlined,
                      color: right == _Right.devices || p.isMirror
                          ? AppColors.accent
                          : AppColors.textSecondary),
                  onPressed: () => onToggle(_Right.devices),
                ),
                const SizedBox(width: 190, child: VolumeControl(expand: true)),
                const SizedBox(width: 8),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  final PlayerService player;
  const _SeekBar({required this.player});
  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    return StreamBuilder<Duration>(
      stream: p.positionStream,
      builder: (_, snap) {
        final pos = p.displayPosition(snap.data ?? Duration.zero);
        final total = p.duration.inMilliseconds.toDouble();
        final cur = (_drag ?? pos.inMilliseconds.toDouble())
            .clamp(0.0, total <= 0 ? 1.0 : total)
            .toDouble();
        const st = TextStyle(fontSize: 11, color: AppColors.textSecondary);
        return Row(children: [
          SizedBox(
              width: 44,
              child: Text(fmtDuration(Duration(milliseconds: cur.round())),
                  textAlign: TextAlign.right, style: st)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5)),
              child: Slider(
                value: cur,
                max: total <= 0 ? 1.0 : total,
                onChanged: total <= 0 ? null : (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  p.seek(Duration(milliseconds: v.round()));
                  setState(() => _drag = null);
                },
              ),
            ),
          ),
          SizedBox(
              width: 44,
              child: Text(fmtDuration(Duration(milliseconds: total.round())),
                  style: st)),
        ]);
      },
    );
  }
}
