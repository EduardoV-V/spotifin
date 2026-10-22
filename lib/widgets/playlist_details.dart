import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../core/cache/local_covers.dart';
import 'playlist_cover.dart';

class PlaylistEdit {
  final String name;
  final bool photoChanged;
  final bool deleted;
  final bool localCover;
  const PlaylistEdit(this.name, this.photoChanged,
      {this.deleted = false, this.localCover = false});
}

/// Diálogo "Nome e detalhes": nome, descrição e foto da playlist.
Future<PlaylistEdit?> showPlaylistDetails(
    BuildContext context, String id, String name, int version) {
  if (MediaQuery.sizeOf(context).width < 700) {
    return showModalBottomSheet<PlaylistEdit>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _Details(id: id, name: name, version: version, sheet: true),
      ),
    );
  }
  return showDialog<PlaylistEdit>(
      context: context,
      builder: (_) => _Details(id: id, name: name, version: version));
}

class _Details extends StatefulWidget {
  final String id, name;
  final int version;
  final bool sheet;
  const _Details(
      {required this.id,
      required this.name,
      required this.version,
      this.sheet = false});
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
      var localCover = false;
      if (_img != null) {
        try {
          await scope.client.uploadPlaylistImage(widget.id, _img!, _mime);
          await LocalCovers.remove(widget.id);
        } catch (e) {
          if ('$e'.contains('403')) {
            // Sem permissão no Jellyfin: guarda a capa só neste aparelho.
            await LocalCovers.save(widget.id, _img!);
            localCover = true;
          } else {
            rethrow;
          }
        }
        scope.client.clearPreview(widget.id);
      }
      if (mounted) Navigator.pop(
            context, PlaylistEdit(outName, _img != null, localCover: localCover));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _delete() async {
    final scope = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Apagar "${widget.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await scope.playlists.delete(widget.id);
    if (!mounted) return;
    if (err != null) {
      setState(() => _err = err);
    } else {
      Navigator.pop(context, PlaylistEdit(widget.name, false, deleted: true));
    }
  }

  Widget _sheet() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.white, fontSize: 13))),
            const Expanded(
                child: Center(
                    child: Text('Nome e detalhes',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)))),
            TextButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Salvar',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 13))),
          ]),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: _pick,
              child: Stack(children: [
                _img != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Image.memory(_img!,
                            width: 120, height: 120, fit: BoxFit.cover))
                    : PlaylistCover(
                        id: widget.id,
                        size: 120,
                        version: widget.version,
                        radius: 2),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                        color: Color(0xCC555555), shape: BoxShape.circle),
                    child: const Icon(Icons.edit, size: 16),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(children: [
                TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                        isDense: true,
                        fillColor: Color(0xFF3E3E3E),
                        contentPadding: EdgeInsets.all(12))),
                const SizedBox(height: 8),
                TextField(
                    controller: _desc,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        isDense: true,
                        fillColor: Color(0xFF3E3E3E),
                        hintText: 'Adicione uma descrição',
                        contentPadding: EdgeInsets.all(12))),
              ]),
            ),
          ]),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_err!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Apagar playlist',
                style: TextStyle(fontWeight: FontWeight.w500)),
            onTap: _busy ? null : _delete,
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sheet) return _sheet();
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
