/// 介面語言切換的端對端測試：入口層選單改變介面語言、寫入本地，
/// 重新啟動後仍沿用該選擇；未支援的系統語言回退 en-US。
library;

import 'package:evernight_realm/app/widgets/language_selector.dart';
import 'package:evernight_realm/core/app_locale.dart';
import 'package:evernight_realm/core/language_settings.dart';
import 'package:evernight_realm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_language.dart';

/// 取得畫面上的下拉選單元件狀態。
Future<void> openSelector(WidgetTester tester) async {
  await tester.tap(find.byKey(LanguageSelector.dropdownKey));
  await tester.pumpAndSettle();
}

void main() {
  group('啟動時的語言', () {
    testWidgets('未手工選擇時跟隨系統語言', (WidgetTester tester) async {
      await tester.pumpWidget(
        await buildTestApp(systemLocale: const Locale('ja', 'JP')),
      );

      final AppLocalizations l10n = await AppLocalizations.delegate.load(
        const Locale('ja'),
      );
      expect(find.text(l10n.interfaceLanguageTitle), findsOneWidget);
      expect(find.text(l10n.serverEntryTitle), findsOneWidget);
    });

    testWidgets('系統語言未支援時回退 en-US', (WidgetTester tester) async {
      await tester.pumpWidget(
        await buildTestApp(systemLocale: const Locale('ko', 'KR')),
      );

      final AppLocalizations l10n = await AppLocalizations.delegate.load(
        const Locale('en'),
      );
      expect(find.text(l10n.interfaceLanguageTitle), findsOneWidget);
      expect(find.text('Interface language'), findsOneWidget);
    });

    testWidgets('系統語言為 zh-HK 時使用繁體', (WidgetTester tester) async {
      await tester.pumpWidget(
        await buildTestApp(systemLocale: const Locale('zh', 'HK')),
      );

      final AppLocalizations l10n = await AppLocalizations.delegate.load(
        const Locale('zh', 'TW'),
      );
      expect(find.text(l10n.interfaceLanguageTitle), findsOneWidget);
    });
  });

  group('手工切換', () {
    testWidgets('選定語言後介面立即換文並寫入持久化', (WidgetTester tester) async {
      final InMemoryLanguagePersistence store = InMemoryLanguagePersistence();
      final LanguageSettings settings = LanguageSettings(
        store,
        systemLocale: const Locale('en'),
      );
      await settings.restore();
      await tester.pumpWidget(await buildTestApp(language: settings));

      final AppLocalizations english = await AppLocalizations.delegate.load(
        const Locale('en'),
      );
      expect(find.text(english.interfaceLanguageTitle), findsOneWidget);

      await openSelector(tester);
      await tester.tap(find.text(AppLocale.zhTW.endonym).last);
      await tester.pumpAndSettle();

      final AppLocalizations traditional = await AppLocalizations.delegate.load(
        const Locale('zh', 'TW'),
      );
      expect(find.text(traditional.interfaceLanguageTitle), findsOneWidget);
      expect(find.text(english.interfaceLanguageTitle), findsNothing);
      expect(store.tag, 'zh-TW');
      expect(settings.followsSystem, isFalse);
    });

    testWidgets('重新啟動後沿用已儲存的選擇，不再跟隨系統', (WidgetTester tester) async {
      // 同一個儲存實例模擬「關掉再打開」。
      final InMemoryLanguagePersistence store = InMemoryLanguagePersistence();
      final LanguageSettings first = LanguageSettings(
        store,
        systemLocale: const Locale('en'),
      );
      await first.select(AppLocale.jaJP);

      final LanguageSettings second = LanguageSettings(
        store,
        systemLocale: const Locale('en'),
      );
      await second.restore();
      await tester.pumpWidget(await buildTestApp(language: second));

      final AppLocalizations japanese = await AppLocalizations.delegate.load(
        const Locale('ja'),
      );
      expect(find.text(japanese.interfaceLanguageTitle), findsOneWidget);
      expect(second.followsSystem, isFalse);
    });

    testWidgets('選回跟隨系統會清除選擇並回到系統語言', (WidgetTester tester) async {
      final InMemoryLanguagePersistence store = InMemoryLanguagePersistence(
        'ja-JP',
      );
      final LanguageSettings settings = LanguageSettings(
        store,
        systemLocale: const Locale('zh', 'CN'),
      );
      await settings.restore();
      await tester.pumpWidget(await buildTestApp(language: settings));

      final AppLocalizations japanese = await AppLocalizations.delegate.load(
        const Locale('ja'),
      );
      expect(find.text(japanese.interfaceLanguageTitle), findsOneWidget);

      await openSelector(tester);
      // 此刻介面語言是日文，選單裡的「跟隨系統」也以日文呈現。
      await tester.tap(find.text(japanese.interfaceLanguageFollowSystem).last);
      await tester.pumpAndSettle();

      final AppLocalizations simplified = await AppLocalizations.delegate.load(
        const Locale('zh'),
      );
      expect(find.text(simplified.interfaceLanguageTitle), findsOneWidget);
      expect(store.tag, isNull);
      expect(settings.followsSystem, isTrue);
    });

    testWidgets('選項名稱以該語言本身書寫，四語言齊備且不被翻譯', (WidgetTester tester) async {
      await tester.pumpWidget(
        await buildTestApp(systemLocale: const Locale('ja', 'JP')),
      );

      await openSelector(tester);
      for (final AppLocale locale in AppLocale.values) {
        expect(find.text(locale.endonym), findsWidgets, reason: locale.tag);
      }
    });
  });

  group('語言選擇的影響範圍', () {
    testWidgets('切換語言不改變狀態條的真實數值', (WidgetTester tester) async {
      final LanguageSettings settings = LanguageSettings(
        InMemoryLanguagePersistence(),
        systemLocale: const Locale('en'),
      );
      await tester.pumpWidget(await buildTestApp(language: settings));

      final AppLocalizations english = await AppLocalizations.delegate.load(
        const Locale('en'),
      );
      expect(
        find.text(
          english.labelValuePair(
            english.statusServerLabel,
            english.serverAddressNotSet,
          ),
        ),
        findsOneWidget,
      );

      await openSelector(tester);
      await tester.tap(find.text(AppLocale.jaJP.endonym).last);
      await tester.pumpAndSettle();

      final AppLocalizations japanese = await AppLocalizations.delegate.load(
        const Locale('ja'),
      );
      expect(
        find.text(japanese.labelValuePair(japanese.statusServerLabel, '尚未設定')),
        findsNothing,
        reason: '換語言後不得殘留另一語言的值',
      );
      expect(
        find.text(
          japanese.labelValuePair(
            japanese.statusServerLabel,
            japanese.serverAddressNotSet,
          ),
        ),
        findsOneWidget,
      );
      // 系統語系欄位仍是裝置語言本身，不隨介面語言改變。
      expect(find.textContaining('en-US'), findsOneWidget);
    });
  });
}
