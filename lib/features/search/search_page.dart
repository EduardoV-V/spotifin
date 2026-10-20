import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/artists/artist_info_service.dart';
import '../../core/jellyfin/models.dart';
import '../../widgets/smooth_scroll.dart';
import '../../widgets/track_tile.dart';
import '../albums/album_page.dart';
import '../artists/artist_page.dart';
import '../settings/settings_page.dart';
import 'desktop_search.dart';

const _tileColors = [
  Color(0xFFDC148C), Color(0xFF608108), Color(0xFF1E3264), Color(0xFF8D67AB),
  Color(0xFF477D95), Color(0xFFE8115B), Color(0xFF148A08), Color(0xFFBA5D07),
  Color(0xFF7358FF), Color(0xFF509BF5), Color(0xFFAF2896), Color(0xFF006450),
  Color(0xFFE13300), Color(0xFF8C1932), Color(0xFF27856A), Color(0xFFB49BC8),
];

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  List<String>? _genres;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    AppScope.of(context).client.genres().then((g) {
      if (mounted) setState(() => _genres = g);
    }).catchError((_) {
      if (mounted) setState(() => _genres = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).client.session?.username ?? '';
    final g = _genres;
    return SafeArea(
      bottom: false,
      child: SmoothListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomReserve(context)),
        children: [
          Row(children: [
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => openSettings(context),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF6A4FC4),
                child: Text(user.isEmpty ? '?' : user[0].toUpperCase(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
                child: Text('Buscar',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => Navigator.of(context).push(PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 180),
                pageBuilder: (_, __, ___) => const MobileSearchPage(),
                transitionsBuilder: (_, a, __, c) =>
                    FadeTransition(opacity: a, child: c))),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(6)),
              child: const Row(children: [
                Icon(Icons.search, color: Colors.black, size: 26),
                SizedBox(width: 10),
                Text('O que você quer ouvir?',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 22),
          const Text('Navegar por todas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (g == null)
            const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.75),
              itemCount: g.length,
              itemBuilder: (_, i) {
                final color = _tileColors[g[i].hashCode.abs() % _tileColors.length];
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GenrePage(genre: g[i], color: color))),
                  child: Ink(
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(6)),
                    child: Stack(clipBehavior: Clip.hardEdge, children: [
                      Positioned(
                        right: -14,
                        bottom: -8,
                        child: Transform.rotate(
                          angle: 0.4,
                          child: Icon(Icons.music_note,
                              size: 70, color: Colors.black.withOpacity(0.22)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(g[i],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class GenrePage extends StatefulWidget {
  final String genre;
  final Color color;
  const GenrePage({super.key, required this.genre, required this.color});
  @override
  State<GenrePage> createState() => _GenrePageState();
}

class _GenrePageState extends State<GenrePage> {
  List<Track>? _l;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_l != null) return;
    AppScope.of(context)
        .client
        .getTracks(genre: widget.genre, limit: 300)
        .then((p) {
      if (mounted) setState(() => _l = p.items);
    }).catchError((_) {
      if (mounted) setState(() => _l = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [widget.color, AppColors.background],
                stops: const [0, 0.45])),
        child: SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
              child: Row(children: [
                IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop()),
                Expanded(
                    child: Text(widget.genre,
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w900))),
              ]),
            ),
            Expanded(
              child: l == null
                  ? const Center(child: CircularProgressIndicator())
                  : SmoothListView.builder(
                      padding: EdgeInsets.only(bottom: bottomReserve(context)),
                      itemCount: l.length,
                      itemBuilder: (_, i) => TrackTile(
                          track: l[i],
                          onTap: () => AppScope.of(context)
                              .player
                              .playQueue(List.of(l), i, source: widget.genre)),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Rec {
  final String k; // track | artist | album
  final String id, name, sub, cover;
  const _Rec(this.k, this.id, this.name, this.sub, this.cover);
  Map<String, String> toJson() =>
      {'k': k, 'i': id, 'n': name, 's': sub, 'c': cover};
  factory _Rec.fromJson(Map<String, dynamic> j) => _Rec(j['k'] as String,
      j['i'] as String, j['n'] as String, j['s'] as String, j['c'] as String);
}

class MobileSearchPage extends StatefulWidget {
  const MobileSearchPage({super.key});
  @override
  State<MobileSearchPage> createState() => _MobileSearchPageState();
}

class _MobileSearchPageState extends State<MobileSearchPage> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<_Rec> _recents = [];
  List<Track> _tracks = const [];
  String? _artist;
  List<Track> _albums = const [];
  bool _loading = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      final raw = sp.getString('search_recent');
      if (raw == null) return;
      try {
        final l = (jsonDecode(raw) as List)
            .map((e) => _Rec.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) setState(() => _recents = l);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _saveRecents() async {
    (await SharedPreferences.getInstance()).setString('search_recent',
        jsonEncode(_recents.map((e) => e.toJson()).toList()));
  }

  void _remember(_Rec r) {
    _recents.removeWhere((e) => e.k == r.k && e.id == r.id);
    _recents.insert(0, r);
    if (_recents.length > 20) _recents = _recents.sublist(0, 20);
    _saveRecents();
  }

  void _onChanged(String v) {
    setState(() => _q = v);
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _tracks = const [];
        _artist = null;
        _albums = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await AppScope.of(context).client.searchTracks(q, limit: 50);
        if (!mounted || _ctrl.text.trim() != q) return;
        final count = <String, int>{};
        for (final t in r) {
          final a = ArtistInfoService.primary(t.artist);
          count[a] = (count[a] ?? 0) + 1;
        }
        final ql = q.toLowerCase();
        final named = count.keys.where((a) => a.toLowerCase().contains(ql));
        final top = named.isEmpty
            ? null
            : named.reduce((a, b) => count[a]! >= count[b]! ? a : b);
        final seen = <String>{};
        final albums = [
          for (final t in r)
            if (t.albumId != null &&
                t.album.toLowerCase().contains(ql) &&
                seen.add(t.albumId!))
              t
        ];
        setState(() {
          _tracks = r.take(8).toList();
          _artist = top;
          _albums = albums.take(3).toList();
          _loading = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  void _open(BuildContext context, _Rec r) async {
    final scope = AppScope.of(context);
    final nav = Navigator.of(context);
    _remember(r);
    switch (r.k) {
      case 'artist':
        nav.push(MaterialPageRoute(builder: (_) => ArtistPage(name: r.name)));
      case 'album':
        nav.push(MaterialPageRoute(
            builder: (_) =>
                AlbumPage(albumId: r.id, name: r.name, artist: r.sub)));
      default:
        try {
          final l = await scope.client.tracksByIds([r.id]);
          if (l.isNotEmpty) scope.player.playQueue(l, 0);
        } catch (_) {}
    }
  }

  Widget _img(String k, String name, String cover, double size) {
    if (k == 'artist') return ArtistAvatar(name: name, size: size);
    final c = AppScope.of(context).client;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
            c.imageUri(cover, maxWidth: (size * 2).round()).toString(),
            headers: c.authHeaders,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppColors.elevated)),
      ),
    );
  }

  Widget _row(_Rec r, {Widget? trailing, VoidCallback? onTap}) => InkWell(
        onTap: onTap ?? () => _open(context, r),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            _img(r.k, r.name, r.cover, 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    Text(
                        r.k == 'artist'
                            ? 'Artista'
                            : r.k == 'album'
                                ? 'Álbum • ${r.sub}'
                                : 'Música • ${r.sub}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ]),
            ),
            if (trailing != null) trailing,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final empty = _q.trim().isEmpty;
    final fav = AppScope.of(context).favorites;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
            child: Row(children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop()),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    fillColor: const Color(0xFF2A2A2A),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    hintText: 'O que você quer ouvir?',
                    suffixIcon: empty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.cancel, size: 20),
                            onPressed: () {
                              _ctrl.clear();
                              _onChanged('');
                            }),
                  ),
                ),
              ),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: empty
                ? SmoothListView(children: [
                    if (_recents.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text('Recentes',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    for (final r in _recents)
                      _row(r,
                          trailing: IconButton(
                              icon: const Icon(Icons.close,
                                  color: AppColors.textSecondary),
                              onPressed: () {
                                setState(() => _recents.remove(r));
                                _saveRecents();
                              })),
                    SizedBox(height: bottomReserve(context)),
                  ])
                : ListenableBuilder(
                    listenable: fav,
                    builder: (context, _) => SmoothListView(children: [
                      if (_artist != null)
                        _row(_Rec('artist', _artist!, _artist!, '', '')),
                      for (final t in _tracks)
                        _row(
                            _Rec('track', t.id, t.title, t.artist,
                                t.albumId ?? t.id),
                            trailing: IconButton(
                              icon: Icon(
                                  fav.isFavorite(t.id)
                                      ? Icons.check_circle
                                      : Icons.add_circle_outline,
                                  color: fav.isFavorite(t.id)
                                      ? AppColors.accent
                                      : AppColors.textSecondary),
                              onPressed: () => fav.toggle(t),
                            )),
                      for (final a in _albums)
                        _row(_Rec('album', a.albumId!, a.album, a.artist,
                            a.albumId!)),
                      if (!_loading && _tracks.isEmpty && _artist == null)
                        const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                                child: Text('Nada encontrado',
                                    style: TextStyle(
                                        color: AppColors.textSecondary)))),
                      SizedBox(height: bottomReserve(context)),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}
