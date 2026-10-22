import 'package:flutter/widgets.dart';

import '../core/audio/player_service.dart';
import '../core/downloads/download_service.dart';
import '../core/favorites/favorites_service.dart';
import '../core/jellyfin/jellyfin_client.dart';
import '../core/playlists/playlists_service.dart';
import '../core/connect/connect_service.dart';
import '../core/sync/play_state_sync.dart';
import '../core/jellyfin/library_watcher.dart';
import '../core/net/connectivity_service.dart';
import '../core/sync/outbox.dart';

class AppScope extends InheritedWidget {
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

  const AppScope({
    super.key,
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
    required this.outbox,
    required super.child,
  });

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
