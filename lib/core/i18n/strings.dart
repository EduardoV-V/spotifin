import 'dart:ui';

/// Textos traduzíveis. Para adicionar um idioma, crie um novo mapa em [_m].
class S {
  static String lang = 'pt';

  static void setFromLocale(Locale l) {
    lang = _m.containsKey(l.languageCode) ? l.languageCode : 'pt';
  }

  static String t(String key, [Map<String, Object>? args]) {
    var s = _m[lang]?[key] ?? _m['pt']![key] ?? key;
    args?.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  static const _m = <String, Map<String, String>>{
    'pt': {
      'search_hint': 'O que você quer ouvir?',
      'search_for': 'Buscar por "{q}"',
      'navigate': 'Navegar',
      'search': 'Buscar',
      'artist': 'Artista',
      'song': 'Música',
      'album': 'Álbum',
      'albums': 'Álbuns',
      'artists': 'Artistas',
      'playlists': 'Playlists',
      'all': 'Tudo',
      'songs': 'Músicas',
      'popular': 'Populares',
      'see_more': 'Ver mais',
      'see_less': 'Ver menos',
      'follow': 'Seguir',
      'following': 'Seguindo',
      'about': 'Sobre',
      'discography': 'Discografia',
      'fans': '{n} fãs',
      'in_library': '{n} músicas na biblioteca',
      'top_result': 'Melhor resultado',
      'nothing_found': 'Nada encontrado',
      'your_library': 'Sua Biblioteca',
      'create': 'Criar',
      'liked': 'Músicas curtidas',
      'recents': 'Recentes',
    },
    'en': {
      'search_hint': 'What do you want to play?',
      'search_for': 'Search for "{q}"',
      'navigate': 'Navigate',
      'search': 'Search',
      'artist': 'Artist',
      'song': 'Song',
      'album': 'Album',
      'albums': 'Albums',
      'artists': 'Artists',
      'playlists': 'Playlists',
      'all': 'All',
      'songs': 'Songs',
      'popular': 'Popular',
      'see_more': 'See more',
      'see_less': 'See less',
      'follow': 'Follow',
      'following': 'Following',
      'about': 'About',
      'discography': 'Discography',
      'fans': '{n} fans',
      'in_library': '{n} songs in library',
      'top_result': 'Top result',
      'nothing_found': 'Nothing found',
      'your_library': 'Your Library',
      'create': 'Create',
      'liked': 'Liked Songs',
      'recents': 'Recents',
    },
  };
}
