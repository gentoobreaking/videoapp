import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'models.dart';

class ResourceSettings {
  const ResourceSettings({
    this.proxyMode = 'auto',
    this.proxyUrl = '',
    this.catalogConcurrency = 3,
    this.downloadConcurrency = 2,
    this.downloadSegmentConcurrency = 4,
    this.prefetchLimit = 4194304,
    this.downloadBySource = false,
    this.moduleAllowlistStrict = true,
    this.browserFollowRedirects = false,
    this.warning = '',
    this.systemProxyStatus = '',
  });
  final String proxyMode, proxyUrl, warning, systemProxyStatus;
  final int catalogConcurrency, downloadConcurrency, downloadSegmentConcurrency;
  final int prefetchLimit;
  final bool downloadBySource, moduleAllowlistStrict, browserFollowRedirects;

  factory ResourceSettings.fromJson(
    Map<String, dynamic> data,
  ) => ResourceSettings(
    proxyMode: data['proxyMode'] as String? ?? 'auto',
    proxyUrl: data['proxyUrl'] as String? ?? '',
    catalogConcurrency: intValue(data['catalogConcurrency']),
    downloadConcurrency: intValue(data['downloadConcurrency']),
    downloadSegmentConcurrency: intValue(data['downloadSegmentConcurrency']),
    prefetchLimit: intValue(data['prefetchLimit']),
    downloadBySource: data['downloadBySource'] == true,
    moduleAllowlistStrict: data['moduleAllowlistStrict'] as bool? ?? true,
    browserFollowRedirects: data['browserFollowRedirects'] as bool? ?? false,
    warning: data['warning'] as String? ?? '',
    systemProxyStatus: data['systemProxyStatus'] as String? ?? '',
  );

  ResourceSettings copyWith({
    String? proxyMode,
    String? proxyUrl,
    int? catalogConcurrency,
    int? downloadConcurrency,
    int? downloadSegmentConcurrency,
    int? prefetchLimit,
    bool? downloadBySource,
    bool? moduleAllowlistStrict,
    bool? browserFollowRedirects,
  }) => ResourceSettings(
    proxyMode: proxyMode ?? this.proxyMode,
    proxyUrl: proxyUrl ?? this.proxyUrl,
    catalogConcurrency: catalogConcurrency ?? this.catalogConcurrency,
    downloadConcurrency: downloadConcurrency ?? this.downloadConcurrency,
    downloadSegmentConcurrency:
        downloadSegmentConcurrency ?? this.downloadSegmentConcurrency,
    prefetchLimit: prefetchLimit ?? this.prefetchLimit,
    downloadBySource: downloadBySource ?? this.downloadBySource,
    moduleAllowlistStrict: moduleAllowlistStrict ?? this.moduleAllowlistStrict,
    browserFollowRedirects:
        browserFollowRedirects ?? this.browserFollowRedirects,
    warning: warning,
    systemProxyStatus: systemProxyStatus,
  );

  Map<String, dynamic> toJson() => {
    'proxyMode': proxyMode,
    'proxyUrl': proxyUrl,
    'catalogConcurrency': catalogConcurrency,
    'downloadConcurrency': downloadConcurrency,
    'downloadSegmentConcurrency': downloadSegmentConcurrency,
    'prefetchLimit': prefetchLimit,
    'downloadBySource': downloadBySource,
    'moduleAllowlistStrict': moduleAllowlistStrict,
    'browserFollowRedirects': browserFollowRedirects,
  };
}

class SystemProxyMonitor with WidgetsBindingObserver {
  SystemProxyMonitor._(this.update);
  final Future<void> Function(Map<String, dynamic>) update;
  static SystemProxyMonitor? _current;
  Timer? _timer;
  bool _reading = false;

  static void start(Future<void> Function(Map<String, dynamic>) update) {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;
    _current?._timer?.cancel();
    if (_current != null) WidgetsBinding.instance.removeObserver(_current!);
    final monitor = SystemProxyMonitor._(update);
    _current = monitor;
    WidgetsBinding.instance.addObserver(monitor);
    monitor._timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => monitor.refresh(),
    );
    unawaited(monitor.refresh());
  }

  Future<void> refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final result = await const MethodChannel(
        'duanju/device',
      ).invokeMapMethod<String, dynamic>('systemProxy');
      if (result != null) await update(result);
    } catch (_) {
    } finally {
      _reading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }
}
