import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../core/audio/player_service.dart';
import '../features/player/now_playing_page.dart';
import '../core/cover_color.dart';
import 'cover.dart';
import 'devices_sheet.dart';
import 'volume_control.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final t = p.current;
        if (t == null) return const SizedBox.shrink();
        final fav = AppScope.of(context).favorites;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: CoverTint(
            itemId: t.albumId ?? t.id,
            fallback: const Color(0xFF2A3A55),
            builder: (context, color) => Material(
              color: color,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => const NowPlayingPage())),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const PlayingOnBar(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
                    child: Row(children: [
                      Cover(track: t, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              Text(t.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white70)),
                            ]),
                      ),
                      const DevicesButton(),
                      ListenableBuilder(
                        listenable: fav,
                        builder: (_, __) => IconButton(
                          icon: Icon(
                              fav.isFavorite(t.id)
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline,
                              color: fav.isFavorite(t.id)
                                  ? AppColors.accent
                                  : Colors.white),
                          onPressed: () => fav.toggle(t),
                        ),
                      ),
                      IconButton(
                        iconSize: 30,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                              p.playing ? Icons.pause : Icons.play_arrow,
                              key: ValueKey(p.playing)),
                        ),
                        onPressed: () => p.togglePlay(),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: _MiniProgress(player: p)),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniProgress extends StatelessWidget {
  final PlayerService player;
  const _MiniProgress({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (_, snap) {
        final pos = player.displayPosition(snap.data ?? Duration.zero);
        final total = player.duration.inMilliseconds;
        final v = total <= 0 ? 0.0 : (pos.inMilliseconds / total).clamp(0.0, 1.0);
        return LinearProgressIndicator(
          value: v,
          minHeight: 2,
          color: Colors.white,
          backgroundColor: Colors.white24,
        );
      },
    );
  }
}
