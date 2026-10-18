import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'download_service.dart';

/// Mostra uma notificação de progresso e mantém o app vivo (Android) enquanto
/// houver downloads na fila ou em andamento.
class DownloadForeground {
  DownloadForeground(this._d);

  final DownloadService _d;
  bool _running = false;
  bool _busy = false;
  String _lastText = '';
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'spotifin_downloads',
        channelName: 'Downloads',
        channelDescription: 'Progresso dos downloads',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  void attach() => _d.addListener(_onChange);

  String _text() {
    final pending = _d.pendingCount;
    final cur = _d.currentItem;
    final pct = cur?.progress;
    final title = cur?.track.title ?? 'Preparando…';
    final p = pct == null ? '' : ' ${(pct * 100).round()}%';
    return '$pending na fila • $title$p';
  }

  Future<void> _onChange() async {
    if (_busy) return;
    try {
      if (_d.pendingCount > 0) {
        final text = _text();
        if (!_running) {
          _busy = true;
          _lastText = text;
          await FlutterForegroundTask.startService(
            serviceId: 4711,
            serviceTypes: [ForegroundServiceTypes.dataSync],
            notificationTitle: 'Baixando músicas',
            notificationText: text,
          );
          _running = true;
        } else if (text != _lastText &&
            DateTime.now().difference(_lastUpdate) >
                const Duration(seconds: 1)) {
          _lastText = text;
          _lastUpdate = DateTime.now();
          await FlutterForegroundTask.updateService(notificationText: text);
        }
      } else if (_running) {
        _busy = true;
        _running = false;
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }
}
