import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../core/jellyfin/models.dart';

/// Capa da playlist: imagem do Jellyfin; se não houver, mosaico 2x2
/// das 4 primeiras faixas. [version] força recarregar após trocar a foto.
class PlaylistCover extends StatelessWidget {
  final String id;
  final double size;
  final int version;
  final double radius;
  const PlaylistCover(
      {super.key,
      required this.id,
      required this.size,
      this.version = 0,
      this.radius = 4});

  @override
  Widget build(BuildContext context) {
    final client = AppScope.of(context).client;
    final px = (size * 2).round().clamp(120, 800);
    final uri = client.imageUri(id, maxWidth: px).toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          version == 0 ? uri : '$uri&v=$version',
          key: ValueKey('$id#$version'),
          headers: client.authHeaders,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _Mosaic(id: id, size: size),
        ),
      ),
    );
  }
}

class _Mosaic extends StatelessWidget {
  final String id;
  final double size;
  const _Mosaic({required this.id, required this.size});

  @override
  Widget build(BuildContext context) {
    final client = AppScope.of(context).client;
    return FutureBuilder<List<Track>>(
      future: client.playlistPreview(id),
      builder: (context, snap) {
        final l = snap.data ?? const <Track>[];
        if (l.isEmpty) {
          return Container(
              color: AppColors.elevated,
              child: Icon(Icons.queue_music,
                  size: size * 0.4, color: AppColors.textSecondary));
        }
        Widget cell(int i) => i < l.length
            ? Image.network(
                client
                    .imageUri(l[i].albumId ?? l[i].id,
                        maxWidth: (size).round().clamp(80, 400))
                    .toString(),
                headers: client.authHeaders,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AppColors.elevated))
            : Container(color: AppColors.elevated);
        // com menos de 4 faixas repete a primeira capa inteira
        if (l.length < 4) return cell(0);
        return Column(children: [
          Expanded(child: Row(children: [Expanded(child: cell(0)), Expanded(child: cell(1))])),
          Expanded(child: Row(children: [Expanded(child: cell(2)), Expanded(child: cell(3))])),
        ]);
      },
    );
  }
}
