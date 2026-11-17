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
}
