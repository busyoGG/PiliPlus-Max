import 'dart:io' show Platform;

import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:nm/nm.dart';

abstract final class ConnectivityUtils {
  static bool? _cachedIsWiFi;
  static DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(seconds: 30);

  /// 起播路径会马上用到网络类型，开机预热一次可省掉平台通道的首次往返。
  static Future<void> warmUp() async {
    await isWiFi;
  }

  static Future<bool> get isWiFi async {
    final cached = _cachedIsWiFi;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }
    try {
      final result =
          PlatformUtils.isMobile &&
          (await Connectivity().checkConnectivity()).contains(
            ConnectivityResult.wifi,
          );
      _cachedIsWiFi = result;
      _cachedAt = DateTime.now();
      return result;
    } catch (_) {
      return true;
    }
  }
}
