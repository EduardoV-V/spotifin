import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../core/audio/player_service.dart';
import '../features/player/now_playing_page.dart';
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Material(
            color: AppColors.elevated,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => const NowPlayingPage())),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const PlayingOnBar(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                  child: Row(children: [
                    Cover(track: t, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            Text(t.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ]),
                    ),
                    const DevicesButton(),
                    IconButton(
                      icon: Icon(p.playing ? Icons.pause : Icons.play_arrow),
                      onPressed: () => p.togglePlay(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: () => p.next(),
                    ),
                    if (MediaQuery.sizeOf(context).width >= 800)
                      const VolumeControl(),
                  ]),
                ),
                _MiniProgress(player: p),
              ]),
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
