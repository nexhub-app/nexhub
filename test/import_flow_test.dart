import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/local/local_content_manager.dart';

/// spec F2.3.3：覆盖 _pickFolder 递归真分类（通过公共核心函数 classifyFolderByContent）。
///
/// classifyFolderByContent 是从 browse_local_screen._pickFolder 抽出的可测顶层函数，
/// 实现 spec F2.D：递归扫描目录，按真实文件多数扩展名决定 LocalMediaKind。
/// 用 Directory.systemTemp 建临时目录，测完清理。
void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('import_flow_test');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  File makeFile(String path) {
    final f = File(path);
    f.createSync(recursive: true);
    f.writeAsStringSync('placeholder');
    return f;
  }

  group('classifyFolderByContent - comics folder', () {
    test('folder with .cbz/.cbr files classifies as images', () {
      makeFile('${tempRoot.path}/chapter1.cbz');
      makeFile('${tempRoot.path}/chapter2.cbr');
      expect(
        classifyFolderByContent(tempRoot.path),
        LocalMediaKind.images,
      );
    });
    test('folder with .zip/.rar archives classifies as images', () {
      makeFile('${tempRoot.path}/vol1.zip');
      makeFile('${tempRoot.path}/vol2.rar');
      expect(
        classifyFolderByContent(tempRoot.path),
        LocalMediaKind.images,
      );
    });
  });

  group('classifyFolderByContent - video folder', () {
    test('folder with .mp4/.mkv files classifies as video', () {
      makeFile('${tempRoot.path}/ep01.mp4');
      makeFile('${tempRoot.path}/ep02.mkv');
      expect(
        classifyFolderByContent(tempRoot.path),
        LocalMediaKind.video,
      );
    });
    test('folder with .ts/.flv files classifies as video', () {
      makeFile('${tempRoot.path}/clip1.ts');
      makeFile('${tempRoot.path}/clip2.flv');
      expect(
        classifyFolderByContent(tempRoot.path),
        LocalMediaKind.video,
      );
    });
  });

  group('classifyFolderByContent - image folder', () {
    test('folder with .jpg/.png files classifies as images', () {
      makeFile('${tempRoot.path}/p001.jpg');
      makeFile('${tempRoot.path}/p002.png');
      makeFile('${tempRoot.path}/p003.jpeg');
      expect(
        classifyFolderByContent(tempRoot.path),
        LocalMediaKind.images,
      );
    });
  });

  group('classifyFolderByContent - novel folder', () {
    test('folder with .txt/.epub files classifies as text', () {
      makeFile('${tempRoot.path}/ch01.txt');
      makeFile('${tempRoot.path}/ch02.epub');
      expect(
        classifyFolderByContent(tempRoot.path),
        LocalMediaKind.text,
      );
    });
  });

  group('classifyFolderByContent - recursive scan', () {
    test('scans nested subdirectories recursively', () {
      makeFile('${tempRoot.path}/season1/ep01.mp4');
      makeFile('${tempRoot.path}/season1/ep02.mp4');
      makeFile('${tempRoot.path}/season2/ep03.mkv');
      expect(
        classifyFolderByContent(tempRoot.path),
        LocalMediaKind.video,
      );
    });
    test('mixed folder decides by majority kind', () {
      // 3 videos vs 1 image -> video
      makeFile('${tempRoot.path}/v1.mp4');
      makeFile('${tempRoot.path}/v2.mkv');
      makeFile('${tempRoot.path}/v3.avi');
      makeFile('${tempRoot.path}/cover.jpg');
      expect(
        classifyFolderByContent(tempRoot.path),
        LocalMediaKind.video,
      );
    });
    test('ignores unrecognized files and counts only recognized', () {
      makeFile('${tempRoot.path}/readme.pdf'); // unrecognized
      makeFile('${tempRoot.path}/notes.mobi'); // unrecognized
      makeFile('${tempRoot.path}/novel.epub'); // text
      expect(
        classifyFolderByContent(tempRoot.path),
        LocalMediaKind.text,
      );
    });
  });

  group('classifyFolderByContent - empty / no recognized', () {
    test('empty folder returns null', () {
      expect(classifyFolderByContent(tempRoot.path), isNull);
    });
    test('folder with only unrecognized files returns null', () {
      makeFile('${tempRoot.path}/doc.pdf');
      makeFile('${tempRoot.path}/data.xyz');
      makeFile('${tempRoot.path}/readme');
      expect(classifyFolderByContent(tempRoot.path), isNull);
    });
    test('folder with only subdirectories (no files) returns null', () {
      Directory('${tempRoot.path}/sub1').createSync();
      Directory('${tempRoot.path}/sub2').createSync();
      expect(classifyFolderByContent(tempRoot.path), isNull);
    });
  });

  group('classifyFolderByContent - error cases', () {
    test('non-existent directory throws FileSystemException', () {
      final ghost = '${tempRoot.path}/does_not_exist';
      expect(
        () => classifyFolderByContent(ghost),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
