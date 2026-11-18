import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:PiliPlus/services/live_timeshift_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假 CDN：模拟 B 站直播 fmp4 的滑动窗口播放列表与分片。
class _FakeCdn {
  _FakeCdn({required this.liveSeq});

  int liveSeq;
  int segmentHits = 0;
  final List<String> timeshiftParams = [];
  HttpServer? _server;

  String get base => 'http://127.0.0.1:${_server!.port}';

  String get playlistUrl =>
      '$base/live-bvc/1/live_7734200_2500/index.m3u8?expires=1&qn=250';

  String segmentUrl(int seq) =>
      '$base/live-bvc/1/live_7734200_2500/$seq.m4s?expires=1&qn=250';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      final response = request.response;
      final path = request.uri.path;
      if (path.endsWith('index.m3u8')) {
        final buffer = StringBuffer()
          ..writeln('#EXTM3U')
          ..writeln('#EXT-X-VERSION:7')
          ..writeln('#EXT-X-MEDIA-SEQUENCE:${liveSeq - 6}')
          ..writeln('#EXT-X-TARGETDURATION:1')
          ..writeln('#EXT-X-MAP:URI="init.m4s"');
        for (var seq = liveSeq - 6; seq <= liveSeq; seq++) {
          buffer
            ..writeln('#EXTINF:1.000,')
            ..writeln('$seq.m4s');
        }
        response.write(buffer.toString());
      } else if (path.endsWith('init.m4s')) {
        response.add(Uint8List.fromList(List.filled(64, 9)));
      } else {
        final name = path.substring(path.lastIndexOf('/') + 1);
        final seq = int.tryParse(name.replaceAll('.m4s', ''));
        segmentHits++;
        timeshiftParams.add(request.uri.queryParameters['tmshift'] ?? '');
        if (seq == null || seq > liveSeq || seq < liveSeq - 4000) {
          response.statusCode = HttpStatus.notFound;
        } else {
          final body = Uint8List(2048)..fillRange(0, 2048, seq % 200);
          body.setRange(4, 8, 'moof'.codeUnits);
          response.add(body);
        }
      }
      await response.close();
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}

void main() {
  group('LiveTimeshiftSource', () {
    test('解析 host/basePath/query 并拼出分片地址', () {
      final source = LiveTimeshiftSource(
        'https://d1--cn-gotcha209.bilivideo.com/live-bvc/887379/'
        'live_7734200_bs_1348183_minihevc/index.m3u8?expires=1&qn=250',
      );
      expect(source.host, 'https://d1--cn-gotcha209.bilivideo.com');
      expect(
        source.basePath,
        '/live-bvc/887379/live_7734200_bs_1348183_minihevc',
      );
      expect(source.query, 'expires=1&qn=250');
      expect(
        source.segmentUrl(527721338),
        'https://d1--cn-gotcha209.bilivideo.com/live-bvc/887379/'
        'live_7734200_bs_1348183_minihevc/527721338.m4s?expires=1&qn=250',
      );
      expect(
        source.segmentUrl(527721338, timeshift: 60),
        endsWith('527721338.m4s?expires=1&qn=250&tmshift=60'),
      );
      expect(
        source.fileUrl('index.m3u8'),
        endsWith('index.m3u8?expires=1&qn=250'),
      );
    });
  });

  group('LiveTimeshiftServer', () {
    late _FakeCdn cdn;
    late LiveTimeshiftServer server;
    late int roomId;

    setUp(() async {
      // 每个用例用独立房间号，避免共享本地缓存目录
      roomId = 8000000 + Random().nextInt(1000000);
      cdn = _FakeCdn(liveSeq: 527721338);
      await cdn.start();
      server = LiveTimeshiftServer(
        roomId: roomId,
        urls: [cdn.playlistUrl],
        windowSeconds: 60,
      );
      expect(await server.start(), isTrue);
    });

    tearDown(() async {
      await server.dispose();
      await cdn.stop();
      final base = Directory('\${Directory.systemTemp.path}/live_dvr');
      if (base.existsSync()) {
        for (final entry in base.listSync()) {
          if (entry.path.split('/').last.startsWith('\$roomId_')) {
            entry.deleteSync(recursive: true);
          }
        }
      }
    });

    Future<(int, List<int>)> get(String url) async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
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

    test('用 refetch 的 MEDIA-SEQUENCE 校准直播 seq', () {
      expect(server.liveSeq, 527721338);
      expect(server.isReady, isTrue);
    });

    test('播放列表只有直播边缘附近的短窗口', () async {
      final (status, bytes) = await get(server.playlistUrl);
      expect(status, 200);
      final lines = String.fromCharCodes(bytes).split(String.fromCharCode(10));
      expect(lines.first, '#EXTM3U');
      expect(lines.contains('#EXT-X-PLAYLIST-TYPE:EVENT'), isTrue);
      final mediaSeq = lines.firstWhere(
        (l) => l.startsWith('#EXT-X-MEDIA-SEQUENCE:'),
      );
      final start = int.parse(mediaSeq.split(':').last);
      expect(start, lessThan(server.liveSeq));
      // 窗口内每个 seq 都要出现在列表里
      // 最新 1~5 个分片可能还没在 CDN 写完，播放列表止于安全边缘
      expect(start, server.liveSeq - 6);
      final segments = lines.where((line) => line.endsWith('.m4s')).toList();
      expect(segments.length, 6);
      expect(lines.contains('${server.liveSeq - 1}.m4s'), isTrue);
      expect(lines.contains('${server.liveSeq}.m4s'), isFalse);
    });

    test('窗口内分片可获取，且带上 tmshift 偏移', () async {
      final target = server.liveSeq - 3;
      final (status, bytes) = await get(
        'http://127.0.0.1:${Uri.parse(server.playlistUrl).port}/$target.m4s',
      );
      expect(status, 200);
      expect(bytes.length, 2048);
      expect(cdn.timeshiftParams.last, '3');
    });

    test('超过直播进度的分片返回 404', () async {
      final (status, _) = await get(
        'http://127.0.0.1:${Uri.parse(server.playlistUrl).port}/'
        '${server.liveSeq + 10}.m4s',
      );
      expect(status, HttpStatus.notFound);
    });

    test('第二次请求命中本地缓存，不再回源', () async {
      final port = Uri.parse(server.playlistUrl).port;
      final target = server.liveSeq - 3;
      final url = 'http://127.0.0.1:$port/$target.m4s';
      final (s1, b1) = await get(url);
      expect(s1, 200);
      final hitsAfterFirst = cdn.segmentHits;
      final (s2, b2) = await get(url);
      expect(s2, 200);
      expect(b2.length, b1.length);
      expect(cdn.segmentHits, hitsAfterFirst);
      expect(server.cache?.range?.newest, target);
    });

    test('直播推进后窗口滑动且长度恒定', () async {
      final before = server.playlistStartSeq;
      cdn.liveSeq += 3;
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      expect(server.liveSeq, cdn.liveSeq);
      expect(server.seekWindowSeconds, greaterThanOrEqualTo(60));
      expect(server.playlistStartSeq, before + 3);
    });

    test('窗口偏移后列表与分片都回退到指定时间', () async {
      server.baseOffset = 120;
      final (status, bytes) = await get(server.playlistUrl);
      expect(status, 200);
      final lines = String.fromCharCodes(bytes).split(String.fromCharCode(10));
      final mediaSeq = lines.firstWhere(
        (line) => line.startsWith('#EXT-X-MEDIA-SEQUENCE:'),
      );
      expect(int.parse(mediaSeq.split(':').last), server.liveSeq - 126);
      final target = server.liveSeq - 123;
      final port = Uri.parse(server.playlistUrl).port;
      final (s2, _) = await get('http://127.0.0.1:$port/$target.m4s');
      expect(s2, 200);
      expect(cdn.timeshiftParams.last, '123');
    });

    test('换流后 seq 跳变则重建窗口', () async {
      final before = server.playlistStartSeq;
      cdn.liveSeq += 500;
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      expect(server.liveSeq, cdn.liveSeq);
      expect(server.playlistStartSeq, isNot(before));
      expect(server.seekWindowSeconds, greaterThanOrEqualTo(60));
    });
  });
}
