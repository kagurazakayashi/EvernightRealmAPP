/// 應用殼狀態條的測試：四個欄位都要以目前語言呈現，且數值有真實來源。
library;

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/widgets/status_bar.dart';
import 'package:evernightrealm/core/app_information.dart';
import 'package:evernightrealm/core/runtime_status.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_language.dart';

/// 測試固定使用繁體中文（模擬已手工選擇），斷言文字由同一份資源取得。
const Locale _locale = Locale('zh', 'TW');

/// 以指定依賴與語言組裝應用根節點。
Future<Widget> _harness(AppDependencies dependencies) {
  return buildTestApp(
    storedTag: _locale.toLanguageTag(),
    dependencies: dependencies,
  );
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  group('連線狀態條', () {
    testWidgets('四個欄位齊全且以目前語言標示', (WidgetTester tester) async {
      await tester.pumpWidget(
        await _harness(
          const AppDependencies(
            runtimeStatus: RuntimeStatus(
              information: AppInformation(buildVersion: '9.9.9-test'),
            ),
          ),
        ),
      );

      expect(find.byKey(ConnectionStatusBar.versionKey), findsOneWidget);
      expect(find.byKey(ConnectionStatusBar.localeKey), findsOneWidget);
      expect(find.byKey(ConnectionStatusBar.serverKey), findsOneWidget);
      expect(find.byKey(ConnectionStatusBar.connectionKey), findsOneWidget);
      expect(
        find.text(l10n.labelValuePair(l10n.statusVersionLabel, '9.9.9-test')),
        findsOneWidget,
      );
      // 狀態條欄位以鍵定位：同一句話也可能出現在入口頁的探測區，
      // 用文字搜尋會把兩處混在一起，量不到「狀態條本身寫了什麼」。
      String statusText(Key key) =>
          tester.widget<Text>(find.byKey(key)).data ?? '';

      expect(
        statusText(ConnectionStatusBar.connectionKey),
        l10n.labelValuePair(
          l10n.statusConnectionLabel,
          l10n.connectionNotConfigured,
        ),
        reason: '未注入位址時不得宣稱已連線或已探測',
      );
    });

    testWidgets('尚未具備的能力如實顯示未設定與未接上', (WidgetTester tester) async {
      await tester.pumpWidget(await _harness(const AppDependencies()));

      expect(
        find.text(
          l10n.labelValuePair(l10n.statusServerLabel, l10n.serverAddressNotSet),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.labelValuePair(l10n.statusVersionLabel, l10n.valueNotProvided),
        ),
        findsOneWidget,
        reason: '建置未注入版號時不得顯示假版號',
      );
    });

    testWidgets('系統語系取自平台設定，不是介面語言', (WidgetTester tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('ja', 'JP');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);

      await tester.pumpWidget(await _harness(const AppDependencies()));

      expect(
        find.text(l10n.labelValuePair(l10n.statusLocaleLabel, 'ja-JP')),
        findsOneWidget,
        reason: '介面語言被固定為 zh_TW，系統語系仍應顯示裝置的 ja-JP',
      );
    });
  });
}
