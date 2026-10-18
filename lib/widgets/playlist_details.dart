import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import 'playlist_cover.dart';

class PlaylistEdit {
  final String name;
  final bool photoChanged;
  const PlaylistEdit(this.name, this.photoChanged);
}

/// Diálogo "Nome e detalhes": nome, descrição e foto da playlist.
Future<PlaylistEdit?> showPlaylistDetails(
        BuildContext context, String id, String name, int version) =>
    showDialog<PlaylistEdit>(
        context: context,
        builder: (_) => _Details(id: id, name: name, version: version));

class _Details extends StatefulWidget {
  final String id, name;
  final int version;
  const _Details({required this.id, required this.name, required this.version});
  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  late final _name = TextEditingController(text: widget.name);
  final _desc = TextEditingController();
  String _descOrig = '';
  Uint8List? _img;
  String _mime = 'image/jpeg';
  bool _busy = false;
  String? _err;

  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final c = AppScope.of(context).client;
    c.playlistOverview(widget.id).then((d) {
      if (!mounted) return;
      _descOrig = d;
      _desc.text = d;
    }).catchError((_) {});
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f?.bytes == null) return;
    final ext = (f!.extension ?? '').toLowerCase();
    setState(() {
      _img = f.bytes;
      _mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    });
  }

  Future<void> _save() async {
    final scope = AppScope.of(context);
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final n = _name.text.trim();
      var outName = widget.name;
      if (n.isNotEmpty && n != widget.name) {
        final e = await scope.playlists.rename(widget.id, n);
        if (e != null) throw Exception(e);
        outName = n;
      }
      if (_desc.text != _descOrig) {
        await scope.client.setPlaylistOverview(widget.id, _desc.text);
      }
      if (_img != null) {
        await scope.client.uploadPlaylistImage(widget.id, _img!, _mime);
        scope.client.clearPreview(widget.id);
      }
      if (mounted) Navigator.pop(context, PlaylistEdit(outName, _img != null));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF282828),
      title: const Text('Editar detalhes'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: _pick,
              child: Stack(children: [
                _img != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(_img!,
                            width: 150, height: 150, fit: BoxFit.cover))
                    : PlaylistCover(
                        id: widget.id, size: 150, version: widget.version),
                const Positioned.fill(
                    child: Center(
                        child: Icon(Icons.photo_camera_outlined,
                            size: 36, color: Colors.white70))),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(children: [
                TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nome')),
                const SizedBox(height: 12),
                TextField(
                    controller: _desc,
                    maxLines: 4,
                    decoration:
                        const InputDecoration(labelText: 'Descrição')),
              ]),
            ),
          ]),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_err!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Sem foto, a capa será um mosaico das 4 primeiras músicas.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar')),
      ],
    );
  }
}
