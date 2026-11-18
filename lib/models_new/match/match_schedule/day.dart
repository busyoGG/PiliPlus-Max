import 'package:PiliPlus/models_new/match/match_info/contest.dart';

/// x/esports/component/contests/schedule 按日期分组返回的赛程。
class MatchScheduleDay {
  int? date;
  int? count;
  List<MatchContest>? list;

  MatchScheduleDay({
    this.date,
    this.count,
    this.list,
  });

  factory MatchScheduleDay.fromJson(Map<String, dynamic> json) =>
      MatchScheduleDay(
        date: json['date'] as int?,
        count: json['count'] as int?,
        list: (json['list'] as List<dynamic>?)
            ?.map((e) => MatchContest.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
