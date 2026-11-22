import 'dart:async';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core_bridge.dart';
import 'diary_service.dart';
import 'platform_capabilities.dart';

/// 原生侧主动回调（duanju/device 通道）的处理函数签名。
typedef DeviceCallHandler = Future<void> Function(MethodCall call);

class AppDevice {
  const AppDevice({this.television = false, this.version = ''});
  final bool television;
  final String version;
  static const channel = MethodChannel('duanju/device');
  static var _televisionMode = false;
  static var _phoneMode = false;

  static Future<AppDevice> detect({
    AppDevice fallback = const AppDevice(),
  }) async {
    if (!PlatformCapabilities.isAndroid) {
      try {
        final info = await PackageInfo.fromPlatform();
        return AppDevice(version: info.version);
      } catch (_) {
        DiaryService.add('[AppDevice] 裝置偵測失敗，使用 fallback');
        return fallback;
      }
    }
    try {
      final data = await channel
          .invokeMapMethod<String, dynamic>('deviceInfo')
          .timeout(const Duration(seconds: 2));
      final television = data?['television'];
      if (television is! bool) return fallback;
      final version = data?['version'];
      return AppDevice(
        television: television,
        version: version is String && version.isNotEmpty
            ? version
            : fallback.version,
      );
    } on PlatformException {
      return fallback;
    } on MissingPluginException {
      return fallback;
    } on TimeoutException {
      return fallback;
    }
  }

  static Future<bool> compatibleRendering() async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      return await channel.invokeMethod<bool>('compatibleRendering') ?? false;
    } catch (_) {
      DiaryService.add('[AppDevice] compatibleRendering 讀取失敗');
      return false;
    }
  }

  /// duanju/device 通道的原生主动回调统一分发：
  /// 多个模块共用一条通道，各自 setMethodCallHandler 会互相覆盖。
  static final List<DeviceCallHandler> _deviceHandlers = [];
  static bool _deviceHandlerInstalled = false;

  static void addDeviceHandler(DeviceCallHandler handler) {
    _deviceHandlers.add(handler);
    _installDeviceHandler();
  }

  static void removeDeviceHandler(DeviceCallHandler handler) {
    _deviceHandlers.remove(handler);
  }

  static void _installDeviceHandler() {
    if (_deviceHandlerInstalled || _deviceHandlers.isEmpty) return;
    try {
      channel.setMethodCallHandler((call) async {
        for (final handler in List.of(_deviceHandlers)) {
          try {
            await handler(call);
          } catch (_) {}
        }
      });
      _deviceHandlerInstalled = true;
    } catch (_) {
      // Binary messenger 尚未初始化（如纯 Dart 测试环境），待下次注册时重试。
    }
  }

  /// 音频焦点变化码（与原生 AudioManager 一致）。
  static const audioFocusGain = 1;
  static const audioFocusLoss = -1;
  static const audioFocusLossTransient = -2;
  static const audioFocusLossTransientCanDuck = -3;

  /// 请求音频焦点（仅 Android 生效），返回是否获得。
  static Future<bool> requestAudioFocus() async {
    if (!PlatformCapabilities.isAndroid) return true;
    try {
      return await channel.invokeMethod<bool>('requestAudioFocus') ?? false;
    } catch (_) {
      DiaryService.add('[AppDevice] requestAudioFocus 失敗');
      return false;
    }
  }

  /// 归还音频焦点（仅 Android 生效）。
  static Future<void> abandonAudioFocus() async {
    if (!PlatformCapabilities.isAndroid) return;
    try {
      await channel.invokeMethod<void>('abandonAudioFocus');
    } catch (_) {}
  }

  static Future<bool> setCompatibleRendering(bool enabled) async {
    if (!PlatformCapabilities.isAndroid) return false;
    try {
      await channel.invokeMethod('setCompatibleRendering', {
        'enabled': enabled,
      });
      return true;
    } catch (_) {
      DiaryService.add('[AppDevice] setCompatibleRendering 失敗');
      return false;
    }
  }

  static Future<void> setTelevisionMode(bool enabled) async {
    if (PlatformCapabilities.isIOS) {
      _televisionMode = enabled;
      return setPlayerOrientation(PlayerOrientation.auto);
    }
    if (!PlatformCapabilities.isAndroid) return;
    try {
      await channel.invokeMethod<void>('setTelevisionMode', {
        'enabled': enabled,
      });
    } catch (_) {
      DiaryService.add('[AppDevice] setTelevisionMode 失敗');
    }
  }

  static Future<void> setPhoneMode(bool enabled) {
    _phoneMode = enabled;
    return releaseOrientation();
  }

  static Future<void> releaseOrientation() => setPlayerOrientation(
    _phoneMode ? PlayerOrientation.lockedPortrait : PlayerOrientation.auto,
  );

  static Future<void> setPlayerOrientation(
    PlayerOrientation orientation,
  ) async {
    if (PlatformCapabilities.isAndroid) {
      try {
        await channel.invokeMethod<void>('setPlayerOrientation', {
          'mode': orientation.name,
        });
      } catch (_) {
        DiaryService.add('[AppDevice] setPlayerOrientation 失敗');
      }
      return;
    }
    try {
      await SystemChrome.setPreferredOrientations(switch (_televisionMode
          ? PlayerOrientation.landscape
          : orientation) {
        PlayerOrientation.landscape ||
        PlayerOrientation.lockedLandscape => const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        PlayerOrientation.portrait || PlayerOrientation.lockedPortrait =>
          const [DeviceOrientation.portraitUp],
        PlayerOrientation.auto => const [],
      });
    } catch (_) {
      DiaryService.add('[AppDevice] setPreferredOrientations 失敗');
    }
  }

  static Future<double?> brightness() async {
    try {
      return await channel.invokeMethod<double>('getBrightness');
    } catch (_) {
      DiaryService.add('[AppDevice] getBrightness 失敗');
      return null;
    }
  }

  static Future<void> setBrightness(double value) async {
    try {
      await channel.invokeMethod<void>('setBrightness', {'brightness': value});
    } catch (_) {
      DiaryService.add('[AppDevice] setBrightness 失敗');
    }
  }

  static Future<void> resetBrightness() async {
    try {
      await channel.invokeMethod<void>('resetBrightness');
    } catch (_) {}
  }

  static Future<double?> volume() async {
    try {
      return await channel.invokeMethod<double>('volume');
    } catch (_) {
      DiaryService.add('[AppDevice] getVolume 失敗');
      return null;
    }
  }

  static Future<void> setVolume(double value) async {
    try {
      await channel.invokeMethod<void>('setVolume', {'volume': value});
    } catch (_) {
      DiaryService.add('[AppDevice] setVolume 失敗');
    }
  }

  static Future<String?> createDocument(String name, String mimeType) async {
    try {
      return await channel.invokeMethod<String>('createDocument', {
        'name': name,
        'mimeType': mimeType,
      });
    } on PlatformException catch (error) {
      throw AppFailure(error.message ?? '无法创建文件');
    }
  }

  static Future<bool> requestVideoExport() async {
    try {
      return await channel.invokeMethod<bool>('requestVideoExport') ?? false;
    } on PlatformException catch (error) {
      throw AppFailure(error.message ?? '无法申请存储权限');
    }
  }

  static Future<void> exportVideo(
    String source,
    String folder,
    String name,
  ) async {
    try {
      await channel.invokeMethod<void>('exportVideo', {
        'source': source,
        'folder': folder,
        'name': name,
      });
    } on PlatformException catch (error) {
      throw AppFailure(error.message ?? '导出失败');
    }
  }

  static Future<void> deleteDocument(String uri) async {
    try {
      await channel.invokeMethod<bool>('deleteDocument', {'uri': uri});
    } catch (_) {
      DiaryService.add('[AppDevice] deleteDocument 失敗');
    }
  }

  static Future<({int level, bool charging})?> battery() async {
    try {
      final data = await channel.invokeMapMethod<String, dynamic>('battery');
      final level = data?['level'];
      if (level is! int) return null;
      return (level: level, charging: data?['charging'] == true);
    } catch (_) {
      DiaryService.add('[AppDevice] battery 讀取失敗');
      return null;
    }
  }

  static Future<void> installApk(String apkPath) async {
    if (!PlatformCapabilities.isAndroid) return;
    try {
      await channel.invokeMethod<void>('installApk', {'path': apkPath});
    } catch (e) {
      DiaryService.add('[AppDevice] installApk 失敗: $e');
      rethrow;
    }
  }
}

enum PlayerOrientation {
  landscape,
  lockedLandscape,
  portrait,
  lockedPortrait,
  auto,
}
