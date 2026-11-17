import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

/// 直播时移的本地分片缓存。
///
/// 边播边落盘：所有经过时移服务器的分片都会被写入，CDN 已不再保留的区间
/// 就由这里补齐。按容量与分片数双闸做环形淘汰（先删最旧的）。
class LiveDvrCache {
  LiveDvrCache({
    required this.roomId,
    required this.epoch,
    this.maxBytes = 400 * 1024 * 1024,
    this.maxSegments = 3600,
  });

  final int roomId;

  /// 流 epoch（seq 前缀），换流后旧缓存不可用，用目录隔离。
  final int epoch;
  final int maxBytes;
  final int maxSegments;

  Directory? _dir;
  final Map<int, int> _sizes = {};
  final Map<int, Future<void>> _writing = {};
  int _totalBytes = 0;
  bool _ready = false;

  Directory? get directory => _dir;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      final dir = Directory(
        '${Directory.systemTemp.path}/live_dvr/${roomId}_$epoch',
      );
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      _dir = dir;
      await _load();
    } catch (e) {
      debugPrint('[LiveDvrCache] init failed: $e');
    }
  }

  Future<void> _load() async {
    final dir = _dir;
    if (dir == null) return;
    final files = <File>[];
    try {
      await for (final e in dir.list()) {
        if (e is File) files.add(e);
      }
    } catch (_) {
      return;
    }
    for (final f in files) {
      final seq = _seqOf(f.path);
      if (seq == null) continue;
      try {
        final size = await f.length();
        _sizes[seq] = size;
        _totalBytes += size;
      } catch (_) {}
    }
    await _prune();
  }

  int? _seqOf(String path) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    if (!name.endsWith('.m4s')) return null;
    return int.tryParse(name.substring(0, name.length - 4));
  }

  File? _fileOf(int seq) {
    final dir = _dir;
    if (dir == null) return null;
    return File('${dir.path}/$seq.m4s');
  }

  Future<Uint8List?> read(int seq) async {
    final f = _fileOf(seq);
    if (f == null) return null;
    try {
      if (!f.existsSync()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<bool> contains(int seq) async {
    final f = _fileOf(seq);
    if (f == null) return false;
    try {
      return f.existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> put(int seq, Uint8List bytes) async {
    final pending = _writing[seq];
    if (pending != null) {
      await pending;
      return;
    }
    final future = _write(seq, bytes);
    _writing[seq] = future;
    try {
      await future;
    } finally {
      _writing.remove(seq);
    }
  }

  Future<void> _write(int seq, Uint8List bytes) async {
    final f = _fileOf(seq);
    if (f == null) return;
    try {
      if (f.existsSync()) return;
      await f.writeAsBytes(bytes, flush: false);
      _sizes[seq] = bytes.length;
      _totalBytes += bytes.length;
      await _prune();
    } catch (e) {
      debugPrint('[LiveDvrCache] write failed: $e');
    }
  }

  Future<void> _prune() async {
    if (_sizes.length <= maxSegments && _totalBytes <= maxBytes) return;
    final seqs = _sizes.keys.toList()..sort();
    for (final seq in seqs) {
      if (_sizes.length <= maxSegments && _totalBytes <= maxBytes) break;
      final size = _sizes.remove(seq) ?? 0;
      _totalBytes -= size;
      try {
        final f = _fileOf(seq);
        if (f != null && f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }

  /// 已缓存的 seq 区间，用于计算可回看窗口。
  ({int oldest, int newest})? get range {
    if (_sizes.isEmpty) return null;
    var oldest = -1;
    var newest = -1;
    for (final s in _sizes.keys) {
      if (oldest < 0 || s < oldest) oldest = s;
      if (s > newest) newest = s;
    }
    if (oldest < 0) return null;
    return (oldest: oldest, newest: newest);
  }

  Future<void> dispose() async {
    _dir = null;
    _sizes.clear();
    _writing.clear();
    _totalBytes = 0;
  }
}
