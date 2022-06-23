/// 介面語言解析規則的測試：中文分流、支援語言直取、未知語言回退 en-US。
library;

import 'dart:ui' show Locale;

import 'package:evernight_realm/core/app_locale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAppLocale 中文分支', () {
    test('台灣、香港、澳門用繁體', () {
      for (final String region in const ['TW', 'HK', 'MO']) {
        expect(
          resolveAppLocale(Locale('zh', region)),
          AppLocale.zhTW,
          reason: 'zh-$region 套繁體',
        );
      }
    });

    test('大陸、新加坡、未編入的地區碼與無地區碼的中文用簡體', () {
      for (final String? region in const ['CN', 'SG', 'XX', null]) {
        expect(
          resolveAppLocale(Locale('zh', region)),
          AppLocale.zhCN,
          reason: 'zh-$region 套簡體',
        );
      }
    });

    test('帶書寫系統標記的中文按地區判定', () {
      expect(
        resolveAppLocale(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ),
        AppLocale.zhTW,
      );
    });
  });

  group('resolveAppLocale 其他支援語言', () {
    test('英文與日文一律落到對應語言', () {
      expect(resolveAppLocale(const Locale('en')), AppLocale.enUS);
      expect(resolveAppLocale(const Locale('en', 'US')), AppLocale.enUS);
      expect(resolveAppLocale(const Locale('en', 'GB')), AppLocale.enUS);
      expect(resolveAppLocale(const Locale('ja')), AppLocale.jaJP);
      expect(resolveAppLocale(const Locale('ja', 'JP')), AppLocale.jaJP);
    });

    test('未知語言回退 en-US，不猜測文字', () {
      for (final Locale locale in <Locale>[
        const Locale('ko', 'KR'),
        const Locale('fr'),
        const Locale('es', 'MX'),
        const Locale('th', 'TH'),
        const Locale('pt', 'BR'),
      ]) {
        expect(
          resolveAppLocale(locale),
          AppLocale.enUS,
          reason: '$locale 應回退英文',
        );
      }
    });
  });

  group('AppLocale 標識', () {
    test('四語言標識與產品約定一致', () {
      expect(AppLocale.values.map((locale) => locale.tag).toList(), <String>[
        'zh-CN',
        'zh-TW',
        'en-US',
        'ja-JP',
      ]);
    });

    test('語言名以該語言本身書寫，不隨介面語言改變', () {
      expect(
        AppLocale.values.map((locale) => locale.endonym).toList(),
        <String>['简体中文', '繁體中文（台灣）', 'English', '日本語'],
      );
    });

    test('fromTag 容忍大小寫與底線寫法，無法辨識時回傳 null', () {
      expect(AppLocale.fromTag('zh-tw'), AppLocale.zhTW);
      expect(AppLocale.fromTag('JA_JP'), AppLocale.jaJP);
      expect(AppLocale.fromTag(' en-US '), AppLocale.enUS);
      expect(AppLocale.fromTag('ko-KR'), isNull);
      expect(AppLocale.fromTag(''), isNull);
      expect(AppLocale.fromTag(null), isNull);
    });
  });
}
