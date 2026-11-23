import 'package:PiliPlus/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/models/common/pgc_review_type.dart';
import 'package:PiliPlus/models/common/theme/theme_color_type.dart';
import 'package:PiliPlus/pages/pgc_review/child/controller.dart';
import 'package:PiliPlus/pages/pgc_review/child/view.dart';
import 'package:PiliPlus/pages/pgc_review/post/view.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class PgcReviewPage extends StatefulWidget {
  const PgcReviewPage({
    super.key,
    required this.name,
    required this.mediaId,
  });

  final String name;
  final dynamic mediaId;

  @override
  State<PgcReviewPage> createState() => _PgcReviewPageState();
}

class _PgcReviewPageState extends State<PgcReviewPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: PgcReviewType.values.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TabBar(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: PgcReviewType.values
                  .map(
                    (e) => PgcReviewChildPage(
                      type: e,
                      name: widget.name,
                      mediaId: widget.mediaId,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
      fab: Padding(
        padding: .only(
          right: kFloatingActionButtonMargin,
          bottom:
              MediaQuery.viewPaddingOf(context).bottom +
              kFloatingActionButtonMargin,
          child: FloatingActionButton(
            backgroundColor: Theme.of(
              context,
            ).uiColor(ThemeUiElement.pgcReviewBackground),
            foregroundColor: Theme.of(
              context,
            ).uiColor(ThemeUiElement.pgcReviewContent),
            onPressed: () => showDialog(
              context: context,
              builder: (context) => SimpleDialog(
                clipBehavior: Clip.hardEdge,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  DialogOption(
                    child: const Text('写短评', style: TextStyle(fontSize: 14)),
                    onPressed: () {
                      Get.back();
                      showModalBottomSheet(
                        context: context,
                        useSafeArea: true,
                        isScrollControlled: true,
                        builder: (context) {
                          return PgcReviewPostPanel(
                            name: widget.name,
                            mediaId: widget.mediaId,
                          );
                        },
                      );
                    },
                  ),
                  DialogOption(
                    child: const Text('写长评', style: TextStyle(fontSize: 14)),
                    onPressed: () => Get
                      ..back()
                      ..toNamed(
                        '/webview',
                        parameters: {
                          'url':
                              'https://member.bilibili.com/article-text/mobile?theme=${theme.isDark ? 1 : 0}&media_id=${widget.mediaId}',
                        },
                      ),
                  ),
                ],
              ),
            ),
          ),
          child: const Icon(Icons.edit),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
