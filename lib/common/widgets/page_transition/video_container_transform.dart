import 'package:flutter/material.dart';

/// 打开详情页时随路由传入的卡片矩形参数名。
const String videoOriginRectKey = 'originRect';

/// 详情页从卡片展开/收回用的时长。
const Duration videoCardTransitionDuration = Duration(milliseconds: 320);

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

/// 从卡片矩形展开成整页。
///
/// 只负责「打开详情页」这一层动画，用独立的 [AnimationController] 播放，
/// 不参与路由转场，也不接管返回手势：预测性返回仍然由
/// PredictiveBackPageTransitionsBuilder 全权处理，两套动画互不干扰。
class VideoCardEntryTransform extends StatefulWidget {
  const VideoCardEntryTransform({super.key, required this.child, this.origin});

  final Widget child;

  /// 卡片在屏幕上的矩形，为空时从路由参数 [videoOriginRectKey] 读取。
  final Rect? origin;

  @override
  State<VideoCardEntryTransform> createState() =>
      _VideoCardEntryTransformState();
}

class _VideoCardEntryTransformState extends State<VideoCardEntryTransform>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _progress;
  ModalRoute<dynamic>? _route;
  Rect? _origin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _route = route;
    _origin = widget.origin ?? videoOriginRectOf(route?.settings.arguments);
    if (_origin == null) return;
    final AnimationController controller = AnimationController(
      duration: videoCardTransitionDuration,
      vsync: this,
    );
    _controller = controller;
    _progress = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Rect? origin = _origin;
    final Animation<double>? progress = _progress;
    if (origin == null || progress == null) return widget.child;
    return AnimatedBuilder(
      animation: progress,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double t = progress.value;
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
