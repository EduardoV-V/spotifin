import 'net_image.dart';
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../core/jellyfin/models.dart';

/// Tamanhos padronizados (também usados ao baixar capas) para o cache ser
/// reaproveitado entre telas e funcionar offline.
const kCoverBuckets = [96, 300, 600];

int coverBucket(double? size) {
  final px = (size ?? 600) * 1.5;
  for (final b in kCoverBuckets) {
    if (px <= b) return b;
  }
  return kCoverBuckets.last;
}

/// Outros tamanhos, do mais próximo (maiores primeiro) ao mais distante.
List<int> coverFallbacks(int b) => [
      ...kCoverBuckets.where((x) => x > b),
      ...kCoverBuckets.where((x) => x < b).toList().reversed,
    ];

class Cover extends StatelessWidget {
  final Track track;
  final double? size;
  final double radius;
  const Cover({super.key, required this.track, this.size, this.radius = 4});

  @override
  Widget build(BuildContext context) {
    final client = AppScope.of(context).client;
    final px = coverBucket(size);
    final cid = track.albumId ?? track.id;
    final img = NetImage(
      client.imageUri(cid, maxWidth: px).toString(),
      fallbacks: [
        for (final b in coverFallbacks(px))
          client.imageUri(cid, maxWidth: b).toString()
      ],
      headers: client.authHeaders,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.elevated,
        child: const Icon(Icons.music_note, color: AppColors.textSecondary),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: size == null
          ? AspectRatio(aspectRatio: 1, child: img)
          : SizedBox(width: size, height: size, child: img),
    );
  }
}
