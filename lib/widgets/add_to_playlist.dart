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
    err = await svc.add(choice.id, tracks);
    done = 'Adicionada a "${choice.name}"';
  }
  if (context.mounted) _snack(context, err ?? done);
}
