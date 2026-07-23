import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import '../../../core/settings/general_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_nav_bar.dart';
import '../../manga/presentation/comic_home_screen.dart';
import '../../media/presentation/media_home_screen.dart';
import '../../novel/presentation/novel_home_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'browse_page.dart';

/// 底部导航顺序：浏览 → 小说 → 媒体 → 漫画 → 设置，默认浏览为首页。
///
/// 桌面端（≥ [AppTokens.desktopBreakpoint]）使用 [Row] +
/// [NavigationRail] + [IndexedStack] 布局；移动端使用 [Scaffold]
/// 底导 + [IndexedStack]。[IndexedStack] 保持所有 Tab 页面状态，
/// 避免切换时重建。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  /// 所有 Tab 页面一次性构建，由 [IndexedStack] 保留状态。
  late final List<Widget> _pages = <Widget>[
    const BrowsePage(),
    const NovelHomeScreen(),
    const MediaHomeScreen(),
    const ComicHomeScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 启动界面设置：默认打开用户指定的首页 Tab（枚举顺序与底部导航一致）。
    _index = GeneralSettingsStore.instance.settings.launchTab.index;
    // 若通用设置尚未加载完成，加载后回写，避免默认值覆盖用户选择。
    if (!GeneralSettingsStore.instance.loaded) {
      GeneralSettingsStore.instance.load().then((s) {
        if (mounted) setState(() => _index = s.launchTab.index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double width = MediaQuery.sizeOf(context).width;
    final List<NavigationDestination> destinations = <NavigationDestination>[
      NavigationDestination(
          icon: const Icon(Icons.explore), label: l10n.navBrowse),
      NavigationDestination(
          icon: const Icon(Icons.menu_book), label: l10n.navNovel),
      NavigationDestination(
          icon: const Icon(Icons.movie), label: l10n.navMedia),
      NavigationDestination(
          icon: const Icon(Icons.auto_stories), label: l10n.navComic),
      NavigationDestination(
          icon: const Icon(Icons.settings), label: l10n.navSettings),
    ];

    // 桌面端：NavigationRail + IndexedStack 横向布局。
    if (width >= AppTokens.desktopBreakpoint) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppNavBar(
              selectedIndex: _index,
              onDestinationSelected: (int i) => setState(() => _index = i),
              destinations: destinations,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: IndexedStack(index: _index, children: _pages),
            ),
          ],
        ),
      );
    }

    // 移动端：底导 + IndexedStack。
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: AppNavBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}

/// 为 StatelessWidget 场景提供统一的占位提示，避免重复代码。
class HomeScreenStateHelper {
  HomeScreenStateHelper._();

  static void showNotImplemented(BuildContext context, String label) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label — ${l10n.loading}')),
    );
  }
}
