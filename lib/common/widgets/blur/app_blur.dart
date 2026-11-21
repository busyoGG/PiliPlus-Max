import 'dart:ui' show ImageFilter;

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

  /// 播放器控制层的基准 σ。
  static const double playerBarSigma = 18;

  /// 弹层、遮罩的基准 σ。
  static const double sheetSigma = 24;

  /// 毛玻璃底色透明度，越小越透。
  static const double tintAlpha = 0.72;

  /// 当前档位。
  static AppBlurStrength get strength => AppBlurStrength.values[Pref.uiBlur
      .clamp(0, AppBlurStrength.values.length - 1)];

  /// 是否启用毛玻璃。
  static bool get enabled => strength != AppBlurStrength.off;

  /// 当前档位下某个基准 σ 的实际值；关闭时为 0。
  static double sigma(double base) => base * strength.scale;
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
    this.border,
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
  final BoxBorder? border;

  /// 与同一 BackdropGroup 下的其它模糊层共享一次背景采样。
  final bool grouped;

  /// 强度覆盖；不传则跟随设置。测试里用它避开存储初始化。
  final AppBlurStrength? strength;

  @override
  Widget build(BuildContext context) {
    final AppBlurStrength level = strength ?? AppBlur.strength;
    final double s = sigma * level.scale;
    if (s <= 0) {
      return plainChild ?? child;
    }
    final Color base = tint ?? Theme.of(context).colorScheme.surface;
    final Widget tinted = DecoratedBox(
      decoration: BoxDecoration(
        color: base.withValues(alpha: tintAlpha),
        borderRadius: borderRadius,
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
    if (borderRadius == null) {
      return blurred;
    }
    return ClipRRect(borderRadius: borderRadius!, child: blurred);
  }
}
