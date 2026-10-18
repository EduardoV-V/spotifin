import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/theme.dart';
import '../core/connect/connect_service.dart';

IconData _iconFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('android') || n.contains('phone') || n.contains('ios')) {
    return Icons.smartphone;
  }
  if (n.contains('web') || n.contains('chrome') || n.contains('firefox')) {
    return Icons.language;
  }
  return Icons.computer;
}

class DevicesButton extends StatelessWidget {
  const DevicesButton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) => IconButton(
        tooltip: 'Dispositivos',
        icon: Icon(Icons.speaker_group_outlined,
            color: p.isMirror ? AppColors.accent : null),
        onPressed: () => showDevicesSheet(context),
      ),
    );
  }
}

class PlayingOnBar extends StatelessWidget {
  const PlayingOnBar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final m = p.mirror;
        if (m == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: AppColors.accent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.speaker_group, size: 14, color: Colors.black),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Tocando em ${m.deviceName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      },
    );
  }
}

void showDevicesSheet(BuildContext context) {
  final scope = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  scope.connect.poll();
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.elevated,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([scope.connect, scope.player]),
        builder: (context, _) {
          final c = scope.connect;
          final m = scope.player.mirror;
          final enabled = c.canConnect;

          Future<void> pick(RemoteDevice? d) async {
            if (c.transferring) return;
            // Fecha a folha ANTES de transferir: a troca demora vários
            // segundos e um pop() tardio/duplicado removia a página errada
            // (inclusive a rota raiz -> tela preta).
            if (ctx.mounted) Navigator.of(ctx).pop();
            final err = await c.transferTo(d);
            if (err != null) {
              messenger.showSnackBar(SnackBar(content: Text(err)));
            }
          }

          return ListView(shrinkWrap: true, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Conectar a um dispositivo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (!enabled)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('Sem conexão com o servidor. Dispositivos indisponíveis.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ListTile(
              leading: Icon(_iconFor(c.myName),
                  color: m == null ? AppColors.accent : null),
              title: Text('Este dispositivo (${c.myName})',
                  style: TextStyle(
                      color: m == null ? AppColors.accent : Colors.white,
                      fontWeight: FontWeight.w500)),
              subtitle: m == null && scope.player.playing
                  ? const Text('Tocando agora')
                  : null,
              onTap: enabled && !c.transferring ? () => pick(null) : null,
              enabled: enabled || m == null,
            ),
            for (final d in c.devices)
              ListTile(
                leading: Icon(_iconFor(d.name),
                    color: m?.sessionId == d.id ? AppColors.accent : null),
                title: Text(d.name,
                    style: TextStyle(
                        color: m?.sessionId == d.id
                            ? AppColors.accent
                            : Colors.white,
                        fontWeight: FontWeight.w500)),
                subtitle: Text(d.playing
                    ? 'Tocando agora'
                    : (d.track != null ? 'Pausado' : 'Disponível')),
                enabled: enabled && !c.transferring,
                onTap: enabled && !c.transferring ? () => pick(d) : null,
              ),
            if (c.devices.isEmpty && enabled)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhum outro dispositivo aberto nesta conta.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
          ]);
        },
      ),
    ),
  );
}
