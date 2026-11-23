import 'package:PiliPlus/models_new/match/match_info/contest.dart';
import 'package:PiliPlus/models_new/match/match_schedule/day.dart';

enum MatchState { upcoming, live, finished, unknown }

abstract final class EsportsUtils {
  /// 只保留在本直播间播出的比赛。
  static List<MatchScheduleDay> filterByRoom(
    List<MatchScheduleDay> days,
    int roomId,
  ) {
    final result = <MatchScheduleDay>[];
    for (final day in days) {
      final list = day.list;
      if (list == null || list.isEmpty) {
        continue;
      }
      final matched = list.where((e) => e.liveRoom == roomId).toList();
      if (matched.isEmpty) {
        continue;
      }
      result.add(
        MatchScheduleDay(
          date: day.date,
          count: matched.length,
          list: matched,
        ),
      );
    }
    return result;
  }

  /// 只有一场比赛的时长上限，用于判断「进行中」。
  static const int defaultMatchSeconds = 7200;

  static MatchState matchState(MatchContest contest, int nowSeconds) {
    final stime = contest.stime;
    if (stime == null) {
      return MatchState.unknown;
    }
    final etime = contest.etime ?? (stime + defaultMatchSeconds);
    if (nowSeconds < stime) {
      return MatchState.upcoming;
    }
    if (nowSeconds <= etime) {
      return MatchState.live;
    }
    return MatchState.finished;
  }

  static String matchStateLabel(MatchState state) => switch (state) {
    MatchState.upcoming => '未开始',
    MatchState.live => '进行中',
    MatchState.finished => '已结束',
    MatchState.unknown => '',
  };

  /// 比分文案，未开赛时返回空字符串。
  static String scoreLabel(MatchContest contest) {
    final home = contest.homeScore;
    final away = contest.awayScore;
    if (home == null || away == null) {
      return '';
    }
    if (home == 0 && away == 0) {
      return '';
    }
    return '$home : $away';
  }

  /// HH:mm
  static String timeLabel(int? seconds) {
    if (seconds == null) {
      return '';
    }
    final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${two(time.hour)}:${two(time.minute)}';
  }

  /// M月d日 周X
  static String dayLabel(int? seconds) {
    if (seconds == null) {
      return '';
    }
    final day = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    return '${day.month}月${day.day}日 周${week[day.weekday - 1]}';
  }

  static String two(int value) => value < 10 ? '0$value' : '$value';
}
