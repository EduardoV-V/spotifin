import '../../widgets/net_image.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/download_badge.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/downloads/auto_download.dart';
import '../../core/jellyfin/jellyfin_client.dart';
import '../../core/jellyfin/models.dart';
import '../../core/recent/recent_store.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/playlist_cover.dart';
import '../../widgets/smooth_scroll.dart';
import '../../widgets/track_tile.dart';
import '../albums/album_page.dart';
import '../artists/artist_page.dart';
import '../create/create_sheet.dart';
import '../home/home_page.dart';
import '../playlists/playlists_page.dart';
import '../search/desktop_search.dart';
import '../settings/settings_page.dart';

class _E {
  final String kind; // liked | playlist | album | artist
  final String id;
  final String name;
  final String sub;
  final PlaylistInfo? pl;
  const _E(this.kind, this.id, this.name, this.sub, [this.pl]);
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _filter = 0; // 0 todos, 1 playlists, 2 álbuns, 3 artistas, 4 baixado
  bool _grid = false;
  bool _alpha = false;
  bool _search = false;
  String _q = '';
  List<LibItem> _albums = const [];
  List<LibItem> _artists = const [];
  bool _init = false;
  late final AppScope _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _scope = AppScope.of(context);
    _albums = _scope.client.albumsCache ?? const [];
    _artists = _scope.client.artistsCache ?? const [];
    _scope.client.libraryAlbums().then((v) {
      if (mounted) setState(() => _albums = v);
    }).catchError((_) {});
    _scope.client.libraryArtists().then((v) {
      if (mounted) setState(() => _artists = v);
    }).catchError((_) {});
  }

  List<_E> _items() {
    final user = _scope.client.session?.username ?? '';
    final pls = _scope.playlists.playlists;
    final liked = _E('liked', 'liked', 'Músicas curtidas', 'Playlist • $user');
    final plEs = [
      for (final p in pls) _E('playlist', p.id, p.name, 'Playlist • $user', p)
    ];
    final alEs = [for (final a in _albums) _E('album', a.id, a.name, 'Álbum • ${a.sub}')];
    final arEs = [for (final a in _artists) _E('artist', a.id, a.name, 'Artista')];
    List<_E> out;
    switch (_filter) {
      case 1:
        out = [liked, ...plEs];
      case 2:
        out = alEs;
      case 3:
        out = arEs;
      default:
        final all = [...plEs, ...alEs, ...arEs];
        final used = <String>{};
        out = [];
        for (final r in RecentStore.instance.items) {
          final i = all.indexWhere((e) => e.kind == r.kind && e.id == r.id);
          if (i >= 0 && used.add('${r.kind}:${r.id}')) out.add(all[i]);
          if (out.length >= 40) break;
        }
        out.insert(out.length.clamp(0, 2), liked);
        for (final e in plEs) {
          if (used.add('playlist:${e.id}')) out.add(e);
        }
    }
    if (_alpha) {
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((e) => e.name.toLowerCase().contains(q)).toList();
    }
    return out;
  }

  void _open(_E e) {
    final nav = Navigator.of(context);
    switch (e.kind) {
      case 'liked':
        nav.push(MaterialPageRoute(builder: (_) => const FavoritesPage()));
      case 'playlist':
        openPlaylist(nav, e.pl!);
      case 'album':
        nav.push(MaterialPageRoute(
            builder: (_) => AlbumPage(
                albumId: e.id,
                name: e.name,
                artist: e.sub.replaceFirst('Álbum • ', ''))));
      case 'artist':
        nav.push(MaterialPageRoute(builder: (_) => ArtistPage(name: e.name)));
    }
  }

  void _menu(_E e) {
    switch (e.kind) {
      case 'playlist':
        showPlaylistMenu(context, Offset.zero, e.pl!);
      case 'album':
        showAlbumMenu(context, Offset.zero,
            albumId: e.id,
            name: e.name,
            artist: e.sub.replaceFirst('Álbum • ', ''));
    }
  }

  Widget _image(_E e, double size) {
    switch (e.kind) {
      case 'liked':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                  colors: [Color(0xFF4A2FD0), Color(0xFF9B8CF0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: Icon(Icons.favorite, color: Colors.white, size: size * 0.4),
        );
      case 'playlist':
        return PlaylistCover(id: e.id, size: size);
      case 'artist':
        return ArtistAvatar(name: e.name, size: size);
      default:
        final c = _scope.client;
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: size,
            height: size,
            child: NetImage(
                c.imageUri(e.id, maxWidth: (size * 2).round()).toString(),
                headers: c.authHeaders,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AppColors.elevated)),
          ),
        );
    }
  }

  Widget _row(_E e) {
    final pl = _scope.player;
    final playing = pl.queueSource == e.name;
    return InkWell(
      onTap: () => _open(e),
      onLongPress: () => _menu(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          _image(e, 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: playing ? AppColors.accent : Colors.white)),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (e.kind == 'playlist' &&
                        AutoDownload.instance.enabled(e.id))
                      const Padding(
                          padding: EdgeInsets.only(right: 5),
                          child: Icon(Icons.arrow_circle_down,
                              size: 14, color: AppColors.accent)),
                    Flexible(
                      child: Text(e.sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ),
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _tile(_E e) {
    final playing = _scope.player.queueSource == e.name;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _open(e),
      onLongPress: () => _menu(e),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(
            builder: (_, c) => _image(e, c.maxWidth)),
        const SizedBox(height: 6),
        Text(e.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: playing ? AppColors.accent : Colors.white)),
        Text(e.sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _chip(String t, int i) {
    final on = _filter == i;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _filter = on ? 0 : i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
              color: on ? AppColors.accent : const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(20)),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: on ? Colors.black : Colors.white)),
        ),
      ),
    );
  }

  Widget _downloaded() => ListenableBuilder(
        listenable: _scope.downloads,
        builder: (context, _) {
          final list = _scope.downloads.completedTracks;
          if (list.isEmpty) {
            return const Center(
                child: Text('Nenhuma música baixada.',
                    style: TextStyle(color: AppColors.textSecondary)));
          }
          return SmoothListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => TrackTile(
                track: list[i],
                onTap: () => _scope.player.playQueue(List.of(list), i)),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final user = _scope.client.session?.username ?? '';
    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(children: [
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => openSettings(context),
              child: const UserAvatar(radius: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
                child: Text('Sua Biblioteca',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            IconButton(
                icon: Icon(_search ? Icons.close : Icons.search, size: 26),
                onPressed: () => setState(() {
                      _search = !_search;
                      if (!_search) _q = '';
                    })),
            IconButton(
                icon: const Icon(Icons.add, size: 28),
                onPressed: () => showCreateSheet(context)),
          ]),
        ),
        if (_search)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Buscar na biblioteca'),
            ),
          ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            children: [
              _chip('Playlists', 1),
              _chip('Álbuns', 2),
              _chip('Artistas', 3),
              _chip('Baixado', 4),
            ],
          ),
        ),
        if (_filter != 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
            child: Row(children: [
              InkWell(
                onTap: () => setState(() => _alpha = !_alpha),
                child: Row(children: [
                  const Icon(Icons.swap_vert, size: 18),
                  const SizedBox(width: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Text(_alpha ? 'Ordem alfabética' : 'Recentes',
                        key: ValueKey(_alpha),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              const Spacer(),
              IconButton(
                  icon: Icon(_grid ? Icons.view_list : Icons.grid_view,
                      size: 20),
                  onPressed: () => setState(() => _grid = !_grid)),
            ]),
          ),
        Expanded(
          child: _filter == 4
              ? _downloaded()
              : ListenableBuilder(
                  listenable: Listenable.merge([
                    _scope.playlists,
                    _scope.player,
                    RecentStore.instance,
                    AutoDownload.instance
                  ]),
                  builder: (context, _) {
                    final items = _items();
                    final bottom = bottomReserve(context);
                    if (_grid) {
                      return GridView.builder(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.78),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _tile(items[i]),
                      );
                    }
                    return SmoothListView.builder(
                      padding: EdgeInsets.only(bottom: bottom),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _row(items[i]),
                    );
                  }),
        ),
      ]),
    );
  }
}
