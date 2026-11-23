import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/match.dart';
import 'package:PiliPlus/models_new/match/match_info/contest.dart';
import 'package:PiliPlus/models_new/match/match_schedule/day.dart';
import 'package:PiliPlus/utils/esports_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

/// 赛事直播间额外的「赛程」入口。
Future<void> showEsportsSchedule({
  required int roomId,
  String? gameTitle,
}) {
  final context = Get.context;
  if (context == null) {
    return Future<void>.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EsportsScheduleSheet(
      roomId: roomId,
      gameTitle: gameTitle,
    ),
  );
}

class EsportsScheduleSheet extends StatefulWidget {
  const EsportsScheduleSheet({
    super.key,
    required this.roomId,
    this.gameTitle,
    this.loader,
  });

  final int roomId;
  final String? gameTitle;

  /// 赛程加载器，默认请求接口，测试时可注入。
  final Future<LoadingState<List<MatchScheduleDay>>> Function()? loader;

  @override
  State<EsportsScheduleSheet> createState() => _EsportsScheduleSheetState();
}

class _EsportsScheduleSheetState extends State<EsportsScheduleSheet> {
  bool _loading = true;
  bool _roomOnly = false;
  List<MatchScheduleDay> _days = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await (widget.loader ?? MatchHttp.matchSchedule)();
    if (!mounted) {
      return;
    }
    switch (res) {
      case Success(:final response):
        final byRoom = EsportsUtils.filterByRoom(response, widget.roomId);
        setState(() {
          _roomOnly = byRoom.isNotEmpty;
          _days = _roomOnly ? byRoom : response;
          _loading = false;
        });
      case Error():
        setState(() {
          _error = '赛程加载失败';
          _loading = false;
        });
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(theme),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Text(error, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              else if (_days.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Text('暂无赛程'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: _days.length,
                    itemBuilder: (context, index) =>
                        _buildDay(theme, _days[index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _roomOnly ? '本直播间赛程' : '赛事赛程',
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: Get.back,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildDay(ThemeData theme, MatchScheduleDay day) {
    final list = day.list ?? const <MatchContest>[];
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            EsportsUtils.dayLabel(day.date),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        for (final contest in list) _buildContest(theme, contest, nowSeconds),
      ],
    );
  }

  Widget _buildContest(ThemeData theme, MatchContest contest, int nowSeconds) {
    final state = EsportsUtils.matchState(contest, nowSeconds);
    final score = EsportsUtils.scoreLabel(contest);
    final home = contest.homeTeam?.title ?? '';
    final away = contest.awayTeam?.title ?? '';
    final stage = contest.gameStage ?? '';
    return InkWell(
      onTap: contest.liveRoom == null
          ? null
          : () {
              final roomId = contest.liveRoom!;
              Get.back();
              PageUtils.toLiveRoom(roomId);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(
                EsportsUtils.timeLabel(contest.stime),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$home vs $away',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (stage.isNotEmpty)
                    Text(
                      stage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            if (score.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(score, style: theme.textTheme.bodyMedium),
              ),
            Text(
              EsportsUtils.matchStateLabel(state),
              style: theme.textTheme.bodySmall?.copyWith(
                color: state == MatchState.live
                    ? theme.colorScheme.error
                    : theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
