import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../core/jellyfin/models.dart';
import '../core/recent/recent_store.dart';
import '../features/albums/album_page.dart';
import '../features/artists/artist_page.dart';
import '../features/playlists/playlists_page.dart';
import 'add_to_playlist.dart';

class MenuEntry {
  final IconData? icon;
  final Widget? leading;
  final String label;
  final VoidCallback? onTap;
  final List<MenuEntry>? children;
  final bool divider;
  const MenuEntry(this.label,
      {this.icon, this.leading, this.onTap, this.children, this.divider = false});
}

Future<void> showMenuEntries(
    BuildContext context, Offset pos, List<MenuEntry> entries) async {
  final size = MediaQuery.of(context).size;
  final chosen = await showMenu<MenuEntry>(
    context: context,
    position: RelativeRect.fromLTRB(
        pos.dx, pos.dy, size.width - pos.dx, size.height - pos.dy),
    color: const Color(0xFF282828),
    elevation: 12,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
    items: [
      for (final e in entries)
        PopupMenuItem<MenuEntry>(
          value: e,
          enabled: e.onTap != null || e.children != null,
          height: 40,
          padding: EdgeInsets.zero,
          child: Container(
            decoration: BoxDecoration(
                border: e.divider
                    ? const Border(top: BorderSide(color: Color(0xFF3E3E3E)))
                    : null),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              SizedBox(
                  width: 24,
                  child: e.leading ??
                      (e.icon == null
                          ? null
                          : Icon(e.icon, size: 20, color: Colors.white70))),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(e.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500))),
              if (e.children != null)
                const Icon(Icons.arrow_right, color: Colors.white70),
            ]),
          ),
        ),
    ],
  );
  if (chosen == null) return;
  if (chosen.children != null) {
    if (!context.mounted) return;
    await showMenuEntries(context, pos + const Offset(250, 0), chosen.children!);
  } else {
    chosen.onTap?.call();
  }
}

void _toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(
    SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

/// Submenu "Adicionar à playlist" com todas as playlists + Nova.
List<MenuEntry> _playlistTargets(BuildContext context,
    Future<List<Track>> Function() tracks, {String? exceptId}) {
  final scope = AppScope.of(context);
  return [
    MenuEntry('Nova playlist', icon: Icons.add, onTap: () async {
      final name = await askName(context);
      if (name == null || name.trim().isEmpty) return;
      final l = await tracks();
      final err = await scope.playlists.create(name, l);
      if (context.mounted) _toast(context, err ?? 'Playlist criada');
    }),
    for (final p in scope.playlists.playlists)
      if (p.id != exceptId)
        MenuEntry(p.name, icon: Icons.queue_music, onTap: () async {
          final l = await tracks();
          final err = await scope.playlists.add(p.id, l);
          if (context.mounted) _toast(context, err ?? 'Adicionada a "${p.name}"');
        }),
  ];
}

Future<void> _queueAll(
    BuildContext context, Future<List<Track>> Function() tracks) async {
  final scope = AppScope.of(context);
  final l = await tracks();
  for (final t in l) {
    await scope.player.addToQueue(t);
  }
  if (context.mounted) _toast(context, 'Adicionadas à fila');
}

void _openArtist(BuildContext context, String name) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => ArtistPage(name: name)));

void showTrackMenu(BuildContext context, Offset pos, Track t,
    {VoidCallback? onRemove}) {
  final scope = AppScope.of(context);
  final fav = scope.favorites.isFavorite(t.id);
  final artists = t.artist
      .split(RegExp(r',\s*|;\s*'))
      .where((e) => e.trim().isNotEmpty)
      .toList();
  showMenuEntries(context, pos, [
    MenuEntry('Adicionar à playlist',
        icon: Icons.add,
        children: _playlistTargets(context, () async => [t])),
    if (onRemove != null)
      MenuEntry('Remover desta playlist',
          icon: Icons.remove_circle_outline, onTap: onRemove),
    MenuEntry(fav ? 'Remover de Músicas curtidas' : 'Adicionar a Músicas curtidas',
        leading: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                  colors: [Color(0xFF4A2FD0), Color(0xFF9B8CF0)])),
          child: const Icon(Icons.favorite, size: 12, color: Colors.white),
        ),
        onTap: () => scope.favorites.toggle(t)),
    MenuEntry('Adicionar à fila', icon: Icons.playlist_add, onTap: () {
      scope.player.addToQueue(t);
      _toast(context, 'Adicionada à fila');
    }),
    MenuEntry('Tocar a seguir', icon: Icons.queue_play_next, onTap: () {
      scope.player.playNext(t);
      _toast(context, 'Vai tocar a seguir');
    }),
    MenuEntry('Ir para a rádio da música',
        icon: Icons.sensors, divider: true, onTap: () async {
      try {
        final l = await scope.client.instantMix(t.id);
        if (l.isNotEmpty) {
          await scope.player.playQueue([t, ...l.where((e) => e.id != t.id)], 0,
              source: 'Rádio de ${t.title}');
        } else if (context.mounted) {
          _toast(context, 'Servidor não gerou uma mix.');
        }
      } catch (_) {
        if (context.mounted) _toast(context, 'Não foi possível criar a rádio.');
      }
    }),
    if (artists.length > 1)
      MenuEntry('Ir para o artista', icon: Icons.person_outline, children: [
        for (final a in artists)
          MenuEntry(a, icon: Icons.person_outline,
              onTap: () => _openArtist(context, a)),
      ])
    else if (artists.isNotEmpty)
      MenuEntry('Ir para o artista',
          icon: Icons.person_outline,
          onTap: () => _openArtist(context, artists.first)),
    if (t.albumId != null)
      MenuEntry('Ir para o álbum', icon: Icons.album_outlined, onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AlbumPage(
                albumId: t.albumId!, name: t.album, artist: t.artist)));
      }),
    MenuEntry('Baixar', icon: Icons.arrow_circle_down_outlined, onTap: () {
      scope.downloads.enqueue([t]);
      _toast(context, 'Download iniciado');
    }),
    MenuEntry('Compartilhar', icon: Icons.ios_share, onTap: () {
      Clipboard.setData(ClipboardData(text: '${t.title} – ${t.artist}'));
      _toast(context, 'Nome copiado');
    }),
  ]);
}

void showAlbumMenu(BuildContext context, Offset pos,
    {required String albumId, required String name, String artist = ''}) {
  final scope = AppScope.of(context);
  Future<List<Track>> tracks() => scope.client.albumTracks(albumId);
  showMenuEntries(context, pos, [
    MenuEntry('Tocar', icon: Icons.play_arrow, onTap: () async {
      final l = await tracks();
      if (l.isEmpty) return;
      RecentStore.instance.add('album', albumId, name, artist);
      scope.player.playQueue(l, 0, source: name);
    }),
    MenuEntry('Adicionar à fila',
        icon: Icons.playlist_add, onTap: () => _queueAll(context, tracks)),
    MenuEntry('Adicionar à playlist',
        icon: Icons.add, children: _playlistTargets(context, tracks)),
    MenuEntry('Ir para o álbum', icon: Icons.album_outlined, onTap: () {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              AlbumPage(albumId: albumId, name: name, artist: artist)));
    }),
    MenuEntry('Baixar', icon: Icons.arrow_circle_down_outlined, onTap: () async {
      final l = await tracks();
      scope.downloads.enqueue(l);
      if (context.mounted) _toast(context, '${l.length} faixas na fila de download');
    }),
    MenuEntry('Compartilhar', icon: Icons.ios_share, onTap: () {
      Clipboard.setData(ClipboardData(text: '$name – $artist'));
      _toast(context, 'Nome copiado');
    }),
  ]);
}

void showPlaylistMenu(BuildContext context, Offset pos, PlaylistInfo p) {
  final scope = AppScope.of(context);
  Future<List<Track>> tracks() => scope.client.playlistTracks(p.id);
  showMenuEntries(context, pos, [
    MenuEntry('Tocar', icon: Icons.play_arrow, onTap: () async {
      final l = await tracks();
      if (l.isEmpty) return;
      RecentStore.instance.add('playlist', p.id, p.name);
      scope.player.playQueue(l, 0, source: p.name);
    }),
    MenuEntry('Adicionar à fila',
        icon: Icons.playlist_add, onTap: () => _queueAll(context, tracks)),
    MenuEntry('Habilitar mix (aleatório)', icon: Icons.tune, onTap: () async {
      final l = await tracks()
        ..shuffle();
      if (l.isEmpty) return;
      scope.player.playQueue(l, 0, source: p.name);
    }),
    MenuEntry('Baixar', icon: Icons.arrow_circle_down_outlined, onTap: () async {
      final l = await tracks();
      scope.downloads.enqueue(l);
      if (context.mounted) _toast(context, '${l.length} faixas na fila de download');
    }),
    MenuEntry('Adicionar a outra playlist',
        icon: Icons.add,
        children: _playlistTargets(context, tracks, exceptId: p.id)),
    MenuEntry('Abrir playlist', icon: Icons.queue_music, onTap: () {
      openPlaylist(Navigator.of(context), p);
    }),
    MenuEntry('Compartilhar', icon: Icons.ios_share, onTap: () {
      Clipboard.setData(ClipboardData(text: p.name));
      _toast(context, 'Nome copiado');
    }),
    MenuEntry('Apagar playlist',
        icon: Icons.delete_outline, divider: true, onTap: () async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Apagar "${p.name}"?'),
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
      if (ok != true) return;
      final err = await scope.playlists.delete(p.id);
      if (err != null && context.mounted) _toast(context, err);
    }),
  ]);
}

/// Envolve [child] para abrir [onMenu] com o botão direito (ou toque longo).
class MenuTarget extends StatelessWidget {
  final Widget child;
  final void Function(Offset pos) onMenu;
  const MenuTarget({super.key, required this.child, required this.onMenu});
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (d) => onMenu(d.globalPosition),
        onLongPressStart: (d) => onMenu(d.globalPosition),
        child: child,
      );
}
