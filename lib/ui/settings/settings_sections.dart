import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_build.dart';
import '../../app_device.dart';
import '../../core_bridge.dart';
import '../../download_preferences.dart';
import '../../local_store.dart';
import '../../playback_preferences.dart';
import '../../resource_settings.dart';
import '../../resource_settings_editor.dart';
import '../../window_on_top.dart';
import '../app_scope.dart';
import '../player/danmaku_settings.dart';
import '../update_prompt.dart';
import '../users/users_view.dart';
import '../widgets/focus_ring.dart';
import '../widgets/form_text_field.dart';
import '../widgets/group_card.dart';
import '../../lan_sync.dart';
import 'appearance_settings.dart';
import 'backup_actions.dart';
import 'diary_view.dart';
import 'settings_rows.dart';
import 'storage_view.dart';

enum SettingsGroup {
  appearance('外观', Icons.palette_outlined),
  playback('播放', Icons.play_arrow_rounded),
  danmaku('弹幕', Icons.subtitles_outlined),
  download('下载', Icons.download_rounded),
  storage('存储', Icons.folder_outlined),
  proxy('代理', Icons.language_rounded),
  users('用户', Icons.manage_accounts_outlined),
  about('关于', Icons.info_outline_rounded),
  diagnostics('诊断', Icons.receipt_long_outlined),
  lanSync('区域网同步', Icons.wifi_tethering_rounded);

  const SettingsGroup(this.label, this.icon);
  final String label;
  final IconData icon;
}

typedef OpenSubpage = void Function(String title, WidgetBuilder body);

const adminOnly = '需要管理员';
const _noDownload = '当前用户没有下载权限';
const _proxyModes = {'auto': '自动', 'direct': '直连', 'manual': '手动代理'};
const _counts = {1: '1', 2: '2', 3: '3', 4: '4', 5: '5', 6: '6'};
const _segmentCounts = {
  1: '1',
  2: '2',
  3: '3',
  4: '4',
  5: '5',
  6: '6',
  7: '7',
  8: '8',
};
const _prefetchLimits = {4194304: '4 MB', 8388608: '8 MB', 16777216: '16 MB'};
const _preloadCounts = {1: '1 集', 2: '2 集', 3: '3 集', 4: '4 集', 5: '5 集'};
const _decoders = {
  TelevisionDecoder.optimized: '默认',
  TelevisionDecoder.hardware: '硬解（兼容）',
  TelevisionDecoder.software: '软解（兼容）',
};
const _bufferSizes = {32: '32 MB', 64: '64 MB', 128: '128 MB', 256: '256 MB'};
const _cacheSizes = {
  null: '關閉',
  64: '64 MB',
  100: '100 MB',
  200: '200 MB',
  400: '400 MB',
};
const _networkTimeouts = {10: '10 秒', 20: '20 秒', 30: '30 秒', 60: '60 秒'};
const _decoderThreads = {
  0: '自動',
  1: '1 執行緒',
  2: '2 執行緒',
  4: '4 執行緒',
  8: '8 執行緒',
};
const _colormatrixs = {
  'auto': '自動',
  'bt601': 'BT.601',
  'bt709': 'BT.709',
  'bt2020': 'BT.2020',
};
const _links = [
  [
    ('GitHub · 重建版', String.fromEnvironment('PROJECT_URL')),
    ('GitHub · 原作者', 'https://github.com/fish2018'),
  ],
  [
    ('Telegram · 交流群组', String.fromEnvironment('TELEGRAM_GROUP_URL')),
    ('Telegram · 更新频道', String.fromEnvironment('TELEGRAM_CHANNEL_URL')),
  ],
];

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.group,
    required this.store,
    required this.editor,
    required this.open,
  });
  final SettingsGroup group;
  final LocalStore store;
  final ResourceSettingsEditor editor;
  final OpenSubpage open;

  Future<void> _saveResource(BuildContext context, ResourceSettings settings) =>
      saveSetting(context, () => editor.save(settings));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, editor]),
    builder: (context, _) => group == SettingsGroup.appearance
        ? AppearanceSettings(store: store)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: switch (group) {
              SettingsGroup.playback => _playback(context),
              SettingsGroup.danmaku => _danmaku(context),
              SettingsGroup.download => _download(context),
              SettingsGroup.storage => _storage(),
              SettingsGroup.proxy => _proxy(context),
              SettingsGroup.users => [UsersView(store: store, open: open)],
              SettingsGroup.about => _about(context),
              SettingsGroup.diagnostics => _diagnostics(),
              SettingsGroup.lanSync when Platform.isAndroid => _lanSync(
                context,
                store,
              ),
              _ => const [],
            },
          ),
  );

  Widget? _editorError() => switch (editor.error) {
    final error? => SettingsTile(
      title: '无法读取网络与下载设置',
      subtitle: error,
      trailing: const Icon(Icons.refresh_rounded),
      onTap: editor.load,
    ),
    null => null,
  };

  List<Widget> _danmaku(BuildContext context) {
    final preferences = store.playbackPreferences;
    void savePreferences(PlaybackPreferences next) =>
        saveSetting(context, () => store.setPlaybackPreferences(next));
    return [
      SettingsCard(
        children: [
          SwitchTile(
            title: '显示弹幕',
            subtitle: '与播放页的弹幕开关同步',
            value: preferences.danmaku,
            onChanged: (value) =>
                savePreferences(preferences.copyWith(danmaku: value)),
          ),
        ],
      ),
      SettingsCard(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: DanmakuSettings(
              preferences: preferences,
              save: savePreferences,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _playback(BuildContext context) {
    final preferences = store.playbackPreferences;
    final television = AppScope.of(context).television;
    void savePreferences(PlaybackPreferences next) =>
        saveSetting(context, () => store.setPlaybackPreferences(next));
    return [
      SettingsCard(
        children: [
          ValueTile<double>(
            title: '默认倍速',
            subtitle: '与播放器内设置同步',
            options: {for (final speed in playbackSpeeds) speed: '${speed}x'},
            value: preferences.speed,
            onChanged: (speed) =>
                savePreferences(preferences.copyWith(speed: speed)),
          ),
          ValueTile<double>(
            title: '长按倍速',
            subtitle: '按住画面或方向键时临时使用的倍速',
            options: {for (final speed in boostSpeeds) speed: '${speed}x'},
            value: preferences.boostSpeed,
            onChanged: (speed) =>
                savePreferences(preferences.copyWith(boostSpeed: speed)),
          ),
          ValueTile<int>(
            title: '默认清晰度',
            subtitle: '指定清晰度不可用时，使用源站可用画质',
            options: {
              for (final quality in {
                ...DownloadPreferences.qualities,
                preferences.quality,
              }.toList()..sort((a, b) => b - a))
                quality: quality == 0 ? '自动（优先高清）' : '${quality}P',
            },
            value: preferences.quality,
            onChanged: (quality) =>
                savePreferences(preferences.copyWith(quality: quality)),
          ),
        ],
      ),
      SettingsCard(
        children: [
          ValueTile<TelevisionDecoder>(
            title: '解码方式',
            subtitle: '有声音没画面或卡顿时可换兼容方式，下次打开视频时生效',
            options: _decoders,
            value: preferences.televisionDecoder,
            onChanged: (decoder) => savePreferences(
              preferences.copyWith(televisionDecoder: decoder),
            ),
          ),
          if (Platform.isAndroid) const _RenderingTile(),
          SwitchTile(
            title: '预开下一集',
            subtitle: '提前打开下一集的播放器，切集无需等待',
            value: preferences.preopens(television: television),
            onChanged: (value) =>
                savePreferences(preferences.copyWith(preopen: value)),
          ),
        ],
      ),
      if ((Platform.isAndroid || Platform.isIOS) && !television)
        SettingsCard(
          children: [
            SwitchTile(
              title: '双击快退/快进',
              subtitle: '左侧双击快退，右侧双击快进，关闭时均为暂停',
              value: preferences.doubleTapSeek,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(doubleTapSeek: value)),
            ),
            SwitchTile(
              title: '滑动调节亮度/音量',
              subtitle: '左侧上下滑动调整亮度，右侧上下滑动调整音量',
              value: preferences.swipeLevels,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(swipeLevels: value)),
            ),
            SwitchTile(
              title: '上下滑动切换剧集',
              subtitle: preferences.swipeLevels
                  ? '需先关闭滑动调节亮度/音量'
                  : '横屏全屏时上滑播放下一集，下滑播放上一集',
              value: preferences.swipeEpisodes,
              onChanged: preferences.swipeLevels
                  ? null
                  : (value) => savePreferences(
                      preferences.copyWith(swipeEpisodes: value),
                    ),
            ),
            SwitchTile(
              title: '竖屏自动隐藏播控',
              subtitle: '竖屏播放几秒后隐藏标题、进度条和选集，单击暂停时重新显示',
              value: preferences.autoHideControls,
              onChanged: (value) => savePreferences(
                preferences.copyWith(autoHideControls: value),
              ),
            ),
            SwitchTile(
              title: '状态栏跟随播控隐藏',
              subtitle: preferences.autoHideControls
                  ? '播控隐藏时一起收起系统状态栏和导航栏'
                  : '需先打开竖屏自动隐藏播控',
              value: preferences.hideSystemBars,
              onChanged: preferences.autoHideControls
                  ? (value) => savePreferences(
                      preferences.copyWith(hideSystemBars: value),
                    )
                  : null,
            ),
            SwitchTile(
              title: '横屏视频也使用竖屏样式',
              subtitle: '竖屏观看横屏视频时画面居中，上下滑动切集，点选集右边的按钮进入全屏',
              value: preferences.portraitStyleForWide,
              onChanged: (value) => savePreferences(
                preferences.copyWith(portraitStyleForWide: value),
              ),
            ),
            SwitchTile(
              title: '横屏底部进度线',
              subtitle: '横屏全屏播控隐藏后，在画面底边保留一条细进度线',
              value: preferences.progressLine,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(progressLine: value)),
            ),
          ],
        ),
      SettingsCard(
        children: [
          SwitchTile(
            title: '预加载下一集',
            subtitle: '播放时提前准备下一集地址并预取开头片段，切集更快',
            value: preferences.preload,
            onChanged: (value) =>
                savePreferences(preferences.copyWith(preload: value)),
          ),
          SwitchTile(
            title: '预载为完整下载',
            subtitle: preferences.preloadDownload
                ? '按观看顺序把接下来的集数提前下载到下载目录，弱网或断网也能连续观看'
                : '开启后预载改为完整下载到磁盘，需要较多存储空间与流量',
            value: preferences.preloadDownload,
            onChanged: (value) =>
                savePreferences(preferences.copyWith(preloadDownload: value)),
          ),
          ValueTile<int>(
            title: '预加载集数',
            subtitle: !preferences.preload
                ? '需先打开预加载下一集'
                : preferences.preloadDownload
                ? '按观看顺序把接下来的集数加入下载队列'
                : '按观看顺序依次预载接下来的集数，占用较多网络与内存',
            options: _preloadCounts,
            value: preferences.preloadCount,
            onChanged: preferences.preload
                ? (value) =>
                      savePreferences(preferences.copyWith(preloadCount: value))
                : null,
          ),
          SwitchTile(
            title: '全屏显示时间',
            subtitle: '全屏播放时在画面顶部显示当前时间',
            value: preferences.showClock,
            onChanged: (value) =>
                savePreferences(preferences.copyWith(showClock: value)),
          ),
          SwitchTile(
            title: '全屏显示网速',
            subtitle: '全屏播放时在画面顶部显示当前下载速度',
            value: preferences.showNetworkSpeed,
            onChanged: (value) =>
                savePreferences(preferences.copyWith(showNetworkSpeed: value)),
          ),
        ],
      ),
      if (television)
        SettingsCard(
          children: [
            SwitchTile(
              title: '電視端保守模式',
              subtitle: '開啟後降低記憶體與運算負載，適用於較舊的電視或機頂盒，下次播放時生效',
              value: preferences.conservativeMode,
              onChanged: (value) => savePreferences(
                preferences.copyWith(conservativeMode: value),
              ),
            ),
          ],
        ),
      SettingsCard(
        children: [
          SwitchTile(
            title: '啟用進階播放器優化',
            subtitle: '預設關閉，開啟後可調整網路超時、解碼執行緒、色彩空間、色調映射、縮放濾鏡、隔行處理與銳化降噪等參數',
            value: preferences.enableMpvAdvanced,
            onChanged: (value) =>
                savePreferences(preferences.copyWith(enableMpvAdvanced: value)),
          ),
          ValueTile<int?>(
            title: '網路快取大小',
            subtitle: '關閉時使用播放器內建預設快取，開啟後可指定快取大小',
            options: _cacheSizes,
            value: preferences.cacheSize,
            onChanged: (value) =>
                savePreferences(preferences.copyWith(cacheSize: value)),
          ),
          if (preferences.enableMpvAdvanced) ...[
            ValueTile<int>(
              title: '播放器緩衝大小',
              subtitle: '播放器緩衝池大小，越大啟動越穩定，佔用記憶體越多',
              options: _bufferSizes,
              value: preferences.bufferSize,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(bufferSize: value)),
            ),
            ValueTile<int>(
              title: '網路超時時間',
              subtitle: '解析播放地址時的等待超時秒數',
              options: _networkTimeouts,
              value: preferences.networkTimeout,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(networkTimeout: value)),
            ),
            ValueTile<int>(
              title: '解碼執行緒數',
              subtitle: '0 為自動，適合多核裝置提升解碼效率',
              options: _decoderThreads,
              value: preferences.decoderThreads,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(decoderThreads: value)),
            ),
            ValueTile<String>(
              title: '色彩空間',
              subtitle: '影片色彩空間解碼標準，自動通常即可',
              options: _colormatrixs,
              value: preferences.colormatrix,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(colormatrix: value)),
            ),
            SwitchTile(
              title: 'HDR 色調映射',
              subtitle: '開啟後可改善 HDR 影片色彩，較耗 GPU 效能',
              value: preferences.tonemapping,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(tonemapping: value)),
            ),
            SwitchTile(
              title: '高品質縮放濾鏡',
              subtitle: '使用 spline36 縮放濾鏡，畫質較佳但較耗效能',
              value: preferences.highQualityScaling,
              onChanged: (value) => savePreferences(
                preferences.copyWith(highQualityScaling: value),
              ),
            ),
            SwitchTile(
              title: '隔行處理',
              subtitle: '針對隔行源影片進行處理，較舊影片可開啟',
              value: preferences.deinterlace,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(deinterlace: value)),
            ),
            SwitchTile(
              title: '銳化與降噪',
              subtitle: '輕微銳化與降噪，改善低畫質來源觀感，較耗效能',
              value: preferences.sharpenDenoise,
              onChanged: (value) =>
                  savePreferences(preferences.copyWith(sharpenDenoise: value)),
            ),
          ],
        ],
      ),
      SettingsCard(
        children: [
          SwitchTile(
            title: '离开应用时自动小窗',
            subtitle: '播放中回到桌面时自动进入画中画',
            value: preferences.autoPictureInPicture,
            onChanged: (value) => savePreferences(
              preferences.copyWith(autoPictureInPicture: value),
            ),
          ),
        ],
      ),
      if (Platform.isWindows || Platform.isMacOS)
        SettingsCard(
          children: [
            ValueListenableBuilder(
              valueListenable: windowOnTop,
              builder: (context, enabled, _) => SwitchTile(
                title: '窗口置顶',
                subtitle: '窗口始终显示在其他窗口上方，重启应用后仍然生效',
                value: enabled,
                onChanged: (value) =>
                    saveSetting(context, () => setWindowOnTop(value)),
              ),
            ),
          ],
        ),
    ];
  }

  List<Widget> _download(BuildContext context) {
    final canDownload = store.canDownload;
    final admin = store.profile.admin;
    final preferences = store.downloadPreferences;
    final settings = editor.settings;
    final editable = settings != null && !editor.saving;
    void savePreferences(DownloadPreferences next) =>
        saveSetting(context, () => store.setDownloadPreferences(next));
    return [
      SettingsCard(
        children: [
          ValueTile<int>(
            title: '默认画质',
            subtitle: canDownload ? '指定画质不可用时，使用源站可用画质' : _noDownload,
            options: {
              for (final quality in DownloadPreferences.qualities)
                quality: quality == 0 ? '自动（优先高清）' : '${quality}P',
            },
            value: preferences.quality,
            onChanged: canDownload
                ? (quality) =>
                      savePreferences(preferences.copyWith(quality: quality))
                : null,
          ),
          SwitchTile(
            title: '默认包含 VIP 集',
            subtitle: canDownload ? 'VIP 集可能仅提供试看内容，下载前仍可调整选择' : _noDownload,
            value: preferences.includeVip,
            onChanged: canDownload
                ? (value) =>
                      savePreferences(preferences.copyWith(includeVip: value))
                : null,
          ),
        ],
      ),
      SettingsCard(
        children: [
          ?_editorError(),
          ValueTile<int>(
            title: '同时下载数量',
            subtitle: admin ? null : adminOnly,
            options: _counts,
            value: settings?.downloadConcurrency,
            onChanged: editable
                ? (value) => _saveResource(
                    context,
                    settings.copyWith(downloadConcurrency: value),
                  )
                : null,
          ),
          ValueTile<int>(
            title: '分片下载并行数',
            subtitle: admin ? '单集内视频分片的同时下载数量，源站限速时可调低' : adminOnly,
            options: _segmentCounts,
            value: settings?.downloadSegmentConcurrency,
            onChanged: editable
                ? (value) => _saveResource(
                    context,
                    settings.copyWith(downloadSegmentConcurrency: value),
                  )
                : null,
          ),
          ValueTile<int>(
            title: '预取大小',
            subtitle: admin ? '预加载下一集时预先缓冲的数据量' : adminOnly,
            options: _prefetchLimits,
            value: settings?.prefetchLimit,
            onChanged: editable
                ? (value) => _saveResource(
                    context,
                    settings.copyWith(prefetchLimit: value),
                  )
                : null,
          ),
          ValueTile<int>(
            title: '同时请求数量',
            subtitle: admin ? '浏览目录时同时请求站源的数量' : adminOnly,
            options: _counts,
            value: settings?.catalogConcurrency,
            onChanged: editable
                ? (value) => _saveResource(
                    context,
                    settings.copyWith(catalogConcurrency: value),
                  )
                : null,
          ),
          SwitchTile(
            title: '按站源分类保存',
            subtitle: admin ? '新任务放入各站源的子目录，已有下载继续使用原位置' : adminOnly,
            value: settings?.downloadBySource ?? false,
            onChanged: editable
                ? (value) => _saveResource(
                    context,
                    settings.copyWith(downloadBySource: value),
                  )
                : null,
          ),
        ],
      ),
      if (Platform.isAndroid)
        SettingsCard(
          children: [
            SwitchTile(
              title: '下载完成后自动导出',
              subtitle: canDownload
                  ? '导出到 Movies/剧名/，相册和文件管理器可见，卸载后保留'
                  : _noDownload,
              value: store.autoExport,
              onChanged: canDownload
                  ? (value) => _setAutoExport(context, value)
                  : null,
            ),
            SwitchTile(
              title: '自动导出后删除 App 内副本',
              subtitle: canDownload ? '删除后 App 内不能再离线播放' : _noDownload,
              value: store.deleteAfterAutoExport,
              onChanged: canDownload
                  ? (value) => saveSetting(
                      context,
                      () => store.setDeleteAfterAutoExport(value),
                    )
                  : null,
            ),
            SwitchTile(
              title: '手动导出后删除 App 内副本',
              subtitle: canDownload ? '在已下载剧页「编辑」里点「导出」后删除' : _noDownload,
              value: store.deleteAfterManualExport,
              onChanged: canDownload
                  ? (value) => saveSetting(
                      context,
                      () => store.setDeleteAfterManualExport(value),
                    )
                  : null,
            ),
          ],
        ),
      if (Platform.isIOS) const _Note('iOS 下载和媒体处理需要保持应用在前台；切到后台会暂停，回到前台后可继续。'),
    ];
  }

  Future<void> _setAutoExport(BuildContext context, bool value) =>
      saveSetting(context, () async {
        if (value && !await AppDevice.requestVideoExport()) {
          throw AppFailure('未获得存储权限，无法自动导出');
        }
        await store.setAutoExport(value);
      });

  List<Widget> _storage() => [
    if (!store.canDownload) const _Note(_noDownload),
    StorageView(store: store),
  ];

  List<Widget> _proxy(BuildContext context) {
    final admin = store.profile.admin;
    final settings = editor.settings;
    final editable = settings != null && !editor.saving;
    final mode = settings?.proxyMode;
    return [
      if (settings != null && settings.warning.isNotEmpty)
        _Note(settings.warning),
      SettingsCard(
        children: [
          ?_editorError(),
          ValueTile<String>(
            title: '连接方式',
            subtitle: !admin
                ? adminOnly
                : switch (mode) {
                    'auto' when settings!.systemProxyStatus.isNotEmpty =>
                      settings.systemProxyStatus,
                    'auto' => '使用系统静态代理；未配置时使用环境变量或直连',
                    _ => null,
                  },
            options: _proxyModes,
            value: mode,
            onChanged: editable
                ? (value) => value == 'manual'
                      ? _editProxy(context, settings)
                      : _saveResource(
                          context,
                          settings.copyWith(proxyMode: value),
                        )
                : null,
          ),
          if (mode == 'manual')
            SettingsTile(
              title: '代理地址',
              subtitle: '支持 HTTP、HTTPS、SOCKS5；仅保存在本机，不进入配置备份',
              value: settings!.proxyUrl.isEmpty ? '未设置' : '已设置',
              enabled: editable,
              onTap: () => _editProxy(context, settings),
            ),
          if (settings != null)
            SwitchTile(
              title: '站源重定向白名单',
              subtitle: '关闭后，站源模组可跟随重定向访问未在清单声明的域名；开启后仅允许清单声明的域名',
              value: settings.moduleAllowlistStrict,
              enabled: editable && admin,
              onChanged: editable && admin
                  ? (value) => _saveResource(
                      context,
                      settings.copyWith(moduleAllowlistStrict: value),
                    )
                  : null,
            ),
        ],
      ),
    ];
  }

  Future<void> _editProxy(
    BuildContext context,
    ResourceSettings settings,
  ) async {
    final address = await showDialog<String>(
      context: context,
      builder: (_) => _ProxyDialog(initial: settings.proxyUrl),
    );
    if (address == null || !context.mounted) return;
    await _saveResource(
      context,
      settings.copyWith(proxyMode: 'manual', proxyUrl: address),
    );
  }

  List<Widget> _about(BuildContext context) {
    final version = AppScope.of(context).version;
    return [
      SettingsCard(
        children: [
          SettingsTile(
            title: appName,
            value: version.isEmpty ? '版本未知' : '版本 $version',
          ),
          const _UpdateCheckTile(),
          SwitchTile(
            title: '启动时检查更新',
            subtitle: '有新版本时每次启动都会提示，可在提示里忽略此版本',
            value: store.checkUpdates,
            onChanged: (value) =>
                saveSetting(context, () => store.setCheckUpdates(value)),
          ),
          SwitchTile(
            title: '匿名使用统计',
            subtitle: '启动时发送随机编号、版本号、平台和所属版本，用于统计使用人数',
            value: store.shareUsage,
            onChanged: (value) =>
                saveSetting(context, () => store.setShareUsage(value)),
          ),
        ],
      ),
      for (final links in _links)
        if (links.any((link) => link.$2.isNotEmpty))
          SettingsCard(
            children: [
              for (final (title, url) in links)
                if (url.isNotEmpty)
                  SettingsTile(
                    title: title,
                    subtitle: url.replaceFirst('https://', ''),
                    onTap: () => _openLink(context, url),
                  ),
            ],
          ),
    ];
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开浏览器，链接已复制')));
    }
  }

  List<Widget> _diagnostics() => [
    SettingsCard(
      children: [
        SettingsTile(
          title: '播放调试日记',
          subtitle: '查看并复制应用运行与播放器的详细事件日志',
          onTap: () => open('播放调试日记', (_) => const DiaryView()),
        ),
      ],
    ),
    _BackupCard(store: store),
  ];
}

List<Widget> _lanSync(BuildContext context, LocalStore store) => [
  LanSyncSection(store: store),
];

class LanSyncSection extends StatefulWidget {
  const LanSyncSection({super.key, required this.store});
  final LocalStore store;

  @override
  State<LanSyncSection> createState() => _LanSyncSectionState();
}

class _LanSyncSectionState extends State<LanSyncSection> {
  final LanSyncService _service = LanSyncService(NativeRepository());
  bool _busy = false;
  List<LanDevice> _devices = const [];
  String? _message;

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _message = null;
      _devices = const [];
    });
    try {
      _devices = await _service.scan();
    } catch (error) {
      _message = error.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync(LanDevice device) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _service.syncFrom(device.id);
      if (mounted) {
        setState(() => _message = '已从 ${device.name} 同步完成');
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        if (_message != null) _Note('$_message'),
        _Note('两台设备都需先点击「扫描区域网设备」启动局域网服务，再互相发现。确保两台设备在同一 Wi-Fi 下，且未开启防火墙拦截。'),
        SettingsTile(
          title: '扫描区域网设备',
          subtitle: '发现同一 Wi-Fi 下运行本应用的其他设备（约需 6 秒）',
          enabled: !_busy,
          onTap: _busy ? null : _scan,
        ),
        if (_devices.isNotEmpty) ...[
          const Divider(indent: 16, endIndent: 16),
          ..._devices.map(
            (device) => SettingsTile(
              title: device.name,
              subtitle: '${device.address} · ${device.version}',
              trailing: _busy ? null : const Icon(Icons.sync_rounded),
              enabled: !_busy,
              onTap: _busy ? null : () => _sync(device),
            ),
          ),
        ],
      ],
    );
  }
}

class _UpdateCheckTile extends StatefulWidget {
  const _UpdateCheckTile();

  @override
  State<_UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<_UpdateCheckTile> {
  var _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await checkUpdateManually(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsTile(
    title: '检查更新',
    value: _busy ? '检查中' : null,
    enabled: !_busy,
    onTap: _check,
  );
}

class _BackupCard extends StatefulWidget {
  const _BackupCard({required this.store});
  final LocalStore store;

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  var _busy = false;

  Future<void> _run(Future<String?> Function() task) async {
    setState(() => _busy = true);
    String? message;
    try {
      message = await task();
    } catch (failure) {
      message = '$failure';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (message != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.store.profile.admin;
    return SettingsCard(
      children: [
        SettingsTile(
          title: '导出备份',
          subtitle: admin ? '包含本地用户、追剧、历史和设置，不含视频文件' : adminOnly,
          enabled: admin && !_busy,
          onTap: () => _run(() => exportBackupFile(widget.store, context)),
        ),
        SettingsTile(
          title: '恢复备份',
          subtitle: admin ? '替换本机的用户、追剧、观看记录和偏好设置，已下载视频保留' : adminOnly,
          enabled: admin && !_busy,
          onTap: () => _run(() => restoreBackupFile(context, widget.store)),
        ),
      ],
    );
  }
}

class _RenderingTile extends StatefulWidget {
  const _RenderingTile();

  @override
  State<_RenderingTile> createState() => _RenderingTileState();
}

class _RenderingTileState extends State<_RenderingTile> {
  bool? _compatible;

  @override
  void initState() {
    super.initState();
    AppDevice.compatibleRendering().then((value) {
      if (mounted) setState(() => _compatible = value);
    });
  }

  Future<void> _switch(bool enabled) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(enabled ? '开启兼容渲染模式？' : '关闭兼容渲染模式？'),
        content: const Text('需要重启应用才能生效，正在进行的下载会中断。'),
        actions: [
          FocusRing(
            radius: 20,
            child: TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
          ),
          FocusRing(
            radius: 20,
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('立即重启'),
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (!await AppDevice.setCompatibleRendering(enabled) && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('兼容渲染模式未能保存，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) => SwitchTile(
    title: '兼容渲染模式',
    subtitle: '改用 Skia 渲染（关闭 Impeller），用于换了解码方式仍没有画面的设备',
    value: _compatible ?? false,
    onChanged: _compatible == null ? null : _switch,
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _ProxyDialog extends StatefulWidget {
  const _ProxyDialog({required this.initial});
  final String initial;

  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  late final _address = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    final address = _address.text.trim();
    if (address.isNotEmpty) Navigator.pop(context, address);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('代理地址'),
    content: SizedBox(
      width: 420,
      child: FormTextField(
        controller: _address,
        autofocus: true,
        url: true,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          hintText: 'http://127.0.0.1:7890',
          helperText: '支持 HTTP、HTTPS、SOCKS5',
        ),
      ),
    ),
    actions: [
      FocusRing(
        radius: 20,
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
      FocusRing(
        radius: 20,
        child: FilledButton(onPressed: _submit, child: const Text('保存')),
      ),
    ],
  );
}
