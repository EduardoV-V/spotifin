import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/jellyfin_client.dart';
import '../../core/jellyfin/models.dart';
import '../../widgets/track_tile.dart';
import '../playlists/playlists_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _tracks = <Track>[];
  final _scroll = ScrollController();
  int _total = 0;
  bool _loading = false;
  bool _onlyDownloaded = false;
  bool _onlyFavorites = false;
  bool _onlyPlaylists = false;
  String? _error;
  bool _init = false;
  late final AppScope _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _scope = AppScope.of(context);
    _scope.reload.addListener(_onReload);
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scope.reload.removeListener(_onReload);
    _scroll.dispose();
    super.dispose();
  }

  void _onReload() => _load(reset: true);

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      _tracks.clear();
      _total = 0;
    } else if (_tracks.isNotEmpty && _tracks.length >= _total) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page =
          await _scope.client.getTracks(startIndex: _tracks.length, limit: 100);
      _tracks.addAll(page.items);
      _total = page.total;
    } on JellyfinException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Sem conexão com o servidor.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _allList() {
    return ListView.builder(
      controller: _scroll,
      itemCount: _tracks.length + (_loading ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _tracks.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return TrackTile(
          track: _tracks[i],
          onTap: () => _scope.player.playQueue(List.of(_tracks), i),
        );
      },
    );
  }

  Widget _downloadedList() {
    return ListenableBuilder(
      listenable: _scope.downloads,
      builder: (context, _) {
        final list = _scope.downloads.completedTracks;
        if (list.isEmpty) {
          return const Center(
            child: Text('Nenhuma música baixada.',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => TrackTile(
            track: list[i],
            onTap: () => _scope.player.playQueue(List.of(list), i),
          ),
        );
      },
    );
  }

  Widget _favoritesList() {
    return ListenableBuilder(
      listenable: _scope.favorites,
      builder: (context, _) {
        final list = _scope.favorites.tracks;
        if (list.isEmpty) {
          return const Center(
            child: Text('Nenhuma música favorita.',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => TrackTile(
            track: list[i],
            onTap: () => _scope.player.playQueue(List.of(list), i),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text('Sua Biblioteca',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, children: [
            ChoiceChip(
              label: const Text('Todas'),
              selected: !_onlyDownloaded && !_onlyFavorites && !_onlyPlaylists,
              onSelected: (_) => setState(() {
                _onlyDownloaded = false;
                _onlyFavorites = false;
                _onlyPlaylists = false;
              }),
            ),
            ChoiceChip(
              label: const Text('Playlists'),
              selected: _onlyPlaylists,
              onSelected: (_) => setState(() {
                _onlyDownloaded = false;
                _onlyFavorites = false;
                _onlyPlaylists = true;
              }),
            ),
            ChoiceChip(
              label: const Text('Favoritas'),
              selected: _onlyFavorites,
              onSelected: (_) => setState(() {
                _onlyDownloaded = false;
                _onlyPlaylists = false;
                _onlyFavorites = true;
              }),
            ),
            ChoiceChip(
              label: const Text('Baixadas'),
              selected: _onlyDownloaded,
              onSelected: (_) => setState(() {
                _onlyDownloaded = true;
                _onlyPlaylists = false;
                _onlyFavorites = false;
              }),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
              _onlyDownloaded
                  ? 'Disponíveis offline'
                  : _onlyPlaylists
                      ? '${_scope.playlists.playlists.length} playlists'
                      : _onlyFavorites
                      ? '${_scope.favorites.tracks.length} favoritas'
                      : (_error == null ? '$_total músicas' : ''),
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
        if (_error != null && !_onlyDownloaded && !_onlyFavorites && !_onlyPlaylists)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
              TextButton(
                  onPressed: () => _load(reset: true),
                  child: const Text('Tentar de novo')),
            ]),
          ),
        const SizedBox(height: 4),
        Expanded(
            child: _onlyPlaylists
                ? const PlaylistsView()
                : _onlyDownloaded
                ? _downloadedList()
                : _onlyFavorites
                    ? _favoritesList()
                    : _allList()),
      ]),
    );
  }
}
