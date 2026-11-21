import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

/// 打开详情页时随路由传入的卡片矩形参数名。
const String videoOriginRectKey = 'originRect';

/// 按住返回手势时的预览缩放下限（预测性返回预览）。
const double videoCardPreviewMinScale = 0.92;

/// 页面形变矩阵所在 Transform 的 key，便于测试定位。
const Key videoCardTransformKey = Key('videoCardTransform');

/// 过渡期间承载卡片内容（封面）的那一层的 key。
const Key videoCardCoverKey = Key('videoCardCover');

/// 松手确认返回后，页面收回到卡片的时长。
const Duration videoCardCollapseDuration = Duration(milliseconds: 260);

/// 从路由参数里取出卡片矩形，没有或类型不符时返回 null。
Rect? videoOriginRectOf(Object? arguments) {
  if (arguments is Map) {
    final Object? value = arguments[videoOriginRectKey];
    if (value is Rect) return value;
  }
  return null;
}

/// 取一个已经完成布局的组件的全局矩形，组件已销毁时返回 null。
Rect? videoCardRectOf(BuildContext context) {
  try {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
  } catch (_) {}
  return null;
}

/// 卡片矩形与全屏矩形之间按进度 t 插值。
Rect videoTransitionRect(Rect origin, Size screen, double t) {
  return Rect.lerp(origin, Offset.zero & screen, t.clamp(0.0, 1.0))!;
}

/// 把 [t] 映射到 [begin, end] 区间内的 0~1 值。
double videoTransitionInterval(double begin, double end, double t) {
  if (end <= begin) return t >= end ? 1.0 : 0.0;
  return ((t - begin) / (end - begin)).clamp(0.0, 1.0);
}

/// 页面内容的淡入进度：起步很快，随即保持不透明。
/// 详情页在过渡后期的淡入进度：封面先长满，页面最后才显出来。
double videoTransitionPageOpacity(double t) =>
    videoTransitionInterval(0.55, 1.0, t);

/// 从路由参数里取出卡片封面地址。
String? videoCoverOf(Object? arguments) {
  if (arguments is! Map) return null;
  final Object? cover = arguments['cover'];
  return cover is String && cover.isNotEmpty ? cover : null;
}

/// 页面左上角对齐 [rect] 左上角的等比缩放矩阵。
///
/// 等比缩放保证页面内容不变形；配合 [rect] 裁剪，视觉上就是从卡片里长出来。
Matrix4 videoTransitionMatrix(Rect rect, Size screen, double t) {
  if (t >= 1) return Matrix4.identity();
  // 宽高各自贴合卡片，终点就是卡片的实际大小，不需要再裁剪。
  return Matrix4.identity()
    ..translateByDouble(rect.left, rect.top, 0.0, 1.0)
    ..scaleByDouble(
      rect.width / screen.width,
      rect.height / screen.height,
      1.0,
      1.0,
    );
}

/// 打开／普通返回时的形变进度：路由动画值套一层缓动曲线。
double videoCardEntryProgress(double routeValue) {
  return Curves.easeOutCubic.transform(routeValue.clamp(0.0, 1.0));
}

/// 带卡片矩形的路由专用转场。
///
/// 这一层把路由自带的视觉转场让出来（直接返回 child），页面展开、返回手势
/// 预览、收起全由 [VideoCardEntryTransform] 驱动，因此不会出现两套动画叠加
/// 把效果冲淡；路由自身的动画仍在跑，保证手势时下层页面能正常显示而不是黑屏。
class VideoCardPageTransitionsBuilder extends PageTransitionsBuilder {
  const VideoCardPageTransitionsBuilder();

  static const PageTransitionsBuilder _fallback =
      PredictiveBackPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (videoOriginRectOf(route.settings.arguments) == null) {
      return _fallback.buildTransitions<T>(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return VideoCardEntryTransform(child: child);
  }
}

/// 页面内容在卡片矩形与全屏之间变化，并接管返回手势的预测性返回预览。
class VideoCardEntryTransform extends StatefulWidget {
  const VideoCardEntryTransform({super.key, required this.child, this.origin});

  final Widget child;

  /// 卡片在屏幕上的矩形，为空时从路由参数 [videoOriginRectKey] 读取。
  final Rect? origin;

  @override
  State<VideoCardEntryTransform> createState() =>
      VideoCardEntryTransformState();
}

/// 对外可见，便于测试直接驱动手势回调。
class VideoCardEntryTransformState extends State<VideoCardEntryTransform>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  ModalRoute<dynamic>? _route;
  Rect? _origin;

  /// 卡片封面地址；过渡期间显示的是卡片内容，而不是详情页本身。
  String? _cover;

  Color get _surfaceColor =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  /// 打开／普通返回由路由动画驱动；松手确认返回时用这个自己收回到卡片。
  late final AnimationController _closing;

  /// 正在播放「收回到卡片」，此时忽略路由动画。
  bool _committing = false;

  /// 手势进行中：按住不动，只在松手时才收回到卡片。
  bool _gestureActive = false;

  @override
  void initState() {
    super.initState();
    _closing = AnimationController(
      duration: videoCardCollapseDuration,
      value: 1,
      vsync: this,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _route = route;
    _origin = widget.origin ?? videoOriginRectOf(route?.settings.arguments);
    _cover = videoCoverOf(route?.settings.arguments);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closing.dispose();
    super.dispose();
  }

  /// 当前路由能否自己驱动预测性返回。
  ///
  /// 不读 [ModalRoute.popGestureEnabled]：GetX 路由把它绑到
  /// navigator.userGestureInProgress，计数一旦残留就会一直为 false。
  bool get _canHandleBackGesture {
    final ModalRoute<dynamic>? route = _route;
    if (!mounted || route == null || _origin == null) return false;
    if (!route.isCurrent) return false;
    if (route.willHandlePopInternally) return false;
    return route.popDisposition != RoutePopDisposition.doNotPop;
  }

  /// 接管返回手势：按住期间给预测性返回预览（轻微缩放），但不收回卡片。
  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent || !_canHandleBackGesture) return false;
    _gestureActive = true;
    // 交给路由自己，让它跟着手指后退：下层页面因此参与绘制，不是黑屏。
    _route!.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_gestureActive) return;
    _route?.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);
  }

  @override
  void handleCancelBackGesture() {
    if (!_gestureActive) return;
    _gestureActive = false;
    _route?.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    if (!_gestureActive) return;
    _gestureActive = false;
    _committing = true;
    _releaseBackGesture();
    // 按住期间页面是冻结的，所以从全屏开始收。
    _closing.value = 1;
    // 先收回到卡片再真正 pop，避免收起动画被路由转场盖掉。
    _closing.animateTo(0, curve: Curves.easeOut).whenComplete(() {
      if (mounted) _route?.navigator?.pop();
    });
  }

  /// 归还 [NavigatorState.didStartUserGesture] 借走的手势计数。
  ///
  /// 我们自己 pop，路由不会再走动画结束回调，不还回去 navigator 会一直认为
  /// 手势还在进行中，从而忽略所有点击，表现为返回后主页卡住。
  void _releaseBackGesture() {
    final NavigatorState? navigator = _route?.navigator;
    if (navigator == null) return;
    if (!navigator.userGestureInProgress) return;
    navigator.didStopUserGesture();
  }

  /// 过渡层：卡片封面（卡片内容），拿不到封面时退回一层底色。
  Widget _buildCover(Size screen) {
    final String? cover = _cover;
    if (cover == null) return ColoredBox(color: _surfaceColor);
    return Image.network(
      cover,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
          ColoredBox(color: _surfaceColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Rect? origin = _origin;
    final Animation<double>? animation = _route?.animation;
    if (origin == null || animation == null) return widget.child;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[animation, _closing]),
      child: RepaintBoundary(child: widget.child),
      builder: (BuildContext context, Widget? child) {
        final Size screen = MediaQuery.sizeOf(context);
        if (_gestureActive) {
          // 预测性返回预览：整页轻微缩小，露出下层页面；不缩到卡片。
          final double scale =
              videoCardPreviewMinScale +
              (1 - videoCardPreviewMinScale) * animation.value.clamp(0.0, 1.0);
          if (scale >= 1) return child!;
          return Transform(
            key: videoCardTransformKey,
            alignment: Alignment.topLeft,
            filterQuality: FilterQuality.none,
            transform: videoTransitionMatrix(
              Rect.fromCenter(
                center: screen.center(Offset.zero),
                width: screen.width * scale,
                height: screen.height * scale,
              ),
              screen,
              0,
            ),
            child: child,
          );
        }
        // 打开：详情页内容从卡片位置长满全屏。
        // 退出：整屏换成卡片内容（封面），收回到卡片位置。
        final bool closing =
            _committing || animation.status == AnimationStatus.reverse;
        if (closing) {
          final double t = _committing ? _closing.value : animation.value;
          if (t <= 0) return child!;
          final Rect rect = videoTransitionRect(origin, screen, t);
          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: videoTransitionInterval(0.0, 0.55, t),
                child: child,
              ),
              Positioned.fromRect(
                rect: rect,
                child: ClipRRect(
                  key: videoCardCoverKey,
                  borderRadius: BorderRadius.circular(12 * (1 - t)),
                  child: _buildCover(screen),
                ),
              ),
            ],
          );
        }
        final double t = videoCardEntryProgress(animation.value);
        if (t >= 1) return child!;
        final Rect rect = videoTransitionRect(origin, screen, t);
        return Transform(
          key: videoCardTransformKey,
          alignment: Alignment.topLeft,
          // 过渡期间整页在缩放，最近的邻近采样比双线性便宜很多。
          filterQuality: FilterQuality.none,
          transform: videoTransitionMatrix(rect, screen, t),
          child: child,
        );
      },
    );
  }
}
