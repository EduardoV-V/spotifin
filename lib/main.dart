import 'core/cache/image_store.dart';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app/app_scope.dart';
import 'app/app_shell.dart';
import 'app/theme.dart';
import 'core/audio/audio_backend.dart';
import 'core/cache/local_covers.dart';
import 'core/audio/audio_handler.dart';
import 'core/audio/player_service.dart';
import 'core/downloads/download_foreground.dart';
import 'core/downloads/download_service.dart';
import 'core/favorites/favorites_service.dart';
import 'core/net/connectivity_service.dart';
import 'core/playlists/playlists_service.dart';
import 'core/sync/outbox.dart';
import 'core/connect/connect_service.dart';
import 'core/sync/play_state_sync.dart';
import 'core/sync/playback_reporter.dart';
import 'core/jellyfin/jellyfin_client.dart';
import 'core/jellyfin/models.dart';
import 'core/jellyfin/library_watcher.dart';
import 'core/storage/session_store.dart';
import 'features/auth/login_page.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initAudioBackend();
  final client = JellyfinClient(
      deviceName: Platform.isAndroid
          ? 'Android'
          : Platform.localHostname.replaceAll('"', ''));
  client.session = await SessionStore.load();
  final player = PlayerService(client);
  final downloads = DownloadService(client);
  if (Platform.isAndroid) {
    DownloadForeground.init();
    DownloadForeground(downloads).attach();
  }
  await downloads.init();
  await LocalCovers.init();
  await ImageStore.init();
  player.localPathResolver = downloads.localPath;
  if (client.session != null) await player.restore();
  if (Platform.isAndroid) {
    try {
      await AudioService.init(
        builder: () => SpotifinAudioHandler(player, client),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.spotifin.playback',
          androidNotificationChannelName: 'Reprodução',
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('audio_service indisponível: $e');
    }
  }
  final reload = ValueNotifier<int>(0);
  final favorites = FavoritesService(client);
  if (client.session != null) await favorites.switchUser();
  final conn = ConnectivityService(client);
  final outbox = OutboxService(client, conn);
  if (client.session != null) await outbox.switchUser();
  final playlists = PlaylistsService(client, outbox: outbox, conn: conn);
  if (client.session != null) await playlists.switchUser();
  outbox.onFlushed = playlists.scheduleRefresh;
  client.offlineTracks = () {
    final seen = <String>{};
    return [
      for (final t in [...downloads.completedTracks, ...favorites.tracks])
        if (seen.add(Track.key(t.id))) t
    ];
  };
  await conn.start();
  PlaybackReporter(player, client).attach();
  final sync = PlayStateSync(player, client)
    ..onNotice = (m) => messengerKey.currentState
        ?.showSnackBar(SnackBar(content: Text(m)));
  if (client.session != null) await sync.start();
  reload.addListener(sync.pull);
  conn.addListener(() {
    if (conn.online) {
      outbox.flush();
      favorites.scheduleRefresh();
      playlists.scheduleRefresh();
      sync.pull();
    }
  });
  reload.addListener(favorites.scheduleRefresh);
  reload.addListener(playlists.scheduleRefresh);
  final connect = ConnectService(client, player)
    ..onNotice = ((m) => messengerKey.currentState
        ?.showSnackBar(SnackBar(content: Text(m))))
    ..start();
  final watcher = LibraryWatcher(client, reload)
    ..onUserDataChanged = favorites.applyUserData
    ..onRemotePlay = ((d) => connect.handlePlay(d))
    ..onRemotePlaystate = ((d) => connect.handlePlaystate(d))
    ..onSessions = connect.ingestPush
    ..onConnected = connect.announce;
  connect.onSessionsPush = watcher.setSessionsPush;
  if (client.session != null) watcher.start();
  runApp(SpotifinApp(
      client: client,
      player: player,
      downloads: downloads,
      favorites: favorites,
      playlists: playlists,
      sync: sync,
      connect: connect,
      reload: reload,
      watcher: watcher,
      conn: conn,
      outbox: outbox));
  if (Platform.isAndroid) FlutterForegroundTask.requestNotificationPermission();
}

class SpotifinApp extends StatelessWidget {
  final JellyfinClient client;
  final PlayerService player;
  final DownloadService downloads;
  final FavoritesService favorites;
  final PlaylistsService playlists;
  final PlayStateSync sync;
  final ConnectService connect;
  final ValueNotifier<int> reload;
  final LibraryWatcher watcher;
  final ConnectivityService conn;
  final OutboxService outbox;
  const SpotifinApp(
      {super.key,
      required this.client,
      required this.player,
      required this.downloads,
      required this.favorites,
      required this.playlists,
      required this.sync,
      required this.connect,
      required this.reload,
      required this.watcher,
      required this.conn,
      required this.outbox});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      client: client,
      player: player,
      downloads: downloads,
      favorites: favorites,
      playlists: playlists,
      sync: sync,
      connect: connect,
      reload: reload,
      watcher: watcher,
      conn: conn,
      outbox: outbox,
      child: MaterialApp(
        title: 'Spotifin',
        scaffoldMessengerKey: messengerKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: client.session == null ? const LoginPage() : const AppShell(),
      ),
    );
  }
}
