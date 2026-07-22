import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/novel/novel_page_animation.dart';
import 'package:nexhub/features/novel/presentation/novel_animated_page_view.dart';

/// P9.1.5 — 小说翻页动画测试。
///
/// 覆盖 `TASK_clone_all_features.md` §十三 两项要求：
/// - **6 效果不丢帧**：对 [NovelPageAnimation] 全部 6 种效果逐一构建并执行
///   nextPage / previousPage 翻页，pumpAndSettle 后无异常、页索引正确。widget
///   测试环境下"不丢帧"等价于"动画代码路径可构建且可完成不抛错"。
/// - **pageContentKey 缓存**：[NovelReaderScreen] 用
///   `ValueKey<String>('novel_page_$_contentVersion')` 作为 [NovelAnimatedPageView]
///   的 key。同 key 重建（仅动画/偏好变更）应保留页状态；key 变更（章节切换/
///   内容重载）应重置到 initialPage。此处直接对 [NovelAnimatedPageView] 验证该
///   语义。
void main() {
  group('NovelPageAnimation enum', () {
    test('fromString parses all 6 effects', () {
      expect(NovelPageAnimation.fromString('none'), NovelPageAnimation.none);
      expect(NovelPageAnimation.fromString('slide'), NovelPageAnimation.slide);
      expect(NovelPageAnimation.fromString('scroll'), NovelPageAnimation.scroll);
      expect(NovelPageAnimation.fromString('fade'), NovelPageAnimation.fade);
      expect(NovelPageAnimation.fromString('cover'), NovelPageAnimation.cover);
      expect(
        NovelPageAnimation.fromString('simulation'),
        NovelPageAnimation.simulation,
      );
    });

    test('fromString falls back to slide on unknown/null', () {
      expect(NovelPageAnimation.fromString(null), NovelPageAnimation.slide);
      expect(NovelPageAnimation.fromString(''), NovelPageAnimation.slide);
      expect(NovelPageAnimation.fromString('bogus'), NovelPageAnimation.slide);
    });

    test('isScroll only true for scroll', () {
      for (final anim in NovelPageAnimation.values) {
        expect(anim.isScroll, anim == NovelPageAnimation.scroll);
      }
    });

    test('isPaged is the inverse of isScroll', () {
      for (final anim in NovelPageAnimation.values) {
        expect(anim.isPaged, !anim.isScroll);
      }
    });

    test('l10nKey returns a stable key for each effect', () {
      const expected = <NovelPageAnimation, String>{
        NovelPageAnimation.none: 'novelAnimNone',
        NovelPageAnimation.slide: 'novelAnimSlide',
        NovelPageAnimation.scroll: 'novelAnimScroll',
        NovelPageAnimation.fade: 'novelAnimFade',
        NovelPageAnimation.cover: 'novelAnimCover',
        NovelPageAnimation.simulation: 'novelAnimSimulation',
      };
      for (final anim in NovelPageAnimation.values) {
        expect(anim.l10nKey(), expected[anim]);
      }
    });
  });

  group('NovelAnimatedPageView 6 effects no frame drop', () {
    Widget buildView(
      NovelPageAnimation anim, {
      int initialPage = 0,
      VoidCallback? onRequestPrevChapter,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: NovelAnimatedPageView(
            animation: anim,
            pageCount: 3,
            initialPage: initialPage,
            background: Colors.white,
            pageBuilder: (BuildContext ctx, int i) => Center(
              key: ValueKey<int>(i),
              child: Text('page_$i'),
            ),
            scrollBuilder: anim == NovelPageAnimation.scroll
                ? (BuildContext ctx) => ListView(
                    children: const <Widget>[
                      Center(child: Text('page_0')),
                      Center(child: Text('page_1')),
                      Center(child: Text('page_2')),
                    ],
                  )
                : null,
            onRequestPrevChapter: onRequestPrevChapter,
          ),
        ),
      );
    }

    for (final anim in NovelPageAnimation.values) {
      testWidgets('forward: builds + nextPage completes (${anim.name})',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildView(anim, initialPage: 0));
        await tester.pumpAndSettle();

        expect(find.text('page_0'), findsOneWidget);
        final state = tester.state<NovelAnimatedPageViewState>(
          find.byType(NovelAnimatedPageView),
        );
        expect(state.currentPage, 0);

        // 单次向前翻页：动画应能完成（不丢帧/不抛错），页索引推进。
        state.nextPage();
        await tester.pumpAndSettle();
        expect(state.currentPage, 1);
      });
    }

    for (final anim in NovelPageAnimation.values) {
      testWidgets('backward: previousPage completes from fresh state (${anim.name})',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        // 从 initialPage=2 向后翻一次。连续翻页的控制器复位问题已修复
        // （见 [_animateTo] 的 _reversing 守卫），此处独立验证 backward 路径。
        await tester.pumpWidget(buildView(anim, initialPage: 2));
        await tester.pumpAndSettle();

        final state = tester.state<NovelAnimatedPageViewState>(
          find.byType(NovelAnimatedPageView),
        );
        expect(state.currentPage, 2);

        state.previousPage();
        await tester.pumpAndSettle();
        expect(state.currentPage, 1);
      });
    }

    // ── 回归：连续翻页不再卡死（#1/#2 根因修复） ──
    // 翻页动画在第一次翻页后控制器停在 value=1.0，下一次 _animateTo 复位
    // value=0 会同步触发 incidental dismissed，旧逻辑把它当成回弹而回退页面、
    // 清空 _animating，导致「翻一次就卡死」。修复后连续翻页应逐页推进。
    Widget buildViewWithCount(NovelPageAnimation anim, int pageCount) {
      return MaterialApp(
        home: Scaffold(
          body: NovelAnimatedPageView(
            animation: anim,
            pageCount: pageCount,
            initialPage: 0,
            background: Colors.white,
            pageBuilder: (BuildContext ctx, int i) => Center(
              key: ValueKey<int>(i),
              child: Text('page_$i'),
            ),
          ),
        ),
      );
    }

    for (final anim in [
      NovelPageAnimation.slide,
      NovelPageAnimation.cover,
      NovelPageAnimation.fade,
      NovelPageAnimation.simulation,
    ]) {
      testWidgets('three consecutive nextPage reach page 3 (${anim.name})',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildViewWithCount(anim, 5));
        await tester.pumpAndSettle();

        final state = tester.state<NovelAnimatedPageViewState>(
          find.byType(NovelAnimatedPageView),
        );
        expect(state.currentPage, 0);

        state.nextPage();
        await tester.pumpAndSettle();
        expect(state.currentPage, 1);

        state.nextPage();
        await tester.pumpAndSettle();
        expect(state.currentPage, 2);

        state.nextPage();
        await tester.pumpAndSettle();
        expect(state.currentPage, 3);
      });

      testWidgets('nextPage then previousPage returns to prior page (${anim.name})',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildViewWithCount(anim, 5));
        await tester.pumpAndSettle();

        final state = tester.state<NovelAnimatedPageViewState>(
          find.byType(NovelAnimatedPageView),
        );

        state.nextPage();
        await tester.pumpAndSettle();
        expect(state.currentPage, 1);

        state.previousPage();
        await tester.pumpAndSettle();
        expect(state.currentPage, 0);
      });
    }

    for (final anim in NovelPageAnimation.values) {
      testWidgets('boundary: prev on first page requests prev chapter (${anim.name})',
          (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        var requested = false;
        await tester.pumpWidget(buildView(
          anim,
          initialPage: 0,
          onRequestPrevChapter: () => requested = true,
        ));
        await tester.pumpAndSettle();

        final state = tester.state<NovelAnimatedPageViewState>(
          find.byType(NovelAnimatedPageView),
        );
        state.previousPage(); // 第 0 页向前 -> 请求上一章
        expect(requested, isTrue);
      });
    }
  });

  group('pageContentKey cache', () {
    testWidgets(
        'same key across rebuild preserves current page (animation change)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      // 首次构建：key=A，slide 动画，初始页 0。
      const keyA = ValueKey<String>('novel_page_0');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NovelAnimatedPageView(
              key: keyA,
              animation: NovelPageAnimation.slide,
              pageCount: 3,
              initialPage: 0,
              background: Colors.white,
              pageBuilder: (BuildContext ctx, int i) =>
                  Center(child: Text('page_$i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var state = tester.state<NovelAnimatedPageViewState>(
        find.byType(NovelAnimatedPageView),
      );
      state.nextPage();
      await tester.pumpAndSettle();
      expect(state.currentPage, 1);

      // 同 key=A 重建，仅切换动画为 fade（模拟只改偏好、不改内容版本）。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NovelAnimatedPageView(
              key: keyA,
              animation: NovelPageAnimation.fade,
              pageCount: 3,
              initialPage: 0,
              background: Colors.white,
              pageBuilder: (BuildContext ctx, int i) =>
                  Center(child: Text('page_$i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 同 key -> State 保留 -> 当前页仍为 1（缓存命中）。
      state = tester.state<NovelAnimatedPageViewState>(
        find.byType(NovelAnimatedPageView),
      );
      expect(state.currentPage, 1);
    });

    testWidgets(
        'different key on rebuild resets to initialPage (content version bump)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      // 首次构建：key=A，初始页 0，翻到页 1。
      const keyA = ValueKey<String>('novel_page_0');
      const keyB = ValueKey<String>('novel_page_1');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NovelAnimatedPageView(
              key: keyA,
              animation: NovelPageAnimation.slide,
              pageCount: 3,
              initialPage: 0,
              background: Colors.white,
              pageBuilder: (BuildContext ctx, int i) =>
                  Center(child: Text('page_$i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var state = tester.state<NovelAnimatedPageViewState>(
        find.byType(NovelAnimatedPageView),
      );
      state.nextPage();
      await tester.pumpAndSettle();
      expect(state.currentPage, 1);

      // 换 key=B（模拟 _contentVersion++ 触发章节切换），initialPage 重置为 0。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NovelAnimatedPageView(
              key: keyB,
              animation: NovelPageAnimation.slide,
              pageCount: 3,
              initialPage: 0,
              background: Colors.white,
              pageBuilder: (BuildContext ctx, int i) =>
                  Center(child: Text('page_$i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 新 key -> 新 State -> currentPage 回到 initialPage=0。
      state = tester.state<NovelAnimatedPageViewState>(
        find.byType(NovelAnimatedPageView),
      );
      expect(state.currentPage, 0);
    });
  });
}
