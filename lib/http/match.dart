import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/match/match_info/contest.dart';
import 'package:PiliPlus/models_new/match/match_info/data.dart';
import 'package:PiliPlus/models_new/match/match_schedule/day.dart';

abstract final class MatchHttp {
  static Future<LoadingState<MatchContest?>> matchInfo(Object cid) async {
    final res = await Request().get(
      Api.matchInfo,
      queryParameters: {
        'cid': cid,
        'platform': 2,
      },
    );
    if (res.data['code'] == 0) {
      return Success(MatchInfoData.fromJson(res.data['data']).contest);
    } else {
      return Error(res.data['message']);
    }
  }

  /// 赛事赛程，按日期分组返回。
  static Future<LoadingState<List<MatchScheduleDay>>> matchSchedule({
    int pn = 1,
    int ps = 20,
  }) async {
    final res = await Request().get(
      Api.matchSchedule,
      queryParameters: {
        'pn': pn,
        'ps': ps,
      },
    );
    if (res.data['code'] == 0) {
      final data = res.data['data'];
      if (data is List) {
        return Success(
          data
              .map(
                (e) => MatchScheduleDay.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
        );
      }
      return const Success(<MatchScheduleDay>[]);
    }
    return Error(res.data['message']);
  }
}
