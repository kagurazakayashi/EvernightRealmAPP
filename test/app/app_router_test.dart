/// Navigator 路由表的測試：只登記五個頂層上下文，未登記路由走統一回退，
/// 且頁面標題與說明隨介面語言改變。
library;

import 'package:evernightrealm/app/app_router.dart';
import 'package:evernightrealm/app/nav_context.dart';
import 'package:evernightrealm/app/nav_context_labels.dart';
import 'package:evernightrealm/app/widgets/status_bar.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_language.dart';

/// 測試固定使用繁體中文。
const Locale _locale = Locale('zh', 'TW');

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  /// 以指定語言啟動應用並回傳測試器。
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      await buildTestApp(storedTag: _locale.toLanguageTag()),
    );
    await tester.pumpAndSettle();
  }

  NavigatorState navigatorOf(WidgetTester tester) {
    return tester.state<NavigatorState>(find.byType(Navigator).last);
  }

  group('路由表登記範圍', () {
    test('只登記五個頂層上下文，路由名稱與文件一致', () {
      expect(AppRouter.routes.keys, NavContext.allRouteNames);
      expect(AppRouter.routes.length, 5);
    });

    test('啟動後的第一個畫面是伺服器入口層，且為根路由', () {
      expect(AppRouter.initialRoute, NavContext.serverEntry.routeName);
      expect(AppRouter.initialRoute, '/');
    });
  });

  group('各頂層上下文', () {
    for (final NavContext context in NavContext.values) {
      testWidgets('${context.routeName} 可開啟、標題隨語言且狀態條常在', (
        WidgetTester tester,
      ) async {
        await pumpApp(tester);
        if (context != NavContext.serverEntry) {
          navigatorOf(tester).pushNamed(context.routeName);
          await tester.pumpAndSettle();
        }

        expect(find.text(context.titleOf(l10n)), findsOneWidget);
        expect(find.text(context.summaryOf(l10n)), findsOneWidget);
        expect(find.byKey(ConnectionStatusBar.connectionKey), findsOneWidget);
      });

      testWidgets('${context.routeName} 如實標明後端尚未實作', (
        WidgetTester tester,
      ) async {
        await pumpApp(tester);
        if (context != NavContext.serverEntry) {
          navigatorOf(tester).pushNamed(context.routeName);
          await tester.pumpAndSettle();
        }

        expect(find.text(l10n.notWiredBody), findsOneWidget);
        expect(find.text(l10n.notWiredHint), findsOneWidget);
        // 模板殘留的範例業務元件必須消失。
        expect(find.byIcon(Icons.add), findsNothing);
        expect(find.byType(ListTile), findsNothing);
      });
    }
  });

  group('根路由與未登記的路由', () {
    testWidgets('根頁面不出現返回按鈕（入口層之上沒有佔位路由）', (WidgetTester tester) async {
      await pumpApp(tester);

      expect(find.byType(BackButton), findsNothing);
      expect(navigatorOf(tester).canPop(), isFalse);
    });

    testWidgets('推入未登記路由時回退到統一頁面', (WidgetTester tester) async {
      await pumpApp(tester);
      navigatorOf(tester).pushNamed('/not-a-real-route');
      await tester.pumpAndSettle();

      expect(find.text(l10n.unknownRouteTitle), findsOneWidget);
      expect(find.text(l10n.unknownRouteBody), findsOneWidget);
      expect(find.textContaining('/not-a-real-route'), findsOneWidget);
      expect(find.byKey(ConnectionStatusBar.connectionKey), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });
  });
}
