import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/services/live_dvr_cache.dart';
import 'package:flutter/foundation.dart' show debugPrint;

const int _lf = 10;

/// 房号 -> 上次探测到的可回看深度（秒），二次进入免探测。
final Map<int, int> _windowCache = <int, int>{};

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
    this.maxDvrSeconds = 600,
  }) : sources = urls.map(LiveTimeshiftSource.new).toList() {
    final seen = <String>{};
    sources.retainWhere((s) => seen.add(s.toString()));
  }

  final int roomId;
  final List<LiveTimeshiftSource> sources;
  final int windowSeconds;
  final int maxSegmentAttempts;

  /// 本地缓存能留多久（秒）。服务端没有回看窗口的房间靠它做回看。
  final int maxDvrSeconds;

  LiveDvrCache? cache;
  HttpServer? _server;
  HttpClient? _client;
  Timer? _timer;
  final _hot = <LiveTimeshiftSource>[];
  final _sourceSeq = <LiveTimeshiftSource, int>{};
  bool _refreshing = false;
  bool _disposed = false;
  bool _startProbed = false;

  /// 深度探测是否已经出结果，出结果前取分片一律先试 tmshift。
  bool _probeDone = false;

  int _liveSeq = -1;
  int _windowSeconds = 0;

  /// 本地已缓存的历史长度（秒），上限 maxDvrSeconds。
  int _cacheSpan = 0;

  /// 服务端回看深度变化时通知业务层刷新进度条时间线。
  void Function(int seconds)? onWindowChanged;

  /// 本地缓存深度变化时通知业务层：只改进度条长度，不动时间线基准。
  void Function(int seconds)? onLocalWindowChanged;
  String? _initName;
  Uint8List? _initBytes;

  int get liveSeq => _liveSeq;

  /// 播放器用的「安全直播边缘」：CDN 最新 1~2 个分片可能还没写完，
  /// 直接给播放器会让 ffmpeg 读到半截数据并判定 I/O error。
  /// 播放器当前窗口相对直播边缘的落后秒数，拖动进度条时改写它。
  int baseOffset = 0;

  /// 播放列表长度（秒）。只给播放器一小段，和 CDN 原始直播列表保持一致，
  /// 避免超长列表导致 ffmpeg 起播/计时异常。
  int playlistSpan = 6;

  /// 播放器可用的最新分片（CDN 最新 1~2 个分片可能还没写完）。
  int get _playerEdge => _liveSeq - baseOffset - 1;

  int get _playerStart => _liveSeq - baseOffset - playlistSpan;

  int get playlistStartSeq => _playerStart;

  /// 本地缓存回看秒数。
  int get cacheSpanSeconds => _cacheSpan;

  /// 可回看的秒数：服务端回看窗口与本地缓存取大者。
  int get seekWindowSeconds =>
      _windowSeconds > _cacheSpan ? _windowSeconds : _cacheSpan;

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
    // 先绑端口：本地播放地址立即可用，取列表与探测都不再压着起播。
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } catch (e) {
      debugPrint('[LiveTimeshift] bind failed: $e');
      await dispose();
      return false;
    }
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
    cache = LiveDvrCache(
      roomId: roomId,
      epoch: _liveSeq ~/ 1000000,
      maxSegments: maxDvrSeconds + 60,
    );
    await cache!.init();
    _server!.listen(_onRequest, onError: (Object _) {});
    final cached = _windowCache[roomId];
    if (cached != null) {
      _windowSeconds = cached;
      _startProbed = true;
      debugPrint('[LiveTimeshift] 复用回看深度 ${cached}s');
    } else {
      // 回看深度后台探测：探测结果通过 onWindowChanged 回填时间线。
      unawaited(_probeRetention());
    }
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
          // 换流/断流后 seq 会跳变
          if (delta < -5 || delta > 40) {
            debugPrint('[LiveTimeshift] seq 跳变 $delta');
          }
        }
        _liveSeq = last;
        if (parsed.initName != null && _initName != parsed.initName) {
          _initName = parsed.initName;
          _initBytes = null;
        }
        _refreshCacheSpan();
        return true;
      }
    } finally {
      _refreshing = false;
    }
    return _liveSeq >= 0;
  }

  /// 探测可回看深度：深历史分片只存在部分 (host, path) 组合上，
  /// 逐档深试，取第一个能取到的值作为进度条长度。
  /// 探测可回看深度：并发探测多个深度，避免串行等待把起播拖住。
  Future<void> _probeRetention() async {
    if (_startProbed || _liveSeq < 0) return;
    _startProbed = true;
    final steps = <int>[3600, 2700, 1800, 1200, 900, 600, 300, 120];
    final probeSources = _orderedSources().take(3).toList();
    if (probeSources.isEmpty) {
      _windowSeconds = 0;
      _probeDone = true;
      return;
    }
    final depths = <int>[];
    Future<void> probe(int back) async {
      final seq = _liveSeq - back;
      if (seq < 0) return;
      for (final source in probeSources) {
        final bytes = await _get(source.segmentUrl(seq, timeshift: back));
        if (bytes != null && _looksLikeFmp4(bytes)) {
          depths.add(back);
          return;
        }
      }
    }

    await Future.wait(steps.map(probe)).timeout(
      const Duration(seconds: 6),
      onTimeout: () => const <void>[],
    );
    _probeDone = true;
    if (depths.isEmpty) {
      _windowSeconds = 0;
      debugPrint('[LiveTimeshift] 服务端无回看窗口，改用本地缓存回看');
      return;
    }
    depths.sort();
    final found = depths.last;
    if (found == _windowSeconds) return;
    _windowSeconds = found;
    _windowCache[roomId] = found;
    debugPrint('[LiveTimeshift] 可回看 back=$found');
    onWindowChanged?.call(found);
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
    if (_liveSeq < 0 || _playerStart < 0) {
      response.statusCode = HttpStatus.serviceUnavailable;
      return;
    }
    final edge = _playerEdge;
    final start = _playerStart;
    final buffer = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:7')
      ..writeln('#EXT-X-TARGETDURATION:1')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:$start')
      ..writeln('#EXT-X-PLAYLIST-TYPE:EVENT');
    if (_initName != null) {
      buffer.writeln('#EXT-X-MAP:URI="init.m4s"');
    }
    for (var seq = start; seq <= edge; seq++) {
      buffer
        ..writeln('#EXTINF:1.000,')
        ..writeln('$seq.m4s');
    }
    response.headers
      ..contentType = ContentType('application', 'vnd.apple.mpegurl')
      ..set('Cache-Control', 'no-store');
    response.write(buffer.toString());
  }

  /// 本地缓存深度变化时刷新进度条长度（服务端回看窗口不变）。
  void _refreshCacheSpan() {
    final range = cache?.range;
    if (range == null || _liveSeq < 0) return;
    final span = (_liveSeq - range.oldest).clamp(0, maxDvrSeconds);
    if (span == _cacheSpan) return;
    _cacheSpan = span;
    debugPrint('[LiveTimeshift] 本地缓存回看 $_cacheSpan s');
    onLocalWindowChanged?.call(seekWindowSeconds);
  }

  Future<void> _handleSegment(int seq, HttpResponse response) async {
    if (_liveSeq < 0 || seq > _playerEdge) {
      debugPrint(
        '[LiveTimeshift] seg 404 range seq=$seq live=$_liveSeq start=$_playerStart',
      );
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final cached = await cache?.read(seq);
    if (cached != null && cached.isNotEmpty) {
      _write(response, cached);
      return;
    }
    // 超出已知回看窗口的分片不必回源：CDN 上没有保留，只会白等重试。
    final back = _liveSeq - seq;
    if (back > seekWindowSeconds + 30) {
      debugPrint('[LiveTimeshift] seg 404 window back=$back');
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final data = await _fetchSegment(seq);
    if (data == null) {
      debugPrint('[LiveTimeshift] seg 404 cdn back=$back');
      response.statusCode = HttpStatus.notFound;
      return;
    }
    await cache?.put(seq, data);
    _refreshCacheSpan();
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
      // 赛事房间靠 tmshift 取历史分片；普通直播间 CDN 不认 tmshift，
      // 探测出「没有服务端历史」之后直接取原地址，省掉一次必然 404 的回源。
      final plainFirst = _probeDone && _windowSeconds == 0;
      final urls = <String>[
        source.segmentUrl(seq, timeshift: plainFirst ? null : back),
      ];
      if (back > 0) {
        urls.add(source.segmentUrl(seq, timeshift: plainFirst ? back : null));
      }
      for (final url in urls) {
        for (var attempt = 0; attempt < 2; attempt++) {
          final bytes = await _get(url);
          if (bytes != null && _looksLikeFmp4(bytes)) {
            _markHot(source);
            return bytes;
          }
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
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
