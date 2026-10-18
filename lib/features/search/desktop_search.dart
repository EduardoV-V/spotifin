import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/artists/artist_info_service.dart';
import '../../core/i18n/strings.dart';
import '../../core/jellyfin/models.dart';
import '../../widgets/cover.dart';
import '../../widgets/track_tile.dart';

class ArtistAvatar extends StatelessWidget {
  final String name;
  final double size;
  const ArtistAvatar({super.key, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<ArtistInfo?>(
          future: ArtistInfoService.instance.get(name),
          builder: (_, s) {
            final url = s.data?.picture ?? s.data?.hero;
            final fallback = Container(
                color: AppColors.elevated,
                child: Icon(Icons.person,
                    size: size * 0.5, color: AppColors.textSecondary));
            if (url == null) return fallback;
            return Image.network(url,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
          },
        ),
      ),
    );
  }
}

class DesktopSearchBox extends StatefulWidget {
  final void Function(String q) onSubmit;
  final void Function(String artist) onOpenArtist;
  const DesktopSearchBox(
      {super.key, required this.onSubmit, required this.onOpenArtist});
  @override
  State<DesktopSearchBox> createState() => _DesktopSearchBoxState();
}

class _DesktopSearchBoxState extends State<DesktopSearchBox> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  OverlayEntry? _entry;
  Timer? _debounce;
  String _q = '';
  bool _loading = false;
  List<Track> _tracks = const [];
  String? _artist;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _show();
      } else {
        _hide();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hide();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _show() {
    if (_entry != null) return;
    _entry = OverlayEntry(builder: _overlay);
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  void _onChanged(String v) {
    setState(() {});
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      _q = '';
      _tracks = const [];
      _artist = null;
      _loading = false;
      _entry?.markNeedsBuild();
      return;
    }
    _loading = true;
    _entry?.markNeedsBuild();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await AppScope.of(context).client.searchTracks(q, limit: 40);
        if (!mounted || _ctrl.text.trim() != q) return;
        final count = <String, int>{};
        for (final t in r) {
          final a = ArtistInfoService.primary(t.artist);
          count[a] = (count[a] ?? 0) + 1;
        }
        String? top;
        final ql = q.toLowerCase();
        final named = count.keys.where((a) => a.toLowerCase().contains(ql));
        if (named.isNotEmpty) {
          top = named.reduce((a, b) => count[a]! >= count[b]! ? a : b);
        }
        _q = q;
        _tracks = r.take(5).toList();
        _artist = top;
      } catch (_) {
        _tracks = const [];
        _artist = null;
      } finally {
        _loading = false;
        _entry?.markNeedsBuild();
      }
    });
  }

  void _submit(String v) {
    final q = v.trim();
    if (q.isEmpty) return;
    _focus.unfocus();
    widget.onSubmit(q);
  }

  Widget _skeleton() => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          for (var i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3A),
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            height: 10,
                            width: 120.0 + (i % 3) * 60,
                            color: const Color(0xFF3A3A3A)),
                        const SizedBox(height: 6),
                        Container(
                            height: 8,
                            width: 70,
                            color: const Color(0xFF333333)),
                      ]),
                ),
              ]),
            ),
        ]),
      );

  Widget _row(Widget lead, Widget title, {String? sub, VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            lead,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (sub != null)
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                  ]),
            ),
          ]),
        ),
      );

  Widget _overlay(BuildContext _) {
    final box = context.findRenderObject() as RenderBox?;
    final w = box?.size.width ?? 420;
    final player = AppScope.of(context).player;
    final children = <Widget>[];
    if (_ctrl.text.trim().isEmpty) {
      children.add(_skeleton());
    } else if (_loading && _tracks.isEmpty) {
      children.add(_skeleton());
    } else {
      children.add(_row(
        const SizedBox(
            width: 40,
            child: Icon(Icons.search, color: AppColors.textSecondary)),
        Text(_q.isEmpty ? _ctrl.text : _q,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: () => _submit(_ctrl.text),
      ));
      if (_artist != null) {
        final a = _artist!;
        children.add(_row(
          ArtistAvatar(name: a, size: 40),
          Text(a, style: const TextStyle(fontWeight: FontWeight.w500)),
          sub: S.t('artist'),
          onTap: () {
            _focus.unfocus();
            widget.onOpenArtist(a);
          },
        ));
      }
      for (final t in _tracks) {
        children.add(_row(
          Cover(track: t, size: 40),
          Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500)),
          sub: '${S.t('song')} • ${t.artist}',
          onTap: () {
            _focus.unfocus();
            player.playQueue([t], 0);
          },
        ));
      }
      if (_tracks.isEmpty && !_loading) {
        children.add(Padding(
          padding: const EdgeInsets.all(16),
          child: Text(S.t('nothing_found'),
              style: const TextStyle(color: AppColors.textSecondary)),
        ));
      }
    }
    return Positioned(
      width: w,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        offset: const Offset(0, 50),
        child: TextFieldTapRegion(
          child: Material(
            color: const Color(0xFF282828),
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Row(children: [
                      Text(S.t('navigate'),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                      const Spacer(),
                      Text('Enter  ${S.t('search')}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ]),
                  ),
                  ...children,
                  const SizedBox(height: 6),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: SizedBox(
        height: 44,
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onChanged,
          onSubmitted: _submit,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.elevated,
            hintText: S.t('search_hint'),
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            prefixIcon:
                const Icon(Icons.search, color: AppColors.textSecondary),
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _ctrl.clear();
                      _onChanged('');
                    }),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: Colors.white, width: 2)),
          ),
        ),
      ),
    );
  }
}

enum _Tab { all, songs, artists, albums }

class SearchResultsPage extends StatefulWidget {
  final String query;
  final void Function(String artist) onOpenArtist;
  const SearchResultsPage(
      {super.key, required this.query, required this.onOpenArtist});
  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  List<Track>? _tracks;
  _Tab _tab = _Tab.all;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    AppScope.of(context)
        .client
        .searchTracks(widget.query, limit: 120)
        .then((v) {
      if (mounted) setState(() => _tracks = v);
    }).catchError((_) {
      if (mounted) setState(() => _tracks = const []);
    });
  }

  List<String> _artists(List<Track> l) {
    final c = <String, int>{};
    for (final t in l) {
      final a = ArtistInfoService.primary(t.artist);
      c[a] = (c[a] ?? 0) + 1;
    }
    final q = widget.query.toLowerCase();
    final k = c.keys.toList()
      ..sort((a, b) {
        final qa = a.toLowerCase().contains(q) ? 1 : 0;
        final qb = b.toLowerCase().contains(q) ? 1 : 0;
        return qb != qa ? qb - qa : c[b]!.compareTo(c[a]!);
      });
    return k;
  }

  Widget _chip(String label, _Tab t) {
    final on = _tab == t;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _tab = t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    final l = _tracks;
    return Scaffold(
      body: l == null
          ? const Center(child: _Dots())
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 700;
              final artists = _artists(l);
              final albums = <Track>[];
              final seen = <String>{};
              for (final t in l) {
                if (seen.add(t.albumId ?? t.album)) albums.add(t);
              }
              Widget songs(int n) => Column(children: [
                    for (var i = 0; i < l.length && i < n; i++)
                      TrackTile(
                        track: l[i],
                        wide: wide,
                        index: i,
                        onTap: () => player.playQueue(List.of(l), i,
                            source: widget.query),
                      ),
                  ]);
              Widget artistRow() => SizedBox(
                    height: 190,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: artists.length.clamp(0, 12),
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (_, i) => InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => widget.onOpenArtist(artists[i]),
                        child: SizedBox(
                          width: 150,
                          child: Column(children: [
                            ArtistAvatar(name: artists[i], size: 150),
                            const SizedBox(height: 8),
                            Text(artists[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text(S.t('artist'),
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ]),
                        ),
                      ),
                    ),
                  );
              Widget albumRow() => SizedBox(
                    height: 210,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: albums.length.clamp(0, 12),
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (_, i) {
                        final a = albums[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            final q = l
                                .where((t) =>
                                    (t.albumId ?? t.album) ==
                                    (a.albumId ?? a.album))
                                .toList();
                            player.playQueue(q, 0, source: a.album);
                          },
                          child: SizedBox(
                            width: 150,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Cover(track: a, size: 150),
                                  const SizedBox(height: 8),
                                  Text(a.album,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  Text(a.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                ]),
                          ),
                        );
                      },
                    ),
                  );
              final top = artists.isEmpty ? null : artists.first;
              final body = <Widget>[
                if (_tab == _Tab.all && top != null) ...[
                  _title(S.t('top_result')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => widget.onOpenArtist(top),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          ArtistAvatar(name: top, size: 92),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(top,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  Text(S.t('artist'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ],
                if (_tab == _Tab.all || _tab == _Tab.songs) ...[
                  if (_tab == _Tab.all) _title(S.t('songs')),
                  songs(_tab == _Tab.all ? 5 : l.length),
                ],
                if ((_tab == _Tab.all || _tab == _Tab.artists) &&
                    artists.isNotEmpty) ...[
                  _title(S.t('artists')),
                  artistRow(),
                ],
                if ((_tab == _Tab.all || _tab == _Tab.albums) &&
                    albums.isNotEmpty) ...[
                  _title(S.t('albums')),
                  albumRow(),
                ],
                if (l.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                        child: Text(S.t('nothing_found'),
                            style: const TextStyle(
                                color: AppColors.textSecondary))),
                  ),
                const SizedBox(height: 24),
              ];
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _chip(S.t('all'), _Tab.all),
                      _chip(S.t('songs'), _Tab.songs),
                      _chip(S.t('artists'), _Tab.artists),
                      _chip(S.t('albums'), _Tab.albums),
                    ]),
                  ),
                ),
                ...body,
              ]);
            }),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots();
  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.3 +
                    0.7 *
                        (((_c.value * 3 - i) % 3) < 1
                            ? 1 - ((_c.value * 3 - i) % 3)
                            : 0))),
          ),
      ]),
    );
  }
}
