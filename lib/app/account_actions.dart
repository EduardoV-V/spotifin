import 'dart:async';

import 'package:flutter/material.dart';

import '../core/jellyfin/models.dart';
import '../core/storage/session_store.dart';
import '../features/auth/login_page.dart';
import 'app_scope.dart';
import 'app_shell.dart';

/// Ativa [s] como conta atual e recarrega o app.
Future<void> applyAccount(
    AppScope scope, NavigatorState nav, JellyfinSession s) async {
  scope.watcher.stop();
  await scope.player.reset();
  scope.client.session = s;
  await SessionStore.setActive(s.userId);
  await scope.downloads.switchUser();
  await scope.favorites.switchUser();
  await scope.outbox.switchUser();
  await scope.playlists.switchUser();
  unawaited(scope.sync.start());
  await scope.sync.switchUser();
  scope.connect.reset();
  scope.reload.value++;
  scope.watcher.start();
  nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppShell()), (_) => false);
}

/// Troca para uma conta salva. Retorna uma mensagem de erro, se houver.
Future<String?> switchAccount(
    AppScope scope, NavigatorState nav, JellyfinSession s) async {
  if (scope.client.session?.userId == s.userId) return null;
  final valid = await scope.client.tokenValid(s);
  if (valid == false) {
    nav.push(MaterialPageRoute(
        builder: (_) => LoginPage(
            initialUrl: s.serverUrl,
            initialUser: s.username,
            canCancel: true)));
    return 'Sessão expirada. Entre novamente.';
  }
  await applyAccount(scope, nav, s);
  return null;
}

/// Remove a conta (e seus downloads). Cai no login se não restar nenhuma.
Future<void> removeAccount(
    AppScope scope, NavigatorState nav, JellyfinSession s) async {
  final wasActive = scope.client.session?.userId == s.userId;
  if (wasActive) scope.watcher.stop();
  await scope.downloads.purgeUser(s.userId);
  final next = await SessionStore.remove(s.userId);
  if (!wasActive) return;
  if (next != null) {
    await applyAccount(scope, nav, next);
  } else {
    scope.sync.stop();
    await scope.player.reset();
    scope.client.session = null;
    nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }
}
