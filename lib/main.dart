import 'package:flutter/material.dart';

import 'core/audio/audio_backend.dart';
import 'core/jellyfin/jellyfin_client.dart';
import 'core/storage/session_store.dart';
import 'features/spike/login_page.dart';
import 'features/spike/tracks_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initAudioBackend();
  final client = JellyfinClient();
  client.session = await SessionStore.load();
  runApp(JellyMusicApp(client: client));
}

class JellyMusicApp extends StatelessWidget {
  final JellyfinClient client;
  const JellyMusicApp({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotifin',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.deepPurple,
          brightness: Brightness.dark,
          useMaterial3: true),
      home: client.session == null
          ? LoginPage(client: client)
          : TracksPage(client: client),
    );
  }
}
