import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Ícone de download do Spotify: círculo verde cheio com seta preta.
class DownloadBadge extends StatelessWidget {
  final double size;
  const DownloadBadge({super.key, this.size = 16});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration:
            const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
        child: Icon(Icons.arrow_downward_rounded,
            size: size * 0.68, color: Colors.black),
      );
}
