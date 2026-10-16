import 'package:flutter/material.dart';

import '../../core/jellyfin/jellyfin_client.dart';
import '../../core/storage/session_store.dart';
import 'tracks_page.dart';

class LoginPage extends StatefulWidget {
  final JellyfinClient client;
  const LoginPage({super.key, required this.client});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await widget.client.login(
        serverUrl: _url.text,
        username: _user.text,
        password: _pass.text,
        deviceId: await SessionStore.deviceId(),
      );
      await SessionStore.save(s);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => TracksPage(client: widget.client)));
    } on JellyfinException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text('Conectar ao Jellyfin',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: 'URL do servidor',
                      hintText: 'http://192.168.0.10:8096')),
              TextField(
                  controller: _user,
                  decoration: const InputDecoration(labelText: 'Usuário')),
              TextField(
                  controller: _pass,
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _login(),
                  decoration: const InputDecoration(labelText: 'Senha')),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Entrar')),
            ],
          ),
        ),
      ),
    );
  }
}
