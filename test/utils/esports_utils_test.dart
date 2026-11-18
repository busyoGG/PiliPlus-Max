import 'package:PiliPlus/models_new/match/match_info/contest.dart';
import 'package:PiliPlus/models_new/match/match_schedule/day.dart';
import 'package:PiliPlus/utils/esports_utils.dart';
import 'package:flutter_test/flutter_test.dart';

int localSeconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

MatchContest contest({
  int? id,
  int? stime,
  int? etime,
  int? liveRoom,
  int homeScore = 0,
  int awayScore = 0,
}) => MatchContest(
  id: id,
  stime: stime,
  etime: etime,
  liveRoom: liveRoom,
  homeScore: homeScore,
  awayScore: awayScore,
);

void main() {
  group('filterByRoom', () {
    test('keeps only contests of the room and drops empty days', () {
      final days = [
        MatchScheduleDay(
          date: 1000,
          count: 3,
          list: [
            contest(id: 1, liveRoom: 7734200),
            contest(id: 2, liveRoom: 6650029),
            contest(id: 3, liveRoom: 7734200),
          ],
        ),
        MatchScheduleDay(
          date: 2000,
          count: 1,
          list: [contest(id: 4, liveRoom: 6650029)],
        ),
        MatchScheduleDay(date: 3000, count: 0, list: const []),
      ];

      final result = EsportsUtils.filterByRoom(days, 7734200);

      expect(result.length, 1);
      expect(result.first.date, 1000);
      expect(result.first.count, 2);
      expect(result.first.list!.map((e) => e.id), [1, 3]);
    });

    test('returns empty list when nothing matches', () {
      final days = [
        MatchScheduleDay(
          date: 1000,
          count: 1,
          list: [contest(id: 1, liveRoom: 1)],
        ),
      ];
      expect(EsportsUtils.filterByRoom(days, 2), isEmpty);
    });
  });

  group('matchState', () {
    test('upcoming before start time', () {
      expect(
        EsportsUtils.matchState(contest(stime: 100, etime: 200), 99),
        MatchState.upcoming,
      );
    });

    test('live between start and end time', () {
      expect(
        EsportsUtils.matchState(contest(stime: 100, etime: 200), 150),
        MatchState.live,
      );
    });

    test('finished after end time', () {
      expect(
        EsportsUtils.matchState(contest(stime: 100, etime: 200), 201),
        MatchState.finished,
      );
    });

    test('falls back to two hours when end time is missing', () {
      expect(
        EsportsUtils.matchState(contest(stime: 100), 100 + 7200),
        MatchState.live,
      );
      expect(
        EsportsUtils.matchState(contest(stime: 100), 100 + 7201),
        MatchState.finished,
      );
    });

    test('unknown without start time', () {
      expect(
        EsportsUtils.matchState(contest(), 1),
        MatchState.unknown,
      );
      expect(EsportsUtils.matchStateLabel(MatchState.unknown), '');
    });
  });

  test('matchStateLabel', () {
    expect(EsportsUtils.matchStateLabel(MatchState.upcoming), '未开始');
    expect(EsportsUtils.matchStateLabel(MatchState.live), '进行中');
    expect(EsportsUtils.matchStateLabel(MatchState.finished), '已结束');
  });

  group('scoreLabel', () {
    test('empty while 0:0', () {
      expect(EsportsUtils.scoreLabel(contest()), '');
    });

    test('formats score', () {
      expect(
        EsportsUtils.scoreLabel(contest(homeScore: 1, awayScore: 3)),
        '1 : 3',
      );
    });
  });

  group('time labels', () {
    test('timeLabel formats HH:mm', () {
      final time = DateTime(2026, 11, 15, 20, 5);
      expect(EsportsUtils.timeLabel(localSeconds(time)), '20:05');
      expect(EsportsUtils.timeLabel(null), '');
    });

    test('dayLabel formats M月d日 周X', () {
      // 2026-11-15 is a Sunday.
      expect(
        EsportsUtils.dayLabel(localSeconds(DateTime(2026, 11, 15))),
        '11月15日 周日',
      );
      expect(
        EsportsUtils.dayLabel(localSeconds(DateTime(2026, 11, 18))),
        '11月18日 周三',
      );
      expect(EsportsUtils.dayLabel(null), '');
    });
  });

  group('MatchContest.fromJson', () {
    test('parses schedule shape', () {
      final parsed = MatchContest.fromJson({
        'id': 37756,
        'start_time': 1794682800,
        'end_time': 1794701010,
        'game_stage': '总决赛',
        'live_room': 7734200,
        'home_score': 1,
        'away_score': 3,
        'contest_status': 3,
        'home': {'id': 19, 'name': 'GEN', 'icon': '/bfs/a.png'},
        'away': {'id': 2, 'name': 'BLG', 'icon': '/bfs/b.png'},
        'season': {'id': 806, 'title': '2026全球总决赛'},
      });

      expect(parsed.id, 37756);
      expect(parsed.stime, 1794682800);
      expect(parsed.etime, 1794701010);
      expect(parsed.gameStage, '总决赛');
      expect(parsed.liveRoom, 7734200);
      expect(parsed.homeScore, 1);
      expect(parsed.awayScore, 3);
      expect(parsed.homeTeam?.title, 'GEN');
      expect(parsed.awayTeam?.title, 'BLG');
      expect(parsed.homeTeam?.logo, '/bfs/a.png');
      expect(parsed.homeId, 19);
      expect(parsed.season?.id, 806);
      expect(parsed.season?.title, '2026全球总决赛');
    });

    test('parses match detail shape', () {
      final parsed = MatchContest.fromJson({
        'game_stage': '半决赛',
        'stime': 1794682800,
        'live_room': 7734200,
        'home_team': {'title': 'T1', 'logo': '/bfs/t1.png'},
        'away_team': {'title': 'JDG', 'logo': '/bfs/jdg.png'},
      });

      expect(parsed.stime, 1794682800);
      expect(parsed.homeTeam?.title, 'T1');
      expect(parsed.awayTeam?.title, 'JDG');
    });
  });
}
