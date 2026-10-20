import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF121212);
  static const sidebar = Color(0xFF000000);
  static const elevated = Color(0xFF282828);
  static const accent = Color(0xFF1DB954);
  static const textSecondary = Color(0xFFB3B3B3);
}

ThemeData buildTheme() {
  final base = ThemeData(
      brightness: Brightness.dark, useMaterial3: true, fontFamily: 'Spotifin');
  return base.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: _FadeSlide(),
      TargetPlatform.windows: _FadeSlide(),
      TargetPlatform.linux: _FadeSlide(),
      TargetPlatform.iOS: _FadeSlide(),
    }),
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Colors.black,
      secondary: AppColors.accent,
      surface: AppColors.background,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.black,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 11,
          color: s.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.textSecondary)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.textSecondary)),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
      activeTrackColor: Colors.white,
      inactiveTrackColor: Color(0xFF4D4D4D),
      thumbColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.elevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class _FadeSlide extends PageTransitionsBuilder {
  const _FadeSlide();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondary, Widget child) {
    if (route.fullscreenDialog) {
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      );
    }
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0.04, 0), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}

/// Espaço no fim de listas (no celular inclui o mini player + barra inferior).
double bottomReserve(BuildContext c) => MediaQuery.paddingOf(c).bottom + 24;
