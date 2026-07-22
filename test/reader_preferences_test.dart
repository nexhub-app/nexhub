import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/comic/models/reader_preferences.dart';
import 'package:nexhub/core/theme/reader_tokens.dart';

void main() {
  test('json round-trip preserves all fields', () {
    const prefs = ReaderPreferences(
      readingMode: ReadingMode.webtoonWithGap,
      background: ReaderBackgroundColor.gray,
      tapZoneLayout: ReaderTapZoneLayout.kindle,
      orientation: ScreenOrientation.lockLandscape,
      doubleTapZoom: false,
      minScale: 1.5,
      maxScale: 5.0,
    );
    final back = ReaderPreferences.fromJson(prefs.toJson());
    expect(back.readingMode, ReadingMode.webtoonWithGap);
    expect(back.background, ReaderBackgroundColor.gray);
    expect(back.tapZoneLayout, ReaderTapZoneLayout.kindle);
    expect(back.orientation, ScreenOrientation.lockLandscape);
    expect(back.doubleTapZoom, false);
    expect(back.minScale, 1.5);
    expect(back.maxScale, 5.0);
  });

  test('defaults applied for unknown / missing values', () {
    final prefs = ReaderPreferences.fromJson(<String, dynamic>{'readingMode': 'nope'});
    expect(prefs.readingMode, ReadingMode.singleLTR);
    expect(prefs.background, ReaderBackgroundColor.black);
  });

  test('store returns default then persists', () async {
    final store = ReaderPreferencesStore(backend: InMemoryBackend());
    expect((await store.get('x')).readingMode, ReadingMode.singleLTR);
    await store.save('x', const ReaderPreferences(readingMode: ReadingMode.singleRTL));
    expect((await store.get('x')).readingMode, ReadingMode.singleRTL);
  });

  test('resolveBackgroundColor maps preset index', () {
    const black = ReaderPreferences(background: ReaderBackgroundColor.black);
    const autoDark = ReaderPreferences(background: ReaderBackgroundColor.auto);
    expect(black.resolveBackgroundColor(false), ReaderTokens.bgPresets[0]);
    expect(autoDark.resolveBackgroundColor(true), ReaderTokens.bgPresets[0]);
    expect(autoDark.resolveBackgroundColor(false), ReaderTokens.bgPresets[2]);
  });

  test('reading mode helpers', () {
    expect(ReadingMode.webtoon.isWebtoon, true);
    expect(ReadingMode.webtoonWithGap.isWebtoon, true);
    expect(ReadingMode.singleLTR.isPaged, true);
    expect(ReadingMode.singleVertical.isPaged, true);
  });
}
