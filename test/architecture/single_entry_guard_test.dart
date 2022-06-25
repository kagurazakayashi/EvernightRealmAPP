/// 架構守衛測試：把「統一存取入口」變成可執行的約束，而不是一句口號。
///
/// 前端規格要求所有網路存取集中一處，否則頁面就能繞過錯誤轉換與位址驗證，
/// 「網路錯誤不顯示為成功」隨時會被一句 `http.get` 破掉。這裡直接掃原始碼：
/// 一旦有 core/api 以外的檔案碰傳輸套件或自開連線，測試即點名失敗。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 允許直接使用傳輸套件的目錄（統一存取層本身）。
const String _allowedDirectory = 'lib/core/api/';

/// 不應出現在 lib/core/api 以外的存取方式。
const List<String> _forbidden = <String>[
  "import 'package:http/",
  'import "package:http/',
  'import package:http/',
  "import 'dart:io'",
  'Socket(',
  'HttpClient(',
  'WebSocket(',
];

/// 遞迴收集 lib 下的 Dart 原始檔。
List<File> _dartFilesUnder(String directory) {
  return Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'))
      .toList();
}

void main() {
  group('統一存取入口', () {
    test('lib/core/api 以外不出現傳輸套件與原生連線', () {
      final List<File> files = _dartFilesUnder('lib');
      expect(files, isNotEmpty, reason: '掃描路徑不對時這條守衛等於沒跑');

      final List<String> offenders = <String>[];
      for (final File file in files) {
        final String path = file.path.replaceAll(r'\', '/');
        if (path.startsWith(_allowedDirectory)) {
          continue;
        }
        // 本地化生成檔由工具產出，不在本約束的範圍內。
        if (path.contains('/l10n/app_localizations')) {
          continue;
        }
        final List<String> lines = file.readAsLinesSync();
        for (int index = 0; index < lines.length; index++) {
          for (final String needle in _forbidden) {
            if (lines[index].contains(needle)) {
              offenders.add('$path:${index + 1} 含 $needle');
            }
          }
        }
      }

      expect(offenders, isEmpty, reason: '網路存取必須經 lib/core/api 收口');
    });

    test('core/api 是唯一導入傳輸套件的目錄', () {
      final List<String> users = _dartFilesUnder('lib/core/api')
          .where(
            (File file) => file.readAsStringSync().contains('package:http'),
          )
          .map((File file) => file.path.replaceAll(r'\', '/'))
          .toList();

      expect(users, containsAll(<String>['lib/core/api/api_client.dart']));
      expect(
        users.every((String path) => path.startsWith(_allowedDirectory)),
        isTrue,
      );
    });
  });
}
