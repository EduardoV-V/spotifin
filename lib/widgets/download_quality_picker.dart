import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../core/downloads/download_service.dart';

/// Escolha da qualidade dos novos downloads (original ou MP3 em 3 taxas).
class DownloadQualityPicker extends StatelessWidget {
  const DownloadQualityPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final d = AppScope.of(context).downloads;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Qualidade dos novos downloads',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final q in const [
                DownloadQuality.original,
                DownloadQuality.mp3High,
                DownloadQuality.mp3,
                DownloadQuality.mp3Low,
              ])
                ChoiceChip(
                  label: Text(q.label),
                  selected: d.quality == q,
                  onSelected: (_) => d.setQuality(q),
                ),
            ]),
            const SizedBox(height: 4),
            const Text(
                'Vale para os próximos downloads. Os já baixados mantêm a qualidade em que foram baixados.',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
          ]),
    );
  }
}
