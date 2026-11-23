import 'package:flutter/widgets.dart';

/// 首页顶栏（搜索栏 + 分类栏）覆盖在内容之上时，内容需要让出的高度。
///
/// 首页把 [inset] 通过本 InheritedWidget 往下传，各 tab 页把它加到自己的
/// 顶部内边距上，列表才能真正滚到顶栏背后、被顶栏的毛玻璃糊住。
/// 不提供本 widget 的地方（同一页面在别的路由里被复用）返回 0。
class HomeHeaderOverlay extends InheritedWidget {
  const HomeHeaderOverlay({
    super.key,
    required this.inset,
    required super.child,
  });

  final double inset;

  static double insetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeHeaderOverlay>()?.inset ??
      0;

  @override
  bool updateShouldNotify(HomeHeaderOverlay oldWidget) =>
      oldWidget.inset != inset;
}
