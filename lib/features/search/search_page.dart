import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/jellyfin_client.dart';
import '../../core/jellyfin/models.dart';
import '../../widgets/track_tile.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Track> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await AppScope.of(context).client.searchTracks(query);
      if (!mounted || _ctrl.text.trim() != query) return;
      setState(() => _results = results);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro de rede na busca.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _ctrl,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'O que você quer ouvir?',
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!))
              : _results.isEmpty
                  ? Center(
                      child: Text(
                        _ctrl.text.trim().isEmpty
                            ? 'Busque por título, artista ou álbum'
                            : (_loading ? '' : 'Nada encontrado'),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) => TrackTile(
                        track: _results[i],
                        onTap: () => player.playQueue(_results, i),
                      ),
                    ),
        ),
      ]),
    );
  }
}
