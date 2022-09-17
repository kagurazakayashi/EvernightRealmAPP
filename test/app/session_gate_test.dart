/// 會話閘的介面測試：受保護內容在伺服器回答之前一個字都不許畫；
/// 未登入與失效都被換到登入頁；身分不合只能看到擋回說明。
///
/// 假傳輸同登入頁測試：一切「已登入／未登入」的依據都由假伺服器的回應造成；
/// 測試直接組裝真實的會話控制器與真實狀態轉換，不繞過閘的判定來源。
library;

import 'dart:async';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/nav_context.dart';
import 'package:evernightrealm/app/nav_context_labels.dart';
import 'package:evernightrealm/app/session_gate.dart';
import 'package:evernightrealm/app/widgets/session_summary_view.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/features/auth/login_page.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_address.dart';
import '../support/test_language.dart';
import '../support/test_server.dart';
import '../support/test_session.dart';

/// 測試固定以繁體中文呈現。
const Locale _locale = Locale('zh', 'TW');

/// `/auth/session` 的 Root 主體回應（演練啟動恢復成功的路徑）。
const String sessionRootBody =
    '{"subject_kind":"root","device_id":"device-77",'
    '"created_at":"2026-09-30T03:04:05.000Z",'
    '"last_active_at":"2026-09-30T03:05:05.000Z",'
    '"expires_at":"2026-10-02T03:04:05.000Z","request_id":"r-sess-root"}';

/// 統一錯誤信封。
String envelope(int code, String requestId) =>
    '{"code":$code,"message":"server text","request_id":"$requestId"}';

/// 內容型別齊備的 JSON 錯誤回應。
http.Response jsonError(int status, int code, String requestId) =>
    http.Response(
      envelope(code, requestId),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  /// 探測路徑的中立回應；其餘路徑交給 [onOther]。
  Future<http.Response> Function(http.Request request) neutralOther(
    Future<http.Response> Function(http.Request request) onOther,
  ) {
    return (http.Request request) async {
      switch (request.url.path) {
        case kHealthPath:
          return jsonOk(healthBody);
        case kTimePath:
          return jsonOk(timeBody);
        default:
          return onOther(request);
      }
    };
  }

  /// 建好「位址設定＋假伺服器＋會話控制器」並掛上應用。
  ///
  /// [build] 在端點組態就緒後取得控制器；需要演練原生注入閉環的測試
  /// 自行按 main.dart 的延後取值閉包手法組裝 api，不走這裡。
  Future<void> mount(
    WidgetTester tester, {
    required Future<SessionController> Function(ServerApi api, _Fixture2 fix)
    build,
    Future<http.Response> Function(http.Request request)? onOther,
  }) async {
    final ServerAddressSettings settings = await buildAddressSettings(
      storedUrl: reachableUrl,
      reachable: <String>[reachableUrl],
    );
    final _Fixture2 fix = _Fixture2(settings);
    fix.api = ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient(
        neutralOther(
          onOther ??
              (http.Request request) async => jsonError(401, 2002, 'r-anon'),
        ),
      ),
    );
    fix.session = await build(fix.api!, fix);
    await tester.pumpWidget(
      await buildTestApp(
        storedTag: _locale.toLanguageTag(),
        addresses: settings,
        dependencies: AppDependencies(api: fix.api!),
        session: fix.session!,
      ),
    );
    await tester.pumpAndSettle();
  }

  NavigatorState navigatorOf(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).last);

  /// 空的 onOther：session 端點一律回 2002（未帶憑據）。
  Future<http.Response> anonymousOther(http.Request request) async =>
      jsonError(401, 2002, 'r-anon');

  group('未登入推入受保護路由', () {
    testWidgets('第一幀只有中性提示：受保護內容一個字都沒畫', (WidgetTester tester) async {
      await mount(
        tester,
        build: (ServerApi api, _Fixture2 fix) async => SessionController(
          api: api,
          addresses: fix.settings,
          mode: SessionTransportMode.web,
        ),
      );
      navigatorOf(tester).pushNamed(NavContext.adminConsole.routeName);

      // 逐幀走查：從推入那一刻到登入頁掛上為止，任何一幀都不准出現管理端內容。
      // 「先畫受保護頁再跳回登入」正是這一閘存在的理由，所以斷言的是每一幀，
      // 不是某一幀。
      final String forbidden = NavContext.adminConsole.summaryOf(l10n);
      bool sawNeutralHint = false;
      for (int frame = 0; frame < 12; frame++) {
        if (find.byType(LoginPage).evaluate().isNotEmpty) {
          break;
        }
        expect(find.text(forbidden), findsNothing);
        if (find.byKey(SessionGate.checkingKey).evaluate().isNotEmpty) {
          sawNeutralHint = true;
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(LoginPage), findsOneWidget);
      expect(sawNeutralHint, isTrue);
    });

    testWidgets('被換到登入頁時帶的返回目標只能是清單內路由', (WidgetTester tester) async {
      await mount(
        tester,
        build: (ServerApi api, _Fixture2 fix) async => SessionController(
          api: api,
          addresses: fix.settings,
          mode: SessionTransportMode.web,
        ),
      );
      navigatorOf(tester).pushNamed(NavContext.rootConsole.routeName);
      await tester.pumpAndSettle();

      final ModalRoute<Object?> loginRoute = ModalRoute.of(
        tester.element(find.byType(LoginPage)),
      )!;
      // 返回目標就是這條受保護路由本身；登入頁那端還會再驗一次身分。
      expect(loginRoute.settings.arguments, NavContext.rootConsole.routeName);
    });
  });

  group('重開應用先恢復再放行', () {
    testWidgets('本机有秘密：驗證通過後受保護頁才出現，且不先畫內容', (WidgetTester tester) async {
      final ServerAddressSettings settings = await buildAddressSettings(
        storedUrl: reachableUrl,
        reachable: <String>[reachableUrl],
      );
      int sessionAsks = 0;
      String? seenAuth;
      SessionController? sessionRef;
      // 拖住驗證回應：讓「恢復中」這一態可被穩定地看到，而不是被微任務一沖而過。
      final Completer<http.Response> sessionGate = Completer<http.Response>();
      final ServerApi api = ServerApi(
        config: ServerApiConfig(
          source: settings,
          transportMode: SessionTransportMode.native,
          credentials: (String identity) => sessionRef?.bearerFor(identity),
        ),
        client: MockClient((http.Request request) async {
          if (request.url.path == kAuthSessionPath) {
            sessionAsks++;
            seenAuth = request.headers['authorization'];
            return sessionGate.future;
          }
          return neutralOther(anonymousOther)(request);
        }),
      );
      final InMemorySessionPersistence store = InMemorySessionPersistence(
        <String, String>{reachableUrl: 'tok-restore-1'},
      );
      final SessionController session = nativeSession(
        api: api,
        addresses: settings,
        persistence: store,
      );
      sessionRef = session;
      await tester.pumpWidget(
        await buildTestApp(
          storedTag: _locale.toLanguageTag(),
          addresses: settings,
          dependencies: AppDependencies(api: api),
          session: session,
        ),
      );
      await tester.pumpAndSettle();

      navigatorOf(tester).pushNamed(NavContext.rootConsole.routeName);
      // 新推入的路由要到下一幀才掛進樹：先讓它建成，閘才開始做事。
      await tester.pump();
      await tester.pump();
      // 推入後的前兩幀：閘已排好恢復且在問伺服器——只有中性提示，受保護頁還沒影。
      expect(find.byKey(SessionGate.checkingKey), findsOneWidget);
      expect(find.text(NavContext.rootConsole.summaryOf(l10n)), findsNothing);

      // 閘自己排的那次恢復走完整的「讀秘密→帶憑據問伺服器」閉環。
      sessionGate.complete(jsonOk(sessionRootBody));
      await tester.pumpAndSettle();
      expect(find.text(NavContext.rootConsole.summaryOf(l10n)), findsOneWidget);
      expect(sessionAsks, 1);
      expect(seenAuth, 'Bearer tok-restore-1');
      expect(find.byKey(SessionGate.checkingKey), findsNothing);
    });

    testWidgets('秘密已被伺服器判定失效：換到登入頁，本機秘密被清除', (WidgetTester tester) async {
      final ServerAddressSettings settings = await buildAddressSettings(
        storedUrl: reachableUrl,
        reachable: <String>[reachableUrl],
      );
      final ServerApi api = ServerApi(
        config: ServerApiConfig(
          source: settings,
          transportMode: SessionTransportMode.native,
        ),
        client: MockClient((http.Request request) async {
          if (request.url.path == kAuthSessionPath) {
            return jsonError(401, 2003, 'r-gone');
          }
          return neutralOther(anonymousOther)(request);
        }),
      );
      final InMemorySessionPersistence store = InMemorySessionPersistence(
        <String, String>{reachableUrl: 'tok-stale-1'},
      );
      await tester.pumpWidget(
        await buildTestApp(
          storedTag: _locale.toLanguageTag(),
          addresses: settings,
          dependencies: AppDependencies(api: api),
          session: nativeSession(
            api: api,
            addresses: settings,
            persistence: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigatorOf(tester).pushNamed(NavContext.playerSurface.routeName);
      await tester.pumpAndSettle();

      // 受保護內容從頭到尾沒出現；失效的恢復路徑就是重新登入。
      expect(find.text(NavContext.playerSurface.summaryOf(l10n)), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(store.secrets, isEmpty);
    });
  });

  group('身分不合', () {
    testWidgets('帳戶主體開 Root 控制台：擋回說明而非受保護頁', (WidgetTester tester) async {
      await mount(
        tester,
        build: (ServerApi api, _Fixture2 fix) => signedInSession(
          api: api,
          addresses: fix.settings,
          persistence: InMemorySessionPersistence(),
          exchange: accountExchange('acct-01'),
        ),
      );
      navigatorOf(tester).pushNamed(NavContext.rootConsole.routeName);
      await tester.pumpAndSettle();

      expect(find.byKey(SessionGate.blockedKey), findsOneWidget);
      expect(find.text(l10n.sessionGateRootRequiredHint), findsOneWidget);
      expect(find.text(NavContext.rootConsole.summaryOf(l10n)), findsNothing);

      await tester.ensureVisible(find.byKey(SessionGate.backHomeKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SessionGate.backHomeKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SessionSummaryView.identityKey), findsOneWidget);
    });

    testWidgets('Root 主體開 Root 控制台：放行看到的是尚未實作的佔位頁', (
      WidgetTester tester,
    ) async {
      await mount(
        tester,
        build: (ServerApi api, _Fixture2 fix) => signedInSession(
          api: api,
          addresses: fix.settings,
          persistence: InMemorySessionPersistence(),
          exchange: rootExchange(),
        ),
      );
      navigatorOf(tester).pushNamed(NavContext.rootConsole.routeName);
      await tester.pumpAndSettle();

      expect(find.byKey(SessionGate.blockedKey), findsNothing);
      expect(find.text(NavContext.rootConsole.summaryOf(l10n)), findsOneWidget);
      // 放行不等於偽裝可用：頁面仍如實標明後端未開發。
      expect(find.text(l10n.notWiredBody), findsOneWidget);
    });
  });

  group('查不了時不冒充', () {
    testWidgets('伺服器沒答上來：停在提示與出口，不畫受保護內容也不裝未登入', (WidgetTester tester) async {
      await mount(
        tester,
        onOther: (http.Request request) async {
          throw http.ClientException('offline');
        },
        build: (ServerApi api, _Fixture2 fix) async => SessionController(
          api: api,
          addresses: fix.settings,
          mode: SessionTransportMode.web,
        ),
      );
      navigatorOf(tester).pushNamed(NavContext.npcConsole.routeName);
      await tester.pumpAndSettle();

      expect(find.text(NavContext.npcConsole.summaryOf(l10n)), findsNothing);
      expect(find.byKey(SessionGate.blockedKey), findsOneWidget);
      expect(find.text(l10n.sessionUnknownHint), findsOneWidget);
      expect(find.byKey(LoginPage.submitKey), findsNothing);
      expect(find.byKey(SessionGate.backHomeKey), findsOneWidget);
    });
  });

  group('切換伺服器', () {
    testWidgets('受保護頁上換到另一台：舊會話作廢，另一台上沒有可信身分就換到登入頁', (
      WidgetTester tester,
    ) async {
      const String otherUrl = 'http://10.0.0.9:5206';
      final ServerAddressSettings settings = await buildAddressSettings(
        storedUrl: reachableUrl,
        reachable: <String>[reachableUrl, otherUrl],
      );
      final InMemorySessionPersistence store = InMemorySessionPersistence();
      final ServerApi api = ServerApi(
        config: ServerApiConfig(
          source: settings,
          transportMode: SessionTransportMode.native,
        ),
        client: MockClient((http.Request request) async {
          if (request.url.path == kAuthSessionPath) {
            return jsonError(401, 2002, 'r-anon2');
          }
          return neutralOther(anonymousOther)(request);
        }),
      );
      final SessionController session = nativeSession(
        api: api,
        addresses: settings,
        persistence: store,
      );
      // 先把「已登入舊伺服器」造成既定事實：真實的 completeLogin 路徑。
      await session.completeLogin(
        ServerAddress.tryParse(reachableUrl)!,
        rootExchange(),
      );
      await tester.pumpWidget(
        await buildTestApp(
          storedTag: _locale.toLanguageTag(),
          addresses: settings,
          dependencies: AppDependencies(api: api),
          session: session,
        ),
      );
      await tester.pumpAndSettle();
      navigatorOf(tester).pushNamed(NavContext.rootConsole.routeName);
      await tester.pumpAndSettle();
      expect(find.text(NavContext.rootConsole.summaryOf(l10n)), findsOneWidget);

      // 換到另一台伺服器（保存走同一個探測判準）。
      await settings.save(otherUrl);
      await tester.pumpAndSettle();
      // 舊會話與受保護內容一起消失：另一台上還沒有可信身分。
      expect(find.text(NavContext.rootConsole.summaryOf(l10n)), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      // 舊伺服器的秘密被清除——這正是「甲伺服器的憑據不會被發往乙伺服器」。
      expect(store.secrets.containsKey(reachableUrl), isFalse);
    });
  });
}

/// 一次掛載的周邊物件：位址設定、端點介面與稍後落地的會話控制器。
class _Fixture2 {
  /// 以位址設定建立。
  _Fixture2(this.settings);

  /// 位址設定。
  final ServerAddressSettings settings;

  /// 端點介面（mount 內組裝）。
  ServerApi? api;

  /// 會話控制器（mount 內組裝）。
  SessionController? session;
}
