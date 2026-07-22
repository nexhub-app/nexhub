import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/comic/models/reader_preferences.dart'
    show InMemoryBackend;
import 'package:nexhub/core/novel/novel_page_animation.dart';
import 'package:nexhub/core/novel/novel_reader_preferences.dart';
import 'package:nexhub/core/theme/reader_tokens.dart';

void main() {
  test('json round-trip preserves all fields', () {
    const prefs = NovelReaderPreferences(
      fontSize: 22.0,
      lineHeight: 2.0,
      paragraphSpacing: 24.0,
      margin: 32.0,
      bgPresetIndex: 0,
      customBgColor: 0xFF112233,
      emphasisColor: 0xFFAABBCC,
      shadow: true,
      pageAnimation: NovelPageAnimation.cover,
      headerLeft: NovelHeaderFooterContent.chapterTitle,
      headerRight: NovelHeaderFooterContent.battery,
      footerLeft: NovelHeaderFooterContent.progressPercent,
      footerRight: NovelHeaderFooterContent.none,
    );
    final back = NovelReaderPreferences.fromJson(prefs.toJson());
    expect(back.fontSize, 22.0);
    expect(back.lineHeight, 2.0);
    expect(back.paragraphSpacing, 24.0);
    expect(back.margin, 32.0);
    expect(back.bgPresetIndex, 0);
    expect(back.customBgColor, 0xFF112233);
    expect(back.emphasisColor, 0xFFAABBCC);
    expect(back.shadow, true);
    expect(back.pageAnimation, NovelPageAnimation.cover);
    expect(back.headerLeft, NovelHeaderFooterContent.chapterTitle);
    expect(back.headerRight, NovelHeaderFooterContent.battery);
    expect(back.footerLeft, NovelHeaderFooterContent.progressPercent);
    expect(back.footerRight, NovelHeaderFooterContent.none);
  });

  test('defaults applied for missing values', () {
    final prefs = NovelReaderPreferences.fromJson(<String, dynamic>{});
    expect(prefs.fontSize, 18.0);
    expect(prefs.lineHeight, 1.8);
    expect(prefs.pageAnimation, NovelPageAnimation.slide);
    expect(prefs.shadow, false);
  });

  test('store returns default then persists', () async {
    final store = NovelReaderPreferencesStore(backend: InMemoryBackend());
    expect((await store.get('x')).fontSize, 18.0);
    await store.save(
      'x',
      const NovelReaderPreferences(fontSize: 28.0),
    );
    expect((await store.get('x')).fontSize, 28.0);
  });

  test('resolveBackgroundColor uses custom then preset', () {
    const custom = NovelReaderPreferences(customBgColor: 0xFF000000);
    expect(custom.resolveBackgroundColor(false), const Color(0xFF000000));

    const preset = NovelReaderPreferences(bgPresetIndex: 0);
    expect(preset.resolveBackgroundColor(false), ReaderTokens.bgPresets[0]);

    const preset2 = NovelReaderPreferences(bgPresetIndex: 2);
    expect(preset2.resolveBackgroundColor(false), ReaderTokens.bgPresets[2]);
  });

  test('resolveTextColor adapts to background luminance', () {
    const darkBg = NovelReaderPreferences(bgPresetIndex: 0);
    final darkColor = darkBg.resolveTextColor(darkBg.resolveBackgroundColor(true));
    expect(darkColor.computeLuminance(), greaterThan(0.5));

    const lightBg = NovelReaderPreferences(bgPresetIndex: 2);
    final lightColor =
        lightBg.resolveTextColor(lightBg.resolveBackgroundColor(false));
    expect(lightColor.computeLuminance(), lessThan(0.5));
  });

  test('NovelPageAnimation helpers', () {
    expect(NovelPageAnimation.scroll.isScroll, true);
    expect(NovelPageAnimation.scroll.isPaged, false);
    expect(NovelPageAnimation.slide.isPaged, true);
    expect(NovelPageAnimation.none.isPaged, true);
  });

  test('NovelPageAnimation.fromString parses correctly', () {
    expect(NovelPageAnimation.fromString('none'), NovelPageAnimation.none);
    expect(NovelPageAnimation.fromString('slide'), NovelPageAnimation.slide);
    expect(NovelPageAnimation.fromString('scroll'), NovelPageAnimation.scroll);
    expect(NovelPageAnimation.fromString('fade'), NovelPageAnimation.fade);
    expect(NovelPageAnimation.fromString('cover'), NovelPageAnimation.cover);
    expect(NovelPageAnimation.fromString('simulation'),
        NovelPageAnimation.simulation);
    expect(NovelPageAnimation.fromString('unknown'), NovelPageAnimation.slide);
    expect(NovelPageAnimation.fromString(null), NovelPageAnimation.slide);
  });
}
