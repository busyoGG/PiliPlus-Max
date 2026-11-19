import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:PiliPlus/services/live_timeshift_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// 普通直播间的 CDN：只保留直播边缘，任何 tmshift 回看都 404。
class _FakeCdn {
  _FakeCdn(this.liveSeq);

  int liveSeq;
  int segmentHits = 0;
  final List<String> timeshiftParams = <String>[];
  late final HttpServer server;

  static const String playlistPath = '/live-bvc/1/live_5050_2500/index.m3u8';

  Uri get playlistUri => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: server.port,
    path: playlistPath,
    query: 'expires=1&sign=1',
  );

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final back =
        int.tryParse(request.uri.queryParameters['tmshift'] ?? '') ?? 0;
    timeshiftParams.add('$back');
    if (back > 0) {
      // 没有历史可回看
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    if (request.uri.path.endsWith('index.m3u8')) {
      final start = liveSeq - 6;
      final buffer = StringBuffer()
        ..writeln('#EXTM3U')
        ..writeln('#EXT-X-VERSION:7')
        ..writeln('#EXT-X-TARGETDURATION:1')
        ..writeln('#EXT-X-MEDIA-SEQUENCE:$start')
        ..writeln('#EXT-X-MAP:URI="init.m4s"');
      for (var seq = start; seq <= liveSeq; seq++) {
        buffer
          ..writeln('#EXTINF:1.000,')
          ..writeln('$seq.m4s');
      }
      response
        ..headers.contentType = ContentType('application', 'mpegurl')
        ..add(buffer.toString().codeUnits);
      await response.close();
      return;
    }
    final name = request.uri.path.split('/').last;
    if (name == 'init.m4s') {
      final init = Uint8List(64)..setRange(4, 8, 'ftyp'.codeUnits);
      response.add(init);
      await response.close();
      return;
    }
    final seq = int.tryParse(name.split('.').first) ?? -1;
    if (seq < liveSeq - 6 || seq > liveSeq) {
      // 边缘之外的分片已经删掉了
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    segmentHits++;
    final body = Uint8List(2048)..setRange(4, 8, 'moof'.codeUnits);
    response.add(body);
    await response.close();
  }
}

Uri _segUri(int port, int seq) => Uri(
  scheme: 'http',
  host: '127.0.0.1',
  port: port,
  path: '/$seq.m4s',
);

void main() {
  group('本地缓存回看（服务端无历史）', () {
    late _FakeCdn cdn;
    late LiveTimeshiftServer server;
    late int roomId;

    setUp(() async {
      cdn = _FakeCdn(527721338);
      await cdn.start();
      roomId = 8100000 + Random().nextInt(1000000);
      server = LiveTimeshiftServer(
        roomId: roomId,
        urls: <String>[cdn.playlistUri.toString()],
      );
      await server.start();
    });

    tearDown(() async {
      await server.dispose();
      await cdn.close();
      final base = Directory(
        Directory.systemTemp.uri.resolve('live_dvr').toFilePath(),
      );
      if (base.existsSync()) {
        for (final entry in base.listSync()) {
          if (entry.path.contains(roomId.toString())) {
            entry.deleteSync(recursive: true);
          }
        }
      }
    });

    Future<(int, List<int>)> get(Uri uri) async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        return (response.statusCode, bytes);
      } finally {
        client.close(force: true);
      }
    }

    test('服务端没有历史时不声称能回看一小时', () async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.isReady, isTrue);
      expect(server.liveSeq, cdn.liveSeq);
      expect(server.seekWindowSeconds, lessThan(60));
      expect(server.cacheSpanSeconds, 0);
      // 确实尝试过 tmshift 回看，只是 CDN 不认
      expect(cdn.timeshiftParams.where((p) => p != '0'), isNotEmpty);
    });

    test('播过的分片落本地缓存，拖回去仍可取到', () async {
      final port = Uri.parse(server.playlistUrl).port;
      for (var back = 1; back <= 4; back++) {
        final target = server.liveSeq - back;
        final (status, _) = await get(_segUri(port, target));
        expect(status, 200);
      }
      expect(server.cacheSpanSeconds, 4);
      expect(server.seekWindowSeconds, 4);
      final hits = cdn.segmentHits;
      final cached = server.liveSeq - 4;
      final (status, bytes) = await get(_segUri(port, cached));
      expect(status, 200);
      expect(bytes.length, 2048);
      // 命中本地缓存，不再回源
      expect(cdn.segmentHits, hits);
    });

    test('缓存之外的分片直接 404，不会疯狂回源', () async {
      final port = Uri.parse(server.playlistUrl).port;
      final hits = cdn.segmentHits;
      final stale = server.liveSeq - 300;
      final (status, _) = await get(_segUri(port, stale));
      expect(status, HttpStatus.notFound);
      expect(cdn.segmentHits, hits);
    });

    test('回看深度不超过本地缓存上限', () {
      expect(server.seekWindowSeconds, lessThanOrEqualTo(server.maxDvrSeconds));
    });
  });
}
