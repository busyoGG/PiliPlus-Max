import 'dart:ui' show ImageFilter;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 界面模糊的强度档位。
enum AppBlurStrength {
  /// 关闭：退回原来的不透明样式。
  off,

  /// 轻：顶栏/底栏 σ=12。
  light,

  /// 重：σ 翻倍。
  heavy;

  /// 该档位相对基准 σ 的倍率。
  double get scale => switch (this) {
    AppBlurStrength.off => 0,
    AppBlurStrength.light => 1,
    AppBlurStrength.heavy => 2,
  };
}

/// 界面毛玻璃参数的唯一来源。
///
/// 只用于界面装饰层（顶栏、底栏、播放器控条），不碰视频画面。
/// 高斯由引擎实现：降采样 + Y/X 两趟可分离卷积，随 σ 自动放大降采样比例。
abstract final class AppBlur {
  /// 顶栏、底部导航条的基准 σ。
  static const double barSigma = 12;

  /// 顶栏落影（向下）：近处加深 + 远处扩散，避免只有一圈硬边。
  static const List<BoxShadow> barShadow = <BoxShadow>[
    BoxShadow(color: Color(0x29000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: 2,
    ),
  ];

  /// 悬浮底栏胶囊的落影。
  static const List<BoxShadow> navPillShadow = <BoxShadow>[
    BoxShadow(color: Color(0x26000000), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 20,
      offset: Offset(0, 6),
      spreadRadius: 1,
    ),
  ];

  /// 底栏落影（向上）。
  static const List<BoxShadow> barShadowUp = <BoxShadow>[
    BoxShadow(color: Color(0x29000000), blurRadius: 6, offset: Offset(0, -2)),
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 24,
      offset: Offset(0, -8),
      spreadRadius: 2,
    ),
  ];

  /// 播放器控制层的基准 σ。
  static const double playerBarSigma = 18;

  /// 弹层、遮罩的基准 σ。
  static const double sheetSigma = 24;

  /// 毛玻璃底色透明度，越小越透。
  static const double tintAlpha = 0.72;

  /// 当前档位。
  static AppBlurStrength get strength => AppBlurStrength.values[Pref.uiBlur
      .clamp(0, AppBlurStrength.values.length - 1)];

  /// 是否启用毛玻璃：总开关关闭或档位为 off 时不画模糊。
  static bool get enabled =>
      Pref.uiBlurEnabled && strength != AppBlurStrength.off;

  /// 当前档位下某个基准 σ 的实际值；关闭时为 0。
  static double sigma(double base) => enabled ? base * strength.scale : 0;
}

/// 毛玻璃容器：模糊背后内容，再叠加半透明主题色。
///
/// 子组件自身背景必须是透明的，否则会把模糊盖住；
/// 关闭毛玻璃时退回 [plainChild]（不传则原样显示 [child]）。
class BlurSurface extends StatelessWidget {
  const BlurSurface({
    super.key,
    required this.child,
    this.plainChild,
    this.sigma = AppBlur.barSigma,
    this.tint,
    this.tintAlpha = AppBlur.tintAlpha,
    this.borderRadius,
    this.tintRadius,
    this.border,
    this.boxShadow,
    this.grouped = false,
    this.strength,
  });

  /// 模糊开启时显示的内容，背景应为透明。
  final Widget child;

  /// 模糊关闭时显示的内容。
  final Widget? plainChild;

  final double sigma;
  final Color? tint;

  /// 底色透明度，默认跟随 [AppBlur.tintAlpha]；压在视频上时调小。
  final double tintAlpha;

  final BorderRadius? borderRadius;

  /// 只给底色用的圆角（毛玻璃本身仍是方的）。
  ///
  /// 用在「顶栏底部做出圆角、圆角外侧露出模糊内容」的场合：
  /// 采样区域保持矩形，底色才切圆角，切掉的地方就是没染色的模糊画面。
  final BorderRadius? tintRadius;

  final BoxBorder? border;

  /// 落在模糊层外侧的投影，形状跟随圆角。
  final List<BoxShadow>? boxShadow;

  /// 与同一 BackdropGroup 下的其它模糊层共享一次背景采样。
  final bool grouped;

  /// 强度覆盖；不传则跟随设置。测试里用它避开存储初始化。
  final AppBlurStrength? strength;

  @override
  Widget build(BuildContext context) {
    final AppBlurStrength level = strength ?? AppBlur.strength;
    final double s = sigma * level.scale;
    if (s <= 0) {
      final Widget? plain = plainChild;
      if (plain == null || boxShadow == null) {
        return plain ?? child;
      }
      // 关掉模糊也保留落影，顶栏/底栏的层次不能丢。
      return CustomPaint(
        painter: _OuterShadowPainter(borderRadius, boxShadow!),
        child: plain,
      );
    }
    final Color base = tint ?? Theme.of(context).colorScheme.surface;
    // 当前页面被别的路由盖住时（转场、二级页），这张模糊每帧都要重新采样整屏内容，
    // 是转场掉帧的主因；此时不做采样，但也不能让顶栏变透明，用实底色顶上。
    final bool routeActive = ModalRoute.of(context)?.isCurrent ?? true;
    if (!routeActive) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            base.withValues(alpha: tintAlpha),
            Theme.of(context).colorScheme.surface,
          ),
          borderRadius: borderRadius,
          border: border,
          boxShadow: boxShadow,
        ),
        child: child,
      );
    }
    final Widget tinted = DecoratedBox(
      decoration: BoxDecoration(
        color: base.withValues(alpha: tintAlpha),
        borderRadius: tintRadius ?? borderRadius,
        border: border,
      ),
      child: child,
    );
    final ImageFilter filter = ImageFilter.blur(
      sigmaX: s,
      sigmaY: s,
      tileMode: TileMode.clamp,
    );
    final Widget blurred = grouped
        ? BackdropFilter.grouped(filter: filter, child: tinted)
        : BackdropFilter(filter: filter, child: tinted);
    // 必须裁到自身范围：BackdropFilter 的采样覆盖区取决于外层裁剪，
    // 不裁的话会把整块背景一起糊掉（而且更贵）。
    final Widget clipped = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: blurred,
    );
    if (boxShadow == null) {
      return clipped;
    }
    // 投影画在裁剪层外侧，否则会被 ClipRRect 一起裁掉。
    return CustomPaint(
      painter: _OuterShadowPainter(borderRadius, boxShadow!),
      child: clipped,
    );
  }
}


/// 只在控件外侧绘制投影，控件自身范围内不落影。
///
/// 毛玻璃是半透明的，BoxDecoration.boxShadow 会透过来把栏内压暗；
/// 这里先用差值路径把自身矩形挖掉，再画模糊后的阴影。
class _OuterShadowPainter extends CustomPainter {
  const _OuterShadowPainter(this.radius, this.shadows);

  final BorderRadius? radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    final RRect inner = (radius ?? BorderRadius.zero).toRRect(bounds);
    canvas
      ..save()
      ..clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(bounds.inflate(160)),
        Path()..addRRect(inner),
        ),
      );
    for (final BoxShadow shadow in shadows) {
      final RRect rrect =
          inner.shift(shadow.offset).inflate(shadow.spreadRadius);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = shadow.color
          ..maskFilter = ui.MaskFilter.blur(
            ui.BlurStyle.normal,
            shadow.blurSigma,
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.shadows != shadows;
}
