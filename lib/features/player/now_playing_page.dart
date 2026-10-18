import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/audio/player_service.dart';
import '../../core/format.dart';
import '../../widgets/cover.dart';
import '../../widgets/devices_sheet.dart';
import '../../widgets/volume_control.dart';

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fav = AppScope.of(context).favorites;
    final p = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: Listenable.merge([p, fav]),
      builder: (context, _) {
        final t = p.current;
        if (t == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            // Remove só ESTA rota (maybePop poderia fechar uma folha/diálogo
            // aberto por cima, ou a rota raiz).
            final route = ModalRoute.of(context);
            if (route != null && route.isActive && !route.isFirst) {
              Navigator.of(context).removeRoute(route);
            }
          });
          return const Scaffold();
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('Tocando agora', style: TextStyle(fontSize: 14)),
            centerTitle: true,
            actions: [
              const DevicesButton(),
              if (!p.isMirror)
                IconButton(
                  icon: const Icon(Icons.queue_music),
                  onPressed: () => showQueueSheet(context),
                ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  children: [
                    if (p.isMirror)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: const PlayingOnBar()),
                      ),
                    Cover(track: t, radius: 8),
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(t.artist,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      color: AppColors.textSecondary)),
                            ]),
                      ),
                      IconButton(
                        iconSize: 28,
                        icon: Icon(
                            fav.isFavorite(t.id)
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            color: fav.isFavorite(t.id)
                                ? AppColors.accent
                                : Colors.white),
                        onPressed: () => fav.toggle(t),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _ProgressBar(player: p),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(Icons.shuffle,
                              color: p.shuffle ? AppColors.accent : Colors.white),
                          onPressed: p.toggleShuffle,
                        ),
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.skip_previous),
                          onPressed: () => p.previous(),
                        ),
                        IconButton.filled(
                          iconSize: 36,
                          style: IconButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black),
                          icon:
                              Icon(p.playing ? Icons.pause : Icons.play_arrow),
                          onPressed: () => p.togglePlay(),
                        ),
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.skip_next),
                          onPressed: () => p.next(),
                        ),
                        IconButton(
                          icon: Icon(
                            p.repeat == QueueRepeat.one
                                ? Icons.repeat_one
                                : Icons.repeat,
                            color: p.repeat == QueueRepeat.off
                                ? Colors.white
                                : AppColors.accent,
                          ),
                          onPressed: p.cycleRepeat,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const VolumeControl(expand: true),
                    const SizedBox(height: 8),
                    if (p.advanced || p.playerError != null) ...[
                      if (p.advanced)
                        Text('Arquivo: ${t.file.label}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(p.playerError ?? p.verdict,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressBar extends StatefulWidget {
  final PlayerService player;
  const _ProgressBar({required this.player});
  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    return StreamBuilder<Duration>(
      stream: p.positionStream,
      builder: (_, snap) {
        final pos = p.displayPosition(snap.data ?? Duration.zero);
        final dur = p.duration;
        final hi = dur.inMilliseconds <= 0 ? 1.0 : dur.inMilliseconds.toDouble();
        final value =
            (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, hi).toDouble();
        return Column(children: [
          Slider(
            value: value,
            max: hi,
            onChanged: (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              p.seek(Duration(milliseconds: v.round()));
              setState(() => _drag = null);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(fmtDuration(Duration(milliseconds: value.round())),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text(fmtDuration(dur),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ]);
      },
    );
  }
}

void showQueueSheet(BuildContext context) {
  final p = AppScope.of(context).player;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.elevated,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListenableBuilder(
        listenable: p,
        builder: (ctx, _) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Fila',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    if (p.queueSource != null)
                      Text('Tocando ${p.queueSource}',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                  ]),
              const Spacer(),
              TextButton(
                  onPressed: () => p.clearUpcoming(),
                  child: const Text('Limpar')),
            ]),
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollController: scroll,
              buildDefaultDragHandles: false,
              itemCount: p.queueLength,
              onReorder: (a, b) => p.reorder(a, b),
              itemBuilder: (ctx, i) {
                final t = p.trackAtOrder(i);
                final isCur = i == p.orderPos;
                return ListTile(
                  key: ValueKey(p.keyAtOrder(i)),
                  leading: Cover(track: t, size: 40),
                  title: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isCur ? AppColors.accent : Colors.white)),
                  subtitle: Text(t.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary)),
                  onTap: () => p.jumpToOrder(i),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => p.removeAt(i),
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle,
                          color: AppColors.textSecondary),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    ),
  );
}
