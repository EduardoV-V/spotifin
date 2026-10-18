import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/models.dart';
import '../../widgets/cover.dart';
import '../../widgets/track_tile.dart';

/// Todas as músicas do servidor, em lista ou ícones; carrega por páginas.
class MusicBrowser extends StatefulWidget {
  const MusicBrowser({super.key});
  @override
  State<MusicBrowser> createState() => _MusicBrowserState();
}

class _MusicBrowserState extends State<MusicBrowser> {
  final _items = <Track>[];
  int _total = 1;
  bool _busy = false;
  bool _grid = false;
  bool _init = false;
  late final AppScope _scope;
  final _scroll = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _scope = AppScope.of(context);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) _more();
    });
    _more();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _more() async {
    if (_busy || _items.length >= _total) return;
    _busy = true;
    try {
      final p = await _scope.client
          .getTracks(startIndex: _items.length, limit: 200);
      if (!mounted) return;
      setState(() {
        _items.addAll(p.items);
        _total = p.total;
      });
    } catch (_) {
      _total = _items.length;
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  void _play(int i) => _scope.player.playQueue(List.of(_items), i);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text('${_total > 1 || _items.isNotEmpty ? _total : 0} músicas',
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
          const Spacer(),
          IconButton(
            tooltip: 'Lista',
            color: _grid ? AppColors.textSecondary : AppColors.accent,
            icon: const Icon(Icons.format_list_bulleted),
            onPressed: () => setState(() => _grid = false),
          ),
          IconButton(
            tooltip: 'Ícones',
            color: _grid ? AppColors.accent : AppColors.textSecondary,
            icon: const Icon(Icons.grid_view),
            onPressed: () => setState(() => _grid = true),
          ),
        ]),
      ),
      Expanded(
        child: _items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _grid
                ? GridView.builder(
                    controller: _scroll,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisExtent: 236,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 8),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final t = _items[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _play(i),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AspectRatio(
                                  aspectRatio: 1, child: Cover(track: t)),
                              const SizedBox(height: 8),
                              Text(t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                              Text(t.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ]),
                      );
                    },
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _items.length,
                    itemBuilder: (_, i) =>
                        TrackTile(track: _items[i], onTap: () => _play(i)),
                  ),
      ),
    ]);
  }
}
