import '../../widgets/net_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/artists/artist_info_service.dart';
import '../../core/format.dart';
import '../../core/recent/recent_store.dart';
import '../../core/i18n/strings.dart';
import '../../core/jellyfin/models.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/cover.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/smooth_scroll.dart';

String fmtPlays(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

class ArtistPage extends StatefulWidget {
  final String name;
  const ArtistPage({super.key, required this.name});
  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  late final String _name = ArtistInfoService.primary(widget.name);
  final _scroll = SmoothScrollController();
  ArtistInfo? _info;
  List<Track>? _tracks;
  bool _more = false;
  bool _bar = false;
  bool _following = false;
  bool _bioOpen = false;
  bool _init = false;
  late final AppScope _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _scope = AppScope.of(context);
    _scroll.addListener(() {
      final b = _scroll.hasClients && _scroll.offset > 300;
      if (b != _bar) setState(() => _bar = b);
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String get _fKey => 'followed_artists';

  Future<void> _load() async {
    ArtistInfoService.instance.get(_name).then((v) {
      if (mounted) setState(() => _info = v);
    });
    SharedPreferences.getInstance().then((sp) {
      final f = sp.getStringList(_fKey) ?? const [];
      if (mounted) setState(() => _following = f.contains(_name.toLowerCase()));
    });
    _scope.client.artistImage(_name).then((u) {
      if (mounted && u != null) setState(() => _jf = u);
    });
    LastFmService.instance.topTracks(_name).then((m) {
      if (mounted && m != null) setState(() => _global = m);
    });
    try {
      var mine = await _scope.client.artistTracks(_name);
      if (mine.isEmpty) {
        final all = await _scope.client.searchTracks(_name, limit: 300);
        final n = _name.toLowerCase();
        mine = all.where((t) => t.artist.toLowerCase().contains(n)).toList();
      }
      if (mounted) setState(() => _tracks = mine);
    } catch (_) {
      if (mounted) setState(() => _tracks = const []);
    }
  }

  Map<String, int> _global = const {};
  String? _jf;
  int _globalOf(Track t) => _global[LastFmService.norm(t.title)] ?? 0;

  Future<void> _toggleFollow() async {
    setState(() => _following = !_following);
    final sp = await SharedPreferences.getInstance();
    final f = (sp.getStringList(_fKey) ?? <String>[]).toList();
    final k = _name.toLowerCase();
    _following ? f.add(k) : f.remove(k);
    await sp.setStringList(_fKey, f.toSet().toList());
  }

  List<Track> get _popular {
    final l = List.of(_tracks ?? const <Track>[]);
    l.sort((a, b) {
      final c = _globalOf(b) != _globalOf(a)
          ? _globalOf(b).compareTo(_globalOf(a))
          : b.plays.compareTo(a.plays); // desempate só entre sem dado global
      return c != 0 ? c : a.title.compareTo(b.title);
    });
    return l;
  }

  List<Track> get _albums {
    final seen = <String>{};
    return [
      for (final t in _tracks ?? const <Track>[])
        if (seen.add(t.albumId ?? t.album)) t
    ];
  }

  Widget _circle(IconData i, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          color: const Color(0x66000000),
          shape: const CircleBorder(),
          child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(i, size: 22)),
        ),
      );

  Widget _playBtn(List<Track> pop, double size) => InkWell(
        customBorder: const CircleBorder(),
        onTap: pop.isEmpty ? null : () => _play(pop, 0),
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
              color: AppColors.accent, shape: BoxShape.circle),
          child: Icon(Icons.play_arrow, color: Colors.black, size: size * 0.6),
        ),
      );

  Widget _followBtn() => OutlinedButton(
        style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF8A8A8A)),
            shape: const StadiumBorder()),
        onPressed: _toggleFollow,
        child: Text(S.t(_following ? 'following' : 'follow'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  List<Track> get _likedBy => _scope.favorites.tracks
      .where((t) => t.artist.toLowerCase().contains(_name.toLowerCase()))
      .toList();

  Widget _likedRow() {
    final l = _likedBy;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _LikedByPage(name: _name, tracks: l))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          Stack(children: [
            ClipOval(
                child: SizedBox(
                    width: 52,
                    height: 52,
                    child: _info?.picture != null
                        ? NetImage(_info!.picture!, fit: BoxFit.cover)
                        : Container(color: AppColors.elevated))),
            const Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                    radius: 9,
                    backgroundColor: AppColors.accent,
                    child: Icon(Icons.favorite, size: 11, color: Colors.black))),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Músicas curtidas',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text('${l.length} músicas • $_name',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary)),
                ]),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ]),
      ),
    );
  }

  void _play(List<Track> l, int i) {
    RecentStore.instance.add('artist', _name, _name);
    _scope.player.playQueue(List.of(l), i, source: _name);
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    final pop = _popular;
    final shown = pop.take(_more ? 10 : 5).toList();
    final hero = _info?.heroOrPicture;
    final fans = _info?.fans;
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 700;
        final h = wide ? 380.0 : 340.0;
        return CustomScrollView(controller: _scroll, slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: h,
            toolbarHeight: 56,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            backgroundColor: const Color(0xFF181818),
            automaticallyImplyLeading: wide,
            centerTitle: !wide,
            leading: wide ? null : _circle(Icons.arrow_back, () => Navigator.of(context).pop()),
            actions: wide
                ? null
                : [
                    _circle(
                        Icons.more_vert,
                        () => showSheetEntries(
                                context,
                                Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                                    child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(_name,
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700)))),
                                [
                                  MenuEntry('Tocar aleatório',
                                      icon: Icons.shuffle,
                                      onTap: pop.isEmpty
                                          ? null
                                          : () => _play(List.of(pop)..shuffle(), 0)),
                                  MenuEntry(
                                      _following ? 'Deixar de seguir' : 'Seguir',
                                      icon: Icons.person_add_alt,
                                      onTap: _toggleFollow),
                                ])),
                  ],
            title: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _bar ? 1 : 0,
              child: Text(_name,
                  style: TextStyle(
                      fontSize: wide ? 22 : 16, fontWeight: FontWeight.w700)),
            ),
            flexibleSpace: LayoutBuilder(builder: (context, bc) {
              final t = ((bc.maxHeight - 56) / (h - 56)).clamp(0.0, 1.0);
              return Stack(fit: StackFit.expand, children: [
                if (hero != null)
                  NetImage(hero,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.5),
                      errorBuilder: (_, __, ___) =>
                          Container(color: const Color(0xFF3A3A3A)))
                else if (_jf != null)
                  NetImage(_jf!,
                      headers: _scope.client.authHeaders,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.5),
                      errorBuilder: (_, __, ___) =>
                          Container(color: const Color(0xFF3A3A3A)))
                else
                  Container(color: const Color(0xFF3A3A3A)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x33000000), Color(0xCC000000)]),
                  ),
                ),
                Container(color: const Color(0xFF181818).withOpacity(1 - t)),
                Positioned(
                  left: wide ? 24 : 16,
                  right: 24,
                  bottom: 20,
                  child: Opacity(
                    opacity: t,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(_name,
                                maxLines: 1,
                                style: TextStyle(
                                    fontSize: wide ? 96 : 44,
                                    height: 1.0,
                                    letterSpacing: -2,
                                    fontWeight: FontWeight.w900)),
                          ),
                          const SizedBox(height: 10),
                          Text(
                              fans != null
                                  ? S.t('fans', {'n': fmtPlays(fans)})
                                  : (tracks == null
                                      ? ''
                                      : S.t('in_library',
                                          {'n': tracks.length})),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w500)),
                        ]),
                  ),
                ),
              ]);
            }),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, 16, 8),
              child: wide
                  ? Row(children: [
                      _playBtn(pop, 48),
                      const SizedBox(width: 12),
                      IconButton(
                        iconSize: 28,
                        color: AppColors.textSecondary,
                        icon: const Icon(Icons.shuffle),
                        onPressed: pop.isEmpty
                            ? null
                            : () => _play(List.of(pop)..shuffle(), 0),
                      ),
                      const SizedBox(width: 8),
                      _followBtn(),
                    ])
                  : Row(children: [
                      _followBtn(),
                      const Spacer(),
                      IconButton(
                        iconSize: 28,
                        color: AppColors.textSecondary,
                        icon: const Icon(Icons.shuffle),
                        onPressed: pop.isEmpty
                            ? null
                            : () => _play(List.of(pop)..shuffle(), 0),
                      ),
                      const SizedBox(width: 4),
                      _playBtn(pop, 56),
                    ]),
            ),
          ),
          if (!wide && _likedBy.isNotEmpty)
            SliverToBoxAdapter(child: _likedRow()),
          if (tracks == null)
            const SliverToBoxAdapter(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator())))
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 8, 16, 8),
                child: Text(wide ? S.t('popular') : 'Mais ouvidas',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _PopularRow(
                  track: shown[i],
                  index: i,
                  wide: wide,
                  global: _globalOf(shown[i]),
                  onTap: () => _play(pop, i),
                ),
                childCount: shown.length,
              ),
            ),
            if (pop.length > 5)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _more = !_more),
                    child: Text(S.t(_more ? 'see_less' : 'see_more'),
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            if (_albums.isNotEmpty)
              SliverToBoxAdapter(child: _discography(wide)),
            if (_info?.bioFor(S.lang) != null)
              SliverToBoxAdapter(child: _about(wide)),
            SliverToBoxAdapter(
                child: SizedBox(height: bottomReserve(context) + 8)),
          ],
        ]);
      }),
    );
  }

  Widget _discography(bool wide) {
    final albums = _albums;
    final size = wide ? 160.0 : 140.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, 0, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.t('discography'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SizedBox(
          height: size + 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, i) {
              final a = albums[i];
              return MenuTarget(
                onMenu: (p) {
                  if (a.albumId != null) {
                    showAlbumMenu(context, p,
                        albumId: a.albumId!, name: a.album, artist: _name);
                  }
                },
                child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  final l = (_tracks ?? const <Track>[])
                      .where((t) => (t.albumId ?? t.album) == (a.albumId ?? a.album))
                      .toList();
                  if (l.isNotEmpty) _play(l, 0);
                },
                child: SizedBox(
                  width: size,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Cover(track: a, size: size),
                        const SizedBox(height: 8),
                        Text(a.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(S.t('album'),
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ]),
                ),
              ));
            },
          ),
        ),
      ]),
    );
  }

  Widget _about(bool wide) {
    final bio = _info!.bioFor(S.lang)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 24, wide ? 24 : 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.t('about'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => setState(() => _bioOpen = !_bioOpen),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_info?.genre != null || _info?.country != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                          [_info?.genre, _info?.country]
                              .whereType<String>()
                              .join(' • '),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topCenter,
                    child: Text(bio,
                        maxLines: _bioOpen ? null : 5,
                        overflow: TextOverflow.fade,
                        style: const TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppColors.textSecondary)),
                  ),
                ]),
          ),
        ),
      ]),
    );
  }
}

class _PopularRow extends StatefulWidget {
  final Track track;
  final int index;
  final bool wide;
  final VoidCallback onTap;
  final int global;
  const _PopularRow(
      {required this.global,
      required this.track,
      required this.index,
      required this.wide,
      required this.onTap});
  @override
  State<_PopularRow> createState() => _PopularRowState();
}

class _PopularRowState extends State<_PopularRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = widget.track;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.player, scope.favorites]),
      builder: (context, _) {
        final cur = scope.player.current?.id == t.id;
        final fav = scope.favorites.isFavorite(t.id);
        const dim = TextStyle(fontSize: 14, color: AppColors.textSecondary);
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onSecondaryTapDown: (d) =>
                showTrackMenu(context, d.globalPosition, t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: EdgeInsets.symmetric(horizontal: widget.wide ? 16 : 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                  color: _hover ? const Color(0x1AFFFFFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4)),
              child: Row(children: [
                SizedBox(
                  width: 32,
                  child: Center(
                    child: _hover
                        ? const Icon(Icons.play_arrow, size: 20)
                        : Text('${widget.index + 1}',
                            style: TextStyle(
                                fontSize: 15,
                                color: cur
                                    ? AppColors.accent
                                    : AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: 8),
                Cover(track: t, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: cur ? AppColors.accent : Colors.white)),
                        if (!widget.wide && widget.global > 0)
                          Text(fmtPlays(widget.global),
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary)),
                      ]),
                ),
                if (widget.wide)
                  Expanded(
                      flex: 3,
                      child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                              widget.global > 0 ? fmtPlays(widget.global) : '',
                              style: dim))),
                SizedBox(
                  width: widget.wide ? 40 : 28,
                  child: Opacity(
                    opacity: (_hover || fav) && (widget.wide || fav) ? 1 : 0,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                          fav ? Icons.check_circle : Icons.add_circle_outline,
                          size: 20,
                          color: fav
                              ? AppColors.accent
                              : AppColors.textSecondary),
                      onPressed: () => scope.favorites.toggle(t),
                    ),
                  ),
                ),
                if (widget.wide)
                  SizedBox(
                      width: 48,
                      child: Text(
                          t.duration == null ? '' : fmtDuration(t.duration!),
                          textAlign: TextAlign.center,
                          style: dim))
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_vert,
                        size: 22, color: AppColors.textSecondary),
                    onPressed: () => showTrackMenu(context, Offset.zero, t),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _LikedByPage extends StatelessWidget {
  final String name;
  final List<Track> tracks;
  const _LikedByPage({required this.name, required this.tracks});
  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).player;
    return Scaffold(
      appBar: AppBar(title: Text('Músicas curtidas • $name')),
      body: ListView.builder(
        padding: EdgeInsets.only(bottom: bottomReserve(context)),
        itemCount: tracks.length,
        itemBuilder: (_, i) => TrackTile(
            track: tracks[i], onTap: () => p.playQueue(List.of(tracks), i)),
      ),
    );
  }
}
