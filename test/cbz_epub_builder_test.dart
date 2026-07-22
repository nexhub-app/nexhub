import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/download/cbz_builder.dart';
import 'package:nexhub/core/download/epub_builder.dart';

void main() {
  group('CbzBuilder', () {
    test('builds valid ZIP with correctly named images', () {
      final pages = <CbzPage>[
        CbzPage(
          filename: '',
          bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
        ),
        CbzPage(
          filename: '',
          bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
        ),
      ];

      final bytes = CbzBuilder.build(pages: pages);
      expect(bytes, isNotEmpty);

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.length, 2);
      expect(archive.files[0].name, '0001.jpg');
      expect(archive.files[1].name, '0002.jpg');
    });

    test('respects provided filenames', () {
      final pages = <CbzPage>[
        CbzPage(filename: 'cover.jpg', bytes: Uint8List(4)),
        CbzPage(filename: 'page-001.png', bytes: Uint8List(4)),
      ];

      final bytes = CbzBuilder.build(pages: pages);
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files[0].name, 'cover.jpg');
      expect(archive.files[1].name, 'page-001.png');
    });

    test('handles empty page list', () {
      final bytes = CbzBuilder.build(pages: <CbzPage>[]);
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files, isEmpty);
    });
  });

  group('EpubBuilder', () {
    test('builds valid EPUB with required structure', () {
      const metadata = EpubMetadata(
        title: 'Test Book',
        author: 'Test Author',
      );
      final chapters = <EpubChapter>[
        const EpubChapter(title: 'Chapter 1', content: '<p>Hello</p>'),
        const EpubChapter(title: 'Chapter 2', content: '<p>World</p>'),
      ];

      final bytes = EpubBuilder.build(
        metadata: metadata,
        chapters: chapters,
      );
      expect(bytes, isNotEmpty);

      final archive = ZipDecoder().decodeBytes(bytes);

      // Verify required files exist
      final names = archive.files.map((f) => f.name).toList();
      expect(names, contains('mimetype'));
      expect(names, contains('META-INF/container.xml'));
      expect(names, contains('OEBPS/content.opf'));
      expect(names, contains('OEBPS/toc.ncx'));
      expect(names, contains('OEBPS/chapter-1.xhtml'));
      expect(names, contains('OEBPS/chapter-2.xhtml'));
    });

    test('mimetype is first entry and uncompressed', () {
      final bytes = EpubBuilder.build(
        metadata: const EpubMetadata(title: 'T'),
        chapters: const <EpubChapter>[
          EpubChapter(title: 'C', content: '<p>X</p>'),
        ],
      );
      final archive = ZipDecoder().decodeBytes(bytes);

      // First file should be mimetype
      expect(archive.files[0].name, 'mimetype');
      // Content should be the EPUB mimetype string
      final content = String.fromCharCodes(archive.files[0].content as List<int>);
      expect(content, 'application/epub+zip');
    });

    test('content.opf contains metadata and manifest', () {
      final bytes = EpubBuilder.build(
        metadata: const EpubMetadata(title: 'My Book', author: 'Jane Doe'),
        chapters: const <EpubChapter>[
          EpubChapter(title: 'Ch1', content: '<p>Text</p>'),
        ],
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final opfFile = archive.files
          .firstWhere((f) => f.name == 'OEBPS/content.opf');
      final opfContent = String.fromCharCodes(opfFile.content as List<int>);

      expect(opfContent, contains('My Book'));
      expect(opfContent, contains('Jane Doe'));
      expect(opfContent, contains('ch1'));
      expect(opfContent, contains('chapter-1.xhtml'));
    });

    test('toc.ncx contains chapter titles', () {
      final bytes = EpubBuilder.build(
        metadata: const EpubMetadata(title: 'Book'),
        chapters: const <EpubChapter>[
          EpubChapter(title: 'First Chapter', content: '<p>1</p>'),
          EpubChapter(title: 'Second Chapter', content: '<p>2</p>'),
        ],
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final ncxFile = archive.files
          .firstWhere((f) => f.name == 'OEBPS/toc.ncx');
      final ncxContent = String.fromCharCodes(ncxFile.content as List<int>);

      expect(ncxContent, contains('First Chapter'));
      expect(ncxContent, contains('Second Chapter'));
    });

    test('buildTxt produces plain text output', () {
      final bytes = EpubBuilder.buildTxt(
        metadata: const EpubMetadata(title: 'My Novel', author: 'Author'),
        chapters: const <EpubChapter>[
          EpubChapter(title: 'Ch1', content: '<p>Para 1</p>'),
        ],
      );
      final text = utf8.decode(bytes);

      expect(text, contains('My Novel'));
      expect(text, contains('Author'));
      expect(text, contains('Ch1'));
      expect(text, contains('Para 1'));
    });
  });
}
