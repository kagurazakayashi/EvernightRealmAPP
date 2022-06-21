/// Navigator 路由表的測試：只登記五個頂層上下文，未登記路由走統一回退。
library;

import 'package:evernight_realm/app/app_dependencies.dart';
import 'package:evernight_realm/app/app_router.dart';
import 'package:evernight_realm/app/nav_context.dart';
import 'package:evernight_realm/app/widgets/status_bar.dart';
import 'package:evernight_realm/core/app_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 以指定路由作為起始畫面組裝應用。
Widget _harness(String initialRoute) {
  return AppScope(
    dependencies: const AppDependencies(),
    child: MaterialApp(
      initialRoute: initialRoute,
      routes: AppRouter.routes,
      onUnknownRoute: AppRouter.onUnknownRoute,
    ),
  );
}

void main() {
  group('路由表登記範圍', () {
    test('只登記五個頂層上下文，路由名稱與文件一致', () {
      expect(AppRouter.routes.keys, NavContext.allRouteNames);
      expect(AppRouter.routes.length, 5);
    });

    test('啟動後的第一個畫面是伺服器入口層，且為不可返回的根路由', () async {
      expect(AppRouter.initialRoute, NavContext.serverEntry.routeName);
      expect(AppRouter.initialRoute, '/');
    });

    testWidgets('根頁面不出現返回按鈕（入口層之上沒有佔位路由）', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(AppRouter.initialRoute));

      expect(find.byType(BackButton), findsNothing);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    });
  });

  group('各頂層上下文', () {
    for (final NavContext context in NavContext.values) {
      testWidgets('${context.routeName} 可開啟且持續顯示狀態條', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(_harness(context.routeName));

        expect(find.text(context.title), findsOneWidget);
        expect(find.byKey(ConnectionStatusBar.connectionKey), findsOneWidget);
      });

      testWidgets('${context.routeName} 如實標明後端尚未實作', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(_harness(context.routeName));

        expect(find.text(AppCopy.notWiredBody), findsOneWidget);
        expect(find.text(context.summary), findsOneWidget);
        // 模板殘留的範例業務元件必須消失。
        expect(find.byIcon(Icons.add), findsNothing);
        expect(find.byType(ListTile), findsNothing);
      });
    }
  });

  group('未登記的路由', () {
    testWidgets('推入未登記路由時回退到統一頁面', (WidgetTester tester) async {
      // initialRoute 未登記時 Flutter 直接回落根路由，故以 pushNamed 觸發回退。
      await tester.pumpWidget(_harness(AppRouter.initialRoute));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/not-a-real-route');
      await tester.pumpAndSettle();

      expect(find.text(AppCopy.unknownRouteTitle), findsOneWidget);
      expect(find.text(AppCopy.unknownRouteBody), findsOneWidget);
      expect(find.textContaining('/not-a-real-route'), findsOneWidget);
      expect(find.byKey(ConnectionStatusBar.connectionKey), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });
  });
}
