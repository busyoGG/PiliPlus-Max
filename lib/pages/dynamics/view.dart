import 'package:PiliPlus/common/widgets/blur/app_blur.dart';
import 'package:PiliPlus/common/widgets/home_header_overlay.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart';
import 'package:PiliPlus/common/widgets/custom_height_widget.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics/widgets/up_panel.dart';
import 'package:PiliPlus/pages/dynamics_create/view.dart';
import 'package:PiliPlus/pages/dynamics_tab/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' hide DraggableScrollableSheet;

class DynamicsPage extends StatefulWidget {
  const DynamicsPage({super.key});

  @override
  State<DynamicsPage> createState() => _DynamicsPageState();
}

class _DynamicsPageState extends CommonPageState<DynamicsPage>
    with AutomaticKeepAliveClientMixin {
  final _dynamicsController = Get.putOrFind(DynamicsController.new);
  UpPanelPosition get upPanelPosition => _dynamicsController.upPanelPosition;
  late final MainController _mainController = Get.find<MainController>();
static const double _topUpPanelHeight = 76.0;

@override
bool get needsCorrection => upPanelPosition == .top;

@override
double get collapsibleExtent => _topUpPanelHeight;
  @override
  bool get wantKeepAlive => true;

  Widget _createDynamicBtn(ColorScheme colorScheme, {bool isRight = true}) =>
      Container(
        width: 34,
        height: 34,
        margin: isRight ? const .only(right: 16) : const .only(left: 16),
        child: IconButton(
          tooltip: '发布动态',
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            backgroundColor: WidgetStatePropertyAll(
              colorScheme.secondaryContainer,
            ),
          ),
          onPressed: () => CreateDynPanel.onCreateDyn(context),
          icon: Icon(
            Icons.add,
            size: 18,
            color: colorScheme.onSecondaryContainer,
          ),
        ),
      );

  Widget upPanelPart(ColorScheme colorScheme) {
    final isTop = upPanelPosition == .top;
    final needBg = upPanelPosition.index > 2;
    return Material(
      type: needBg ? .canvas : .transparency,
      color: needBg ? colorScheme.surface : null,
      child: SizedBox(
        width: isTop ? null : 64,
        height: isTop ? _topUpPanelHeight : null,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 300) {
              _dynamicsController.onLoadMore();
            }
            return false;
          },
          child: Obx(
            () => _buildUpPanel(_dynamicsController.loadingState.value),
          ),
        ),
      ),
    );
  }
Widget _collapsibleTopUpPanel(ThemeData theme) {
  // 放在 Obx 外，避免每一个滚动像素都重新创建整个头像栏组件树。
  final panel = upPanelPart(theme);

  final barOffset = _mainController.barOffset;

  // sync 模式
  if (barOffset != null) {
    return Obx(() {
      final offset =
          (barOffset.value /
                  Style.topBarHeight *
                  _topUpPanelHeight)
              .clamp(0.0, _topUpPanelHeight)
              .toDouble();

      return ClipRect(
        child: CustomHeightWidget(
          height: _topUpPanelHeight - offset,
          offset: Offset(0.0, -offset),
          child: panel,
        ),
      );
    });
  }

  final showBottomBar = _mainController.showBottomBar;

  // instant 模式
  if (showBottomBar != null) {
    return Obx(
      () => TweenAnimationBuilder<double>(
        tween: Tween<double>(
          end: showBottomBar.value
              ? 0.0
              : _topUpPanelHeight,
        ),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: panel,
        builder: (context, offset, child) {
          return ClipRect(
            child: CustomHeightWidget(
              height: _topUpPanelHeight - offset,
              offset: Offset(0.0, -offset),
              child: child!,
            ),
          );
        },
      ),
    );
  }

  return panel;
}
  Widget _buildUpPanel(LoadingState<FollowUpModel> upState) {
    return switch (upState) {
      Loading() => const SizedBox.shrink(),
      Success(:final response) => UpPanel(
        upData: response,
        dynamicsController: _dynamicsController,
      ),
      Error() => Center(
        child: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _dynamicsController.onReload,
        ),
      ),
    };
  }

  bool get _isCurrentPage =>
    _mainController.navigationBars[
        _mainController.selectedIndex.value
    ] ==
    .dynamics;

  @override
bool onNotificationType1(
  UserScrollNotification notification,
) {
  if (!_isCurrentPage) {
    return false;
  }
  return super.onNotificationType1(notification);
}

@override
bool onNotificationType2(
  ScrollNotification notification,
) {
  if (!_isCurrentPage) {
    return false;
  }
  return super.onNotificationType2(notification);
}

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);

    Widget? drawer;
    Widget? endDrawer;

    Widget? leading;
    Widget actions;

    final Widget tabsView = tabBarView(
      controller: _dynamicsController.tabController,
      children: DynamicsTabType.values
          .map((e) => DynamicsTabPage(dynamicsType: e))
          .toList(),
    );
    Widget child = tabsView;

    switch (upPanelPosition) {
      case UpPanelPosition.top:
  // UP 面板浮在列表上方，列表滚到面板和顶栏背后被糊住。
  child = Stack(
    children: [
      Positioned.fill(
        child: HomeHeaderOverlay(
          inset: _statusBarHeight(context) + _barHeight + _topUpPanelHeight,
          child: tabsView,
        ),
      ),
      Positioned(
        top: _statusBarHeight(context) + _barHeight,
        left: 0,
        right: 0,
        child: _collapsibleTopUpPanel(theme),
      ),
    ],
  );
  actions = [_createDynamicBtn(theme)];
      case UpPanelPosition.leftFixed:
        child = Row(
          children: [
            upPanelPart(colorScheme),
            Expanded(child: child),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .rightFixed:
        child = Row(
          children: [
            Expanded(child: child),
            upPanelPart(colorScheme),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .leftDrawer:
        drawer = upPanelPart(colorScheme);
        actions = _createDynamicBtn(colorScheme);
        leading = const DrawerButton();
      case .rightDrawer:
        endDrawer = upPanelPart(colorScheme);
        leading = _createDynamicBtn(colorScheme, isRight: false);
        actions = const EndDrawerButton();
    }

    final bool overlayBar = upPanelPosition == UpPanelPosition.top;
    final AppBar bar = AppBar(
        // primary: true 让 AppBar 自己让出状态栏高度，页头不再压到状态栏里。
        primary: true,
        leading: leading,
        leadingWidth: 50,
        toolbarHeight: 50,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // 顶栏毛玻璃：铺满整个 AppBar（含状态栏占位那一条）。
        flexibleSpace: BlurSurface(
          sigma: AppBlur.barSigma,
          tint: theme.colorScheme.surface,
          tintAlpha: 0.6,
          // 模糊和底色一起裁圆角：采样不溢出顶栏范围。
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(14),
          ),
          boxShadow: AppBlur.barShadow,
          child: const SizedBox.expand(),
        ),
        title: SizedBox(
          height: 50,
          child: TabBar(
            dividerHeight: 0,
            isScrollable: true,
            tabAlignment: .center,
            dividerColor: Colors.transparent,
            labelColor: theme.colorScheme.primary,
            indicatorColor: theme.colorScheme.primary,
            controller: _dynamicsController.tabController,
            unselectedLabelColor: theme.colorScheme.onSurface,
            labelStyle:
                TabBarTheme.of(context).labelStyle?.copyWith(fontSize: 13) ??
                const TextStyle(fontSize: 13),
            tabs: DynamicsTabType.values
                .map((e) => Tab(text: e.label))
                .toList(),
            onTap: (index) {
              if (!_dynamicsController.tabController.indexIsChanging) {
                _dynamicsController.animateToTop();
              }
            },
          ),
        ),
        actions: actions,
      );
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      // top 模式不用 appBar 占位：body 铺到屏幕顶部，顶栏浮在上面。
      appBar: overlayBar ? null : bar,
      drawer: drawer,
      endDrawer: endDrawer,
      body: overlayBar
          ? Stack(
              children: [
                Positioned.fill(child: onBuild(child)),
                // AppBar 不给高度会撑满整个 Stack，挡掉所有手势。
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _statusBarHeight(context) + _barHeight,
                  child: bar,
                ),
              ],
            )
          : onBuild(child),
    );
  }
}

/// 顶栏高度（不含状态栏）。
const double _barHeight = 50.0;

/// 状态栏高度。
double _statusBarHeight(BuildContext context) =>
    MediaQuery.paddingOf(context).top;
