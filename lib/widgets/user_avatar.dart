import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/app_scope.dart';

/// Foto de perfil do usuário no Jellyfin; sem foto, mostra a inicial.
class UserAvatar extends StatefulWidget {
  final double radius;
  const UserAvatar({super.key, this.radius = 18});
  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Uint8List? _bytes;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    AppScope.of(context).client.userAvatar().then((b) {
      if (mounted && b != null) setState(() => _bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).client.session?.username ?? '';
    final b = _bytes;
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: const Color(0xFF6A4FC4),
      backgroundImage: b == null ? null : MemoryImage(b),
      child: b != null
          ? null
          : Text(user.isEmpty ? '?' : user[0].toUpperCase(),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}
