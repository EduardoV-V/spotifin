import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/downloads/download_service.dart';
import '../lib/core/jellyfin/jellyfin_client.dart';
import '../lib/core/jellyfin/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('download retoma de onde parou e valida o tamanho', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = await Directory.systemTemp.createTemp('dl_test');
    final bytes = List<int>.generate(10, (i) => i);
    final mock = MockClient((req) async {
      if (req.headers['Range'] == 'bytes=3-') {
        return http.Response.bytes(bytes.sublist(3), 206,
            headers: {'content-range': 'bytes 3-9/10'});
      }
      return http.Response.bytes(bytes, 200);
    });
    final client = JellyfinClient(httpClient: mock)
      ..session = const JellyfinSession(
          serverUrl: 'http://s', userId: 'u', token: 't', deviceId: 'd');
    final svc = DownloadService(client, baseDir: tmp);
    await svc.init();

    const track = Track(
      id: 't1',
      title: 'T',
      artist: 'A',
      album: 'B',
      duration: null,
      file: AudioFileInfo(container: 'flac', sizeBytes: 10),
    );
    final partial = File('${svc.directoryPath}${Platform.pathSeparator}t1.flac.part');
    await partial.create(recursive: true);
    await partial.writeAsBytes(bytes.sublist(0, 3));

    svc.enqueue([track]);
    for (var i = 0; i < 300; i++) {
      if (svc.itemFor('t1')!.state == DownloadState.completed) break;
      await Future.delayed(const Duration(milliseconds: 10));
    }

    expect(svc.itemFor('t1')!.state, DownloadState.completed);
    expect(await File(svc.localPath('t1')!).readAsBytes(), bytes);
    await tmp.delete(recursive: true);
  });
}
