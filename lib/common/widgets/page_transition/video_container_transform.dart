import 'package:flutter/material.dart';

/// 视频卡片在屏幕上的位置，作为「卡片 → 详情页」展开动画的起点。
const String videoOriginRectKey = 'originRect';

/// 从路由参数中取出卡片位置，没有（或不是 [Rect]）时返回 null。
Rect? videoOriginRectOf(Object? arguments) {
  final Object? value = switch (arguments) {
    final Map<dynamic, dynamic> map => map[videoOriginRectKey],
    _ => null,
  };
  return value is Rect ? value : null;
}

/// 触发动画的卡片在屏幕上的位置，取不到时返回 null（此时不做展开动画）。
Rect? videoCardRectOf(BuildContext context) {
  try {
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize) {
      return null;
    }
    return object.localToGlobal(Offset.zero) & object.size;
  } catch (_) {
    // 卡片可能已经在异步请求过程中被销毁，退化为默认转场。
    return null;
  }
}

/// 过渡过程中页面内容占据的位置：0 时贴在卡片上，1 时铺满屏幕。
Rect videoTransitionRect(Rect origin, Size screen, double t) {
  return Rect.lerp(origin, Offset.zero & screen, t.clamp(0.0, 1.0))!;
}

/// 页面内容的可见度：开头很快淡入，避免从空白里长出来。
double videoTransitionPageOpacity(double t) {
  return videoTransitionInterval(0.0, 0.15, t);
}

/// 把 [t] 映射到 [begin, end] 区间内的 0~1 进度。
double videoTransitionInterval(double begin, double end, double t) {
  if (t <= begin) {
    return 0;
  }
  if (t >= end) {
    return 1;
  }
  return (t - begin) / (end - begin);
}

/// 页面展开的进度：只在「打开」时生效。
///
/// 返回时 [Animation.status] 变为 [AnimationStatus.reverse]，此时直接返回 1，
/// 由系统预测性返回 / 默认转场接管退出动画，两者不会互相干扰。
double videoTransitionEntryProgress(Animation<double> animation) {
  if (animation.status == AnimationStatus.reverse) {
    return 1;
  }
  return Curves.easeOutCubic.transform(animation.value.clamp(0.0, 1.0));
}

/// 把整页内容按比例压进 [rect]，[t] 到 1 时恢复原尺寸。
Matrix4 videoTransitionMatrix(Rect rect, Size screen, double t) {
  if (t >= 1) {
    return Matrix4.identity();
  }
  return Matrix4.identity()
    ..translateByDouble(rect.left, rect.top, 0.0, 1.0)
    ..scaleByDouble(
      rect.width / screen.width,
      rect.height / screen.height,
      1.0,
      1.0,
    );
}

/// 让详情页内容从视频卡片的位置展开：整页内容按比例压进卡片矩形，再放大到全屏。
///
/// 卡片位置由发起跳转的一方通过路由参数 [videoOriginRectKey] 传入；
/// 没有该参数时保持原样，完全不影响预测性返回。
class VideoCardEntryTransform extends StatefulWidget {
  const VideoCardEntryTransform({super.key, required this.child, this.origin});

  final Widget child;

  /// 显式指定卡片位置，默认从当前路由参数里取（测试用）。
  final Rect? origin;

  @override
  State<VideoCardEntryTransform> createState() => _VideoCardEntryTransformState();
}

class _VideoCardEntryTransformState extends State<VideoCardEntryTransform> {
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final animation = route?.animation;
    final origin =
        widget.origin ?? videoOriginRectOf(route?.settings.arguments);
    if (origin == null || animation == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: animation,
      child: widget.child,
      builder: (context, child) {
        final t = videoTransitionEntryProgress(animation);
        final size = MediaQuery.sizeOf(context);
        final rect = videoTransitionRect(origin, size, t);
        return ClipRRect(
          clipBehavior: t >= 1 ? Clip.none : Clip.antiAlias,
          borderRadius: BorderRadius.all(Radius.circular(12 * (1 - t))),
          child: Opacity(
            opacity: videoTransitionPageOpacity(t),
            child: Transform(
              alignment: Alignment.topLeft,
              transform: videoTransitionMatrix(rect, size, t),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
