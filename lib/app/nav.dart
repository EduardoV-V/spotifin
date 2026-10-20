import 'package:flutter/material.dart';

/// Navigator interno do app no celular (fica sob o mini player e a barra inferior).
final GlobalKey<NavigatorState> shellNav = GlobalKey<NavigatorState>();

/// Abre [route] dentro do app (no celular fecha o player em tela cheia, se aberto).
void pushShell(BuildContext context, Route<dynamic> route) {
  final shell = shellNav.currentState;
  if (shell != null) {
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    shell.push(route);
  } else {
    Navigator.of(context).push(route);
  }
}
