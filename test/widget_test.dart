import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/download/download_file_system.dart';
import 'package:nexhub/core/download/download_manager.dart';
import 'package:nexhub/core/download/download_storage.dart';
import 'package:nexhub/core/favorites/favorites_manager.dart';
import 'package:nexhub/core/history/history_manager.dart';
import 'package:nexhub/core/local/local_content_manager.dart';
import 'package:nexhub/core/locale/locale_controller.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/rss/browse_article_feed_manager.dart';
import 'package:nexhub/core/rss/rss_manager.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';
import 'package:nexhub/core/services/source_repository.dart';
import 'package:nexhub/core/theme/theme_controller.dart';
import 'package:nexhub/core/widgets/app_nav_bar.dart';
import 'package:nexhub/features/home/presentation/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('HomeScreen renders bottom nav and browse page',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final registry = ResolverRegistry.instance;
    final mediaService = MediaApiService(registry);
    final sourceRepo = SourceRepository(<PluginConfig>[]);
    final fs = InMemoryFileSystem();
    final storage = DownloadStorage();
    final downloadManager = DownloadManager(
      storage: storage,
      fs: fs,
      service: mediaService,
      sourceRepo: sourceRepo,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>(
            create: (_) => ThemeController(),
          ),
          ChangeNotifierProvider<LocaleController>(
            create: (_) => LocaleController(),
          ),
          ChangeNotifierProvider<SourceRepository>.value(value: sourceRepo),
          Provider<ResolverRegistry>.value(value: registry),
          Provider<MediaApiService>.value(value: mediaService),
          ChangeNotifierProvider<DownloadManager>.value(value: downloadManager),
          ChangeNotifierProvider<FavoritesManager>(
            create: (_) => FavoritesManager(),
          ),
          ChangeNotifierProvider<HistoryManager>(
            create: (_) => HistoryManager(),
          ),
          ChangeNotifierProvider<LocalContentManager>(
            create: (_) => LocalContentManager(),
          ),
          ChangeNotifierProvider<RssManager>(
            create: (_) => RssManager(),
          ),
          ChangeNotifierProvider<BrowseArticleFeedManager>(
            create: (_) => BrowseArticleFeedManager(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(useMaterial3: true),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // AppNavBar 替代裸 NavigationBar，移动端用自定义控件渲染。
    expect(find.byType(AppNavBar), findsOneWidget);
    expect(find.text('浏览'), findsWidgets);
  });
}
