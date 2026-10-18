import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/downloads/auto_download.dart';
import 'app_scope.dart';
import 'desktop_shell.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
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
  }

  static const _pages = [HomePage(), SearchPage(), LibraryPage()];
  static const _items = [
    (Icons.home_outlined, Icons.home, 'Início'),
    (Icons.search, Icons.search, 'Buscar'),
    (Icons.library_music_outlined, Icons.library_music, 'Sua Biblioteca'),
  ];

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(index: _index, children: _pages);
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
      if (c.maxWidth >= 800) {
        return const DesktopShell();
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final it in _items)
                NavigationDestination(
                    icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: it.$3),
            ],
          ),
        ]),
      );
        }),
      ),
    );
  }
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
