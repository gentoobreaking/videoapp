import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'source_modules.dart';

class ModulesFeed extends ChangeNotifier {
  ModulesFeed(this.repository, this.store) {
    store.addListener(_storeChanged);
    refresh();
    loadIndex();
  }

  final AppRepository repository;
  final LocalStore store;

  List<SourceModule>? _modules;
  String? _error;
  ModuleStore? _index;
  String? _indexError;
  bool _busy = false;
  bool _disposed = false;

  List<SourceModule>? get modules => _modules;
  String? get error => _error;
  ModuleStore? get index => _index;
  String? get indexError => _indexError;
  bool get busy => _busy;
  bool get canInstall => store.profile.admin && !store.locked && !_busy;

  Future<void> refresh() async {
    try {
      final modules = await repository.modules();
      if (!_disposed) {
        _modules = modules;
        _error = null;
        notifyListeners();
      }
    } catch (failure) {
      if (!_disposed) {
        _error = '$failure';
        notifyListeners();
      }
    }
  }

  Future<void> loadIndex() async {
    if (!_disposed) {
      _index = null;
      _indexError = null;
      notifyListeners();
    }
    try {
      final index = await repository.moduleIndex();
      if (!_disposed) {
        _index = index;
        _indexError = null;
        notifyListeners();
      }
    } catch (failure) {
      if (!_disposed) {
        _indexError = '$failure';
        notifyListeners();
      }
    }
  }

  Future<void> installIndexed(ModuleIndexEntry entry) async {
    if (_busy || _disposed) return;
    _busy = true;
    notifyListeners();
    try {
      await _install(
        await repository.prepareModule(
          indexed: entry.id,
          bundled: entry.bundled,
        ),
      );
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
        await refresh();
      }
    }
  }

  Future<void> installFile() async {
    if (_busy || _disposed) return;
    _busy = true;
    notifyListeners();
    try {
      // File picker logic will be handled by UI
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
        await refresh();
      }
    }
  }

  Future<void> installAddress(String address) async {
    if (_busy || _disposed) return;
    _busy = true;
    notifyListeners();
    try {
      await _install(await repository.prepareModule(url: address));
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
        await refresh();
      }
    }
  }

  Future<void> _install(SourceModule module) async {
    if (_disposed) return;
    final id = await repository.installModule(module.token);
    if (!module.installed) {
      await store.setSourceEnabled(id, true);
    }
    final site = SourceSite.byId(id);
    if (site.devices && !await repository.sourceDevices(id)) {
      try {
        if (!await repository.sourceDevices(id, register: true)) {
          throw AppFailure('设备注册未完成');
        }
      } catch (failure) {
        return;
      }
    }
  }

  void _storeChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    store.removeListener(_storeChanged);
    super.dispose();
  }
}
