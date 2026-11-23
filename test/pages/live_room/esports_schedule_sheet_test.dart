import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/match/match_info/contest.dart';
import 'package:PiliPlus/models_new/match/match_info/season.dart';
import 'package:PiliPlus/models_new/match/match_info/team.dart';
import 'package:PiliPlus/models_new/match/match_schedule/day.dart';
import 'package:PiliPlus/pages/live_room/widgets/esports_schedule_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const int _roomId = 7734200;

int _secondsFromNow(int offset) =>
    DateTime.now().millisecondsSinceEpoch ~/ 1000 + offset;

MatchContest _contest({
  int? liveRoom,
  int startOffset = -600,
  int endOffset = 3600,
  int homeScore = 1,
  int awayScore = 3,
  String home = 'GEN',
  String away = 'BLG',
}) => MatchContest(
  id: 1,
  stime: _secondsFromNow(startOffset),
  etime: _secondsFromNow(endOffset),
  gameStage: '总决赛',
  liveRoom: liveRoom,
  homeScore: homeScore,
  awayScore: awayScore,
  homeTeam: MatchTeam(title: home),
  awayTeam: MatchTeam(title: away),
  season: Season(id: 806, title: '2026全球总决赛'),
);

Widget _wrap(Future<LoadingState<List<MatchScheduleDay>>> Function() loader) {
  return MaterialApp(
    home: Scaffold(
      body: EsportsScheduleSheet(roomId: _roomId, loader: loader),
    ),
  );
}

void main() {
  testWidgets('shows only this room matches when available', (tester) async {
    Future<LoadingState<List<MatchScheduleDay>>> loader() async => Success(<MatchScheduleDay>[
      MatchScheduleDay(
        date: _secondsFromNow(0),
        count: 2,
        list: [
          _contest(liveRoom: _roomId),
          _contest(liveRoom: 6650029, home: 'T1', away: 'JDG'),
        ],
      ),
    ]);

    await tester.pumpWidget(_wrap(loader));
    await tester.pumpAndSettle();

    expect(find.text('本直播间赛程'), findsOneWidget);
    expect(find.text('GEN vs BLG'), findsOneWidget);
    expect(find.text('T1 vs JDG'), findsNothing);
    expect(find.text('1 : 3'), findsOneWidget);
    expect(find.text('总决赛'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
  });

  testWidgets('falls back to all matches when the room has none',
      (tester) async {
    Future<LoadingState<List<MatchScheduleDay>>> loader() async => Success(<MatchScheduleDay>[
      MatchScheduleDay(
        date: _secondsFromNow(0),
        count: 1,
        list: [_contest(liveRoom: 6650029, home: 'T1', away: 'JDG')],
      ),
    ]);

    await tester.pumpWidget(_wrap(loader));
    await tester.pumpAndSettle();

    expect(find.text('赛事赛程'), findsOneWidget);
    expect(find.text('T1 vs JDG'), findsOneWidget);
  });

  testWidgets('shows empty hint', (tester) async {
    await tester.pumpWidget(
      _wrap(() async => const Success(<MatchScheduleDay>[])),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无赛程'), findsOneWidget);
  });

  testWidgets('shows error with retry', (tester) async {
    var calls = 0;
    Future<LoadingState<List<MatchScheduleDay>>> loader() async {
      calls++;
      if (calls == 1) {
        return const Error('network');
      }
      return const Success(<MatchScheduleDay>[]);
    }

    await tester.pumpWidget(_wrap(loader));
    await tester.pumpAndSettle();

    expect(find.text('赛程加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('赛程加载失败'), findsNothing);
    expect(find.text('暂无赛程'), findsOneWidget);
    expect(calls, 2);
  });
}
