/// ARB 資源檔的鍵集一致性檢查：讓「缺鍵」在測試階段就能被點名。
///
/// gen-l10n 對缺鍵只做回退而不報錯（同語言的地區變體甚至會回退到基礎語言文字），
/// 因此這裡把四份資源的鍵集、空值與檔名/欄位一致性當成硬性斷言。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 參與檢查的資源檔與產品四語言的對應。
const Map<String, String> _arbFilesByLocale = <String, String>{
  'en': 'app_en.arb',
  'zh': 'app_zh.arb',
  'zh_TW': 'app_zh_TW.arb',
  'ja': 'app_ja.arb',
};

/// 模板檔對應的語言（鍵集權威來源，缺鍵回退到此檔文字）。
const String _templateLocale = 'en';

/// 讀取資源檔內容，路徑相對於套件根目錄。
Map<String, dynamic> _readArb(String fileName) {
  final File file = File('lib/l10n/$fileName');
  if (!file.existsSync()) {
    throw StateError('缺少資源檔 ${file.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// 取出一般鍵（排除 @@ 與 @ 開頭的欄位定義）。
List<String> _keysOf(Map<String, dynamic> arb) {
  return arb.keys.where((key) => !key.startsWith('@')).toList()..sort();
}

void main() {
  late final Map<String, Map<String, dynamic>> arbByLocale;
  late final List<String> templateKeys;

  // 讀檔集中在 setUpAll，讓缺檔與格式問題以測試失敗呈現，
  // 而不是在測試外的 expect 觸發 OutsideTestException。
  setUpAll(() {
    arbByLocale = _arbFilesByLocale.map(
      (locale, fileName) => MapEntry(locale, _readArb(fileName)),
    );
    templateKeys = _keysOf(arbByLocale[_templateLocale]!);
  });

  group('ARB 資源檔', () {
    test('四份資源齊備，檔名與 @@locale 一致', () {
      expect(arbByLocale.length, 4);
      expect(templateKeys, isNotEmpty);
      for (final entry in _arbFilesByLocale.entries) {
        expect(
          arbByLocale[entry.key]!['@@locale'],
          entry.key,
          reason: '${entry.value} 的 @@locale 與檔名不符',
        );
      }
    });

    test('四語言鍵集與模板完全對齊，缺鍵與多鍵都要被點名', () {
      for (final entry in arbByLocale.entries) {
        final List<String> keys = _keysOf(entry.value);
        expect(
          keys,
          equals(templateKeys),
          reason:
              '${entry.key} 相對模板缺鍵 '
              '${templateKeys.toSet().difference(keys.toSet()).toList()}、'
              '多鍵 ${keys.toSet().difference(templateKeys.toSet()).toList()}',
        );
      }
    });

    test('每個鍵在四語言都有非空文字，且模板都有欄位說明', () {
      final Map<String, dynamic> template = arbByLocale[_templateLocale]!;
      for (final key in templateKeys) {
        for (final entry in arbByLocale.entries) {
          final Object? value = entry.value[key];
          expect(
            value is String && value.isNotEmpty,
            isTrue,
            reason: '${entry.key} 的 $key 是空字串',
          );
        }
        expect(
          template['@$key'],
          isA<Map<String, dynamic>>(),
          reason: '模板缺 $key 的欄位說明',
        );
      }
    });
  });
}
