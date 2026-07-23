import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/favorites/favorites_manager.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/models/episode.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';
import 'package:nexhub/core/services/source_repository.dart';
import 'package:nexhub/features/manga/presentation/comic_reader_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读器界面测试：widget 测试环境下 HttpClient 被桩为返回 400，
/// 无法走真实网络。此处注入 [FakeMediaApiService] 提供固定的图片列表，
/// 真实 fetchImages 路径由 media_api_service_images_test 的 loopback 测试覆盖。
class FakeMediaApiService extends MediaApiService {
  FakeMediaApiService() : super(ResolverRegistry.instance);

  @override
  Future<List<String>> fetchImages(
    PluginConfig source, {
    required String comicId,
    required String chapterId,
    String? renderedHtml,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return const <String>[
      'https://example.com/p1.png',
      'https://example.com/p2.png',
      'https://example.com/p3.png',
    ];
  }
}

void main() {
  testWidgets('reader renders pages and toggles UI', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // 默认开启双击缩放（InteractiveViewer 参与手势竞技场），
      // 用于验证「单击导航不被缩放手势吞掉」的修复。
      'reader_prefs_m1':
          '{"readingMode":"singleLTR","doubleTapZoom":true,"tapZoneLayout":"lShape"}',
    });
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;

    final source = PluginConfig.fromJson(<String, dynamic>{
      'id': 'src1', 'name': 'S', 'type': 'mangaSource', 'responseType': 'json',
      'site': {'domain': 'https://example.com', 'baseUrl': 'https://example.com'},
      'parser': {'type': 'builtin'},
      'routes': {'images': '/images?cid={cid}'},
      'selectors': {'images': '\$.images'},
    });
    final repo = SourceRepository(<PluginConfig>[source]);
    final service = FakeMediaApiService();
    final favorites = FavoritesManager();
    await favorites.init();
    const chapters = <Episode>[Episode(id: 'c1', title: '第1话', url: '/c1')];

    await tester.pumpWidget(
      Provider<MediaApiService>.value(
        value: service,
        child: ChangeNotifierProvider<SourceRepository>.value(
          value: repo,
          child: ChangeNotifierProvider<FavoritesManager>.value(
            value: favorites,
            child: const MaterialApp(
              locale: Locale('zh'),
              supportedLocales: <Locale>[Locale('zh'), Locale('en')],
              localizationsDelegates: <LocalizationsDelegate<dynamic>>[
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: ComicReaderScreen(
                comicId: 'm1',
                title: '测试漫画',
                sourceId: 'src1',
                chapters: chapters,
              ),
            ),
          ),
        ),
      ),
    );

    // 等待异步加载完成（FakeMediaApiService.fetchImages 延迟 20ms）。
    // 不用 pumpAndSettle：SourceImage 的 CachedNetworkImage 在测试环境
    // 发起网络请求返回 400，placeholder 的 CircularProgressIndicator
    // 无限动画会导致 pumpAndSettle 超时。pump 推进足够时间让 fetchImages
    // 完成并触发 setState 重建即可，断言不依赖图片真正解码。
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 50));

    // 至少一页漫画已渲染（MangaPageImage 在加载/解码中即存在；
    // 分页模式下 PageView 仅实例化可见页，故用 atLeast）。
    expect(find.byType(MangaPageImage), findsAtLeastNWidgets(1));

    // 点击中心（默认布局中部 1/3 为切换控件）切换阅读器控件显隐。
    await tester.tapAt(const Offset(400, 600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // 再次点击中心收起控件。
    await tester.tapAt(const Offset(400, 600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });
}
