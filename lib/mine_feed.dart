import 'package:flutter/foundation.dart';

import 'core_bridge.dart';
import 'download_overview.dart';
import 'download_preferences.dart';
import 'local_profiles.dart';
import 'local_store.dart';
import 'models.dart';

class MineFeed extends ChangeNotifier {
  MineFeed(this.repository, this.store, this.downloads) {
    store.addListener(_storeChanged);
  }

  final AppRepository repository;
  final LocalStore store;
  final DownloadOverview downloads;

  bool _disposed = false;

  // Derived getters - no local state needed
  bool get canDownload => store.canDownload;
  bool get isAdmin => store.profile.admin;
  bool get locked => store.locked;
  LocalProfile get profile => store.profile;
  List<WatchEntry> get history => store.history;
  List<LocalProfile> get profiles => store.profiles;
  DownloadPreferences get downloadPreferences => store.downloadPreferences;

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
