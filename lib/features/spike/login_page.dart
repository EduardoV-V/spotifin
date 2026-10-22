import 'package:flutter/material.dart';

import '../../app/account_actions.dart';
import '../../app/app_scope.dart';
import '../../core/jellyfin/jellyfin_client.dart';
import '../../core/storage/session_store.dart';

class LoginPage extends StatefulWidget {
  final String? initialUrl;
  final String? initialUser;
  final bool canCancel;
  const LoginPage(
      {super.key, this.initialUrl, this.initialUser, this.canCancel = false});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _url = TextEditingController(text: widget.initialUrl);
  late final _user = TextEditingController(text: widget.initialUser);
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    final scope = AppScope.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final base = await scope.client.resolveServerUrl(_url.text);
      if (mounted) _url.text = base;
      final s = await scope.client.login(
        serverUrl: base,
        username: _user.text,
        password: _pass.text,
        deviceId: await SessionStore.deviceId(),
      );
      await SessionStore.save(s);
      await applyAccount(scope, nav, s);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: widget.canCancel ? AppBar() : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
            children: [
              Text(widget.canCancel ? 'Adicionar conta' : 'Conectar ao Jellyfin',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: 'URL do servidor',
                      hintText: 'jellyfin.home:8096 (http/https é detectado)')),
              const SizedBox(height: 12),
              TextField(
                  controller: _user,
                  decoration: const InputDecoration(labelText: 'Usuário')),
              const SizedBox(height: 12),
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
