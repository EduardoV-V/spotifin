import 'net_image.dart';
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../core/jellyfin/models.dart';

class Cover extends StatelessWidget {
  final Track track;
  final double? size;
  final double radius;
  const Cover({super.key, required this.track, this.size, this.radius = 4});

  @override
  Widget build(BuildContext context) {
    final client = AppScope.of(context).client;
    final px = ((size ?? 400) * 2).round().clamp(120, 800);
    final img = NetImage(
      client.imageUri(track.albumId ?? track.id, maxWidth: px).toString(),
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
