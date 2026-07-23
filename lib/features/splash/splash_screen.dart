import 'package:fvp/fvp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../app.dart';
import '../../core/article/article_reading_preferences.dart';
import '../../core/download/download_file_system.dart';
import '../../core/download/download_manager.dart';
import '../../core/download/download_settings.dart';
import '../../core/download/download_storage.dart';
import '../../core/favorites/favorites_manager.dart';
import '../../core/history/history_manager.dart';
import '../../core/local/local_content_manager.dart';
import '../../core/locale/locale_controller.dart';
import '../../core/models/hive_adapters.dart';
import '../../core/platform/platform_service.dart';
import '../../core/resolver/resolver_registry.dart';
import '../../core/rss/browse_article_feed_manager.dart';
import '../../core/rss/rss_manager.dart';
import '../../core/rss/rss_update_checker.dart';
import '../../core/history/media_watched_manager.dart';
import '../../core/history/media_playback_position_manager.dart';
import '../../core/scraper/media_api_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/settings/general_settings.dart';
import '../../core/services/source_repository.dart';
import '../../core/services/config_loader.dart';
import '../../core/theme/theme_controller.dart';
import '../shuyuan/presentation/shuyuan_novel_resolver.dart';

/// Holds all artifacts produced during app initialization.
///
/// These are created during the splash phase and then injected into the
/// widget tree via [MultiProvider] once initialization completes.
class InitResult {
  final SourceRepository sourceRepo;
  final ResolverRegistry registry;
  final MediaApiService mediaService;
  final DownloadManager downloadManager;
  final FavoritesManager favoritesManager;
  final HistoryManager historyManager;
  final RssManager rssManager;
  final BrowseArticleFeedManager browseArticleFeedManager;
  final RssUpdateChecker rssUpdateChecker;
  final MediaWatchedManager mediaWatchedManager;
  final MediaPlaybackPositionManager mediaPlaybackPositionManager;
  final LocalContentManager localContentManager;
  final CloudSyncService cloudSyncService;

  const InitResult({
    required this.sourceRepo,
    required this.registry,
    required this.mediaService,
    required this.downloadManager,
    required this.favoritesManager,
    required this.historyManager,
    required this.rssManager,
    required this.browseArticleFeedManager,
    required this.rssUpdateChecker,
    required this.mediaWatchedManager,
    required this.mediaPlaybackPositionManager,
    required this.localContentManager,
    required this.cloudSyncService,
  });
}

/// Splash screen that drives full app initialization before handing off to
/// [App]. While initialization is in flight a logo with a progress indicator
/// is shown; on failure a retry UI is offered.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Future<InitResult>? _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  /// Runs the full initialization pipeline previously hosted in [main].
  /// Order matches the original main() exactly: fvp registration, Hive init,
  /// adapter registration, box opening, source loading, resolver/media setup,
  /// download manager, then favorites/history/rss/article-feed managers.
  Future<InitResult> _initialize() async {
    // Windows desktop: register fvp video backend.
    if (PlatformService.instance.isWindows) {
      // fvp provides hardware-accelerated decoding; Windows desktop only.
      try {
        registerWith();
      } catch (_) {
        // Ignore in test or non-Windows desktop environments.
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDir.path);

    Hive.registerAdapter(HiveMediaItemAdapter());
    Hive.registerAdapter(HiveEpisodeAdapter());
    Hive.registerAdapter(HivePluginConfigAdapter());
    Hive.registerAdapter(HiveReadingProgressAdapter());
    Hive.registerAdapter(HiveFavoriteAdapter());
    Hive.registerAdapter(HiveDownloadTaskAdapter());
    Hive.registerAdapter(HiveDanmakuCacheAdapter());
    Hive.registerAdapter(HiveRssFeedAdapter());
    Hive.registerAdapter(HiveSettingsAdapter());

    await Future.wait([
      Hive.openBox('sources'),
      Hive.openBox('favorites'),
      Hive.openBox('media_progress'),
      Hive.openBox('comic_progress'),
      Hive.openBox('novel_progress'),
      Hive.openBox('download_tasks'),
      Hive.openBox('danmaku_cache'),
      Hive.openBox('book_sources'),
      Hive.openBox('rss_feeds'),
      Hive.openBox('article_feeds'),
      Hive.openBox('settings'),
      Hive.openBox('novel_bookmarks'),
      Hive.openBox('comic_bookmarks'),
      Hive.openBox('media_watched'),
      Hive.openBox('media_playback_position'),
      Hive.openBox('source_mirrors'),
      Hive.openBox('chapter_fetch_times'),
    ]);

    final sourceRepo = await SourceRepository.loadBuiltins();
    await sourceRepo.loadImported();
    // 加载持久化的镜像选择（P8.2.2 §廿二）
    await ConfigLoader.instance.init();
    final registry = ResolverRegistry.instance;
    // 注入书源解析器（ShuyuanNovelResolver），避免 core 反向依赖 feature 层。
    // 必须在 registry 被使用前注册；ShuyuanNovelResolver 内部自建 WebBook/XiaoshuoHttp。
    registerShuyuanResolver(ShuyuanNovelResolver.new);
    final mediaService = MediaApiService(registry);

    // Download base path: prefer the user-configured path from Download
    // Manager; fall back to <app docs>/downloads when unset.
    final downloadSettings = await DownloadSettingsStore().load();
    final String downloadBasePath;
    if (downloadSettings.downloadPath.isNotEmpty) {
      downloadBasePath = downloadSettings.downloadPath;
    } else {
      downloadBasePath =
          '${appDir.path}${appDir.path.endsWith('/') ? '' : '/'}downloads';
    }
    final downloadFs = PathProviderFileSystem(downloadBasePath);
    final downloadManager = DownloadManager(
      storage: DownloadStorage(),
      fs: downloadFs,
      service: mediaService,
      sourceRepo: sourceRepo,
    );
    await downloadManager.init();

    // Favorites / history / RSS / article-feed managers initialization.
    final favoritesManager = FavoritesManager();
    await favoritesManager.init();
    final historyManager = HistoryManager();
    await historyManager.init();
    final rssManager = RssManager();
    await rssManager.init();
    final browseArticleFeedManager = BrowseArticleFeedManager();
    await browseArticleFeedManager.init();
    final rssUpdateChecker = RssUpdateChecker(rssManager: rssManager);
    await rssUpdateChecker.init();
    final mediaWatchedManager = MediaWatchedManager();
    await mediaWatchedManager.init();
    final mediaPlaybackPositionManager = MediaPlaybackPositionManager();
    await mediaPlaybackPositionManager.init();
    final localContentManager = LocalContentManager();
    await localContentManager.init();

    final cloudSyncService = CloudSyncService();
    await cloudSyncService.init();
    // 通用设置（启动界面 / 日期格式）需在首页构建前就绪。
    await GeneralSettingsStore.instance.load();

    return InitResult(
      sourceRepo: sourceRepo,
      registry: registry,
      mediaService: mediaService,
      downloadManager: downloadManager,
      favoritesManager: favoritesManager,
      historyManager: historyManager,
      rssManager: rssManager,
      browseArticleFeedManager: browseArticleFeedManager,
      rssUpdateChecker: rssUpdateChecker,
      mediaWatchedManager: mediaWatchedManager,
      mediaPlaybackPositionManager: mediaPlaybackPositionManager,
      localContentManager: localContentManager,
      cloudSyncService: cloudSyncService,
    );
  }

  void _retry() {
    setState(() {
      _initFuture = _initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InitResult>(
      future: _initFuture,
      builder: (context, snapshot) {
        // Done + success: inject providers and hand off to App.
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          final result = snapshot.data!;
          return MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeController>.value(
                value: ThemeController(),
              ),
              ChangeNotifierProvider<SourceRepository>.value(
                  value: result.sourceRepo),
              Provider<ResolverRegistry>.value(value: result.registry),
              Provider<MediaApiService>.value(value: result.mediaService),
              ChangeNotifierProvider<DownloadManager>.value(
                  value: result.downloadManager),
              ChangeNotifierProvider<FavoritesManager>.value(
                  value: result.favoritesManager),
              ChangeNotifierProvider<HistoryManager>.value(
                  value: result.historyManager),
              ChangeNotifierProvider<RssManager>.value(
                  value: result.rssManager),
              ChangeNotifierProvider<BrowseArticleFeedManager>.value(
                  value: result.browseArticleFeedManager),
              ChangeNotifierProvider<RssUpdateChecker>.value(
                  value: result.rssUpdateChecker),
              ChangeNotifierProvider<MediaWatchedManager>.value(
                  value: result.mediaWatchedManager),
              ChangeNotifierProvider<MediaPlaybackPositionManager>.value(
                  value: result.mediaPlaybackPositionManager),
              ChangeNotifierProvider<LocalContentManager>.value(
                  value: result.localContentManager),
              ChangeNotifierProvider<CloudSyncService>.value(
                  value: result.cloudSyncService),
              ChangeNotifierProvider<ArticleReadingPreferencesNotifier>(
                create: (_) => ArticleReadingPreferencesNotifier(),
              ),
              ChangeNotifierProvider<LocaleController>(
                create: (_) => LocaleController()..load(),
              ),
            ],
            child: const App(),
          );
        }

        // Loading or error: wrap in a minimal MaterialApp so that
        // Theme.of(context) and AppLocalizations.of(context) resolve.
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
          ],
          home: snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasError
              ? _ErrorView(
                  error: snapshot.error,
                  onRetry: _retry,
                )
              : const _SplashView(),
        );
      },
    );
  }
}

/// Logo + progress indicator shown while initialization is in flight.
/// No text is displayed (per spec, no l10n keys added for splash).
class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icon/icon.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 24),
            CircularProgressIndicator(
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Error UI shown when initialization fails. Offers a retry button that
/// re-runs the initialization pipeline.
class _ErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.loadFailed,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
