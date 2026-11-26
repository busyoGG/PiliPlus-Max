import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/live/live_pk_battle/pk_battle_info.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 播放器顶栏上的 PK 标识，点击弹出对方直播间信息。
class PkBattleBadge extends StatelessWidget {
  const PkBattleBadge({super.key, required this.item, this.onTap});

  final PkBattleInfo item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String name = (item.uname != null && item.uname!.isNotEmpty)
        ? item.uname!
        : '对方主播';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.only(left: 4, right: 10),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PkAvatar(url: item.face, size: 20),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                'PK $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PkAvatar extends StatelessWidget {
  const PkAvatar({super.key, this.url, this.size = 36, this.radius});

  final String? url;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final String? src = url;
    final double r = radius ?? size / 2;
    final BorderRadius borderRadius = BorderRadius.circular(r);
    if (src == null || src.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: borderRadius,
        ),
        child: Icon(Icons.person, size: size * 0.6, color: Colors.white70),
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.network(
        src,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          color: const Color(0x33FFFFFF),
          child: Icon(Icons.person, size: size * 0.6, color: Colors.white70),
        ),
      ),
    );
  }
}

/// 弹出对方直播间信息面板。
Future<void> showPkBattleSheet({required PkBattleInfo item}) {
  return showModalBottomSheet<void>(
    context: Get.context!,
    backgroundColor: Colors.transparent,
    builder: (context) => PkBattleSheet(item: item),
  );
}

class PkBattleSheet extends StatefulWidget {
  const PkBattleSheet({super.key, required this.item});

  final PkBattleInfo item;

  @override
  State<PkBattleSheet> createState() => _PkBattleSheetState();
}

class _PkBattleSheetState extends State<PkBattleSheet> {
  String? _title;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final int? roomId = widget.item.roomId;
    if (roomId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final LoadingState response = await LiveHttp.liveRoomInfoH5(
      roomId: roomId,
    );
    if (!mounted) return;
    String? title;
    if (response case Success(:final response)) {
      title = response.roomInfo?.title;
    }
    setState(() {
      _title = title;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = (widget.item.uname != null && widget.item.uname!.isNotEmpty)
        ? widget.item.uname!
        : '对方主播';
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PkAvatar(url: widget.item.face, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.item.isEnded ? 'PK 已结束' : 'PK 中',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: widget.item.isEnded
                              ? theme.colorScheme.outline
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator(),
            if (_title case final String title)
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: Get.back,
                    child: const Text('关闭'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: widget.item.roomId == null
                        ? null
                        : () {
                            final int roomId = widget.item.roomId!;
                            Get.back();
                            PageUtils.toLiveRoom(roomId);
                          },
                    child: const Text('进入直播间'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}