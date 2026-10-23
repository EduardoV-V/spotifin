import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:just_audio_media_kit/just_audio_media_kit.dart';

/// Em Android o just_audio usa ExoPlayer. Em Windows/Linux não há backend
/// nativo, então usamos media_kit (libmpv), que decodifica FLAC Hi-Res.
void initAudioBackend() {
  if (Platform.isWindows || Platform.isLinux) {
    try {
      JustAudioMediaKit.ensureInitialized();
    } catch (e) {
      // Sem libmpv o app abre, mas não toca (instale libmpv2/libmpv-dev).
      debugPrint('Áudio indisponível: $e');
    }
  }
}
