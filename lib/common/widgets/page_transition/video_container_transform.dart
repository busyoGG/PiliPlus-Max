import 'package:flutter/material.dart';

/// 视频卡片在屏幕上的位置，作为「卡片 → 详情页」过渡动画的起点。
const String videoOriginRectKey = 'originRect';

/// 从路由参数中取出卡片位置，没有（或不是 [Rect]）时返回 null。
Rect? videoOriginRectOf(Object? arguments) {
  final Object? value = switch (arguments) {
    final Map<dynamic, dynamic> map => map[videoOriginRectKey],
    _ => null,
  };
  return value is Rect ? value : null;
}

/// 触发过渡的卡片在屏幕上的位置，取不到时返回 null（此时退回默认转场）。
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

/// 过渡过程中卡片缩略图占据的位置：0 时贴在卡片上，1 时铺满屏幕。
Rect videoTransitionRect(Rect origin, Size screen, double t) {
  return Rect.lerp(origin, Offset.zero & screen, t.clamp(0.0, 1.0))!;
}

/// 缩略图的可见度：先接管画面，铺满屏幕后再淡出露出页面。
double videoTransitionCoverOpacity(double t) {
  return 1.0 - videoTransitionInterval(0.55, 1.0, t);
}

/// 页面内容的可见度：跟随缩略图淡入，避免开场就露出白屏。
double videoTransitionPageOpacity(double t) {
  return videoTransitionInterval(0.35, 1.0, t);
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

/// 视频详情页从卡片位置展开、退出时缩回卡片的转场；
/// 没有带 [videoOriginRectKey] 参数的路由仍交给 [fallback]（预测性返回）。
class VideoContainerTransformBuilder extends PageTransitionsBuilder {
  const VideoContainerTransformBuilder({
    this.fallback = const PredictiveBackPageTransitionsBuilder(),
  });

  final PageTransitionsBuilder fallback;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final arguments = route.settings.arguments;
    final origin = videoOriginRectOf(arguments);
    final cover = switch (arguments) {
      final Map<dynamic, dynamic> map => map['cover'],
      _ => null,
    };
    if (origin == null || cover is! String || cover.isEmpty) {
      return fallback.buildTransitions<T>(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return _VideoContainerTransform(
      animation: animation,
      origin: origin,
      cover: cover,
      child: child,
    );
  }
}

class _VideoContainerTransform extends StatelessWidget {
  const _VideoContainerTransform({
    required this.animation,
    required this.origin,
    required this.cover,
    required this.child,
  });

  final Animation<double> animation;
  final Rect origin;
  final String cover;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, page) {
        final t = Curves.easeOutCubic.transform(animation.value);
        final coverOpacity = videoTransitionCoverOpacity(t);
        return Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: videoTransitionPageOpacity(t),
                child: Transform.scale(scale: 0.96 + 0.04 * t, child: page),
              ),
            ),
            if (coverOpacity > 0.01)
              Positioned.fromRect(
                rect: videoTransitionRect(
                  origin,
                  MediaQuery.sizeOf(context),
                  t,
                ),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: coverOpacity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(
                        Radius.circular(12 * (1 - t)),
                      ),
                      child: Image.network(
                        cover,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
