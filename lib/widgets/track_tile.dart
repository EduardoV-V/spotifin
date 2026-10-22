import 'download_badge.dart';
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../core/downloads/download_service.dart';
import '../core/format.dart';
import '../core/jellyfin/models.dart';
import 'add_to_playlist.dart';
import 'context_menu.dart';
import 'cover.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool wide;
  final bool showAdded;
  final int? index;
  const TrackTile(
      {super.key,
      required this.track,
      required this.onTap,
      this.onRemove,
      this.wide = false,
      this.showAdded = false,
      this.index});

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  Future<void> _downloadAlbum(BuildContext context, AppScope scope) async {
    try {
      final tracks = await scope.client.albumTracks(track.albumId!);
      scope.downloads.enqueue(tracks);
      if (context.mounted) {
        _snack(context, '${tracks.length} faixas na fila de download');
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Não foi possível buscar o álbum.');
    }
  }

  Widget _badge(DownloadItem? it) {
    switch (it?.state) {
      case DownloadState.completed:
        return const Icon(Icons.download_done,
            size: 18, color: AppColors.accent);
      case DownloadState.downloading:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(value: it!.progress, strokeWidth: 2),
        );
      case DownloadState.queued:
        return const Icon(Icons.schedule,
            size: 18, color: AppColors.textSecondary);
      case DownloadState.error:
        return const Icon(Icons.error_outline, size: 18, color: Colors.redAccent);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final player = scope.player;
    final downloads = scope.downloads;
    return ListenableBuilder(
      listenable: Listenable.merge([player, downloads, scope.favorites, scope.conn]),
      builder: (context, _) {
        final isCurrent = player.current?.id == track.id;
        final dl = downloads.itemFor(track.id);
        final state = dl?.state;
        final unavailable =
            scope.conn.offline && state != DownloadState.completed;
        final tap = unavailable
            ? () => _snack(context, 'Sem conexão: faixa não baixada.')
            : onTap;
        final menuW = PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
              color: AppColors.elevated,
              onSelected: (v) {
                switch (v) {
                  case 'next':
                    player.playNext(track);
                    _snack(context, 'Adicionada à fila');
                  case 'queue':
                    player.addToQueue(track);
                    _snack(context, 'Adicionada à fila');
                  case 'dl':
                    downloads.enqueue([track]);
                    _snack(context, 'Download iniciado');
                  case 'dl_cancel':
                    downloads.cancel(track.id);
                  case 'dl_rm':
                    downloads.remove(track.id);
                  case 'album':
                    _downloadAlbum(context, scope);
                  case 'pl':
                    showAddToPlaylist(context, [track]);
                  case 'rm':
                    onRemove?.call();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'next', child: Text('Tocar a seguir')),
                const PopupMenuItem(
                    value: 'queue', child: Text('Adicionar à fila')),
                const PopupMenuItem(
                    value: 'pl', child: Text('Adicionar à playlist')),
                if (onRemove != null)
                  const PopupMenuItem(
                      value: 'rm', child: Text('Remover da playlist')),
                if (state == DownloadState.completed)
                  const PopupMenuItem(
                      value: 'dl_rm', child: Text('Remover download'))
                else if (state == DownloadState.downloading ||
                    state == DownloadState.queued)
                  const PopupMenuItem(
                      value: 'dl_cancel', child: Text('Cancelar download'))
                else
                  const PopupMenuItem(value: 'dl', child: Text('Baixar')),
                if (track.albumId != null)
                  const PopupMenuItem(
                      value: 'album', child: Text('Baixar álbum')),
              ],
            );
        final trailingW = Row(mainAxisSize: MainAxisSize.min, children: [
            _badge(dl),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Favoritar',
              icon: Icon(
                  scope.favorites.isFavorite(track.id)
                      ? Icons.check_circle
                      : Icons.add_circle_outline,
                  size: 22,
                  color: scope.favorites.isFavorite(track.id)
                      ? AppColors.accent
                      : AppColors.textSecondary),
              onPressed: () => scope.favorites.toggle(track),
            ),
            menuW,
          ]);
        if (wide) {
          return _WideRow(
            track: track,
            index: index ?? 0,
            current: isCurrent,
            playing: isCurrent && player.playing,
            showAdded: showAdded,
            downloaded: state == DownloadState.completed,
            favorite: scope.favorites.isFavorite(track.id),
            onTap: tap,
            unavailable: unavailable,
            trailing: menuW,
            onFav: () => scope.favorites.toggle(track),
            onMenu: (p) => showTrackMenu(context, p, track, onRemove: onRemove),
          );
        }
        return Opacity(
          opacity: unavailable ? 0.4 : 1,
          child: InkWell(
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
            child: Row(children: [
              Cover(track: track, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color:
                                  isCurrent ? AppColors.accent : Colors.white)),
                      const SizedBox(height: 2),
                      Row(children: [
                        if (scope.favorites.isFavorite(track.id))
                          const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.check_circle,
                                  size: 14, color: AppColors.accent)),
                        if (state == DownloadState.completed)
                          const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.arrow_circle_down,
                                  size: 14, color: AppColors.accent)),
                        Flexible(
                          child: Text(track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary)),
                        ),
                      ]),
                    ]),
              ),
              Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.more_vert,
                      color: AppColors.textSecondary),
                  onPressed: () => showTrackMenu(
                      ctx, Offset.zero, track,
                      onRemove: onRemove),
                ),
              ),
            ]),
          ),
        ));
      },
    );
  }
}

const _months = [
  'jan.', 'fev.', 'mar.', 'abr.', 'mai.', 'jun.',
  'jul.', 'ago.', 'set.', 'out.', 'nov.', 'dez.'
];

String fmtAdded(DateTime? d) {
  if (d == null) return '';
  final days = DateTime.now().difference(d).inDays;
  if (days < 1) return 'hoje';
  if (days < 7) return 'há $days ${days == 1 ? 'dia' : 'dias'}';
  if (days < 30) {
    final w = days ~/ 7;
    return 'há $w ${w == 1 ? 'semana' : 'semanas'}';
  }
  return '${d.day} de ${_months[d.month - 1]} de ${d.year}';
}

class _WideRow extends StatefulWidget {
  final Track track;
  final int index;
  final bool current;
  final bool playing;
  final bool showAdded;
  final bool downloaded;
  final bool favorite;
  final bool unavailable;
  final VoidCallback onTap;
  final VoidCallback onFav;
  final Widget trailing;
  final void Function(Offset) onMenu;
  const _WideRow(
      {required this.onMenu,
      required this.track,
      required this.index,
      required this.current,
      required this.playing,
      required this.showAdded,
      required this.downloaded,
      required this.favorite,
      this.unavailable = false,
      required this.onTap,
      required this.onFav,
      required this.trailing});

  @override
  State<_WideRow> createState() => _WideRowState();
}

class _WideRowState extends State<_WideRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final green = widget.current;
    const dim = TextStyle(fontSize: 14, color: AppColors.textSecondary);
    Widget lead;
    if (_hover) {
      lead = const Icon(Icons.play_arrow, size: 20);
    } else if (widget.playing) {
      lead = const Icon(Icons.equalizer, size: 18, color: AppColors.accent);
    } else {
      lead = Text('${widget.index + 1}',
          style: TextStyle(
              fontSize: 15,
              color: green ? AppColors.accent : AppColors.textSecondary));
    }
    return Opacity(
      opacity: widget.unavailable ? 0.4 : 1,
      child: MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: (d) => widget.onMenu(d.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
              color: _hover ? const Color(0x1AFFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            SizedBox(width: 32, child: Center(child: lead)),
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
                            color: green ? AppColors.accent : Colors.white)),
                    Row(children: [
                      if (widget.downloaded)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.arrow_circle_down,
                              size: 14, color: AppColors.accent),
                        ),
                      Flexible(
                        child: Text(t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: dim.copyWith(
                                color: _hover
                                    ? Colors.white
                                    : AppColors.textSecondary)),
                      ),
                    ]),
                  ]),
            ),
            Expanded(
              flex: 4,
              child: Text(t.album,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: dim),
            ),
            if (widget.showAdded)
              Expanded(
                flex: 3,
                child: Text(fmtAdded(t.added),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: dim),
              ),
            SizedBox(
              width: 40,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _hover || widget.favorite ? 1 : 0,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (c, a) =>
                        ScaleTransition(scale: a, child: c),
                    child: Icon(
                        widget.favorite
                            ? Icons.check_circle
                            : Icons.add_circle_outline,
                        key: ValueKey(widget.favorite),
                        size: 20,
                        color: widget.favorite
                            ? AppColors.accent
                            : AppColors.textSecondary),
                  ),
                  onPressed: widget.onFav,
                ),
              ),
            ),
            SizedBox(
                width: 48,
                child: Text(
                    t.duration == null ? '' : fmtDuration(t.duration!),
                    textAlign: TextAlign.center,
                    style: dim)),
            SizedBox(
              width: 40,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _hover ? 1 : 0,
                child: widget.trailing,
              ),
            ),
          ]),
        ),
      ),
    ));
  }
}
