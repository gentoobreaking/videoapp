import 'package:flutter/foundation.dart';

import 'local_profiles.dart';
import 'local_store.dart';

const maxProfiles = 20;

class UsersFeed extends ChangeNotifier {
  UsersFeed(this.store) {
    store.addListener(_storeChanged);
  }

  final LocalStore store;

  bool _disposed = false;

  // Derived getters - no local state needed
  bool get admin => store.profile.admin;
  List<LocalProfile> get profiles => store.profiles;
  bool get adminProtected => profiles.firstWhere((p) => p.admin).protected;
  bool get full => profiles.length >= maxProfiles;
  bool get forceLogin => store.forceLogin;
  bool get currentProtected => store.profile.protected;

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
