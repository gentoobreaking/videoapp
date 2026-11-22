import 'package:flutter_test/flutter_test.dart';

import 'package:videoapp/app_update.dart';
import 'package:videoapp/core_bridge.dart';
import 'package:videoapp/danmaku_models.dart';
import 'package:videoapp/download_collections.dart';
import 'package:videoapp/models.dart';
import 'package:videoapp/playback_loader.dart';
import 'package:videoapp/ranking_models.dart';
import 'package:videoapp/resource_settings.dart';
import 'package:videoapp/sorani_account.dart';
import 'package:videoapp/source_modules.dart';

class _StubRepository extends AppRepository {
  Future<PlaybackPlan> Function(Drama, Episode, {int? quality})? onResolve;
  int resolveCalls = 0;
  int cancelPlaybackCalls = 0;
  int releaseCalls = 0;

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async => throw UnimplementedError();

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      throw UnimplementedError();

  @override
  Future<String> cover(Drama drama, {bool force = false}) async =>
      throw UnimplementedError();

  @override
  Future<DramaDetail> detail(Drama drama) async => throw UnimplementedError();

  @override
  Future<void> initialize() async {}

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    resolveCalls++;
    if (onResolve != null) {
      return onResolve!(drama, episode, quality: quality);
    }
    return const PlaybackPlan(
      url: 'https://example.com/video.mp4',
      session: 's1',
    );
  }

  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) async => current;

  @override
  Future<void> cancelPlayback() async {
    cancelPlaybackCalls++;
  }

  @override
  Future<void> release(String session) async {
    releaseCalls++;
  }

  @override
  Future<ResourceSettings> resourceSettings() async => const ResourceSettings();

  @override
  Future<ResourceSettings> saveResourceSettings(
    ResourceSettings settings,
  ) async => throw UnimplementedError();

  @override
  Future<void> cancelPreload() async {}

  @override
  Future<PlaybackPlan?> preload(
    Drama drama,
    Episode episode, {
    int quality = 0,
    bool online = false,
  }) async => null;

  @override
  Future<List<CastDevice>> castDevices() async => const [];

  @override
  Future<void> castPlay(
    CastDevice device,
    Drama drama,
    Episode episode, {
    int quality = 0,
    double position = 0,
  }) async {}

  @override
  Future<CastStatus> castStatus() async => throw UnimplementedError();

  @override
  Future<void> castControl(String command, {double position = 0}) async {}

  @override
  Future<bool> castActive() async => false;

  @override
  Future<void> cancelDanmaku() async {}

  @override
  Future<DanmakuPage> danmaku(
    PlaybackPlan plan, {
    required int startMs,
    required int durationMs,
  }) async => throw UnimplementedError();

  @override
  Future<void> cancelCatalog() async {}

  @override
  Future<void> cancelSuggestions() async {}

  @override
  Future<void> cancelRecommendations() async {}

  @override
  Future<Drama?> supplementMetadata(Drama drama) async => null;

  @override
  Future<List<DramaSeason>> seasons(Drama drama) async => const [];

  @override
  Future<Drama> followCheck(Drama drama) async => throw UnimplementedError();

  @override
  Future<CatalogPage> recommendations(
    String source,
    String genre, {
    bool more = false,
    bool force = false,
  }) async => throw UnimplementedError();

  @override
  Future<List<RankingBoard>> rankingBoards() async => const [];

  @override
  Future<RankingPage> rankings(
    RankingBoard board, {
    int page = 1,
    bool force = false,
  }) async => throw UnimplementedError();

  @override
  Future<List<CatalogCategory>> categories(
    String source, {
    bool force = false,
  }) async => const [];

  @override
  bool get supportsSourceManagement => false;

  @override
  Future<List<SourceModule>> modules() async => const [];

  @override
  bool get supportsDownloads => false;

  @override
  Future<List<DownloadJob>> downloads() async => [];

  @override
  Future<int> enqueueDownloads(
    DramaDetail detail,
    List<Episode> episodes, {
    int quality = 0,
  }) async => throw UnimplementedError();

  @override
  Future<void> controlDownloads(String command, {String id = ''}) async {}

  @override
  Future<DownloadBatchResult> controlDownloadBatch(
    String command,
    List<String> ids,
  ) async => throw UnimplementedError();

  @override
  Future<int> updateDownloadCollection(
    DramaDetail detail,
    List<Episode> episodes, {
    int quality = 0,
  }) async => throw UnimplementedError();

  @override
  Future<ModuleStore> moduleIndex() async => throw UnimplementedError();

  @override
  Future<SourceModule> prepareModule({
    String file = '',
    String url = '',
    String indexed = '',
    bool bundled = false,
  }) async => throw UnimplementedError();

  @override
  Future<String> installModule(String token) async =>
      throw UnimplementedError();

  @override
  Future<void> uninstallModule(String id) async {}

  @override
  Map<String, int> missingSourceDownloads() => const {};

  @override
  Future<List<String>> suggestions(String source, String query) async =>
      const [];

  @override
  Future<Map<String, dynamic>> storage() async => {};

  @override
  Future<String> downloadDirectory() async => '';

  @override
  Future<({String path, String reason})> moveDownloads(
    String directory,
  ) async => throw UnimplementedError();

  @override
  Future<int> workLease(String id, String command) async => 0;

  @override
  Future<int> cacheBytes() async => 0;

  @override
  Future<void> clearCache() async {}

  @override
  Future<List<String>> deleteAllData() async => throw UnimplementedError();

  @override
  Future<DownloadConversion> beginConversion(String id) async =>
      throw UnimplementedError();

  @override
  Future<void> finishConversion(String id, String result) async {}

  @override
  Future<PlaybackPlan?> localPlayback(Drama drama, Episode episode) async =>
      null;

  @override
  Future<PlaybackPlan> resolveOnline(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) => resolve(drama, episode, quality: quality);

  @override
  Future<AppUpdate?> checkUpdate(String version, {String? abi}) async => null;

  @override
  Future<void> reportUsage(String version) async {}

  @override
  Future<bool> sourceDevices(String source, {bool register = false}) async =>
      true;

  @override
  Future<SoraniAccount> soraniAccount() async => const SoraniAccount();

  @override
  Future<SoraniCaptcha> soraniCaptcha() async => throw UnimplementedError();

  @override
  Future<SoraniAccount> soraniLogin({
    required String identifier,
    required String password,
    required String captchaId,
    required SoraniCaptchaTrack track,
  }) async => throw UnimplementedError();

  @override
  Future<SoraniAccount> soraniLogout() async => const SoraniAccount();

  @override
  Future<void> lanStart() async {}

  @override
  Future<void> lanStop() async {}

  @override
  Future<Map<String, dynamic>> lanScan() async => {};

  @override
  Future<Map<String, dynamic>> lanInfo() async => {};

  @override
  Future<void> lanSync(String deviceId) async {}

  @override
  bool coverCached(Drama drama) => false;
}

Drama testDrama() => const Drama(
  id: 'hongguo:1',
  source: 'hongguo',
  title: 'Test Drama',
  category: '',
  episodes: 10,
);

Episode testEpisode() => Episode({}, 1);

void main() {
  group('PlaybackLoader', () {
    test('load success returns plan', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);

      final plan = await loader.load(testDrama(), testEpisode());

      expect(plan, isNotNull);
      expect(plan?.url, 'https://example.com/video.mp4');
      expect(repo.resolveCalls, 1);
      expect(repo.cancelPlaybackCalls, 1);
    });

    test('load with localOnly uses localPlayback', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);

      // localPlayback 默認返回 null，應該拋出 AppFailure
      expect(
        () async =>
            await loader.load(testDrama(), testEpisode(), localOnly: true),
        throwsA(isA<AppFailure>()),
      );
    });

    test('load with online uses resolveOnline', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);

      final plan = await loader.load(testDrama(), testEpisode(), online: true);

      expect(plan, isNotNull);
      expect(repo.resolveCalls, 1);
    });

    test('fallback calls repository.fallback', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);
      final current = const PlaybackPlan(
        url: 'https://example.com/video.mp4',
        session: 's1',
      );

      await loader.fallback(current);

      expect(repo.cancelPlaybackCalls, 1);
    });

    test('use returns prepared plan', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);
      final prepared = const PlaybackPlan(
        url: 'https://example.com/video.mp4',
        session: 's1',
      );

      final plan = await loader.use(prepared);

      expect(plan?.url, 'https://example.com/video.mp4');
    });

    test('close prevents further loads', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);

      await loader.close();

      final plan = await loader.load(testDrama(), testEpisode());
      expect(plan, isNull);
    });

    test('load after close returns null without calling resolve', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);

      await loader.close();

      await loader.load(testDrama(), testEpisode());
      expect(repo.resolveCalls, 0);
    });

    test('resolve failure propagates error', () async {
      final repo = _StubRepository()
        ..onResolve = (_, _, {int? quality}) =>
            Future.error(AppFailure('播放地址获取失败'));
      final loader = PlaybackLoader(repo);

      expect(
        () async => await loader.load(testDrama(), testEpisode()),
        throwsA(isA<AppFailure>()),
      );
    });
  });
}
