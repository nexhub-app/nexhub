import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/local/local_content_manager.dart';

/// spec F2.3.2：覆盖 classifyByPath 各格式识别 + 未识别返回 null + 大小写不敏感。
///
/// 注意：LocalMediaKind 枚举仅 video/images/text 三种；
/// 漫画（cbz/cbr/zip/rar）映射到 images，小说（txt/epub/umd）映射到 text。
void main() {
  group('classifyByPath - comics (LocalMediaKind.images)', () {
    test('recognizes .cbz as images', () {
      expect(classifyByPath('foo.cbz'), LocalMediaKind.images);
    });
    test('recognizes .cbr as images', () {
      expect(classifyByPath('foo.cbr'), LocalMediaKind.images);
    });
    test('recognizes .zip as images', () {
      expect(classifyByPath('foo.zip'), LocalMediaKind.images);
    });
    test('recognizes .rar as images', () {
      expect(classifyByPath('foo.rar'), LocalMediaKind.images);
    });
  });

  group('classifyByPath - novels (LocalMediaKind.text)', () {
    test('recognizes .txt as text', () {
      expect(classifyByPath('foo.txt'), LocalMediaKind.text);
    });
    test('recognizes .epub as text', () {
      expect(classifyByPath('foo.epub'), LocalMediaKind.text);
    });
    test('recognizes .umd as text', () {
      expect(classifyByPath('foo.umd'), LocalMediaKind.text);
    });
  });

  group('classifyByPath - videos (LocalMediaKind.video)', () {
    test('recognizes .mp4 as video', () {
      expect(classifyByPath('foo.mp4'), LocalMediaKind.video);
    });
    test('recognizes .mkv as video', () {
      expect(classifyByPath('foo.mkv'), LocalMediaKind.video);
    });
    test('recognizes .mov as video', () {
      expect(classifyByPath('foo.mov'), LocalMediaKind.video);
    });
    test('recognizes .webm as video', () {
      expect(classifyByPath('foo.webm'), LocalMediaKind.video);
    });
    test('recognizes .avi as video', () {
      expect(classifyByPath('foo.avi'), LocalMediaKind.video);
    });
    test('recognizes .flv as video', () {
      expect(classifyByPath('foo.flv'), LocalMediaKind.video);
    });
    test('recognizes .m4v as video', () {
      expect(classifyByPath('foo.m4v'), LocalMediaKind.video);
    });
    test('recognizes .ts as video', () {
      expect(classifyByPath('foo.ts'), LocalMediaKind.video);
    });
  });

  group('classifyByPath - images (LocalMediaKind.images)', () {
    test('recognizes .jpg as images', () {
      expect(classifyByPath('foo.jpg'), LocalMediaKind.images);
    });
    test('recognizes .jpeg as images', () {
      expect(classifyByPath('foo.jpeg'), LocalMediaKind.images);
    });
    test('recognizes .png as images', () {
      expect(classifyByPath('foo.png'), LocalMediaKind.images);
    });
    test('recognizes .webp as images', () {
      expect(classifyByPath('foo.webp'), LocalMediaKind.images);
    });
    test('recognizes .gif as images', () {
      expect(classifyByPath('foo.gif'), LocalMediaKind.images);
    });
    test('recognizes .bmp as images', () {
      expect(classifyByPath('foo.bmp'), LocalMediaKind.images);
    });
  });

  group('classifyByPath - directory', () {
    // F2 后目录由 classifyFolderByContent 处理；classifyByPath 对目录返回 null。
    test('treats trailing slash path as null (handled by classifyFolderByContent)',
        () {
      expect(classifyByPath('some/folder/'), isNull);
    });
    test(
        'treats trailing backslash path as null (handled by classifyFolderByContent)',
        () {
      expect(classifyByPath(r'some\folder\'), isNull);
    });
  });

  group('classifyByPath - unrecognized returns null', () {
    test('returns null for .pdf', () {
      expect(classifyByPath('foo.pdf'), isNull);
    });
    test('returns null for .unknown', () {
      expect(classifyByPath('foo.unknown'), isNull);
    });
    test('returns null for no extension', () {
      expect(classifyByPath('README'), isNull);
    });
  });

  group('classifyByPath - case insensitive', () {
    test('recognizes .CBZ as images', () {
      expect(classifyByPath('foo.CBZ'), LocalMediaKind.images);
    });
    test('recognizes .EPUB as text', () {
      expect(classifyByPath('foo.EPUB'), LocalMediaKind.text);
    });
    test('recognizes .MKV as video', () {
      expect(classifyByPath('foo.MKV'), LocalMediaKind.video);
    });
    test('recognizes .JPG as images', () {
      expect(classifyByPath('foo.JPG'), LocalMediaKind.images);
    });
    test('recognizes mixed-case .Cbz as images', () {
      expect(classifyByPath('foo.Cbz'), LocalMediaKind.images);
    });
  });

  group('classifyByPath - full path with directories', () {
    test('classifies file in nested windows path', () {
      expect(
        classifyByPath(r'C:\Users\me\Books\novel.epub'),
        LocalMediaKind.text,
      );
    });
    test('classifies file in nested posix path', () {
      expect(
        classifyByPath('/home/me/Downloads/video.mkv'),
        LocalMediaKind.video,
      );
    });
  });

  group('LocalMediaKind', () {
    test('parse returns matching kind', () {
      expect(LocalMediaKind.parse('video'), LocalMediaKind.video);
      expect(LocalMediaKind.parse('images'), LocalMediaKind.images);
      expect(LocalMediaKind.parse('text'), LocalMediaKind.text);
    });
    test('parse returns null for unknown', () {
      expect(LocalMediaKind.parse('comics'), isNull);
      expect(LocalMediaKind.parse(null), isNull);
      expect(LocalMediaKind.parse(''), isNull);
    });
    test('apiName matches name', () {
      for (final k in LocalMediaKind.values) {
        expect(k.apiName, k.name);
      }
    });
  });

  group('isImageFile', () {
    test('returns true for image extensions', () {
      expect(isImageFile('a.jpg'), isTrue);
      expect(isImageFile('a.cbz'), isTrue);
    });
    test('returns false for non-image extensions', () {
      expect(isImageFile('a.mp4'), isFalse);
      expect(isImageFile('a.pdf'), isFalse);
    });
  });
}
