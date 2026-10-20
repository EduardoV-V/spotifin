import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/artists/artist_info_service.dart';

import '../../app/account_actions.dart';
import '../../app/app_scope.dart';
import '../../core/jellyfin/models.dart';
import '../../core/storage/session_store.dart';
import '../downloads/downloads_page.dart';
import '../spike/login_page.dart';

void openSettings(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const SettingsPage()));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _url =
      TextEditingController(text: AppScope.of(context).client.session!.serverUrl);
  String? _status;
  bool _busy = false;

  Future<void> _save() async {
    final scope = AppScope.of(context);
    setState(() {
      _busy = true;
      _status = null;
    });
    final ok = await scope.client.ping(_url.text);
    if (!ok) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Servidor inacessível nesse endereço.';
        });
      }
      return;
    }
    final old = scope.client.session!.serverUrl;
    final updated = scope.client.updateServerUrl(_url.text);
    await SessionStore.replaceServerUrl(old, updated.serverUrl);
    await SessionStore.save(updated);
    await scope.player.stop();
    scope.reload.value++;
    scope.watcher.restart();
    if (mounted) Navigator.of(context).pop();
  }

  List<JellyfinSession> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final l = await SessionStore.accounts();
    if (mounted) setState(() => _accounts = l);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _switch(JellyfinSession a) async {
    final err =
        await switchAccount(AppScope.of(context), Navigator.of(context), a);
    if (err != null && mounted) _toast(err);
  }

  Future<void> _remove(JellyfinSession a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remover ${a.username}?'),
        content: const Text('Os downloads desta conta também serão apagados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await removeAccount(AppScope.of(context), Navigator.of(context), a);
    if (mounted) _loadAccounts();
  }

  Future<void> _add() async {
    final s = AppScope.of(context).client.session!;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LoginPage(initialUrl: s.serverUrl, canCancel: true)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'URL do Jellyfin',
                  hintText: 'http://jellyfin.home:8096'),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_status!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Testar e salvar')),
            const SizedBox(height: 24),
            ListenableBuilder(
              listenable: AppScope.of(context).player,
              builder: (context, _) {
                final pl = AppScope.of(context).player;
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Qualidade do streaming',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        for (final q in const [
                          (0, 'Original'),
                          (320, 'Alta · 320k'),
                          (192, 'Normal · 192k'),
                          (96, 'Baixa · 96k'),
                        ])
                          ChoiceChip(
                            label: Text(q.$2),
                            selected: pl.streamKbps == q.$1,
                            onSelected: (_) => pl.setStreamKbps(q.$1),
                          ),
                      ]),
                    ]);
              },
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: AppScope.of(context).player,
              builder: (context, _) {
                final pl = AppScope.of(context).player;
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Opções avançadas'),
                  subtitle: const Text(
                      'Sincronização manual e diagnóstico do arquivo'),
                  value: pl.advanced,
                  onChanged: pl.setAdvanced,
                );
              },
            ),
            ListenableBuilder(
              listenable: Listenable.merge([
                AppScope.of(context).player,
                AppScope.of(context).sync,
              ]),
              builder: (context, _) {
                final sync = AppScope.of(context).sync;
                if (!AppScope.of(context).player.advanced) {
                  return const SizedBox.shrink();
                }
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      sync.lastError == null ? Icons.sync : Icons.sync_problem),
                  title: const Text('Sincronizar reprodução agora'),
                  subtitle: Text(sync.lastError ??
                      (sync.lastOk == null
                          ? 'Ainda não sincronizado'
                          : sync.remoteInfo)),
                  onTap: () async {
                    final err = await sync.pullNow();
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(err)));
                    }
                  },
                );
              },
            ),
            const _MetaKeys(),
            const SizedBox(height: 8),
            const Text('Spotifin build ui14',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_outlined),
              title: const Text('Downloads e armazenamento'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DownloadsPage())),
            ),
            const SizedBox(height: 16),
            Text('Contas', style: Theme.of(context).textTheme.titleMedium),
            for (final a in _accounts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                    a.userId == AppScope.of(context).client.session?.userId
                        ? Icons.check_circle
                        : Icons.account_circle_outlined),
                title: Text(a.username.isEmpty ? a.userId : a.username),
                subtitle: Text(a.serverUrl),
                onTap: () => _switch(a),
                trailing: IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Remover conta',
                    onPressed: () => _remove(a)),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Adicionar conta')),
          ]),
        ),
      ),
    );
  }
}

class _MetaKeys extends StatefulWidget {
  const _MetaKeys();
  @override
  State<_MetaKeys> createState() => _MetaKeysState();
}

class _MetaKeysState extends State<_MetaKeys> {
  final _fields = <String, TextEditingController>{
    ArtistInfoService.audioDbPref: TextEditingController(),
    LastFmService.prefKey: TextEditingController(),
    LastFmService.lbPref: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      _fields.forEach((k, c) => c.text = sp.getString(k) ?? '');
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _f(String key, String label, String help) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _fields[key],
          decoration: InputDecoration(
              labelText: label,
              helperText: help,
              helperMaxLines: 2,
              suffixIcon: _fields[key]!.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _fields[key]!.clear();
                        SharedPreferences.getInstance()
                            .then((sp) => sp.remove(key));
                        setState(() {});
                      })),
          onChanged: (v) {
            SharedPreferences.getInstance().then((sp) => v.trim().isEmpty
                ? sp.remove(key)
                : sp.setString(key, v.trim()));
            setState(() {});
          },
        ),
      );

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        Text('Metadados (opcional)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
            'Fotos e reproduções globais vêm de serviços externos. Sem chaves, fica só o que o Deezer/ListenBrainz entregam.',
            style: TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 12),
        _f(ArtistInfoService.audioDbPref, 'Chave do TheAudioDB',
            'Vazio usa a chave pública de teste (2).'),
        _f(LastFmService.prefKey, 'Chave da API do Last.fm',
            'Reproduções globais por música (recomendado).'),
        _f(LastFmService.lbPref, 'Token do ListenBrainz', 'Opcional.'),
        OutlinedButton(
          onPressed: () async {
            showDialog(
                context: context,
                builder: (_) => const AlertDialog(
                    content: SizedBox(
                        height: 48,
                        child: Center(child: CircularProgressIndicator()))));
            final r = await diagnoseMetadata();
            if (!context.mounted) return;
            Navigator.of(context).pop();
            showDialog(
                context: context,
                builder: (_) => AlertDialog(
                    title: const Text('Teste de conexão'), content: Text(r)));
          },
          child: const Text('Testar conexão'),
        ),
      ]);
}
