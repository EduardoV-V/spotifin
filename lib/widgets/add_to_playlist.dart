import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../core/jellyfin/models.dart';

Future<String?> askName(BuildContext context,
    {String title = 'Nova playlist', String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome'),
          onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Salvar')),
      ],
    ),
  );
}

void _snack(BuildContext context, String msg) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

Future<void> showAddToPlaylist(BuildContext context, List<Track> tracks) async {
  final svc = AppScope.of(context).playlists;
  final choice = await showModalBottomSheet<PlaylistInfo?>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: svc,
        builder: (_, __) => ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Nova playlist'),
            onTap: () => Navigator.pop(ctx, const PlaylistInfo('', '', 0)),
          ),
          for (final p in svc.playlists)
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(p.name),
              subtitle: Text('${p.count} faixas'),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ]),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  String? err;
  String done;
  if (choice.id.isEmpty) {
    final name = await askName(context);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    err = await svc.create(name, tracks);
    done = 'Playlist "${name.trim()}" criada';
  } else {
    final r = await addToPlaylistChecked(context, choice, tracks);
    if (r == null) return;
    done = r;
  }
  if (context.mounted) _snack(context, err ?? done);
}

/// Adiciona à playlist avisando se alguma faixa já estiver nela.
/// Retorna a mensagem a exibir, ou null se o usuário cancelou.
Future<String?> addToPlaylistChecked(
    BuildContext context, PlaylistInfo p, List<Track> tracks) async {
  final scope = AppScope.of(context);
  var toAdd = tracks;
  try {
    final existing = (await scope.client.playlistTracks(p.id))
        .map((t) => Track.key(t.id))
        .toSet();
    final dup = tracks.where((t) => existing.contains(Track.key(t.id))).toList();
    if (dup.isNotEmpty) {
      if (!context.mounted) return null;
      final all = dup.length == tracks.length;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(all
              ? (tracks.length == 1
                  ? 'Já está nesta playlist'
                  : 'Já estão nesta playlist')
              : '${dup.length} já estão nesta playlist'),
          content: Text(all
              ? 'Deseja adicionar mesmo assim a "${p.name}"?'
              : 'Adicionar todas ou só as que ainda não estão em "${p.name}"?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            if (!all)
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'new'),
                  child: const Text('Só as novas')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'all'),
                child: Text(all ? 'Adicionar' : 'Adicionar todas')),
          ],
        ),
      );
      if (choice == null) return null;
      if (choice == 'new') {
        toAdd = tracks.where((t) => !existing.contains(Track.key(t.id))).toList();
      }
    }
  } catch (_) {}
  final err = await scope.playlists.add(p.id, toAdd);
  return err ?? 'Adicionada a "${p.name}"';
}
