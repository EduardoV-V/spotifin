import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Roda do mouse com um leve amortecimento (em vez de "pular").
class _SmoothPosition extends ScrollPositionWithSingleContext {
  _SmoothPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  double? _target;
  DateTime _last = DateTime(0);

  @override
  void pointerScroll(double delta) {
    if (delta == 0) {
      goBallistic(0);
      return;
    }
    final now = DateTime.now();
    final base =
        (_target != null && now.difference(_last).inMilliseconds < 220)
            ? _target!
            : pixels;
    final t = (base + delta)
        .clamp(minScrollExtent, maxScrollExtent < minScrollExtent ? minScrollExtent : maxScrollExtent)
        .toDouble();
    _target = t;
    _last = now;
    if ((t - pixels).abs() < 0.5) return;
    animateTo(t,
        duration: const Duration(milliseconds: 170), curve: Curves.easeOutCubic);
  }
}

class SmoothScrollController extends ScrollController {
  SmoothScrollController({super.initialScrollOffset, super.keepScrollOffset});

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      _SmoothPosition(
        physics: physics,
        context: context,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        oldPosition: oldPosition,
        debugLabel: debugLabel,
      );
}

/// ListView com rolagem suave (mesma API reduzida).
class SmoothListView extends StatefulWidget {
  final List<Widget>? children;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final EdgeInsetsGeometry? padding;
  const SmoothListView({super.key, required List<Widget> this.children, this.padding})
      : itemCount = null,
        itemBuilder = null;
  const SmoothListView.builder(
      {super.key, required this.itemCount, required this.itemBuilder, this.padding})
      : children = null;
  @override
  State<SmoothListView> createState() => _SmoothListViewState();
}

class _SmoothListViewState extends State<SmoothListView> {
  final _c = SmoothScrollController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.children != null
      ? ListView(controller: _c, padding: widget.padding, children: widget.children!)
      : ListView.builder(
          controller: _c,
          padding: widget.padding,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder!);
}
