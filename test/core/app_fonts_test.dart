/// 本地字體資產的測試：路徑規則與檔案存在性。
///
/// 實測教訓：資產檔名含 `[` `]` 時，AssetManifest 會存成百分號編碼名稱，
/// 而靜態伺服器不解碼，Web 端取字體直接 404、字體載入失敗。
/// 因此把「檔名不含方括號」與「三個字體檔案都在」寫成斷言。
library;

import 'dart:io';

import 'package:evernightrealm/core/app_fonts.dart';
import 'package:evernightrealm/core/app_locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppFonts 資產', () {
    test('每個介面語言都對到一個字體家族', () {
      final List<String> families = AppLocale.values
          .map(AppFonts.familyFor)
          .toList(growable: false);

      expect(families.toSet(), <String>{
        AppFonts.notoSansSc,
        AppFonts.notoSansTc,
        AppFonts.notoSansJp,
      });
    });

    test('資產路徑不含方括號或其他需編碼字元', () {
      for (final AppLocale locale in AppLocale.values) {
        final String asset = AppFonts.assetFor(AppFonts.familyFor(locale));

        expect(asset, isNot(contains('[')));
        expect(asset, isNot(contains(']')));
        expect(asset, startsWith('assets/fonts/'));
      }
    });

    test('三個字體檔案存在且非空', () {
      for (final String family in <String>[
        AppFonts.notoSansSc,
        AppFonts.notoSansTc,
        AppFonts.notoSansJp,
      ]) {
        final File file = File(AppFonts.assetFor(family));

        expect(file.existsSync(), isTrue, reason: '缺少 ${file.path}');
        expect(file.lengthSync(), greaterThan(1000000));
      }
    });
  });
}
