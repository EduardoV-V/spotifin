import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/jellyfin_client.dart';
import '../../core/jellyfin/models.dart';
import '../../core/artists/artist_info_service.dart';
import '../../core/recent/recent_store.dart';
import '../../widgets/cover.dart';
import '../../widgets/playlist_cover.dart';
import '../artists/artist_page.dart';
import '../../widgets/context_menu.dart';
import 'music_browser.dart';
import '../../widgets/devices_sheet.dart';
import '../../widgets/track_tile.dart';
import '../downloads/downloads_page.dart';
import '../playlists/playlists_page.dart';
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeFeed? _feed;
  bool _loading = true;
  String? _error;
  bool _init = false;
  late final AppScope _scope;
  bool _music = false;
  bool _allPl = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _scope = AppScope.of(context);
    _scope.reload.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    _scope.reload.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _load(force: true);

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = _feed == null;
      _error = null;
    });
    try {
      final f = await _scope.client.homeFeed(force: force);
      if (mounted) setState(() => _feed = f);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro de rede ao carregar músicas.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_Album> _albums(List<Track> l) {
    final seen = <String>{};
    final out = <_Album>[];
    for (final t in l) {
      final k = t.albumId ?? t.id;
      if (seen.add(k)) out.add(_Album(t));
    }
    return out;
  }

  List<_Mix> _mixes(HomeFeed f) {
    final count = <String, int>{};
    final first = <String, Track>{};
    for (final t in [...f.top, ...f.recent]) {
      if (t.artist.isEmpty) continue;
      count[t.artist] = (count[t.artist] ?? 0) + 1;
      first.putIfAbsent(t.artist, () => t);
    }
    final names = count.keys.toList()
      ..sort((a, b) => count[b]!.compareTo(count[a]!));
    return [
      for (final n in names.take(8)) _Mix(n, first[n]!),
    ];
  }

  Future<void> _playAlbum(Track t) async {
    if (t.albumId == null) {
      await _scope.player.playQueue([t], 0);
      return;
    }
    try {
      final l = await _scope.client.albumTracks(t.albumId!);
      if (l.isEmpty) return;
      final i = l.indexWhere((e) => e.id == t.id);
      RecentStore.instance
          .add('album', t.albumId!, t.album.isEmpty ? t.title : t.album, t.artist);
      await _scope.player.playQueue(l, i < 0 ? 0 : i);
    } catch (_) {}
  }

  void _openRecent(BuildContext context, RecentItem r) {
    switch (r.kind) {
      case 'playlist':
        final i = _scope.playlists.playlists.indexWhere((p) => p.id == r.id);
        if (i >= 0) _openPlaylist(context, _scope.playlists.playlists[i]);
      case 'artist':
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ArtistPage(name: r.name)));
      case 'album':
        _scope.client.albumTracks(r.id).then((l) {
          if (l.isNotEmpty) {
            RecentStore.instance.add('album', r.id, r.name, r.sub);
            _scope.player.playQueue(l, 0);
          }
        }).catchError((_) {});
    }
  }

  Future<void> _playMix(_Mix m) async {
    try {
      final l = await _scope.client.searchTracks(m.artist, limit: 80);
      final mine = l.where((t) => t.artist == m.artist).toList();
      final q = (mine.isEmpty ? l : mine)..shuffle();
      if (q.isNotEmpty) await _scope.player.playQueue(q, 0);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 700;
      final pad = wide ? 24.0 : 16.0;
      final card = wide ? 160.0 : 140.0;
      return Stack(children: [
        Container(
          height: 300,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF212121), Color(0xFF121212)]),
          ),
        ),
        SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _feed == null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: _load,
                          child: const Text('Tentar de novo')),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const DownloadsPage())),
                        child: const Text('Ver músicas baixadas'),
                      ),
                    ]),
                  )
                : ListenableBuilder(
                    listenable: _scope.playlists,
                    builder: (context, _) =>
                        _content(context, wide, pad, card)),
      ),
      ]);
    });
  }

  Widget _content(BuildContext context, bool wide, double pad, double card) {
    final f = _feed!;
    final lists = _scope.playlists.playlists;
    final albums = _albums(f.recent);
    final user = _scope.client.session?.username ?? '';
    final top = <Widget>[
      if (!wide)
        Row(children: [
          const Expanded(
              child: Text('Início',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
          const DevicesButton(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => openSettings(context),
          ),
        ]),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          _chip('Tudo', !_music, () => setState(() => _music = false)),
          const SizedBox(width: 8),
          _chip('Música', _music, () => setState(() => _music = true)),
        ]),
      ),
    ];
    if (_music) {
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
        child: Column(children: [
          ...top,
          const Expanded(child: MusicBrowser()),
        ]),
      );
    }
    return ListView(padding: EdgeInsets.fromLTRB(pad, 8, pad, 24), children: [
      ...top,
      const SizedBox(height: 8),
      ListenableBuilder(
        listenable: RecentStore.instance,
        builder: (context, _) =>
            _shortcuts(context, lists, wide ? 4 : 2, RecentStore.instance.items),
      ),
      if (lists.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 28, 0, 12),
          child: Row(children: [
            Expanded(
              child: Text(user.isEmpty ? 'Suas playlists' : 'Playlists de $user',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => setState(() => _allPl = !_allPl),
              child: Text(_allPl ? 'Mostrar menos' : 'Mostrar tudo',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        if (_allPl)
          Wrap(spacing: 16, runSpacing: 16, children: [
            for (final p in lists)
              _CardItem(
                size: card,
                title: p.name,
                subtitle: 'Playlist • ${p.count} faixas',
                image: PlaylistCover(id: p.id, size: card),
                onTap: () => _openPlaylist(context, p),
                onMenu: (pos) => showPlaylistMenu(context, pos, p),
              ),
          ])
        else
          _row(card, [
            for (final p in lists)
              _CardItem(
                size: card,
                title: p.name,
                subtitle: 'Playlist • ${p.count} faixas',
                image: PlaylistCover(id: p.id, size: card),
                onTap: () => _openPlaylist(context, p),
                onMenu: (pos) => showPlaylistMenu(context, pos, p),
              ),
          ]),
      ],
      if (albums.isNotEmpty) ...[
        _title('Recentes'),
        _row(card, [
          for (final a in albums.take(20))
            _CardItem(
              size: card,
              title: a.track.album.isEmpty ? a.track.title : a.track.album,
              subtitle: 'Álbum • ${a.track.artist}',
              image: Cover(track: a.track, size: card),
              onTap: () => _playAlbum(a.track),
              onMenu: a.track.albumId == null
                  ? null
                  : (pos) => showAlbumMenu(context, pos,
                      albumId: a.track.albumId!,
                      name: a.track.album,
                      artist: a.track.artist),
            ),
        ]),
      ],
      if (f.added.isNotEmpty) ...[
        _title('Adicionadas recentemente'),
        _row(card, [
          for (var i = 0; i < f.added.length; i++)
            _CardItem(
              size: card,
              title: f.added[i].title,
              subtitle: f.added[i].artist,
              image: Cover(track: f.added[i], size: card),
              onTap: () => _scope.player.playQueue(f.added, i),
            ),
        ]),
      ],
      if (f.top.isNotEmpty) ...[
        _title('Mais tocadas'),
        _row(card, [
          for (var i = 0; i < f.top.length; i++)
            _CardItem(
              size: card,
              title: f.top[i].title,
              subtitle: f.top[i].artist,
              image: Cover(track: f.top[i], size: card),
              onTap: () => _scope.player.playQueue(f.top, i),
            ),
        ]),
      ],
    ]);
  }

  Widget _chip(String t, bool on, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: on ? AppColors.accent : const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(20)),
          child: Text(t,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: on ? Colors.black : Colors.white)),
        ),
      );

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 28, 0, 12),
        child: Text(t,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      );

  Widget _row(double card, List<Widget> children) => SizedBox(
        height: card + 62,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: children.length,
          separatorBuilder: (_, __) => const SizedBox(width: 16),
          itemBuilder: (_, i) => children[i],
        ),
      );

  void _openPlaylist(BuildContext context, PlaylistInfo p) =>
      openPlaylist(Navigator.of(context), p);

  Widget _shortcuts(BuildContext context, List<PlaylistInfo> lists, int cols,
      List<RecentItem> recent) {
    final n = cols * 2;
    final items = <Widget>[];
    for (final r in recent) {
      if (items.length >= n) break;
      if (r.kind == 'playlist' && !lists.any((p) => p.id == r.id)) continue;
      items.add(_Shortcut(
        title: r.name,
        image: r.kind == 'playlist'
            ? PlaylistCover(id: r.id, size: 56, radius: 0)
            : _RecentImage(r),
        onTap: () => _openRecent(context, r),
        onMenu: (pos) {
          if (r.kind == 'playlist') {
            final i = lists.indexWhere((p) => p.id == r.id);
            if (i >= 0) showPlaylistMenu(context, pos, lists[i]);
          } else if (r.kind == 'album') {
            showAlbumMenu(context, pos,
                albumId: r.id, name: r.name, artist: r.sub);
          }
        },
      ));
    }
    if (items.length < n) {
      items.add(_Shortcut(
        title: 'Músicas curtidas',
        image: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF4A2FD0), Color(0xFF9B8CF0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: const Icon(Icons.favorite, color: Colors.white, size: 26),
        ),
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FavoritesPage())),
      ));
      for (final p in lists) {
        if (items.length >= n) break;
        if (recent.any((r) => r.kind == 'playlist' && r.id == p.id)) continue;
        items.add(_Shortcut(
          title: p.name,
          image: PlaylistCover(id: p.id, size: 56, radius: 0),
          onTap: () => _openPlaylist(context, p),
          onMenu: (pos) => showPlaylistMenu(context, pos, p),
        ));
      }
    }
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: cols == 4 ? 4.4 : 3.2,
      children: items,
    );
  }
}

class _RecentImage extends StatelessWidget {
  final RecentItem r;
  const _RecentImage(this.r);
  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context).client;
    if (r.kind == 'artist') {
      return FutureBuilder<ArtistInfo?>(
        future: ArtistInfoService.instance.get(r.name),
        builder: (_, s) {
          final u = s.data?.picture;
          return u == null
              ? Container(
                  color: AppColors.elevated,
                  child: const Icon(Icons.person,
                      color: AppColors.textSecondary))
              : Image.network(u, fit: BoxFit.cover);
        },
      );
    }
    return Image.network(c.imageUri(r.id, maxWidth: 120).toString(),
        headers: c.authHeaders,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: AppColors.elevated));
  }
}

class _Album {
  final Track track;
  _Album(this.track);
}

class _Mix {
  final String artist;
  final Track track;
  _Mix(this.artist, this.track);
}

class _PlaylistImage extends StatelessWidget {
  final PlaylistInfo p;
  final double size;
  const _PlaylistImage(this.p, this.size);

  @override
  Widget build(BuildContext context) {
    final client = AppScope.of(context).client;
    return Image.network(
      client.imageUri(p.id, maxWidth: (size * 2).round()).toString(),
      headers: client.authHeaders,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
          color: AppColors.elevated,
          child: const Icon(Icons.queue_music, color: AppColors.textSecondary)),
    );
  }
}

class _Shortcut extends StatelessWidget {
  final String title;
  final Widget image;
  final VoidCallback onTap;
  final void Function(Offset)? onMenu;
  const _Shortcut(
      {required this.title,
      required this.image,
      required this.onTap,
      this.onMenu});

  @override
  Widget build(BuildContext context) {
    return MenuTarget(
      onMenu: (p) => onMenu?.call(p),
      child: Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(children: [
          AspectRatio(aspectRatio: 1, child: image),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 8),
        ]),
      ),
    ));
  }
}

class _CardItem extends StatelessWidget {
  final double size;
  final String title;
  final String subtitle;
  final Widget image;
  final VoidCallback onTap;
  final void Function(Offset)? onMenu;
  const _CardItem(
      {this.onMenu,
      required this.size,
      required this.title,
      required this.subtitle,
      required this.image,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MenuTarget(
      onMenu: (p) => onMenu?.call(p),
      child: SizedBox(
      width: size,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(width: size, height: size, child: image),
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text(subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ]),
      ),
    ));
  }
}

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});
  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Track>? _l;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_l == null) {
      AppScope.of(context).client.favoriteTracks().then((v) {
        if (mounted) setState(() => _l = v);
      }).catchError((_) {
        if (mounted) setState(() => _l = const []);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).player;
    final l = _l;
    return Scaffold(
      appBar: AppBar(title: const Text('Músicas curtidas')),
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: l.length,
              itemBuilder: (_, i) => TrackTile(
                  track: l[i], onTap: () => p.playQueue(List.of(l), i)),
            ),
    );
  }
}
