import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/services/live_dvr_cache.dart';
import 'package:flutter/foundation.dart' show debugPrint;

const int _lf = 10;

/// 一个可回源的候选（host + 流路径 + 原始查询串）。
///
/// 深历史分片只存在部分 (host, path) 组合上，所以需要保留多个候选轮询。
class LiveTimeshiftSource {
  LiveTimeshiftSource(this.url) {
    final schemeEnd = url.indexOf('://');
    final hostStart = schemeEnd < 0 ? 0 : schemeEnd + 3;
    final pathStart = url.indexOf('/', hostStart);
    if (pathStart < 0) {
      host = url;
      basePath = '';
      query = '';
      return;
    }
    host = url.substring(0, pathStart);
    final queryStart = url.indexOf('?', pathStart);
    final pathEnd = queryStart < 0 ? url.length : queryStart;
    var fullPath = url.substring(pathStart, pathEnd);
    if (fullPath.endsWith('/')) {
      fullPath = fullPath.substring(0, fullPath.length - 1);
    }
    const playlistSuffix = '/index.m3u8';
    if (fullPath.endsWith(playlistSuffix)) {
      fullPath = fullPath.substring(0, fullPath.length - playlistSuffix.length);
    }
    basePath = fullPath;
    query = queryStart < 0 ? '' : url.substring(queryStart + 1);
  }

  final String url;
  late final String host;
  late final String basePath;
  late final String query;

  String segmentUrl(int seq, {int? timeshift}) {
    final base = fileUrl('$seq.m4s');
    if (timeshift == null || timeshift <= 0) return base;
    return query.isEmpty
        ? '$base?tmshift=$timeshift'
        : '$base&tmshift=$timeshift';
  }

  String fileUrl(String name) {
    final base = '$host$basePath/$name';
    return query.isEmpty ? base : '$base?$query';
  }

  @override
  String toString() => '$host$basePath';
}

/// 直播时移服务器：把 B 站直播 CDN 的「过去 N 秒」窗口包装成本地 HLS，
/// 让播放器可以正常拖动进度条。
class LiveTimeshiftServer {
  LiveTimeshiftServer({
    required this.roomId,
    required List<String> urls,
    this.windowSeconds = 3600,
    this.maxSegmentAttempts = 6,
  }) : sources = urls.map(LiveTimeshiftSource.new).toList() {
    final seen = <String>{};
    sources.retainWhere((s) => seen.add(s.toString()));
  }

  final int roomId;
  final List<LiveTimeshiftSource> sources;
  final int windowSeconds;
  final int maxSegmentAttempts;

  LiveDvrCache? cache;
  HttpServer? _server;
  HttpClient? _client;
  Timer? _timer;
  final _hot = <LiveTimeshiftSource>[];
  final _sourceSeq = <LiveTimeshiftSource, int>{};
  bool _refreshing = false;
  bool _disposed = false;
  bool _startProbed = false;

  int _liveSeq = -1;
  int _playlistStartSeq = -1;
  String? _initName;
  Uint8List? _initBytes;

  int get liveSeq => _liveSeq;

  /// 播放器用的「安全直播边缘」：CDN 最新 1~2 个分片可能还没写完，
  /// 直接给播放器会让 ffmpeg 读到半截数据并判定 I/O error。
  int get _safeEdge => _liveSeq - 5;
  int get playlistStartSeq => _playlistStartSeq;

  /// 可回看的秒数（受 windowSeconds 与本地缓存上限约束）。
  int get seekWindowSeconds {
    if (_liveSeq < 0 || _playlistStartSeq < 0) return 0;
    return _liveSeq - _playlistStartSeq;
  }

  bool get isReady => _server != null && _liveSeq >= 0;

  String get playlistUrl => 'http://127.0.0.1:${_server!.port}/index.m3u8';

  /// 追加候选（补抓 playinfo 或换流时使用）。
  void addSources(List<String> urls) {
    if (_disposed) return;
    final known = sources.map((s) => s.toString()).toSet();
    for (final url in urls) {
      if (!url.contains('index.m3u8')) continue;
      final parsed = LiveTimeshiftSource(url);
      if (known.add(parsed.toString())) sources.add(parsed);
    }
  }

  Future<bool> start() async {
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 10);
    bool ready;
    try {
      ready = await _refreshOnce();
    } catch (e) {
      debugPrint('[LiveTimeshift] 初始化异常: $e');
      ready = false;
    }
    if (!ready) {
      debugPrint('[LiveTimeshift] 无法获取直播列表，放弃时移');
      await dispose();
      return false;
    }
    await _probeWindowStart();
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } catch (e) {
      debugPrint('[LiveTimeshift] bind failed: $e');
      await dispose();
      return false;
    }
    cache = LiveDvrCache(roomId: roomId, epoch: _liveSeq ~/ 1000000);
    await cache!.init();
    _server!.listen(_onRequest, onError: (Object _) {});
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshOnce());
    });
    debugPrint(
      '[LiveTimeshift] ready seq=$_liveSeq window=$seekWindowSeconds port=${_server!.port}',
    );
    return true;
  }

  // ---------------------------------------------------------------- 刷新

  Future<bool> _refreshOnce() async {
    if (_refreshing || _disposed) return _liveSeq >= 0;
    _refreshing = true;
    try {
      for (final source in _orderedSources()) {
        final text = await _getText(source.fileUrl('index.m3u8'));
        if (text == null) continue;
        final parsed = _parsePlaylist(text);
        if (parsed == null) continue;
        _markHot(source);
        final last = parsed.lastSeq;
        _sourceSeq[source] = last;
        if (_liveSeq >= 0) {
          final delta = last - _liveSeq;
          // 换流/断流后 seq 会跳变，重建窗口
          if (delta < -5 || delta > 40) {
            debugPrint('[LiveTimeshift] seq 跳变 $delta，重建窗口');
            _playlistStartSeq = -1;
          }
        }
        _liveSeq = last;
        if (parsed.initName != null && _initName != parsed.initName) {
          _initName = parsed.initName;
          _initBytes = null;
        }
        // 窗口随直播推进滑动，长度恒定（受 windowSeconds 约束）
        final minStart = last - windowSeconds;
        if (_playlistStartSeq < minStart) _playlistStartSeq = minStart;
        return true;
      }
    } finally {
      _refreshing = false;
    }
    return _liveSeq >= 0;
  }

  /// 探测窗口起点：HLS 播放器总是从播放列表第一个分片开始拉流，
  /// 所以第一个分片必须真的能取到，否则起播即卡死。
  /// 深历史分片只存在于部分 (host, path) 组合，需要逐个深度试探。
  Future<void> _probeWindowStart() async {
    if (_startProbed || _liveSeq < 0) return;
    _startProbed = true;
    final steps = <int>[windowSeconds, 1800, 900, 300, 60];
    for (final back in steps) {
      if (back > windowSeconds) continue;
      final seq = _liveSeq - back;
      if (seq < 0) continue;
      final data = await _fetchSegment(seq);
      if (data != null && data.isNotEmpty) {
        _playlistStartSeq = seq;
        debugPrint('[LiveTimeshift] 窗口起点 back=$back');
        return;
      }
    }
    _playlistStartSeq = _liveSeq - 60;
    debugPrint('[LiveTimeshift] 窗口起点退回直播边缘');
  }

  Iterable<LiveTimeshiftSource> _orderedSources() {
    if (_hot.isEmpty) return sources;
    return [
      ..._hot,
      ...sources.where((s) => !_hot.contains(s)),
    ];
  }

  void _markHot(LiveTimeshiftSource source) {
    _hot
      ..remove(source)
      ..insert(0, source);
    if (_hot.length > 4) _hot.removeLast();
  }

  ({int lastSeq, String? initName})? _parsePlaylist(String text) {
    var lastSeq = -1;
    String? initName;
    for (final raw in text.split(String.fromCharCode(_lf))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-MAP')) {
        final start = line.indexOf('"');
        if (start >= 0) {
          final end = line.indexOf('"', start + 1);
          if (end > start) initName = line.substring(start + 1, end);
        }
        continue;
      }
      if (line.startsWith('#')) continue;
      if (!line.endsWith('.m4s')) continue;
      final seq = int.tryParse(line.substring(0, line.length - 4));
      if (seq != null && seq > lastSeq) lastSeq = seq;
    }
    if (lastSeq < 0) return null;
    return (lastSeq: lastSeq, initName: initName);
  }

  // ---------------------------------------------------------------- HTTP

  Future<void> _onRequest(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (path.endsWith('index.m3u8')) {
        await _handlePlaylist(response);
      } else if (path.endsWith('.m4s')) {
        final name = path.substring(path.lastIndexOf('/') + 1);
        final seq = int.tryParse(name.substring(0, name.length - 4));
        if (seq == null) {
          await _handleFile(name, response);
        } else {
          await _handleSegment(seq, response);
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      debugPrint('[LiveTimeshift] request failed: $e');
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _handlePlaylist(HttpResponse response) async {
    if (_liveSeq < 0) await _refreshOnce();
    if (_liveSeq < 0 || _playlistStartSeq < 0) {
      response.statusCode = HttpStatus.serviceUnavailable;
      return;
    }
    // 窗口随直播推进滑动，但不超过 windowSeconds
    final edge = _safeEdge;
    final minStart = edge - windowSeconds;
    if (_playlistStartSeq < minStart) _playlistStartSeq = minStart;
    final buffer = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:7')
      ..writeln('#EXT-X-TARGETDURATION:1')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:$_playlistStartSeq')
      ..writeln('#EXT-X-PLAYLIST-TYPE:EVENT');
    if (_initName != null) {
      buffer.writeln('#EXT-X-MAP:URI="init.m4s"');
    }
    for (var seq = _playlistStartSeq; seq <= edge; seq++) {
      buffer
        ..writeln('#EXTINF:1.000,')
        ..writeln('$seq.m4s');
    }
    response.headers
      ..contentType = ContentType('application', 'vnd.apple.mpegurl')
      ..set('Cache-Control', 'no-store');
    response.write(buffer.toString());
  }

  Future<void> _handleSegment(int seq, HttpResponse response) async {
    if (_liveSeq < 0 || seq > _safeEdge) {
      debugPrint(
        '[LiveTimeshift] seg 404 range seq=$seq live=$_liveSeq start=$_playlistStartSeq',
      );
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final cached = await cache?.read(seq);
    if (cached != null && cached.isNotEmpty) {
      _write(response, cached);
      return;
    }
    final data = await _fetchSegment(seq);
    if (data == null) {
      debugPrint('[LiveTimeshift] seg 404 cdn seq=$seq back=${_liveSeq - seq}');
      response.statusCode = HttpStatus.notFound;
      return;
    }
    await cache?.put(seq, data);
    _write(response, data);
  }

  Future<void> _handleFile(String name, HttpResponse response) async {
    if (_initBytes != null) {
      _write(response, _initBytes!);
      return;
    }
    final data = await _fetchFromCdn(
      _orderedSources().map((s) => s.fileUrl(_initName ?? name)).toList(),
    );
    if (data == null) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    _initBytes = data;
    _write(response, data);
  }

  /// 校验分片确实是 fMP4：CDN 异常时会返回 200 + 错误页，
  /// 直接喂给播放器会表现为「error reading packet: Input/output error」。
  static bool _looksLikeFmp4(Uint8List bytes) {
    if (bytes.length < 1024) return false;
    final type = String.fromCharCodes(bytes.sublist(4, 8));
    return type == 'styp' ||
        type == 'moof' ||
        type == 'moov' ||
        type == 'sidx' ||
        type == 'ftyp' ||
        type == 'emsg' ||
        type == 'free';
  }

  /// 与当前 seq 空间一致的候选（换流后 seq 前缀会变，混用必然 404）。
  List<LiveTimeshiftSource> _candidateSources() {
    final list = <LiveTimeshiftSource>[];
    for (final source in _orderedSources()) {
      final sourceSeq = _sourceSeq[source];
      if (sourceSeq != null && (sourceSeq - _liveSeq).abs() > 120) continue;
      list.add(source);
      if (list.length >= maxSegmentAttempts) break;
    }
    if (list.isEmpty) {
      return _orderedSources().take(maxSegmentAttempts).toList();
    }
    return list;
  }

  /// 取分片：优先命中最新的候选，失败换候选并重试一次（CDN 回源抖动很常见）。
  Future<Uint8List?> _fetchSegment(int seq) async {
    final back = _liveSeq - seq;
    for (final source in _candidateSources()) {
      for (var attempt = 0; attempt < 2; attempt++) {
        final bytes = await _get(source.segmentUrl(seq, timeshift: back));
        if (bytes != null && _looksLikeFmp4(bytes)) {
          _markHot(source);
          return bytes;
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    return null;
  }

  void _write(HttpResponse response, Uint8List body) {
    response.headers
      ..contentType = ContentType('video', 'mp4')
      ..set('Cache-Control', 'no-store')
      ..contentLength = body.length;
    response.add(body);
  }

  // ---------------------------------------------------------------- 网络

  Future<String?> _getText(String url, {int maxBytes = 64 * 1024}) async {
    final bytes = await _get(url, maxBytes: maxBytes);
    if (bytes == null) return null;
    try {
      return String.fromCharCodes(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _fetchFromCdn(List<String> urls) async {
    for (final url in urls) {
      final bytes = await _get(url);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }
    return null;
  }

  Future<Uint8List?> _get(String url, {int maxBytes = 8 * 1024 * 1024}) async {
    final client = _client;
    if (client == null) return null;
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers
        ..set(HttpHeaders.refererHeader, 'https://live.bilibili.com/')
        ..set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
        );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response) {
        builder.add(chunk);
        total += chunk.length;
        if (total >= maxBytes) break;
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _client?.close(force: true);
    _client = null;
    await cache?.dispose();
    cache = null;
  }
}
