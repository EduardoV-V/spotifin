import '../core/artists/artist_info_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/downloads/auto_download.dart';
import 'app_scope.dart';
import 'nav.dart';
import 'desktop_shell.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../features/create/create_sheet.dart';
import '../widgets/mini_player.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _adInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_adInit) return;
    _adInit = true;
    AutoDownload.instance.start(AppScope.of(context));
    _warmUp(AppScope.of(context));
  }

  /// Em segundo plano, baixa aos poucos fotos/dados dos artistas da biblioteca
  /// (150 por abertura) para que já estejam prontos na busca e offline.
  Future<void> _warmUp(AppScope scope) async {
    await Future.delayed(const Duration(seconds: 6));
    try {
      final l = await scope.client.libraryArtists();
      if (l.isEmpty) return;
      final sp = await SharedPreferences.getInstance();
      final key = 'warm_idx_${scope.client.session?.userId}';
      var i = (sp.getInt(key) ?? 0) % l.length;
      for (var n = 0; n < 150 && n < l.length; n++) {
        if (!mounted) return;
        ArtistInfoService.instance.prefetch([l[(i + n) % l.length].name]);
        if (n % 3 == 2) await Future.delayed(const Duration(milliseconds: 800));
      }
      await sp.setInt(key, (i + 150) % l.length);
    } catch (_) {}
  }

  static const _items = [
    (Icons.home_outlined, Icons.home, 'Início'),
    (Icons.search, Icons.search, 'Buscar'),
    (Icons.library_music_outlined, Icons.library_music, 'Sua Biblioteca'),
  ];

  final _nav = shellNav;
  final _tab = ValueNotifier<int>(0);

  void _select(int i) {
    _nav.currentState?.popUntil((r) => r.isFirst);
    _tab.value = i;
    setState(() => _index = i);
  }

  Widget _mobile(BuildContext context) {
    final mq = MediaQuery.of(context);
    const reserve = 150.0; // mini player + barra inferior
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        final n = _nav.currentState;
        if (n != null && n.canPop()) {
          n.pop();
        } else if (_index != 0) {
          _select(0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: MediaQuery(
              data: mq.copyWith(
                  viewInsets: mq.viewInsets.copyWith(bottom: 0),
                  padding: mq.padding
                      .copyWith(bottom: mq.padding.bottom + reserve)),
              child: KeyboardInset(
                value: mq.viewInsets.bottom,
                child: Theme(
                data: theme.copyWith(
                    snackBarTheme: SnackBarThemeData(
                        behavior: SnackBarBehavior.floating,
                        insetPadding: EdgeInsets.fromLTRB(
                            12, 0, 12, reserve + mq.padding.bottom))),
                child: Navigator(
                  key: _nav,
                  onGenerateRoute: (_) => MaterialPageRoute(
                    builder: (_) => ValueListenableBuilder<int>(
                      valueListenable: _tab,
                      builder: (_, i, __) => IndexedStack(
                          index: i,
                          children: const [
                            HomePage(),
                            SearchPage(),
                            LibraryPage()
                          ]),
                    ),
                  ),
                ),
              )),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0xB3000000),
                      Color(0xF2000000)
                    ],
                    stops: [0, 0.35, 0.7]),
              ),
              padding: const EdgeInsets.only(top: 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListenableBuilder(
                  listenable: AppScope.of(context).conn,
                  builder: (context, _) => AppScope.of(context).conn.offline
                      ? Container(
                          width: double.infinity,
                          color: const Color(0xFF282828),
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: const Text('Offline • só músicas baixadas',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.white70)))
                      : const SizedBox.shrink(),
                ),
                const MiniPlayer(),
                _NavBar(
                    index: _index,
                    onSelect: _select,
                    onCreate: () => showCreateSheet(context)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
            player.togglePlay(),
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () =>
            player.next(),
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () =>
            player.previous(),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 800) return const DesktopShell();
          return _mobile(context);
        }),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;
  const _NavBar(
      {required this.index, required this.onSelect, required this.onCreate});

  Widget _it(IconData i, IconData sel, String l, bool on, VoidCallback t) =>
      Expanded(
        child: InkWell(
          onTap: t,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedScale(
                  scale: on ? 1.08 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(on ? sel : i,
                      size: 26,
                      color: on ? Colors.white : AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(l,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? Colors.white : AppColors.textSecondary)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Row(children: [
          for (var i = 0; i < _AppShellState._items.length; i++)
            _it(_AppShellState._items[i].$1, _AppShellState._items[i].$2,
                _AppShellState._items[i].$3, index == i, () => onSelect(i)),
          _it(Icons.add, Icons.add, 'Criar', false, onCreate),
        ]),
      );
}

class _Sidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Text('Spotifin',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ),
        for (var i = 0; i < _AppShellState._items.length; i++)
          _SidebarItem(
            icon: index == i
                ? _AppShellState._items[i].$2
                : _AppShellState._items[i].$1,
            label: _AppShellState._items[i].$3,
            selected: index == i,
            onTap: () => onSelect(i),
          ),
        const Spacer(),
        _SidebarItem(
          icon: Icons.settings_outlined,
          label: 'Configurações',
          selected: false,
          onTap: () => openSettings(context),
        ),
      ]),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SidebarItem(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.textSecondary;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
  }
}
