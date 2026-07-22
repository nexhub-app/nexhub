// Unit tests for JsonPath evaluator (M4.1 JSONPath expressiveness extension).
//
// Covers nested paths, conditional filters, recursive descent `..`, array
// slicing (positive/negative indices, ranges, step), edge cases (empty arrays,
// missing fields, invalid expressions do not throw), and backward compatibility
// with the legacy simple forms (`$.foo`, `$.foo.bar`, `$[0]`, `$.list[*].id`).
//
// Fixtures are ASCII; any CJK fixture data uses `\uXXXX` escapes to avoid
// tripping the encoding guard.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/utils/json_path.dart';

// Goessner-style sample store used across many JSONPath specs.
const Map<String, dynamic> _store = {
  'store': {
    'book': [
      {'category': 'reference', 'author': 'Nigel Rees', 'title': 'Sayings of the Century', 'price': 8.95},
      {'category': 'fiction', 'author': 'Evelyn Waugh', 'title': 'Sword of Honour', 'price': 12.99},
      {'category': 'fiction', 'author': 'Herman Melville', 'title': 'Moby Dick', 'isbn': '0-553-21311-3', 'price': 8.99},
      {'category': 'fiction', 'author': 'J. R. R. Tolkien', 'title': 'The Lord of the Rings', 'isbn': '0-395-19395-8', 'price': 22.99},
    ],
    'bicycle': {'color': 'red', 'price': 19.95},
  },
};

void main() {
  group('nested paths (with array indices)', () {
    test('\$.store.book[0].title resolves a deeply nested field', () {
      expect(JsonPath.eval(r'$.store.book[0].title', _store), 'Sayings of the Century');
    });

    test('\$.store.book[2].author resolves via numeric index', () {
      expect(JsonPath.eval(r'$.store.book[2].author', _store), 'Herman Melville');
    });

    test('\$.store.bicycle.color resolves a nested map field', () {
      expect(JsonPath.eval(r'$.store.bicycle.color', _store), 'red');
    });

    test('\$.store.book[3].isbn resolves the last book isbn', () {
      expect(JsonPath.eval(r'$.store.book[3].isbn', _store), '0-395-19395-8');
    });

    test('negative index \$.store.book[-1].title returns last element', () {
      expect(JsonPath.eval(r'$.store.book[-1].title', _store), 'The Lord of the Rings');
    });

    test('negative index \$.store.book[-2].title returns second to last', () {
      expect(JsonPath.eval(r'$.store.book[-2].title', _store), 'Moby Dick');
    });
  });

  group('conditional filters [?(...)]', () {
    test('numeric < filter returns matching elements', () {
      final r = JsonPath.eval(r'$.store.book[?(@.price < 10)]', _store) as List;
      expect(r, hasLength(2));
      expect((r[0] as Map)['title'], 'Sayings of the Century');
      expect((r[1] as Map)['title'], 'Moby Dick');
    });

    test('numeric > filter returns matching elements', () {
      final r = JsonPath.eval(r'$.store.book[?(@.price > 20)]', _store) as List;
      expect(r, hasLength(1));
      expect((r[0] as Map)['title'], 'The Lord of the Rings');
    });

    test('numeric >= filter is inclusive', () {
      final r = JsonPath.eval(r'$.store.book[?(@.price >= 12.99)]', _store) as List;
      expect(r, hasLength(2));
      expect((r[0] as Map)['title'], 'Sword of Honour');
      expect((r[1] as Map)['title'], 'The Lord of the Rings');
    });

    test('numeric <= filter is inclusive', () {
      final r = JsonPath.eval(r'$.store.book[?(@.price <= 8.99)]', _store) as List;
      expect(r, hasLength(2));
    });

    test("string == filter with single quotes", () {
      final r = JsonPath.eval(r"$.store.book[?(@.category=='fiction')]", _store) as List;
      expect(r, hasLength(3));
    });

    test('string == filter with double quotes', () {
      final r = JsonPath.eval(r'$.store.book[?(@.category=="fiction")]', _store) as List;
      expect(r, hasLength(3));
    });

    test('string != filter returns non-matching elements', () {
      final r = JsonPath.eval(r"$.store.book[?(@.category!='fiction')]", _store) as List;
      expect(r, hasLength(1));
      expect((r[0] as Map)['category'], 'reference');
    });

    test('field presence via != on missing isbn', () {
      // Books without isbn should satisfy @.isbn != '0-553-21311-3' (null != value -> true).
      final r = JsonPath.eval(r"$.store.book[?(@.isbn != '0-553-21311-3')]", _store) as List;
      expect(r, hasLength(3));
    });

    test('combined: filter then index path returns scalar', () {
      expect(
        JsonPath.eval(r"$.store.book[?(@.category=='fiction')][0].author", _store),
        'Evelyn Waugh',
      );
    });
  });

  group('recursive descent ..', () {
    test('\$..author collects all author values at any depth', () {
      expect(
        JsonPath.eval(r'$..author', _store),
        ['Nigel Rees', 'Evelyn Waugh', 'Herman Melville', 'J. R. R. Tolkien'],
      );
    });

    test('\$..price collects every price (books + bicycle)', () {
      expect(
        JsonPath.eval(r'$..price', _store),
        [8.95, 12.99, 8.99, 22.99, 19.95],
      );
    });

    test('\$..book flattens the book array into the result list', () {
      final r = JsonPath.eval(r'$..book', _store) as List;
      expect(r, hasLength(4));
      expect((r[0] as Map)['title'], 'Sayings of the Century');
      expect((r[3] as Map)['title'], 'The Lord of the Rings');
    });

    test('\$..book[0].title applies index + key after descent', () {
      // Descent always yields a collection; the single match is wrapped in a list.
      expect(JsonPath.eval(r'$..book[0].title', _store), ['Sayings of the Century']);
    });

    test('\$..book[?(@.price < 10)] filters within descent', () {
      final r = JsonPath.eval(r'$..book[?(@.price < 10)]', _store) as List;
      expect(r, hasLength(2));
      expect((r[0] as Map)['title'], 'Sayings of the Century');
      expect((r[1] as Map)['title'], 'Moby Dick');
    });

    test('\$.store..book descends from a sub-root', () {
      final r = JsonPath.eval(r'$.store..book', _store) as List;
      expect(r, hasLength(4));
    });

    test('\$..title collects all titles', () {
      expect(
        JsonPath.eval(r'$..title', _store),
        ['Sayings of the Century', 'Sword of Honour', 'Moby Dick', 'The Lord of the Rings'],
      );
    });

    test('recursive descent collects CJK-titled field (unicode escapes)', () {
      // \u4e09\u56fd\u6f14\u4e49 = 三国演义, \u897f\u6e38\u8bb0 = 西游记.
      const data = {
        'shelf': [
          {'name': '\u4e09\u56fd\u6f14\u4e49', 'price': 59},
          {'name': '\u897f\u6e38\u8bb0', 'price': 49},
        ],
      };
      expect(
        JsonPath.eval(r'$..name', data),
        ['\u4e09\u56fd\u6f14\u4e49', '\u897f\u6e38\u8bb0'],
      );
    });

    test('filter with CJK string literal (unicode escapes) matches', () {
      // \u5c0f\u8bf4 = 小说 (fiction), \u6f2b\u753b = 漫画 (manga).
      const data = {
        'list': [
          {'cat': '\u5c0f\u8bf4', 'n': 1},
          {'cat': '\u6f2b\u753b', 'n': 2},
        ],
      };
      // Non-raw string so \uXXXX becomes the actual CJK char in the path.
      final r = JsonPath.eval("\$..list[?(@.cat=='\u5c0f\u8bf4')]", data) as List;
      expect(r, hasLength(1));
      expect((r[0] as Map)['n'], 1);
    });
  });

  group('array slicing', () {
    test('[1:3] returns indices 1 and 2', () {
      final r = JsonPath.eval(r'$.store.book[1:3]', _store) as List;
      expect(r, hasLength(2));
      expect((r[0] as Map)['title'], 'Sword of Honour');
      expect((r[1] as Map)['title'], 'Moby Dick');
    });

    test('[:2] returns first two elements', () {
      final r = JsonPath.eval(r'$.store.book[:2]', _store) as List;
      expect(r, hasLength(2));
      expect((r[0] as Map)['title'], 'Sayings of the Century');
    });

    test('[2:] returns from index 2 to end', () {
      final r = JsonPath.eval(r'$.store.book[2:]', _store) as List;
      expect(r, hasLength(2));
      expect((r[1] as Map)['title'], 'The Lord of the Rings');
    });

    test('[-2:] returns last two elements', () {
      final r = JsonPath.eval(r'$.store.book[-2:]', _store) as List;
      expect(r, hasLength(2));
      expect((r[0] as Map)['title'], 'Moby Dick');
      expect((r[1] as Map)['title'], 'The Lord of the Rings');
    });

    test('[-1] returns the last element as single value', () {
      expect(
        JsonPath.eval(r'$.store.book[-1].title', _store),
        'The Lord of the Rings',
      );
    });

    test('[::2] returns every other element (step)', () {
      final r = JsonPath.eval(r'$.store.book[::2]', _store) as List;
      expect(r, hasLength(2));
      expect((r[0] as Map)['title'], 'Sayings of the Century');
      expect((r[1] as Map)['title'], 'Moby Dick');
    });

    test('[1::2] returns every other starting at 1', () {
      final r = JsonPath.eval(r'$.store.book[1::2]', _store) as List;
      expect(r, hasLength(2));
      expect((r[0] as Map)['title'], 'Sword of Honour');
      expect((r[1] as Map)['title'], 'The Lord of the Rings');
    });

    test('slice out of range is clamped, no throw', () {
      final r = JsonPath.eval(r'$.store.book[10:20]', _store) as List;
      expect(r, isEmpty);
    });
  });

  group('edge cases', () {
    test('filter on empty array returns empty list', () {
      expect(JsonPath.eval(r'$.items[?(@.x > 1)]', {'items': <dynamic>[]}), isEmpty);
    });

    test('slice on empty array returns empty list', () {
      expect(JsonPath.eval(r'$.items[1:3]', {'items': <dynamic>[]}), isEmpty);
    });

    test('descent for non-existent field returns empty list', () {
      expect(JsonPath.eval(r'$..nonexistent', _store), isEmpty);
    });

    test('index out of range returns null (no throw)', () {
      expect(JsonPath.eval(r'$.store.book[99].title', _store), isNull);
    });

    test('missing nested field returns null (no throw)', () {
      expect(JsonPath.eval(r'$.store.book[0].missing', _store), isNull);
    });

    test('filter where no element matches returns empty list', () {
      expect(JsonPath.eval(r'$.store.book[?(@.price > 1000)]', _store), isEmpty);
    });

    test('invalid expression does not throw (unterminated bracket, garbage)', () {
      // The key requirement is robustness: malformed paths never throw.
      expect(() => JsonPath.eval(r'$.store.book[', _store), returnsNormally);
      expect(() => JsonPath.eval(r'$.][', _store), returnsNormally);
      expect(() => JsonPath.eval(r'$$$..[', _store), returnsNormally);
      expect(() => JsonPath.eval(r'$.store.book[?(@.price <<<', _store), returnsNormally);
    });

    test('non-\$ path returns null', () {
      expect(JsonPath.eval('store.book', _store), isNull);
    });

    test('filter on non-list returns null (no throw)', () {
      expect(JsonPath.eval(r'$.store.bicycle[?(@.price > 1)]', _store), isNull);
    });

    test('slice on non-list returns null (no throw)', () {
      expect(JsonPath.eval(r'$.store.bicycle[0:2]', _store), isNull);
    });
  });

  group('backward compatibility', () {
    test('\$.foo returns scalar for top-level key', () {
      expect(JsonPath.eval(r'$.store', _store), isA<Map>());
    });

    test('\$.foo.bar returns nested scalar', () {
      expect(JsonPath.eval(r'$.store.bicycle.color', _store), 'red');
    });

    test('\$[0] returns first list element on a top-level list', () {
      const data = [10, 20, 30];
      expect(JsonPath.eval(r'$[0]', data), 10);
    });

    test('\$.list returns the list value itself', () {
      const data = {'list': [1, 2, 3]};
      expect(JsonPath.eval(r'$.list', data), [1, 2, 3]);
    });

    test('\$.list[*] returns the list (legacy star pass-through)', () {
      const data = {'list': [1, 2, 3]};
      expect(JsonPath.eval(r'$.list[*]', data), [1, 2, 3]);
    });

    test('\$.list[*].id maps over elements (legacy auto-map)', () {
      const data = {
        'list': [
          {'id': 'a'},
          {'id': 'b'},
          {'id': 'c'},
        ],
      };
      expect(JsonPath.eval(r'$.list[*].id', data), ['a', 'b', 'c']);
    });

    test('\$.list[1] returns a single indexed element', () {
      const data = {'list': [10, 20, 30]};
      expect(JsonPath.eval(r'$.list[1]', data), 20);
    });

    test('plugin-style \$.vod_name on a flat record', () {
      const record = {'vod_id': 7, 'vod_name': 'Demo'};
      expect(JsonPath.eval(r'$.vod_name', record), 'Demo');
      expect(JsonPath.eval(r'$.vod_id', record), 7);
    });
  });
}
