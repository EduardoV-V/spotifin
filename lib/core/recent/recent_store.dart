import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentItem {
  final String kind; // playlist | album | artist
  final String id;
  final String name;
  final String sub;
  const RecentItem(this.kind, this.id, this.name, [this.sub = '']);

  Map<String, dynamic> toJson() =>
      {'k': kind, 'i': id, 'n': name, 's': sub};
  factory RecentItem.fromJson(Map<String, dynamic> j) => RecentItem(
      j['k'] as String, j['i'] as String, j['n'] as String,
      (j['s'] as String?) ?? '');
}

/// Playlists, álbuns e artistas tocados por último (só neste aparelho).
class RecentStore extends ChangeNotifier {
  RecentStore._() {
    _load();
  }
  static final instance = RecentStore._();

  List<RecentItem> items = [];

  Future<void> _load() async {
    try {
      final raw =
          (await SharedPreferences.getInstance()).getString('recent_ctx');
      if (raw != null) {
        items = (jsonDecode(raw) as List)
            .map((e) => RecentItem.fromJson(e as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  void add(String kind, String id, String name, [String sub = '']) {
    items.removeWhere((e) => e.kind == kind && e.id == id);
    items.insert(0, RecentItem(kind, id, name, sub));
    if (items.length > 30) items = items.sublist(0, 30);
    notifyListeners();
    SharedPreferences.getInstance().then((sp) =>
        sp.setString('recent_ctx', jsonEncode(items.map((e) => e.toJson()).toList())));
  }
}
