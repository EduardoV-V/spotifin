import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';

/// Menu "Criar" (botão + da barra inferior): cartão com opções e X no lugar da aba.
Future<void> showCreateSheet(BuildContext context) {
  final nav = Navigator.of(context, rootNavigator: true);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar',
    barrierColor: const Color(0xCC000000),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (c, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child),
    ),
    pageBuilder: (ctx, _, __) {
      final mq = MediaQuery.of(ctx);
      return Stack(children: [
        Positioned(
          left: 12,
          right: 12,
          bottom: mq.padding.bottom + 78,
          child: Material(
            color: const Color(0xFF282828),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _opt(Icons.music_note, 'Playlist',
                    'Crie uma playlist com músicas', () {
                  Navigator.of(ctx).pop();
                  nav.push(MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => const CreatePlaylistPage()));
                }),
              ]),
            ),
          ),
        ),
        Positioned(
          right: mq.size.width * 0.125 - 24,
          bottom: mq.padding.bottom + 14,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(ctx).pop(),
              child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.close, color: Colors.black, size: 28)),
            ),
          ),
        ),
      ]);
    },
  );
}

Widget _opt(IconData i, String t, String sub, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
                color: Color(0xFF3E3E3E), shape: BoxShape.circle),
            child: Icon(i, color: Colors.white70),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ]),
          ),
        ]),
      ),
    );

class CreatePlaylistPage extends StatefulWidget {
  const CreatePlaylistPage({super.key});
  @override
  State<CreatePlaylistPage> createState() => _CreatePlaylistPageState();
}

class _CreatePlaylistPageState extends State<CreatePlaylistPage> {
  TextEditingController? _c;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final n = AppScope.of(context).playlists.playlists.length + 1;
    _c = TextEditingController(text: 'Minha playlist #$n');
    _c!.selection = TextSelection(baseOffset: 0, extentOffset: _c!.text.length);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _c!.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    final err = await AppScope.of(context).playlists.create(name, const []);
    if (!mounted) return;
    if (err != null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF4A4A4A), Color(0xFF121212)],
                stops: [0, 0.55])),
        child: SafeArea(
          child: Column(children: [
            const Spacer(flex: 3),
            const Text('Dê um nome à sua playlist',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: TextField(
                controller: _c,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  filled: false,
                  border: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                ),
                onSubmitted: (_) => _create(),
              ),
            ),
            const SizedBox(height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF8A8A8A)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: const StadiumBorder()),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: const StadiumBorder()),
                onPressed: _busy ? null : _create,
                child: const Text('Criar',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
            const Spacer(flex: 5),
          ]),
        ),
      ),
    );
  }
}
