import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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
  final String current;
  final AppUpdate update;
  try {
    current = await currentAppVersion();
    if (store.shareUsage) {
      unawaited(repository.reportUsage(current).catchError((_) {}));
    }
    if (!store.checkUpdates) return;
    final latest = await repository.checkUpdate(current);
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
      if (context.mounted) await _downloadAndInstall(context, update.url);
    case _UpdateChoice.dismiss || null:
      return;
  }
}

Future<void> checkUpdateManually(BuildContext context) async {
  final repository = AppScope.of(context).repository;
  final messenger = ScaffoldMessenger.of(context);
  final String current;
  final AppUpdate? update;
  try {
    current = await currentAppVersion();
    final last = _lastManualCheck;
    if (last != null && DateTime.now().difference(last) < _manualCooldown) {
      update = _lastManualUpdate;
    } else {
      update = await repository.checkUpdate(current);
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
    await _downloadAndInstall(context, update.url);
  }
}

Future<void> _downloadAndInstall(BuildContext context, String url) async {
  if (!Platform.isAndroid) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('仅支持 Android 平台的原生安装')));
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.parse(url);
  final fileName =
      'videoapp-${DateTime.now().toIso8601String().substring(0, 10)}.apk';

  // Download APK
  messenger.showSnackBar(const SnackBar(content: Text('正在下载更新包...')));

  try {
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      messenger.showSnackBar(
        SnackBar(content: Text('下载失败：${response.statusCode}')),
      );
      return;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final apkFile = File('${appDir.path}/$fileName');
    await apkFile.writeAsBytes(response.bodyBytes);

    messenger.showSnackBar(const SnackBar(content: Text('下载完成，正在安装...')));

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
