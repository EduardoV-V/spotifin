import 'dart:io';

import 'package:flutter/material.dart';

import '../core/cache/image_store.dart';

/// Como Image.network, mas guarda a imagem em disco (funciona offline depois
/// da primeira vez).
class NetImage extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  const NetImage(this.url,
      {super.key,
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
  bool _failed = false;
  bool _net = false; // cache falhou/demorou: carrega direto da rede

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _file = null;
      _failed = false;
      _net = false;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final url = widget.url;
    File? f;
    try {
      f = await ImageStore.get(url, headers: widget.headers)
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
    if (!mounted || url != widget.url) return;
    setState(() {
      _file = f;
      _net = f == null;
    });
  }

  Widget _err(BuildContext c, [Object e = 'erro']) =>
      widget.errorBuilder?.call(c, e, null) ?? const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    if (_failed) return _err(context);
    if (_net) {
      return Image.network(widget.url,
          headers: widget.headers,
          width: widget.width,
          height: widget.height,
          alignment: widget.alignment,
          fit: widget.fit,
          errorBuilder: (c, e, s) => _err(c, e));
    }
    final f = _file;
    if (f == null) return SizedBox(width: widget.width, height: widget.height);
    return Image.file(f,
        key: ValueKey(f.path),
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        fit: widget.fit, errorBuilder: (c, e, s) {
      ImageStore.evict(widget.url);
      return _err(c, e);
    });
  }
}
