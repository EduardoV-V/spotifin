import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../lib/core/jellyfin/models.dart';

void main() {
  test('Track serializa e restaura (fila persistida)', () {
    final t = Track.fromJson({
      'Id': 't1',
      'AlbumId': 'alb1',
      'Name': 'Faixa',
      'Artists': ['Artista'],
      'Album': 'Álbum',
      'RunTimeTicks': 2400000000,
      'MediaSources': [
        {
          'Container': 'flac',
          'Size': 1000,
          'MediaStreams': [
            {'Type': 'Audio', 'Codec': 'flac', 'SampleRate': 96000, 'BitDepth': 24, 'BitRate': 2800000}
          ]
        }
      ]
    });
    final r = Track.fromStored(
        jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);
    expect(r.id, 't1');
    expect(r.albumId, 'alb1');
    expect(r.duration, t.duration);
    expect(r.file.label, t.file.label);
  });
}
