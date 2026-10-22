import 'dart:io';

import 'package:flutter/material.dart';

import '../core/cache/image_store.dart';

/// Como Image.network, mas guarda a imagem em disco (funciona offline depois
/// da primeira vez). [fallbacks]: outras URLs da mesma imagem (outro tamanho)
/// usadas enquanto a principal não está no cache (ou se estiver offline).
class NetImage extends StatefulWidget {
  final String url;
  final List<String> fallbacks;
  final Map<String, String>? headers;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  const NetImage(this.url,
      {super.key,
      this.fallbacks = const [],
      this.headers,
      this.fit,
      this.width,
      this.height,
      this.alignment = Alignment.center,
      this.errorBuilder});
  @override
  State<NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<NetImage> {
  File? _file;
  bool _exact = false;
  bool _net = false; // cache falhou/demorou: carrega direto da rede

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _start();
  }

  void _start() {
    _net = false;
    final e = ImageStore.peek(widget.url);
    _exact = e != null;
    _file = e;
    if (e == null) {
      for (final u in widget.fallbacks) {
        final f = ImageStore.peek(u);
        if (f != null) {
          _file = f;
          break;
        }
      }
    }
    _resolve();
  }

  Future<void> _resolve() async {
    final url = widget.url;
    File? f;
    try {
      f = await ImageStore.get(url, headers: widget.headers)
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (!mounted || url != widget.url) return;
    if (f != null) {
      if (f.path == _file?.path && _exact) return;
      setState(() {
        _file = f;
        _exact = true;
      });
    } else if (_file == null) {
      setState(() => _net = true);
    }
  }

  Widget _err(BuildContext c, [Object e = 'erro']) =>
      widget.errorBuilder?.call(c, e, null) ?? const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null && _net) {
      return Image.network(widget.url,
          headers: widget.headers,
          width: widget.width,
          height: widget.height,
          alignment: widget.alignment,
          fit: widget.fit,
          errorBuilder: (c, e, s) => _err(c, e));
    }
    if (f == null) return SizedBox(width: widget.width, height: widget.height);
    return Image.file(f,
        key: ValueKey(f.path),
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        gaplessPlayback: true,
        fit: widget.fit, errorBuilder: (c, e, s) {
      ImageStore.evict(widget.url);
      return _err(c, e);
    });
  }
}
