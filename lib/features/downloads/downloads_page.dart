import '../../widgets/download_quality_picker.dart';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_service.dart';
import '../../core/format.dart';
import '../../widgets/cover.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  late final _dir = TextEditingController(
      text: AppScope.of(context).downloads.directoryPath);
  String? _dirMsg;

  String _status(DownloadItem it) {
    switch (it.state) {
      case DownloadState.queued:
        return 'Na fila';
      case DownloadState.downloading:
        final t = it.totalBytes;
        return '${fmtBytes(it.bytesReceived)}${t != null ? ' / ${fmtBytes(t)}' : ''}';
      case DownloadState.completed:
        return '${it.quality.shortLabel} • ${fmtBytes(it.bytesReceived)}';
      case DownloadState.error:
        return it.error ?? 'Erro';
      case DownloadState.cancelled:
        return 'Cancelado';
      case DownloadState.missing:
        return 'Arquivo ausente';
    }
  }

  Future<void> _confirmClear(DownloadService d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover todos os downloads?'),
        content: const Text(
            'Os arquivos deste aparelho serão apagados. O servidor e as playlists não são afetados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok == true) await d.removeAll();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final d = scope.downloads;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final items = d.items;
        final done = items.where((i) => i.state == DownloadState.completed);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Downloads'),
            actions: [
              IconButton(
                tooltip: 'Remover todos',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: items.isEmpty ? null : () => _confirmClear(d),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                      '${done.length} faixas • ${fmtBytes(d.usedBytes)} usados',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: const DownloadQualityPicker(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Platform.isAndroid
                      ? Text('Pasta: ${d.directoryPath}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary))
                      : Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _dir,
                              decoration: const InputDecoration(
                                  labelText: 'Pasta de downloads', isDense: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: () async {
                              final err = await d.setDirectory(_dir.text.trim());
                              if (mounted) {
                                setState(() => _dirMsg = err ??
                                    'Pasta atualizada (vale para novos downloads).');
                              }
                            },
                            child: const Text('Salvar'),
                          ),
                        ]),
                ),
                if (_dirMsg != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(_dirMsg!,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                          'Nenhum download. Use o menu ⋮ de uma música para baixar.',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                for (final it in items)
                  ListTile(
                    leading: Cover(track: it.track, size: 40),
                    title: Text(it.track.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${it.track.artist} • ${_status(it)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                          if (it.state == DownloadState.downloading)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: LinearProgressIndicator(
                                  value: it.progress, minHeight: 2),
                            ),
                        ]),
                    onTap: it.state == DownloadState.completed
                        ? () {
                            final list = d.completedTracks;
                            final i =
                                list.indexWhere((t) => t.id == it.track.id);
                            if (i >= 0) scope.player.playQueue(list, i);
                          }
                        : null,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (it.state == DownloadState.downloading ||
                          it.state == DownloadState.queued)
                        IconButton(
                          tooltip: 'Cancelar',
                          icon: const Icon(Icons.close),
                          onPressed: () => d.cancel(it.track.id),
                        )
                      else ...[
                        if (it.state != DownloadState.completed)
                          IconButton(
                            tooltip: 'Tentar de novo',
                            icon: const Icon(Icons.refresh),
                            onPressed: () => d.retry(it.track.id),
                          ),
                        IconButton(
                          tooltip: 'Remover',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => d.remove(it.track.id),
                        ),
                      ],
                    ]),
                  ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        );
      },
    );
  }
}
