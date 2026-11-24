import 'package:PiliPlus/common/widgets/gesture/tap_gesture_recognizer.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:PiliPlus/models_new/video/video_ai_conclusion/model_result.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class AiConclusionPanel extends CommonSlidePage {
  final AiConclusionResult item;

  const AiConclusionPanel({
    super.key,
    required this.item,
  });

  @override
  State<AiConclusionPanel> createState() => _AiDetailState();

  static Widget buildContent(
    BuildContext context,
    ThemeData theme,
    AiConclusionResult res, {
    Key? key,
    bool tap = true,
  }) {
    final subtitleParts = res.webSubtitleParts.toList(growable: false);
    final fallbackSubtitle = res.fallbackSubtitle?.trim();
    final subtitleCopyText = subtitleParts.isNotEmpty
        ? subtitleParts
              .map((e) => e.content ?? '')
              .where((e) => e.isNotEmpty)
              .join(String.fromCharCode(10))
        : (fallbackSubtitle ?? '');
    final outline = res.outline;
    final hasOutline = outline != null && outline.isNotEmpty;
    return SelectionArea(
      child: CustomScrollView(
        key: key,
        shrinkWrap: !tap,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (res.summary?.isNotEmpty == true) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  res.summary!,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
              ),
            ),
            if (hasOutline)
              SliverToBoxAdapter(
                child: Divider(
                  height: 20,
                  color: theme.dividerColor.withValues(alpha: 0.1),
                  thickness: 6,
                ),
              ),
          ],
          if (hasOutline)
            SliverPadding(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                bottom: !tap
                    ? 0
                    : MediaQuery.viewPaddingOf(context).bottom + 100,
              ),
              sliver: SliverList.builder(
                itemCount: outline.length,
                itemBuilder: (context, index) {
                  final item = outline[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (index != 0) const SizedBox(height: 10),
                      Text(
                        item.title!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...?item.partOutline?.map(
                        (item) => Wrap(
                          children: [
                            Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface,
                                  height: 1.5,
                                ),
                                children: [
                                  TextSpan(
                                    text: DurationUtils.formatDuration(
                                      item.timestamp,
                                    ),
                                    style: tap
                                        ? TextStyle(
                                            color: theme.colorScheme.primary,
                                          )
                                        : null,
                                    recognizer: tap
                                        ? (NoDeadlineTapGestureRecognizer()
                                            ..onTap = () {
                                              try {
                                                Get.find<VideoDetailController>(
                                                  tag: Get.arguments['heroTag'],
                                                ).plPlayerController.seekTo(
                                                  Duration(
                                                    seconds: item.timestamp!,
                                                  ),
                                                  isSeek: false,
                                                );
                                              } catch (_) {}
                                            })
                                        : null,
                                  ),
                                  const TextSpan(text: ' '),
                                  TextSpan(text: item.content!),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          if (subtitleParts.isNotEmpty ||
              fallbackSubtitle?.isNotEmpty == true) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 14, top: 12),
                child: Row(
                  children: [
                    const Text(
                      '字幕',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => Utils.copyText(
                        subtitleCopyText,
                        toastText: '已复制全部内容',
                      ),
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: const Text('复制全部'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                bottom: !tap
                    ? 0
                    : MediaQuery.viewPaddingOf(context).bottom + 100,
              ),
              sliver: subtitleParts.isNotEmpty
                  ? SliverList.builder(
                      itemCount: subtitleParts.length,
                      itemBuilder: (context, index) {
                        final item = subtitleParts[index];
                        final start = item.startTimestamp;
                        return Padding(
                          padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
                          child: Text.rich(
                            TextSpan(
                              style: const TextStyle(fontSize: 14, height: 1.5),
                              children: [
                                if (start != null)
                                  TextSpan(
                                    text:
                                        DurationUtils.formatDuration(
                                          start.round(),
                                        ) +
                                        ' ',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                TextSpan(text: item.content ?? ''),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  : SliverToBoxAdapter(
                      child: Text(
                        fallbackSubtitle!,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AiDetailState extends State<AiConclusionPanel>
    with SingleTickerProviderStateMixin, CommonSlideMixin {
  @override
  Widget buildPage() {
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          GestureDetector(
            onTap: Get.back,
            child: SizedBox(
              height: 35,
              child: Center(
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: const BorderRadius.all(Radius.circular(3)),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: enableSlide ? slideList() : buildList(),
          ),
        ],
      ),
    );
  }

  late Key _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = PrimaryScrollController.of(context);
    _key = ValueKey(controller.hashCode);
  }

  @override
  Widget buildList() {
    return AiConclusionPanel.buildContent(
      context,
      theme,
      widget.item,
      key: _key,
    );
  }
}
