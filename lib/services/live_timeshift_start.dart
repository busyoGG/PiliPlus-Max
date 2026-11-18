/// 直播时移起播位置判定。
///
/// 安卓 mpv 起播时若音频 underrun，会把播放位置重启到播放列表最早的分片，
/// 表现为「打开直播就停在一小时前」。这里用纯函数决定何时把播放位置拉回
/// 直播边缘，便于单测覆盖。
///
/// 返回 null 表示不干预；返回目标位置表示应当跳转过去。
Duration? timeShiftAdoptTarget({
  required int positionSeconds,
  required int windowSeconds,
  required int attempts,
  required Duration elapsed,
  required Duration sinceLastAttempt,
  int maxAttempts = 4,
  int edgeGuardSeconds = 30,
  Duration deadline = const Duration(seconds: 20),
  Duration minInterval = const Duration(seconds: 3),
}) {
  if (positionSeconds <= 0) {
    return null;
  }
  // 窗口太短说明时移没准备好，或者这根本不是时移播放。
  if (windowSeconds < 60) {
    return null;
  }
  // 已经在直播边缘附近，不需要干预。
  if (positionSeconds >= edgeGuardSeconds) {
    return null;
  }
  if (attempts >= maxAttempts) {
    return null;
  }
  if (elapsed > deadline) {
    return null;
  }
  if (elapsed - sinceLastAttempt < minInterval) {
    return null;
  }
  return Duration(seconds: windowSeconds - 3);
}


/// 时移时间线：进度条总长度与「播放器时间线 -> 窗口时间」的偏移。
///
/// 播放器只播列表末尾的几个分片，所以它的时间线接近 0；
/// 进度条要显示的是「窗口时间」，因此需要把窗口深度换算成偏移。
({Duration duration, Duration positionBase}) timeShiftTimeline({
  required int windowSeconds,
  required int baseOffset,
  required int playlistSpan,
}) {
  if (windowSeconds <= 0) {
    return (duration: Duration.zero, positionBase: Duration.zero);
  }
  final base = windowSeconds - baseOffset - playlistSpan;
  return (
    duration: Duration(seconds: windowSeconds),
    positionBase: Duration(seconds: base.clamp(0, windowSeconds)),
  );
}
