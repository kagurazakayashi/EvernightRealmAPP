/// 四語言資源是否各自生效的檢查：避免「看著有翻譯、其實全部回退英文」。
library;

import 'dart:ui' show Locale;

import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 逐一載入四語言，取得該語言實際會顯示的文字。
Future<AppLocalizations> _load(String languageCode, [String? countryCode]) {
  return AppLocalizations.delegate.load(Locale(languageCode, countryCode));
}

void main() {
  late AppLocalizations en;
  late AppLocalizations zh;
  late AppLocalizations zhTw;
  late AppLocalizations ja;

  setUpAll(() async {
    en = await _load('en');
    zh = await _load('zh');
    zhTw = await _load('zh', 'TW');
    ja = await _load('ja');
  });

  group('四語言載入', () {
    test('支援的語言正是產品四語言', () {
      expect(
        AppLocalizations.supportedLocales.map((locale) => locale.toString()),
        containsAll(<String>['en', 'zh', 'zh_TW', 'ja']),
      );
      expect(AppLocalizations.supportedLocales, hasLength(4));
    });

    test('同一鍵在四語言各自生效，不是一律回退模板', () {
      final List<String> versionLabels = <String>[
        en.statusVersionLabel,
        zh.statusVersionLabel,
        zhTw.statusVersionLabel,
        ja.statusVersionLabel,
      ];
      expect(versionLabels.toSet(), hasLength(4), reason: '$versionLabels');

      final List<String> bodies = <String>[
        en.notWiredBody,
        zh.notWiredBody,
        zhTw.notWiredBody,
        ja.notWiredBody,
      ];
      expect(bodies.toSet(), hasLength(4));

      final List<String> unknownTitles = <String>[
        en.unknownRouteTitle,
        zh.unknownRouteTitle,
        zhTw.unknownRouteTitle,
        ja.unknownRouteTitle,
      ];
      expect(unknownTitles.toSet(), hasLength(4));
    });

    test('繁簡中文用字不同，確認兩份中文資源不是同一份文字', () {
      expect(zh.statusServerLabel, isNot(zhTw.statusServerLabel));
      expect(zh.serverAddressNotSet, isNot(zhTw.serverAddressNotSet));
      expect(zh.notWiredBody, isNot(zhTw.notWiredBody));
    });

    test('帶插值的訊息在當地語言下仍帶入原值', () {
      expect(en.labelValuePair('Version', '1.2.3'), 'Version: 1.2.3');
      expect(zhTw.labelValuePair('版號', '1.2.3'), '版號：1.2.3');
      expect(zh.unknownRouteDetail('/nope'), contains('/nope'));
    });

    test('五個頂層上下文在每種語言都有標題與說明', () async {
      for (final AppLocalizations l10n in <AppLocalizations>[
        en,
        zh,
        zhTw,
        ja,
      ]) {
        final List<String> titles = <String>[
          l10n.serverEntryTitle,
          l10n.rootConsoleTitle,
          l10n.adminConsoleTitle,
          l10n.npcConsoleTitle,
          l10n.playerSurfaceTitle,
        ];
        final List<String> summaries = <String>[
          l10n.serverEntrySummary,
          l10n.rootConsoleSummary,
          l10n.adminConsoleSummary,
          l10n.npcConsoleSummary,
          l10n.playerSurfaceSummary,
        ];
        expect(titles.every((value) => value.trim().isNotEmpty), isTrue);
        expect(summaries.every((value) => value.trim().isNotEmpty), isTrue);
        expect(titles.toSet(), hasLength(5));
      }
    });
  });
}
