import 'package:flutter/material.dart';

import '../app/app_scope.dart';

class VolumeControl extends StatelessWidget {
  final bool expand;
  const VolumeControl({super.key, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final slider = Slider(
          value: p.volume,
          onChanged: (v) => p.setVolume(v, persist: false),
          onChangeEnd: (_) => p.commitVolume(),
        );
        return Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(p.volume == 0
                  ? Icons.volume_off
                  : p.volume < 0.5
                      ? Icons.volume_down
                      : Icons.volume_up),
              onPressed: () => p.toggleMute(),
            ),
            if (expand) Expanded(child: slider) else SizedBox(width: 110, child: slider),
          ],
        );
      },
    );
  }
}
