import 'package:PiliPlus/services/live_timeshift_start.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timeShiftAdoptTarget', () {
    Duration? call({
      int positionSeconds = 2,
      int windowSeconds = 3600,
      int attempts = 0,
      Duration elapsed = const Duration(seconds: 1),
      Duration sinceLastAttempt = const Duration(seconds: -5),
    }) {
      return timeShiftAdoptTarget(
        positionSeconds: positionSeconds,
        windowSeconds: windowSeconds,
        attempts: attempts,
        elapsed: elapsed,
        sinceLastAttempt: sinceLastAttempt,
      );
    }

    test('位置还没起来时不干预', () {
      expect(call(positionSeconds: 0), isNull);
      expect(call(positionSeconds: -1), isNull);
    });

    test('已经在直播边缘时不干预', () {
      expect(call(positionSeconds: 3598), isNull);
      expect(call(positionSeconds: 30), isNull);
    });

    test('窗口太短时视为普通直播', () {
      expect(call(windowSeconds: 30), isNull);
      expect(call(positionSeconds: 2, windowSeconds: 59), isNull);
    });

    test('停在窗口开头时拉到直播边缘', () {
      expect(call(), const Duration(seconds: 3597));
      expect(call(positionSeconds: 29), const Duration(seconds: 3597));
      expect(
        call(positionSeconds: 5, windowSeconds: 600),
        const Duration(seconds: 597),
      );
    });

    test('重试次数用尽后不再干预', () {
      expect(call(attempts: 4), isNull);
      expect(call(attempts: 3), isNotNull);
    });

    test('超过起播保护期后交给用户', () {
      expect(call(elapsed: const Duration(seconds: 21)), isNull);
      expect(call(elapsed: const Duration(seconds: 19)), isNotNull);
    });

    test('两次跳转之间留出间隔', () {
      expect(
        call(
          elapsed: const Duration(seconds: 4),
          sinceLastAttempt: const Duration(seconds: 3),
        ),
        isNull,
      );
      expect(
        call(
          elapsed: const Duration(seconds: 6),
          sinceLastAttempt: const Duration(seconds: 3),
        ),
        isNotNull,
      );
    });
  });

  group('timeShiftTimeline', () {
    test('直播边缘：偏移等于窗口减去列表长度', () {
      final timeline = timeShiftTimeline(
        windowSeconds: 3600,
        baseOffset: 0,
        playlistSpan: 6,
      );
      expect(timeline.duration, const Duration(seconds: 3600));
      expect(timeline.positionBase, const Duration(seconds: 3594));
    });

    test('回退 20 分钟后偏移同步减少', () {
      final timeline = timeShiftTimeline(
        windowSeconds: 3600,
        baseOffset: 1200,
        playlistSpan: 6,
      );
      expect(timeline.duration, const Duration(seconds: 3600));
      expect(timeline.positionBase, const Duration(seconds: 2394));
    });

    test('深度只有 1 分钟时进度条也只有 1 分钟', () {
      final timeline = timeShiftTimeline(
        windowSeconds: 60,
        baseOffset: 0,
        playlistSpan: 6,
      );
      expect(timeline.duration, const Duration(seconds: 60));
      expect(timeline.positionBase, const Duration(seconds: 54));
    });

    test('深度未知时返回零时间线', () {
      final timeline = timeShiftTimeline(
        windowSeconds: 0,
        baseOffset: 0,
        playlistSpan: 6,
      );
      expect(timeline.duration, Duration.zero);
      expect(timeline.positionBase, Duration.zero);
    });

    test('偏移超过窗口时钳到 0', () {
      final timeline = timeShiftTimeline(
        windowSeconds: 300,
        baseOffset: 400,
        playlistSpan: 6,
      );
      expect(timeline.duration, const Duration(seconds: 300));
      expect(timeline.positionBase, Duration.zero);
    });
  });
}
