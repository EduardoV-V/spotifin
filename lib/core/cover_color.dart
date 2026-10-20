import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app/app_scope.dart';

/// Cor dominante (escurecida) da capa de um item — usada em degradês
/// de playlist/artista e no mini player, como no Spotify.
class CoverColor {
  static final _cache = <String, Color>{};

  static Future<Color?> of(AppScope scope, String itemId) async {
    final c = _cache[itemId];
    if (c != null) return c;
    try {
      final client = scope.client;
      final res = await http
          .get(client.imageUri(itemId, maxWidth: 48),
              headers: client.authHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final codec = await ui.instantiateImageCodec(res.bodyBytes,
          targetWidth: 16, targetHeight: 16);
      final img = (await codec.getNextFrame()).image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return null;
      double r = 0, g = 0, b = 0, w = 0;
      for (var i = 0; i + 3 < bd.lengthInBytes; i += 4) {
        final pr = bd.getUint8(i), pg = bd.getUint8(i + 1), pb = bd.getUint8(i + 2);
        final mx = [pr, pg, pb].reduce((a, b) => a > b ? a : b);
        final mn = [pr, pg, pb].reduce((a, b) => a < b ? a : b);
        final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
        final wt = 0.1 + sat * sat * 3 + (mx > 40 && mx < 235 ? 0.3 : 0);
        r += pr * wt;
        g += pg * wt;
        b += pb * wt;
        w += wt;
      }
      if (w == 0) return null;
      final avg = Color.fromARGB(255, (r / w).round(), (g / w).round(), (b / w).round());
      final hsl = HSLColor.fromColor(avg);
      final out = hsl
          .withLightness(0.32)
          .withSaturation(hsl.saturation.clamp(0.0, 0.65).toDouble())
          .toColor();
      return _cache[itemId] = out;
    } catch (_) {
      return null;
    }
  }
}

/// Entrega a cor (com transição suave) para [builder].
class CoverTint extends StatefulWidget {
  final String? itemId;
  final Color fallback;
  final Widget Function(BuildContext, Color) builder;
  const CoverTint(
      {super.key,
      required this.itemId,
      required this.builder,
      this.fallback = const Color(0xFF3A3A3A)});
  @override
  State<CoverTint> createState() => _CoverTintState();
}

class _CoverTintState extends State<CoverTint> {
  Color? _color;
  String? _for;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CoverTint old) {
    super.didUpdateWidget(old);
    _resolve();
  }

  void _resolve() {
    final id = widget.itemId;
    if (id == null || id == _for) return;
    _for = id;
    CoverColor.of(AppScope.of(context), id).then((c) {
      if (mounted && _for == id && c != null) setState(() => _color = c);
    });
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: _color ?? widget.fallback),
        duration: const Duration(milliseconds: 450),
        builder: (c, v, _) => widget.builder(c, v ?? widget.fallback),
      );
}
