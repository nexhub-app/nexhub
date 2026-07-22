// Unit tests for HtmlUtils XPath engine (V2 spec 6.1 / 16.4 function set).
//
// Covers the legacy forms plus the new functions required by builtin sources
// such as pms_fsdm.json / pms_gugu3.json:
//   //tag, //tag[@attr], //tag[@attr='v'], //tag[contains(@attr,'v')],
//   //tag/@attr, //tag/text(), following-sibling::tag,
//   substring-before / substring-after (including nested combinations).
//
// All fixtures are ASCII on purpose (no user-visible l10n strings here).
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/utils/html_utils.dart';

// Sample HTML mirroring a pms_fsdm-style listing + detail page: list items
// carry /voddetail/{id}.html links, a detail block has an h1, a cover image,
// and a Director label followed by sibling <a> actors.
const String _html = '''
<html><body>
<ul class="list">
  <li class="item" data-id="123">
    <a href="https://www.fsdm02.com/voddetail/123.html" title="Show A">Show A</a>
    <img data-src="https://cdn/a.jpg" />
  </li>
  <li class="item" data-id="456">
    <a href="https://www.fsdm02.com/voddetail/456.html" title="Show B">Show B</a>
    <img data-src="https://cdn/b.jpg" />
  </li>
</ul>
<div class="detail">
  <h1>Show A Title</h1>
  <div class="detail-pic"><img src="https://cdn/cover.jpg" /></div>
  <span class="label">Director</span>
  <a href="/person/1">Alice</a>
  <a href="/person/2">Bob</a>
</div>
</body></html>
''';

void main() {
  group('HtmlUtils XPath - basic forms', () {
    test('//tag returns all matching element texts', () {
      expect(HtmlUtils.queryAll(_html, '//li'), ['Show A', 'Show B']);
    });

    test("//tag[@attr] matches elements that declare attr", () {
      expect(HtmlUtils.query(_html, '//li[@data-id]'), 'Show A');
    });

    test("//tag[@attr='v'] matches by attribute value", () {
      expect(HtmlUtils.query(_html, "//li[@data-id='456']"), 'Show B');
    });

    test("//tag[contains(@attr,'v')] matches by substring", () {
      expect(
        HtmlUtils.queryAll(_html, "//a[contains(@href,'/voddetail/')]"),
        ['Show A', 'Show B'],
      );
    });

    test('//tag/@attr reads an attribute value via query', () {
      expect(HtmlUtils.query(_html, '//li/@data-id'), '123');
    });

    test('//tag/@attr returns all values via queryAll', () {
      expect(HtmlUtils.queryAll(_html, '//li/@data-id'), ['123', '456']);
    });

    test('//tag/text() extracts element text', () {
      expect(HtmlUtils.query(_html, '//h1/text()'), 'Show A Title');
    });

    test('//div[@class]//img/@src resolves a descendant attribute', () {
      expect(
        HtmlUtils.query(_html, "//div[@class='detail-pic']//img/@src"),
        'https://cdn/cover.jpg',
      );
    });
  });

  group('HtmlUtils XPath - following-sibling axis', () {
    test('//tag/following-sibling::tag2 returns following siblings', () {
      expect(
        HtmlUtils.queryAll(_html, '//span/following-sibling::a'),
        ['Alice', 'Bob'],
      );
    });

    test('predicate + following-sibling + text() combination', () {
      expect(
        HtmlUtils.queryAll(
          _html,
          "//span[contains(text(),'Director')]/following-sibling::a/text()",
        ),
        ['Alice', 'Bob'],
      );
    });
  });

  group('HtmlUtils XPath - substring functions (pms_fsdm id selector)', () {
    test("substring-before(./a/@href, '/voddetail/')", () {
      expect(
        HtmlUtils.query(_html, "substring-before(./a/@href, '/voddetail/')"),
        'https://www.fsdm02.com',
      );
    });

    test("substring-after(./a/@href, '/voddetail/')", () {
      expect(
        HtmlUtils.query(_html, "substring-after(./a/@href, '/voddetail/')"),
        '123.html',
      );
    });

    test('nested substring-before(substring-after(...)) yields the id', () {
      expect(
        HtmlUtils.query(
          _html,
          "substring-before(substring-after(./a/@href, '/voddetail/'), '.html')",
        ),
        '123',
      );
    });

    test('substring functions work via queryAll too', () {
      expect(
        HtmlUtils.queryAll(
          _html,
          "substring-before(substring-after(./a/@href, '/voddetail/'), '.html')",
        ),
        ['123'],
      );
    });
  });

  group('HtmlUtils queryAttr - XPath branch', () {
    test('reads a separate attr from the first matched element', () {
      expect(
        HtmlUtils.queryAttr(_html, "//li[@class='item']", 'data-id'),
        '123',
      );
    });

    test('trailing /@attr on selector is stripped in favour of the arg', () {
      // Selector targets @href but the explicit attr arg (title) wins; the
      // first <a> carries both href and title.
      expect(
        HtmlUtils.queryAttr(_html, '//a/@href', 'title'),
        'Show A',
      );
    });
  });

  group('HtmlUtils - CSS routing unaffected', () {
    test('CSS class selector still works alongside XPath', () {
      expect(HtmlUtils.queryAll(_html, 'li.item'), ['Show A', 'Show B']);
      expect(HtmlUtils.query(_html, 'h1'), 'Show A Title');
    });
  });
}
