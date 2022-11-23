/// Navigator 路由表的測試：五個頂層上下文加登入頁共六條登記路由；
/// 受保護上下文未登入時一律換入登入頁，已登入才看得到佔位頁面本身，
/// 未登記路由走統一回退，頁面標題與說明隨介面語言改變。
library;

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/app_router.dart';
import 'package:evernightrealm/app/nav_context.dart';
import 'package:evernightrealm/app/nav_context_labels.dart';
import 'package:evernightrealm/app/session_gate.dart';
import 'package:evernightrealm/app/widgets/status_bar.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/features/auth/login_page.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_address.dart';
import '../support/test_language.dart';
import '../support/test_server.dart';
import '../support/test_session.dart';

/// 測試固定使用繁體中文。
const Locale _locale = Locale('zh', 'TW');

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  NavigatorState navigatorOf(WidgetTester tester) {
    return tester.state<NavigatorState>(find.byType(Navigator).last);
  }

  /// 以「已登入」的會話控制器啟動應用：身分由 [exchange] 決定，
  /// 讓受保護頁面的測試走真實的閘判定，而不是繞過它。
  Future<void> pumpSignedIn(
    WidgetTester tester, {
    required LoginExchange exchange,
  }) async {
    final ServerAddressSettings addresses = await buildAddressSettings(
      storedUrl: reachableUrl,
      reachable: <String>[reachableUrl],
    );
    final AppDependencies deps = AppDependencies.assembled(
      addresses: addresses,
    );
    final SessionController session = await signedInSession(
      api: deps.api,
      addresses: addresses,
      persistence: InMemorySessionPersistence(),
      exchange: exchange,
    );
    await tester.pumpWidget(
      await buildTestApp(
        storedTag: _locale.toLanguageTag(),
        addresses: addresses,
        dependencies: deps,
        session: session,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('路由表登記範圍', () {
    test('登記五個頂層上下文與登入頁，路由名稱與文件一致', () {
      expect(AppRouter.routes.keys, <String>[
        ...NavContext.allRouteNames,
        kLoginRoute,
      ]);
      expect(AppRouter.routes.length, 6);
    });

    test('啟動後的第一個畫面是伺服器入口層，且為根路由', () {
      expect(AppRouter.initialRoute, NavContext.serverEntry.routeName);
      expect(AppRouter.initialRoute, '/');
    });

    test('受保護清單與路由名稱逐字一致，Root 專屬只含 Root 控制台', () {
      expect(AppRouter.guardedRouteNames, <String>{
        NavContext.rootConsole.routeName,
        NavContext.adminConsole.routeName,
        NavContext.npcConsole.routeName,
        NavContext.playerSurface.routeName,
      });
      expect(AppRouter.rootOnlyRouteNames, <String>{
        NavContext.rootConsole.routeName,
      });
    });
  });

  group('未登入時的受保護上下文', () {
    for (final NavContext context in NavContext.values.where(
      (NavContext c) => AppRouter.guardedRouteNames.contains(c.routeName),
    )) {
      testWidgets('${context.routeName} 未登入會被換到登入頁，不顯示受保護內容', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          await buildTestApp(storedTag: _locale.toLanguageTag()),
        );
        await tester.pumpAndSettle();
        navigatorOf(tester).pushNamed(context.routeName);
        await tester.pumpAndSettle();

        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.text(context.summaryOf(l10n)), findsNothing);
        expect(find.byKey(SessionGate.checkingKey), findsNothing);
      });
    }
  });

  group('已登入時各頂層上下文', () {
    testWidgets('Root 身分可開啟 Root 控制台，標題隨語言且狀態條常在', (WidgetTester tester) async {
      await pumpSignedIn(tester, exchange: rootExchange());
      navigatorOf(tester).pushNamed(NavContext.rootConsole.routeName);
      await tester.pumpAndSettle();

      expect(find.text(NavContext.rootConsole.titleOf(l10n)), findsOneWidget);
      expect(find.text(NavContext.rootConsole.summaryOf(l10n)), findsOneWidget);
      expect(find.byKey(ConnectionStatusBar.connectionKey), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });

    for (final NavContext context in <NavContext>[
      NavContext.adminConsole,
      NavContext.npcConsole,
      NavContext.playerSurface,
    ]) {
      testWidgets('${context.routeName} 可開啟、標題隨語言且狀態條常在', (
        WidgetTester tester,
      ) async {
        await pumpSignedIn(tester, exchange: accountExchange('acct-1'));
        navigatorOf(tester).pushNamed(context.routeName);
        await tester.pumpAndSettle();

        expect(find.text(context.titleOf(l10n)), findsOneWidget);
        expect(find.text(context.summaryOf(l10n)), findsOneWidget);
        expect(find.byKey(ConnectionStatusBar.connectionKey), findsOneWidget);
      });
    }

    // 「如實標明尚未實作」這句話的對象隨 R2-001 縮小：Root 控制台已經接上
    // 「開設伺服器級管理員」一項，所以它不再整頁佔位；其餘三個上下文仍是佔位頁。
    // 兩個方向都要釘住——把 Root 控制台也寫成佔位是謊報落後，把管理員端寫成已實作
    // 是謊報進度，而「不出現範例業務元件」對兩者都還成立。
    for (final NavContext context in <NavContext>[
      NavContext.adminConsole,
      NavContext.npcConsole,
      NavContext.playerSurface,
    ]) {
      testWidgets('${context.routeName} 如實標明後端尚未實作', (
        WidgetTester tester,
      ) async {
        await pumpSignedIn(tester, exchange: accountExchange('acct-1'));
        navigatorOf(tester).pushNamed(context.routeName);
        await tester.pumpAndSettle();

        expect(find.text(l10n.notWiredBody), findsOneWidget);
        expect(find.text(l10n.notWiredHint), findsOneWidget);
        expect(find.byIcon(Icons.add), findsNothing);
        expect(find.byType(ListTile), findsNothing);
      });
    }

    testWidgets('Root 控制台不再整頁佔位，但仍不擺範例業務元件', (WidgetTester tester) async {
      await pumpSignedIn(tester, exchange: rootExchange());
      navigatorOf(tester).pushNamed(NavContext.rootConsole.routeName);
      await tester.pumpAndSettle();

      expect(find.text(l10n.notWiredBody), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('root-console-remaining-notice')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });
  });

  group('根路由與未登記的路由', () {
    testWidgets('根頁面不出現返回按鈕（入口層之上沒有佔位路由）', (WidgetTester tester) async {
      await tester.pumpWidget(
        await buildTestApp(storedTag: _locale.toLanguageTag()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsNothing);
      expect(navigatorOf(tester).canPop(), isFalse);
    });

    testWidgets('推入未登記路由時回退到統一頁面', (WidgetTester tester) async {
      await tester.pumpWidget(
        await buildTestApp(storedTag: _locale.toLanguageTag()),
      );
      await tester.pumpAndSettle();
      navigatorOf(tester).pushNamed('/not-a-real-route');
      await tester.pumpAndSettle();

      expect(find.text(l10n.unknownRouteTitle), findsOneWidget);
      expect(find.text(l10n.unknownRouteBody), findsOneWidget);
      expect(find.textContaining('/not-a-real-route'), findsOneWidget);
      expect(find.byKey(ConnectionStatusBar.connectionKey), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('登入頁本身不需登入即可開啟（它正是取得身分的通路）', (WidgetTester tester) async {
      final ServerAddressSettings addresses = await buildAddressSettings(
        storedUrl: reachableUrl,
        reachable: <String>[reachableUrl],
      );
      await tester.pumpWidget(
        await buildTestApp(
          storedTag: _locale.toLanguageTag(),
          addresses: addresses,
          dependencies: AppDependencies(api: stubApi()),
        ),
      );
      await tester.pumpAndSettle();
      navigatorOf(tester).pushNamed(kLoginRoute);
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byKey(LoginPage.submitKey), findsOneWidget);
    });
  });
}
