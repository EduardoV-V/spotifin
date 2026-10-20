import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../core/jellyfin/models.dart';
import '../core/recent/recent_store.dart';
import '../features/albums/album_page.dart';
import '../features/artists/artist_page.dart';
import '../features/playlists/playlists_page.dart';
import '../app/nav.dart';
import '../features/player/now_playing_page.dart';
import 'add_to_playlist.dart';
import 'cover.dart';
import 'playlist_cover.dart';

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

OverlayEntry? _openMenu;

/// Menu próprio no overlay raiz: aparece exatamente na posição do clique,
/// independente de Navigators aninhados ou painéis.
Future<void> showMenuEntries(
    BuildContext context, Offset pos, List<MenuEntry> entries) async {
  _openMenu?.remove();
  _openMenu = null;
  final overlay = Overlay.of(context, rootOverlay: true);
  final box = overlay.context.findRenderObject() as RenderBox;
  final local = box.globalToLocal(pos);
  late OverlayEntry entry;
  void close() {
    if (identical(_openMenu, entry)) _openMenu = null;
    entry.remove();
  }

  entry = OverlayEntry(
      builder: (_) => _MenuLayer(
          origin: local, screen: box.size, entries: entries, onClose: close));
  _openMenu = entry;
  overlay.insert(entry);
}

const _kItemH = 40.0;
const _kMenuW = 270.0;

double _heightOf(List<MenuEntry> l) =>
    l.fold<double>(8, (a, e) => a + _kItemH + (e.divider ? 1 : 0));

class _MenuLayer extends StatefulWidget {
  final Offset origin;
  final Size screen;
  final List<MenuEntry> entries;
  final VoidCallback onClose;
  const _MenuLayer(
      {required this.origin,
      required this.screen,
      required this.entries,
      required this.onClose});
  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> {
  int? _sub;

  Widget _panel(List<MenuEntry> list, Offset at, {required bool root}) {
    final h = _heightOf(list);
    final left = at.dx.clamp(8.0, (widget.screen.width - _kMenuW - 8).clamp(8.0, 99999.0));
    final top = at.dy.clamp(8.0, (widget.screen.height - h - 8).clamp(8.0, 99999.0));
    return Positioned(
      left: left.toDouble(),
      top: top.toDouble(),
      width: _kMenuW,
      child: Material(
        color: const Color(0xFF282828),
        elevation: 12,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < list.length; i++) _item(list[i], i, root, left.toDouble(), top.toDouble(), list),
          ]),
        ),
      ),
    );
  }

  Widget _item(MenuEntry e, int i, bool root, double left, double top,
      List<MenuEntry> list) {
    final enabled = e.onTap != null || e.children != null;
    final color = enabled ? Colors.white : Colors.white38;
    var y = top + 4;
    for (var k = 0; k < i; k++) {
      y += _kItemH + (list[k].divider ? 1 : 0);
    }
    return MouseRegion(
      onEnter: (_) {
        if (!root) return;
        final next = e.children != null ? i : null;
        if (next != _sub) setState(() => _sub = next);
      },
      child: InkWell(
        onTap: !enabled
            ? null
            : () {
                if (e.children != null) {
                  if (root) setState(() => _sub = i);
                  return;
                }
                widget.onClose();
                e.onTap?.call();
              },
        child: Container(
          height: _kItemH + (e.divider ? 1 : 0),
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
                        : Icon(e.icon, size: 20, color: color))),
            const SizedBox(width: 12),
            Expanded(
                child: Text(e.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: color))),
            if (e.children != null)
              Icon(Icons.arrow_right, color: color),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.entries;
    final h = _heightOf(list);
    final rootLeft = widget.origin.dx
        .clamp(8.0, (widget.screen.width - _kMenuW - 8).clamp(8.0, 99999.0))
        .toDouble();
    final rootTop = widget.origin.dy
        .clamp(8.0, (widget.screen.height - h - 8).clamp(8.0, 99999.0))
        .toDouble();
    Widget? sub;
    final si = _sub;
    if (si != null && list[si].children != null) {
      var y = rootTop + 4;
      for (var k = 0; k < si; k++) {
        y += _kItemH + (list[k].divider ? 1 : 0);
      }
      var x = rootLeft + _kMenuW - 4;
      if (x + _kMenuW > widget.screen.width - 8) x = rootLeft - _kMenuW + 4;
      sub = _panel(list[si].children!, Offset(x, y), root: false);
    }
    return Focus(
      autofocus: true,
      onKeyEvent: (_, ev) {
        if (ev is KeyDownEvent && ev.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => widget.onClose(),
            onSecondaryTapDown: (_) => widget.onClose(),
            child: const SizedBox.expand(),
          ),
        ),
        _panel(list, Offset(rootLeft, rootTop), root: true),
        if (sub != null) sub,
      ]),
    );
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
          if (!context.mounted) return;
          final r = await addToPlaylistChecked(context, p, l);
          if (r != null && context.mounted) _toast(context, r);
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

void _openArtist(BuildContext context, String name) =>
    pushShell(context, MaterialPageRoute(builder: (_) => ArtistPage(name: name)));

List<MenuEntry> trackEntries(BuildContext context, Track t,
    {VoidCallback? onRemove}) {
  final scope = AppScope.of(context);
  final fav = scope.favorites.isFavorite(t.id);
  final artists = t.artist
      .split(RegExp(r',\s*|;\s*'))
      .where((e) => e.trim().isNotEmpty)
      .toList();
  final share = MenuEntry('Compartilhar', icon: Icons.share_outlined, onTap: () {
    Clipboard.setData(ClipboardData(text: '${t.title} – ${t.artist}'));
    _toast(context, 'Nome copiado');
  });
  final addPl = MenuEntry('Adicionar à playlist',
      icon: Icons.add_circle_outline,
      children: _playlistTargets(context, () async => [t]));
  final rm = onRemove == null
      ? null
      : MenuEntry('Remover desta playlist',
          icon: Icons.remove_circle_outline, onTap: onRemove);
  final like = MenuEntry(
      fav ? 'Remover de Músicas curtidas' : 'Adicionar a Músicas curtidas',
      leading: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(
                colors: [Color(0xFF4A2FD0), Color(0xFF9B8CF0)])),
        child: const Icon(Icons.favorite, size: 13, color: Colors.white),
      ),
      onTap: () => scope.favorites.toggle(t));
  final queue = MenuEntry('Adicionar à fila', icon: Icons.playlist_add, onTap: () {
    scope.player.addToQueue(t);
    _toast(context, 'Adicionada à fila');
  });
  final openQueue = MenuEntry('Abrir a fila de reprodução',
      icon: Icons.format_list_bulleted, onTap: () => showQueueSheet(context));
  final next = MenuEntry('Tocar a seguir', icon: Icons.queue_play_next, onTap: () {
    scope.player.playNext(t);
    _toast(context, 'Vai tocar a seguir');
  });
  final radio = MenuEntry('Ir para a rádio da música',
      icon: Icons.sensors, onTap: () async {
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
  });
  final artist = artists.length > 1
      ? MenuEntry('Ir para o artista', icon: Icons.person_outline, children: [
          for (final a in artists)
            MenuEntry(a,
                icon: Icons.person_outline,
                onTap: () => _openArtist(context, a)),
        ])
      : artists.isEmpty
          ? null
          : MenuEntry('Ir para o artista',
              icon: Icons.person_outline,
              onTap: () => _openArtist(context, artists.first));
  final album = t.albumId == null
      ? null
      : MenuEntry('Ir para o álbum', icon: Icons.album_outlined, onTap: () {
          pushShell(
              context,
              MaterialPageRoute(
                  builder: (_) => AlbumPage(
                      albumId: t.albumId!, name: t.album, artist: t.artist)));
        });
  final dl = MenuEntry('Baixar', icon: Icons.arrow_circle_down_outlined, onTap: () {
    scope.downloads.enqueue([t]);
    _toast(context, 'Download iniciado');
  });
  if (_mobile(context)) {
    return [
      share, addPl, if (rm != null) rm, like, queue, openQueue, if (album != null) album, if (artist != null) artist, next, radio, dl,
    ];
  }
  return [
    addPl, if (rm != null) rm, like, queue, next,
    MenuEntry(radio.label, icon: radio.icon, onTap: radio.onTap, divider: true),
    if (artist != null) artist, if (album != null) album, dl, share,
  ];
}

List<MenuEntry> albumEntries(BuildContext context,
    {required String albumId, required String name, String artist = ''}) {
  final scope = AppScope.of(context);
  Future<List<Track>> tracks() => scope.client.albumTracks(albumId);
  return [
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
  ];
}

List<MenuEntry> playlistEntries(BuildContext context, PlaylistInfo p) {
  final scope = AppScope.of(context);
  Future<List<Track>> tracks() => scope.client.playlistTracks(p.id);
  return [
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
  ];
}

bool _mobile(BuildContext c) => MediaQuery.sizeOf(c).width < 800;

void showTrackMenu(BuildContext context, Offset pos, Track t,
    {VoidCallback? onRemove}) {
  final e = trackEntries(context, t, onRemove: onRemove);
  if (_mobile(context)) {
    showSheetEntries(context, _SheetHeader(
        cover: Cover(track: t, size: 48), title: t.title, sub: t.artist), e);
  } else {
    showMenuEntries(context, pos, e);
  }
}

void showAlbumMenu(BuildContext context, Offset pos,
    {required String albumId, required String name, String artist = ''}) {
  final e = albumEntries(context, albumId: albumId, name: name, artist: artist);
  if (_mobile(context)) {
    showSheetEntries(
        context,
        _SheetHeader(
            cover: _IdImage(id: albumId), title: name, sub: 'Álbum • $artist'),
        e);
  } else {
    showMenuEntries(context, pos, e);
  }
}

void showPlaylistMenu(BuildContext context, Offset pos, PlaylistInfo p) {
  final e = playlistEntries(context, p);
  if (_mobile(context)) {
    showSheetEntries(
        context,
        _SheetHeader(
            cover: PlaylistCover(id: p.id, size: 48),
            title: p.name,
            sub: 'Playlist'),
        e);
  } else {
    showMenuEntries(context, pos, e);
  }
}

class _IdImage extends StatelessWidget {
  final String id;
  const _IdImage({required this.id});
  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context).client;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.network(c.imageUri(id, maxWidth: 120).toString(),
            headers: c.authHeaders,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppColors.elevated)),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final Widget cover;
  final String title, sub;
  const _SheetHeader(
      {required this.cover, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          SizedBox(width: 48, height: 48, child: cover),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ]),
          ),
        ]),
      );
}

/// Folha inferior estilo Spotify mobile: abre até ~metade, arrasta pela alça/
/// cabeçalho ou rolando a lista para expandir.
Future<void> showSheetEntries(
    BuildContext context, Widget header, List<MenuEntry> entries) {
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 400),
        reverseDuration: Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic),
    builder: (ctx) => _SheetBody(header: header, entries: entries),
  );
}

class _SheetBody extends StatefulWidget {
  final Widget header;
  final List<MenuEntry> entries;
  const _SheetBody({required this.header, required this.entries});
  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double h;
  _PinnedHeader(this.child, this.h);
  @override
  double get minExtent => h;
  @override
  double get maxExtent => h;
  @override
  Widget build(BuildContext c, double shrink, bool overlaps) => child;
  @override
  bool shouldRebuild(covariant _PinnedHeader o) => o.child != child || o.h != h;
}

class _SheetBodyState extends State<_SheetBody> {
  List<MenuEntry>? _sub;
  String _subTitle = '';

  @override
  Widget build(BuildContext context) {
    final list = _sub ?? widget.entries;
    final mq = MediaQuery.of(context);
    final content = 100 + list.length * 56.0 + mq.padding.bottom + 8;
    final init = (content / mq.size.height).clamp(0.3, 0.58).toDouble();
    final bottom = mq.padding.bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: init,
      minChildSize: 0,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: [init],
      builder: (ctx, ctl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF282828),
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: CustomScrollView(
          controller: ctl,
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedHeader(
                Container(
                  color: const Color(0xFF282828),
                  child: Column(children: [
                    const SizedBox(height: 8),
                    Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white38,
                            borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 12),
                    if (_sub == null)
                      widget.header
                    else
                      SizedBox(
                        height: 64,
                        child: ListTile(
                          leading: const Icon(Icons.arrow_back),
                          title: Text(_subTitle,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          onTap: () => setState(() => _sub = null),
                        ),
                      ),
                    const Divider(height: 1, color: Color(0xFF3E3E3E)),
                  ]),
                ),
                100,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (c, i) {
                  final e = list[i];
                  return ListTile(
                    enabled: e.onTap != null || e.children != null,
                    visualDensity: const VisualDensity(vertical: -1),
                    leading: SizedBox(
                        width: 26,
                        child: e.leading ??
                            (e.icon == null
                                ? null
                                : Icon(e.icon, size: 26, color: Colors.white))),
                    title: Text(e.label,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                    trailing: e.children != null
                        ? const Icon(Icons.chevron_right)
                        : null,
                    onTap: () {
                      if (e.children != null) {
                        setState(() {
                          _sub = e.children;
                          _subTitle = e.label;
                        });
                        return;
                      }
                      Navigator.of(context).pop();
                      e.onTap?.call();
                    },
                  );
                },
                childCount: list.length,
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottom + 8)),
          ],
        ),
      ),
    );
  }
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
