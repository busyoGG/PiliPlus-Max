import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

/// 打开详情页时随路由传入的卡片矩形参数名。
const String videoOriginRectKey = 'originRect';

/// 页面形变矩阵所在 Transform 的 key，便于测试定位。
const Key videoCardTransformKey = Key('videoCardTransform');

/// 详情页展开/收起的时长。
const Duration videoCardTransitionDuration = Duration(milliseconds: 380);

/// 返回手势提交后，收起动画走完再 pop 的时长。
const Duration videoCardCollapseDuration = Duration(milliseconds: 200);

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
double videoTransitionPageOpacity(double t) =>
    videoTransitionInterval(0.0, 0.15, t);

/// 页面左上角对齐 [rect] 左上角的等比缩放矩阵。
///
/// 等比缩放保证页面内容不变形；配合 [rect] 裁剪，视觉上就是从卡片里长出来。
Matrix4 videoTransitionMatrix(Rect rect, Size screen, double t) {
  if (t >= 1) return Matrix4.identity();
  final double scale = rect.width / screen.width;
  return Matrix4.identity()
    ..translateByDouble(rect.left, rect.top, 0.0, 1.0)
    ..scaleByDouble(scale, scale, 1.0, 1.0);
}

/// 带卡片矩形的路由专用转场。
///
/// 这一层把路由自带的转场让出来（返回 child，不加任何缩放/淡入），
/// 页面展开、返回手势预览、收起都由 [VideoCardEntryTransform] 自己驱动，
/// 因此不会出现「两套动画叠加导致效果被冲淡」。
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

/// 页面内容在卡片矩形与全屏之间变化，并负责返回手势的预测性返回预览。
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
  late final AnimationController _controller;
  late final Animation<double> _progress;

  ModalRoute<dynamic>? _route;
  Rect? _origin;

  /// 手势进行中：进度直接跟手指走，不再套缓动曲线。
  bool _gestureActive = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: videoCardTransitionDuration,
      vsync: this,
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
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
    if (_origin == null) return;
    // 等页面完成第一帧再开始，避免首帧渲染耗时把动画吃掉大半。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_gestureActive) _controller.forward();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
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

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!_canHandleBackGesture) return false;
    _controller.stop();
    setState(() => _gestureActive = true);
    _controller.value = 1 - backEvent.progress;
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_gestureActive) return;
    _controller.value = 1 - backEvent.progress;
  }

  @override
  void handleCancelBackGesture() {
    if (!_gestureActive) return;
    setState(() => _gestureActive = false);
    _controller.animateTo(1, duration: videoCardCollapseDuration);
  }

  @override
  void handleCommitBackGesture() {
    if (!_gestureActive) return;
    setState(() => _gestureActive = false);
    // 先收起回卡片，再真正 pop，避免路由转场和收起动画叠在一起。
    _controller
        .animateTo(0, duration: videoCardCollapseDuration)
        .whenComplete(() {
          if (mounted) _route?.navigator?.pop();
        });
  }

  @override
  Widget build(BuildContext context) {
    final Rect? origin = _origin;
    if (origin == null) return widget.child;
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = _gestureActive
            ? _controller.value
            : _progress.value;
        if (t >= 1) return child!;
        final Size screen = MediaQuery.sizeOf(context);
        final Rect rect = videoTransitionRect(origin, screen, t);
        final double radius = 12 * (1 - t);
        return ClipRRect(
          clipBehavior: Clip.antiAlias,
          clipper: _RectClipper(
            RRect.fromRectAndRadius(rect, Radius.circular(radius)),
          ),
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          child: Opacity(
            opacity: videoTransitionPageOpacity(t),
            child: Transform(
              key: videoCardTransformKey,
              alignment: Alignment.topLeft,
              transform: videoTransitionMatrix(rect, screen, t),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _RectClipper extends CustomClipper<RRect> {
  const _RectClipper(this.rect);

  final RRect rect;

  @override
  RRect getClip(Size size) => rect;

  @override
  bool shouldReclip(_RectClipper oldClipper) => oldClipper.rect != rect;
}
