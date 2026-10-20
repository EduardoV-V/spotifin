import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/audio/player_service.dart';
import '../../core/cover_color.dart';
import '../../core/format.dart';
import '../../core/jellyfin/lyrics.dart';
import '../../core/jellyfin/models.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/cover.dart';
import '../../widgets/devices_sheet.dart';
import '../artists/artist_page.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});
  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  PageController? _pc;
  bool _animating = false;

  @override
  void dispose() {
    _pc?.dispose();
    super.dispose();
  }

  void _sync(PlayerService p) {
    final c = _pc;
    if (c == null || !c.hasClients || p.queueLength == 0) return;
    final cur = (c.page ?? c.initialPage.toDouble()).round();
    if (cur == p.orderPos || _animating) return;
    _animating = true;
    c
        .animateToPage(p.orderPos,
            duration: const Duration(milliseconds: 320), curve: Curves.easeOut)
        .whenComplete(() => _animating = false);
  }

  Widget _carousel(PlayerService p, Track t) {
    if (p.isMirror || p.queueLength == 0) {
      return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
              child: AspectRatio(
                  aspectRatio: 1, child: Cover(track: t, radius: 8))));
    }
    _pc ??= PageController(
        initialPage: p.orderPos.clamp(0, p.queueLength - 1),
        viewportFraction: 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(p));
    return PageView.builder(
        controller: _pc,
        itemCount: p.queueLength,
        onPageChanged: (i) {
          if (_animating || i == p.orderPos) return;
          p.jumpToOrder(i);
        },
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 24,
                        offset: Offset(0, 8))
                  ],
                ),
                child: Cover(track: p.trackAtOrder(i), radius: 8),
              ),
            ),
          ),
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final fav = scope.favorites;
    final p = scope.player;
    return ListenableBuilder(
      listenable: Listenable.merge([p, fav]),
      builder: (context, _) {
        final t = p.current;
        if (t == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final route = ModalRoute.of(context);
            if (route != null && route.isActive && !route.isFirst) {
              Navigator.of(context).removeRoute(route);
            }
          });
          return const Scaffold();
        }
        final isFav = fav.isFavorite(t.id);
        return CoverTint(
          itemId: t.albumId ?? t.id,
          builder: (context, tint) {
            final dark = Color.lerp(tint, Colors.black, 0.82)!;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [tint, Color.lerp(tint, Colors.black, 0.5)!, dark],
                  stops: const [0, 0.55, 1],
                ),
              ),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: LayoutBuilder(
                        builder: (context, box) => ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          SizedBox(
                            height: box.maxHeight,
                            child: Column(children: [
                          _topBar(context, p, t),
                          if (p.isMirror)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: const PlayingOnBar()),
                            ),
                          const SizedBox(height: 8),
                          Expanded(child: _carousel(p, t)),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(children: [
                              Expanded(
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(t.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 2),
                                      GestureDetector(
                                        onTap: () {
                                          final a = t.artist
                                              .split(RegExp(r',\s*|;\s*'))
                                              .first;
                                          pushShell(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      ArtistPage(name: a)));
                                        },
                                        child: Text(t.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xB3FFFFFF))),
                                      ),
                                    ]),
                              ),
                              IconButton(
                                iconSize: 28,
                                onPressed: () => fav.toggle(t),
                                icon: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  transitionBuilder: (c, a) =>
                                      ScaleTransition(scale: a, child: c),
                                  child: Icon(
                                      isFav
                                          ? Icons.check_circle
                                          : Icons.add_circle_outline,
                                      key: ValueKey(isFav),
                                      color: isFav
                                          ? AppColors.accent
                                          : Colors.white),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 8),
                          _ProgressBar(player: p),
                          _controls(p),
                          _bottomRow(context, p, t),
                            ]),
                          ),
                          const SizedBox(height: 8),
                          _LyricsCard(track: t, tint: tint),
                          if (p.advanced || p.playerError != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (p.advanced)
                                      Text('Arquivo: ${t.file.label}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary)),
                                    Text(p.playerError ?? p.verdict,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary)),
                                  ]),
                            ),
                        ],
                      )),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _topBar(BuildContext context, PlayerService p, Track t) => SizedBox(
        height: 56,
        child: Row(children: [
          IconButton(
            iconSize: 32,
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('TOCANDO DA PLAYLIST',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                      color: Color(0xB3FFFFFF))),
              Text(p.queueSource ?? t.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => showTrackMenu(context, Offset.zero, t),
          ),
        ]),
      );

  Widget _controls(PlayerService p) {
    Widget dot(bool on) => Container(
        width: 4,
        height: 4,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? AppColors.accent : Colors.transparent));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            iconSize: 26,
            icon: Icon(Icons.shuffle,
                color: p.shuffle ? AppColors.accent : Colors.white),
            onPressed: p.toggleShuffle,
          ),
          dot(p.shuffle),
        ]),
        IconButton(
          iconSize: 44,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: () => p.previous(),
        ),
        GestureDetector(
          onTap: () => p.togglePlay(),
          child: Container(
            width: 66,
            height: 66,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(
                  p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(p.playing),
                  size: 42,
                  color: Colors.black),
            ),
          ),
        ),
        IconButton(
          iconSize: 44,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: () => p.next(),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            iconSize: 26,
            icon: Icon(
                p.repeat == QueueRepeat.one ? Icons.repeat_one : Icons.repeat,
                color:
                    p.repeat == QueueRepeat.off ? Colors.white : AppColors.accent),
            onPressed: p.cycleRepeat,
          ),
          dot(p.repeat != QueueRepeat.off),
        ]),
      ]),
    );
  }

  Widget _bottomRow(BuildContext context, PlayerService p, Track t) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Row(children: [
          const DevicesButton(),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '${t.title} – ${t.artist}'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Nome copiado'),
                  duration: Duration(seconds: 2)));
            },
          ),
          if (!p.isMirror)
            IconButton(
              icon: const Icon(Icons.format_list_bulleted),
              onPressed: () => showQueueSheet(context),
            ),
        ]),
      );
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 19),
            child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Colors.white,
              inactiveTrackColor: const Color(0x44FFFFFF),
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: _drag == null ? 5 : 7),
            ),
            child: Slider(
              value: value,
              max: hi,
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                p.seek(Duration(milliseconds: v.round()));
                setState(() => _drag = null);
              },
            ),
          )),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(fmtDuration(Duration(milliseconds: value.round())),
                    style: const TextStyle(fontSize: 11, color: Color(0xB3FFFFFF))),
                Text(fmtDuration(dur),
                    style: const TextStyle(fontSize: 11, color: Color(0xB3FFFFFF))),
              ],
            ),
          ),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- Letra

class _LyricsCard extends StatelessWidget {
  final Track track;
  final Color tint;
  const _LyricsCard({required this.track, required this.tint});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context).client;
    final bg = Color.lerp(tint, Colors.white, 0.12)!;
    return FutureBuilder<List<LyricLine>>(
      key: ValueKey(track.id),
      future: c.lyrics(track.id),
      builder: (_, snap) {
        final lines = snap.data ?? const <LyricLine>[];
        final has = lines.any((l) => l.text.trim().isNotEmpty);
        final preview = lines
            .map((l) => l.text.trim())
            .where((e) => e.isNotEmpty)
            .take(5)
            .join('\n');
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: has
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => LyricsPage(tint: tint)))
                  : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(
                            child: Text('Letra',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800))),
                        if (has) const Icon(Icons.open_in_full, size: 20),
                      ]),
                      const SizedBox(height: 12),
                      Text(
                          has
                              ? preview
                              : (snap.connectionState == ConnectionState.done
                                  ? 'Letra indisponível para esta música.'
                                  : ''),
                          style: const TextStyle(
                              fontSize: 22,
                              height: 1.3,
                              fontWeight: FontWeight.w800)),
                    ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class LyricsPage extends StatefulWidget {
  final Color tint;
  const LyricsPage({super.key, required this.tint});
  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  final _keys = <int, GlobalKey>{};
  int _last = -1;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final p = scope.player;
    final bg = Color.lerp(widget.tint, Colors.white, 0.1)!;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final t = p.current;
        if (t == null) return const Scaffold();
        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            leading: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: () => Navigator.of(context).pop()),
            titleSpacing: 0,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              Text(t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xB3FFFFFF))),
            ]),
          ),
          body: FutureBuilder<List<LyricLine>>(
            key: ValueKey(t.id),
            future: scope.client.lyrics(t.id),
            builder: (_, snap) {
              final lines = snap.data ?? const <LyricLine>[];
              if (lines.isEmpty) {
                return const Center(child: Text('Letra indisponível.'));
              }
              final synced = lines.any((l) => l.startMs != null);
              return StreamBuilder<Duration>(
                stream: p.positionStream,
                builder: (_, ps) {
                  final ms = p
                      .displayPosition(ps.data ?? Duration.zero)
                      .inMilliseconds;
                  var cur = -1;
                  if (synced) {
                    for (var i = 0; i < lines.length; i++) {
                      final s = lines[i].startMs;
                      if (s != null && s <= ms) cur = i;
                    }
                  }
                  if (cur != _last) {
                    _last = cur;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final k = _keys[cur]?.currentContext;
                      if (k != null) {
                        Scrollable.ensureVisible(k,
                            alignment: 0.3,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOut);
                      }
                    });
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < lines.length; i++)
                            GestureDetector(
                              key: _keys.putIfAbsent(i, () => GlobalKey()),
                              onTap: lines[i].startMs == null
                                  ? null
                                  : () => p.seek(
                                      Duration(milliseconds: lines[i].startMs!)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 250),
                                  style: TextStyle(
                                      fontSize: 28,
                                      height: 1.25,
                                      fontWeight: FontWeight.w800,
                                      color: !synced || i == cur
                                          ? Colors.white
                                          : (i < cur
                                              ? const Color(0xAA000000)
                                              : const Color(0x88000000))),
                                  child: Text(lines[i].text),
                                ),
                              ),
                            ),
                        ]),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Fila

Timer? _sleepTimer;

void _showSleepTimer(BuildContext context, PlayerService p) {
  void set(int? min) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (min != null) {
      _sleepTimer = Timer(Duration(minutes: min), () => p.pause());
    }
  }

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: const Color(0xFF282828),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Timer',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        for (final m in const [5, 10, 15, 30, 45, 60])
          ListTile(
            title: Text('$m minutos'),
            onTap: () {
              set(m);
              Navigator.pop(ctx);
            },
          ),
        if (_sleepTimer != null)
          ListTile(
            title: const Text('Desativar timer'),
            onTap: () {
              set(null);
              Navigator.pop(ctx);
            },
          ),
      ]),
    ),
  );
}

void showQueueSheet(BuildContext context) {
  final p = AppScope.of(context).player;
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 420),
        reverseDuration: Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic),
    builder: (_) => _QueueSheet(player: p),
  );
}

class _QueueSheet extends StatefulWidget {
  final PlayerService player;
  const _QueueSheet({required this.player});
  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  bool _edit = false;

  Widget _pill(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Material(
          color: const Color(0xFF2E2E2E),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );

  Widget _tile(IconData icon, String label, bool on, VoidCallback onTap) =>
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: const Color(0xFF2E2E2E),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 22, color: on ? AppColors.accent : Colors.white),
                  const SizedBox(height: 4),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: on ? AppColors.accent : Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _currentRow(Track cur, PlayerService p) => Container(
        height: 72,
        color: const Color(0xFF121212),
        child: ListTile(
          leading: Cover(track: cur, size: 48),
          title: Text(cur.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.w600)),
          subtitle: Text(cur.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary)),
          trailing: GestureDetector(
            onTap: p.togglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: Icon(p.playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.black),
            ),
          ),
        ),
      );

  Widget _swipeBg(Color c, IconData i, Alignment al) => Container(
        color: c,
        alignment: al,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(i, color: Colors.black),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final bottom = MediaQuery.of(context).padding.bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      minChildSize: 0,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.95],
      builder: (ctx, ctl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: ListenableBuilder(
          listenable: p,
          builder: (ctx, _) {
            final base = p.orderPos + 1;
            final count = (p.queueLength - base).clamp(0, 1 << 30);
            final cur = p.current;
            return Stack(children: [
              CustomScrollView(
              controller: ctl,
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _FixedHeader(
                    76 + 72 + 10,
                    Column(children: [
                    Container(
                      height: 76,
                      color: const Color(0xFF121212),
                      child: Column(children: [
                        const SizedBox(height: 8),
                        Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                                color: Colors.white38,
                                borderRadius: BorderRadius.circular(2))),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Fila',
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800)),
                                    if (p.queueSource != null)
                                      Text('Tocando ${p.queueSource}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary)),
                                  ]),
                            ),
                            _pill('Limpar', p.clearUpcoming),
                            _pill(_edit ? 'Concluído' : 'Editar',
                                () => setState(() => _edit = !_edit)),
                          ]),
                        ),
                      ]),
                    ),
                    if (cur != null) _currentRow(cur, p),
                    Container(
                      height: 10,
                      decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF121212), Color(0x00121212)])),
                    ),
                    ]),
                  ),
                ),
                SliverReorderableList(
                  itemCount: count,
                  onReorder: (a, b) => p.reorder(a + base, b + base),
                  itemBuilder: (ctx, i) {
                    final o = i + base;
                    final t = p.trackAtOrder(o);
                    final manual = p.isManualAt(o);
                    return Dismissible(
                      key: ValueKey('q${p.keyAtOrder(o)}'),
                      movementDuration: const Duration(milliseconds: 320),
                      resizeDuration: const Duration(milliseconds: 320),
                      background: _swipeBg(
                          AppColors.accent, Icons.playlist_add, Alignment.centerLeft),
                      secondaryBackground: _swipeBg(const Color(0xFFE22134),
                          Icons.delete_outline, Alignment.centerRight),
                      confirmDismiss: (dir) async {
                        if (dir == DismissDirection.startToEnd) {
                          p.addToQueue(t);
                          return false;
                        }
                        return true;
                      },
                      onDismissed: (_) => p.removeAt(o),
                      child: Material(
                        color: const Color(0xFF121212),
                        child: ListTile(
                          leading: Cover(track: t, size: 48),
                          title: Text(t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Row(children: [
                            if (manual)
                              Container(
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                    color: AppColors.accent,
                                    borderRadius: BorderRadius.circular(2)),
                                child: const Icon(Icons.playlist_add,
                                    size: 9, color: Colors.black),
                              ),
                            Flexible(
                              child: Text(t.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary)),
                            ),
                          ]),
                          onTap: _edit ? null : () => p.jumpToOrder(o),
                          trailing: ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                SliverToBoxAdapter(child: SizedBox(height: 96 + bottom)),
              ],
            ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: const Color(0xF2121212),
                  padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 8),
                  child: Row(children: [
                    _tile(Icons.shuffle, 'Ordem aleatória', p.shuffle,
                        p.toggleShuffle),
                    _tile(
                        p.repeat == QueueRepeat.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                        'Repetir',
                        p.repeat != QueueRepeat.off,
                        p.cycleRepeat),
                    _tile(Icons.timer_outlined, 'Timer', _sleepTimer != null,
                        () => _showSleepTimer(context, p)),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _FixedHeader extends SliverPersistentHeaderDelegate {
  final double h;
  final Widget child;
  _FixedHeader(this.h, this.child);
  @override
  double get minExtent => h;
  @override
  double get maxExtent => h;
  @override
  Widget build(BuildContext c, double s, bool o) => child;
  @override
  bool shouldRebuild(covariant _FixedHeader old) => true;
}
