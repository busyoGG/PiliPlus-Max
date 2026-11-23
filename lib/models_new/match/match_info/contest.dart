import 'package:PiliPlus/models_new/match/match_info/season.dart';
import 'package:PiliPlus/models_new/match/match_info/team.dart';
typedef Season = MatchSeason;

class MatchContest {
  String? get playback => playBack;
  int? id;
  String? gameStage;
  int? stime;
  int? etime;
  int? homeId;
  int? awayId;
  int? homeScore;
  int? awayScore;
  int? liveRoom;
  String? playBack;
  Season? season;
  MatchTeam? homeTeam;
  MatchTeam? awayTeam;
  int? contestStatus;

  MatchContest({
    this.id,
    this.gameStage,
    this.stime,
    this.etime,
    this.homeId,
    this.awayId,
    this.homeScore,
    this.awayScore,
    this.liveRoom,
    this.playBack,
    this.season,
    this.homeTeam,
    this.awayTeam,
    this.contestStatus,
  });

  /// 兼容两种返回结构：
  /// - 赛事详情 x/esports/match/info：stime / home_team / away_team
  /// - 赛程 x/esports/component/contests/schedule：start_time / end_time / home / away
  factory MatchContest.fromJson(Map<String, dynamic> json) => MatchContest(
    id: json['id'] as int?,
    gameStage: json['game_stage'] as String?,
    stime: (json['stime'] ?? json['start_time']) as int?,
    etime: (json['etime'] ?? json['end_time']) as int?,
    homeId: (json['home_id'] ?? (json['home'] as Map?)?['id']) as int?,
    awayId: (json['away_id'] ?? (json['away'] as Map?)?['id']) as int?,
    homeScore: json['home_score'] as int?,
    awayScore: json['away_score'] as int?,
    liveRoom: json['live_room'] as int?,
    playBack: json['play_back'] as String?,
    season: switch (json['season']) {
      final Map<String, dynamic> season => Season.fromJson(season),
      _ => null,
    },
    homeTeam: switch (json['home_team'] ?? json['home']) {
      final Map<String, dynamic> team => MatchTeam.fromJson(team),
      _ => null,
    },
    awayTeam: switch (json['away_team'] ?? json['away']) {
      final Map<String, dynamic> team => MatchTeam.fromJson(team),
      _ => null,
    },
    contestStatus: json['contest_status'] as int?,
  );
}
