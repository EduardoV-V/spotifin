import 'package:flutter/material.dart';

import '../../core/jellyfin/jellyfin_client.dart';
import '../../core/storage/session_store.dart';

class SettingsPage extends StatefulWidget {
  final JellyfinClient client;
  const SettingsPage({super.key, required this.client});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _url = TextEditingController(text: widget.client.session!.serverUrl);
  String? _status;
  bool _busy = false;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final ok = await widget.client.ping(_url.text);
    if (!ok) {
      setState(() {
        _busy = false;
        _status = 'Servidor inacessível nesse endereço.';
      });
      return;
    }
    await SessionStore.save(widget.client.updateServerUrl(_url.text));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'URL do Jellyfin',
                  hintText: 'http://jellyfin.home:8096')),
          if (_status != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_status!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _busy ? null : _save, child: const Text('Testar e salvar')),
        ]),
      ),
    );
  }
}