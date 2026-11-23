import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_device.dart';
import '../app_update.dart';
import '../core_bridge.dart';
import '../local_store.dart';
import 'app_scope.dart';
import 'widgets/focus_ring.dart';

var _checked = false;
const _manualCooldown = Duration(seconds: 30);
DateTime? _lastManualCheck;
AppUpdate? _lastManualUpdate;

enum _UpdateChoice { mute, skip, dismiss, download }

Future<void> runStartupChecks(BuildContext context, LocalStore store) async {
  if (_checked) return;
  _checked = true;
  final repository = AppScope.of(context).repository;
  final abi = AppScope.of(context).abi;
  final String current;
  final AppUpdate update;
  try {
    current = await currentAppVersion();
    if (store.shareUsage) {
      unawaited(repository.reportUsage(current).catchError((_) {}));
    }
    if (!store.checkUpdates) return;
    final latest = await repository.checkUpdate(current, abi: abi);
    if (latest == null) return;
    update = latest;
  } catch (_) {
    return;
  }
  if (update.version == store.ignoredUpdate || !context.mounted) return;
  final choice = await _askUpdate(context, current, update, manual: false);
  switch (choice) {
    case _UpdateChoice.mute:
      await store.setCheckUpdates(false);
    case _UpdateChoice.skip:
      await store.setIgnoredUpdate(update.version);
    case _UpdateChoice.download:
      if (context.mounted) await _downloadAndInstall(context, update);
    case _UpdateChoice.dismiss || null:
      return;
  }
}

Future<void> checkUpdateManually(BuildContext context) async {
  final repository = AppScope.of(context).repository;
  final messenger = ScaffoldMessenger.of(context);
  final abi = AppScope.of(context).abi;
  final String current;
  final AppUpdate? update;
  try {
    current = await currentAppVersion();
    final last = _lastManualCheck;
    if (last != null && DateTime.now().difference(last) < _manualCooldown) {
      update = _lastManualUpdate;
    } else {
      update = await repository.checkUpdate(current, abi: abi);
      _lastManualCheck = DateTime.now();
      _lastManualUpdate = update;
    }
  } catch (failure) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure is AppFailure ? '检查更新失败：$failure' : '检查更新失败，请稍后再试',
        ),
      ),
    );
    return;
  }
  if (update == null) {
    messenger.showSnackBar(const SnackBar(content: Text('已是最新版本')));
    return;
  }
  if (!context.mounted) return;
  final choice = await _askUpdate(context, current, update, manual: true);
  if (choice == _UpdateChoice.download && context.mounted) {
    await _downloadAndInstall(context, update);
  }
}

Future<void> _downloadAndInstall(BuildContext context, AppUpdate update) async {
  if (!Platform.isAndroid) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('仅支持 Android 平台的原生安装')));
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.parse(update.url);

  // 先問儲存權限：取得才順手存一份到公開 Download 供手動安裝後備；
  // 被拒絕或不支援時不阻斷下載與安裝流程。
  final copyToDownloads = await AppDevice.requestStoragePermission();

  messenger.showSnackBar(const SnackBar(content: Text('正在下载更新包...')));

  try {
    final apkFile = File(await AppDevice.apkCachePath());
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      messenger.showSnackBar(
        SnackBar(content: Text('下载失败：${response.statusCode}')),
      );
      return;
    }
    // APK 為 ZIP 封裝，開頭魔數應為 "PK"；攔截誤抓 HTML 頁面的情況
    final bytes = response.bodyBytes;
    final isApk = bytes.length > 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    if (!isApk) {
      messenger.showSnackBar(
        const SnackBar(content: Text('更新失败：下载内容不是有效的 APK')),
      );
      return;
    }
    await apkFile.writeAsBytes(bytes);

    String? savedName;
    if (copyToDownloads) {
      final semanticVersion =
          RegExp(r'\d+\.\d+\.\d+').firstMatch(update.version)?.group(0) ??
          update.version;
      final date = DateTime.now().toIso8601String().substring(0, 10);
      try {
        savedName = await AppDevice.saveApkToDownloads(
          apkPath: apkFile.path,
          name: 'videoapp-$semanticVersion-$date.apk',
        );
      } catch (_) {
        savedName = null;
      }
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          savedName == null
              ? '下载完成，正在安装...'
              : '下载完成，正在安装...\n已另存到 Download 文件夹：$savedName，未自动安装时可手动安装',
        ),
      ),
    );

    // Trigger installation via native code
    await AppDevice.installApk(apkFile.path);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('更新失败：$e')));
  }
}

Future<_UpdateChoice?> _askUpdate(
  BuildContext context,
  String current,
  AppUpdate update, {
  required bool manual,
}) {
  return showDialog<_UpdateChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('发现新版本 ${update.version}'),
      content: Text(
        manual ? '当前版本 $current。' : '当前版本 $current。选「不再提醒」后可在设置 › 关于中重新打开检查更新。',
      ),
      actions: [
        for (final (choice, label) in [
          if (!manual) (_UpdateChoice.mute, '不再提醒'),
          if (!manual) (_UpdateChoice.skip, '忽略此版本'),
          (_UpdateChoice.dismiss, '忽略'),
        ])
          FocusRing(
            radius: 20,
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, choice),
              child: Text(label),
            ),
          ),
        FocusRing(
          radius: 20,
          child: FilledButton(
            autofocus: true,
            onPressed: () =>
                Navigator.pop(dialogContext, _UpdateChoice.download),
            child: const Text('更新'),
          ),
        ),
      ],
    ),
  );
}
