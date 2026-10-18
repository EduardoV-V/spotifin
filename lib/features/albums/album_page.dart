import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/models.dart';
import '../../core/recent/recent_store.dart';
import '../../widgets/cover.dart';
import '../../widgets/smooth_scroll.dart';
import '../../widgets/track_tile.dart';

class AlbumPage extends StatefulWidget {
  final String albumId, name, artist;
  const AlbumPage(
      {super.key,
      required this.albumId,
      required this.name,
      required this.artist});
  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  List<Track>? _l;
  final _sc = SmoothScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_l != null) return;
    AppScope.of(context).client.albumTracks(widget.albumId).then((v) {
      if (mounted) setState(() => _l = v);
    }).catchError((_) {
      if (mounted) setState(() => _l = const []);
    });
  }

  void _play(List<Track> l, int i) {
    RecentStore.instance
        .add('album', widget.albumId, widget.name, widget.artist);
    AppScope.of(context).player.playQueue(List.of(l), i, source: widget.name);
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    return Scaffold(
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(controller: _sc, slivers: [
              SliverAppBar(pinned: true, backgroundColor: const Color(0xFF181818)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (l.isNotEmpty) Cover(track: l.first, size: 200),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Álbum',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w500)),
                            Text(widget.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 48,
                                    height: 1.05,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            Text('${widget.artist} • ${l.length} músicas',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                          ]),
                    ),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Row(children: [
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: l.isEmpty ? null : () => _play(l, 0),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                            color: AppColors.accent, shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow,
                            color: Colors.black, size: 30),
                      ),
                    ),
                  ]),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                    (_, i) => TrackTile(
                        track: l[i],
                        wide: true,
                        index: i,
                        onTap: () => _play(l, i)),
                    childCount: l.length),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ]),
    );
  }
}
