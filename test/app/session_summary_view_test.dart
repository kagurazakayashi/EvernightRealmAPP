/// 入口層會話卡的介面測試：五種會話狀態各說各句，身分列只准抄伺服器的回話。
///
/// 「重開應用先恢復再呈現」是這組測試的主軸：第一幀必須停在中性提示，
/// 恢復成功才亮出身分卡，失效要能被理解、查不了不能被講成沒登入。
/// 全部走注入的假傳輸與記憶體安全儲存假件，不碰網路也不落任何真實憑據。
library;

import 'dart:async';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/app_router.dart';
import 'package:evernightrealm/app/nav_context.dart';
import 'package:evernightrealm/app/nav_context_labels.dart';
import 'package:evernightrealm/app/widgets/session_summary_view.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/core/session/session_status.dart';
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

/// `/auth/session` 的 Root 主體回應。
const String sessionRootBody =
    '{"subject_kind":"root","device_id":"device-77",'
    '"created_at":"2026-09-30T03:04:05.000Z",'
    '"last_active_at":"2026-09-30T03:05:05.000Z",'
    '"expires_at":"2026-10-02T03:04:05.000Z","request_id":"r-sess-root"}';

/// `/auth/session` 的帳戶主體回應。
const String sessionAccountBody =
    '{"subject_kind":"account","account_id":"acct-01","device_id":"device-88",'
    '"created_at":"2026-09-30T03:04:05.000Z",'
    '"last_active_at":"2026-09-30T03:05:05.000Z",'
    '"expires_at":"2026-10-02T03:04:05.000Z","request_id":"r-sess-acct"}';

String envelope(int code, String requestId) =>
    '{"code":$code,"message":"server text","request_id":"$requestId"}';

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

  /// 探測路徑中立、session 路徑由 [onSession] 決定的假伺服器。
  ServerApi apiFor(
    ServerAddressSettings settings, {
    Future<http.Response> Function(http.Request request)? onSession,
    void Function(http.Request request)? onAny,
  }) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        onAny?.call(request);
        switch (request.url.path) {
          case kHealthPath:
            return jsonOk(healthBody);
          case kTimePath:
            return jsonOk(timeBody);
          case kAuthSessionPath:
            return onSession == null
                ? jsonError(401, 2002, 'r-anon')
                : await onSession(request);
          default:
            return jsonError(404, 1001, 'r-404');
        }
      }),
    );
  }

  /// 建一位址設定（可指定「未設定」演練）。
  Future<ServerAddressSettings> addressesFor({String? storedUrl}) {
    final String url = storedUrl ?? reachableUrl;
    return buildAddressSettings(storedUrl: url, reachable: <String>[url]);
  }

  /// 以既有會話控制器掛上應用；[restoreOnLaunch] 演練「重開應用」的起點。
  Future<void> mount(
    WidgetTester tester, {
    required SessionController session,
    required ServerAddressSettings settings,
    required ServerApi api,
    bool restoreOnLaunch = false,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      await buildTestApp(
        storedTag: _locale.toLanguageTag(),
        addresses: settings,
        dependencies: AppDependencies(api: api),
        session: session,
        restoreOnLaunch: restoreOnLaunch,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  /// 狀態結論行的文字。
  String statusLine(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(SessionSummaryView.statusKey)).data ?? '';

  group('未登入與無位址', () {
    testWidgets('有位址未登入：說尚未登入並給前往登入', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(settings);
      await mount(
        tester,
        settings: settings,
        api: api,
        session: SessionController(
          api: api,
          addresses: settings,
          mode: SessionTransportMode.web,
        )..restore(),
      );

      expect(statusLine(tester), l10n.sessionSignedOutHint);
      await tester.ensureVisible(find.byKey(SessionSummaryView.goLoginKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SessionSummaryView.goLoginKey));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets('沒有位址：說明無從登入，不給登入按鈕', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor(storedUrl: '');
      final ServerApi api = apiFor(settings);
      int asks = 0;
      await mount(
        tester,
        settings: settings,
        api: ServerApi(
          config: ServerApiConfig(source: settings),
          client: MockClient((http.Request request) async {
            asks++;
            return jsonError(401, 2002, 'r-anon');
          }),
        ),
        session: SessionController(
          api: api,
          addresses: settings,
          mode: SessionTransportMode.web,
        ),
      );

      expect(statusLine(tester), l10n.sessionNotConfiguredHint);
      expect(find.byKey(SessionSummaryView.goLoginKey), findsNothing);
      expect(asks, 0);
    });
  });

  group('重開應用先恢復再呈現', () {
    testWidgets('本機秘密有效：第一幀只有驗證中提示，伺服器答完才亮身分卡', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final InMemorySessionPersistence store = InMemorySessionPersistence(
        <String, String>{reachableUrl: 'tok-reopen-1'},
      );
      // 用受控完成器拖住驗證回應：否則 MockClient 的微任務會在第一幀前就
      // 把恢復推完，「驗證中」那一幀根本抓不到。
      final Completer<http.Response> sessionGate = Completer<http.Response>();
      final ServerApi api = ServerApi(
        config: ServerApiConfig(
          source: settings,
          transportMode: SessionTransportMode.native,
          credentials: (String identity) => store.secrets[identity],
        ),
        client: MockClient((http.Request request) async {
          if (request.url.path == kAuthSessionPath) {
            expect(request.headers['authorization'], 'Bearer tok-reopen-1');
            return sessionGate.future;
          }
          return jsonOk(healthBody);
        }),
      );
      final SessionController session = nativeSession(
        api: api,
        addresses: settings,
        persistence: store,
      );
      await mount(
        tester,
        settings: settings,
        api: api,
        session: session,
        restoreOnLaunch: true,
        settle: false,
      );

      // 第一幀：恢復已在路上——只有中性提示，沒有身分卡、也沒有受保護內容。
      expect(find.text(l10n.sessionVerifyingHint), findsOneWidget);
      expect(find.byKey(SessionSummaryView.identityKey), findsNothing);

      sessionGate.complete(jsonOk(sessionRootBody));
      await tester.pumpAndSettle();
      expect(find.byKey(SessionSummaryView.identityKey), findsOneWidget);
      expect(
        find.text(
          l10n.labelValuePair(
            l10n.sessionSubjectLabel,
            l10n.sessionSubjectRoot,
          ),
        ),
        findsOneWidget,
      );
      expect(store.readCounts[reachableUrl], 1);
    });

    testWidgets('本機秘密已被判定失效：如實說失效、祕密清除、給重新登入', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final InMemorySessionPersistence store = InMemorySessionPersistence(
        <String, String>{reachableUrl: 'tok-stale-2'},
      );
      final ServerApi api = apiFor(
        settings,
        onSession: (http.Request request) async =>
            jsonError(401, 2003, 'r-stale'),
      );
      await mount(
        tester,
        settings: settings,
        api: api,
        session: nativeSession(
          api: api,
          addresses: settings,
          persistence: store,
        ),
        restoreOnLaunch: true,
      );

      expect(statusLine(tester), l10n.sessionExpiredNotice);
      expect(find.byKey(SessionSummaryView.goLoginKey), findsOneWidget);
      expect(find.byKey(SessionSummaryView.identityKey), findsNothing);
      // 「清理受保護緩存」在最內層的那件事：失效後本機不再留住那枚秘密。
      expect(store.secrets, isEmpty);
    });

    testWidgets('連不上時問不出結果：查不了不等於未登入，秘密留住', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final InMemorySessionPersistence store = InMemorySessionPersistence(
        <String, String>{reachableUrl: 'tok-keep-1'},
      );
      final ServerApi api = ServerApi(
        config: ServerApiConfig(source: settings),
        client: MockClient((http.Request request) async {
          throw http.ClientException('offline');
        }),
      );
      await mount(
        tester,
        settings: settings,
        api: api,
        session: nativeSession(
          api: api,
          addresses: settings,
          persistence: store,
        ),
        restoreOnLaunch: true,
      );

      expect(statusLine(tester), l10n.sessionUnknownHint);
      expect(statusLine(tester), isNot(l10n.sessionSignedOutHint));
      expect(find.byKey(SessionSummaryView.revalidateKey), findsOneWidget);
      expect(find.byKey(SessionSummaryView.goLoginKey), findsOneWidget);
      expect(store.secrets[reachableUrl], 'tok-keep-1');
    });

    testWidgets('安全儲存讀取失敗：停在無法確定並註明儲存問題，不發驗證請求', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final InMemorySessionPersistence store = InMemorySessionPersistence()
        ..failReadWith = StateError('keychain locked');
      int asks = 0;
      final ServerApi api = ServerApi(
        config: ServerApiConfig(source: settings),
        client: MockClient((http.Request request) async {
          if (request.url.path == kAuthSessionPath) {
            asks++;
          }
          return jsonOk(healthBody);
        }),
      );
      await mount(
        tester,
        settings: settings,
        api: api,
        session: nativeSession(
          api: api,
          addresses: settings,
          persistence: store,
        ),
        restoreOnLaunch: true,
      );

      expect(statusLine(tester), l10n.sessionUnknownHint);
      expect(find.byKey(SessionSummaryView.storageNoteKey), findsOneWidget);
      expect(asks, 0);
    });

    testWidgets('查不了之後按重新驗證：再問一次並隨伺服器答案刷新', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      int asks = 0;
      final ServerApi api = ServerApi(
        config: ServerApiConfig(source: settings),
        client: MockClient((http.Request request) async {
          if (request.url.path != kAuthSessionPath) {
            return jsonOk(healthBody);
          }
          asks++;
          if (asks == 1) {
            throw http.ClientException('offline');
          }
          return jsonOk(sessionAccountBody);
        }),
      );
      await mount(
        tester,
        settings: settings,
        api: api,
        session: nativeSession(
          api: api,
          addresses: settings,
          persistence: InMemorySessionPersistence(<String, String>{
            reachableUrl: 'tok-retry-1',
          }),
        ),
        restoreOnLaunch: true,
      );
      expect(statusLine(tester), l10n.sessionUnknownHint);

      await tester.ensureVisible(find.byKey(SessionSummaryView.revalidateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SessionSummaryView.revalidateKey));
      await tester.pumpAndSettle();

      expect(asks, 2);
      expect(find.byKey(SessionSummaryView.identityKey), findsOneWidget);
      expect(
        find.text(
          l10n.labelValuePair(
            l10n.sessionSubjectLabel,
            l10n.sessionSubjectAccount,
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('已登入的身分卡', () {
    testWidgets('Root 主體：列伺服器給的事實，不列帳戶 ID，給 Root 控制台入口', (
      WidgetTester tester,
    ) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(settings);
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: InMemorySessionPersistence(),
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);

      expect(find.byKey(SessionSummaryView.identityKey), findsOneWidget);
      expect(
        find.text(
          l10n.labelValuePair(
            l10n.sessionSubjectLabel,
            l10n.sessionSubjectRoot,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.sessionAccountIdLabel), findsNothing);
      // 到期時間以伺服器给的 UTC 呈現，不做本機時區換算。
      expect(find.textContaining('2026-10-02 03:04 UTC'), findsOneWidget);
      expect(find.text(l10n.sessionRootConsoleAction), findsOneWidget);

      await tester.ensureVisible(find.byKey(SessionSummaryView.rootConsoleKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SessionSummaryView.rootConsoleKey));
      await tester.pumpAndSettle();
      expect(find.text(NavContext.rootConsole.summaryOf(l10n)), findsOneWidget);
    });

    testWidgets('帳戶主體：列帳戶 ID，不給 Root 控制台入口', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(settings);
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: InMemorySessionPersistence(),
        exchange: accountExchange('acct-01'),
      );
      await mount(tester, settings: settings, api: api, session: session);

      expect(
        find.text(
          l10n.labelValuePair(
            l10n.sessionSubjectLabel,
            l10n.sessionSubjectAccount,
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('acct-01'), findsOneWidget);
      expect(find.text(l10n.sessionRootConsoleAction), findsNothing);
    });

    testWidgets('秘密保存失敗的會話：身分卡照常呈現並附一句不會被記住', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(settings);
      final InMemorySessionPersistence store = InMemorySessionPersistence()
        ..failWriteWith = StateError('secure storage unavailable');
      final ServerAddress server = ServerAddress.tryParse(reachableUrl)!;
      final SessionController session = nativeSession(
        api: api,
        addresses: settings,
        persistence: store,
      );
      await session.completeLogin(server, rootExchange());
      await mount(tester, settings: settings, api: api, session: session);

      expect(session.status, SessionStatus.signedIn);
      expect(find.byKey(SessionSummaryView.identityKey), findsOneWidget);
      expect(find.byKey(SessionSummaryView.storageNoteKey), findsOneWidget);
      expect(store.secrets, isEmpty);
    });
  });

  group('換伺服器', () {
    testWidgets('位址換到另一台：舊身分卡立刻消失，改口「查不了」而不沿用舊主體', (WidgetTester tester) async {
      const String otherUrl = 'http://10.0.0.9:5206';
      final ServerAddressSettings settings = await buildAddressSettings(
        storedUrl: reachableUrl,
        reachable: <String>[reachableUrl, otherUrl],
      );
      final InMemorySessionPersistence store = InMemorySessionPersistence();
      final ServerApi api = apiFor(settings);
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);
      expect(find.byKey(SessionSummaryView.identityKey), findsOneWidget);

      await settings.save(otherUrl);
      await tester.pumpAndSettle();

      expect(find.byKey(SessionSummaryView.identityKey), findsNothing);
      expect(statusLine(tester), l10n.sessionUnknownHint);
      // 舊伺服器的秘密被清除：不會被帶去新位址。
      expect(store.secrets.containsKey(reachableUrl), isFalse);
    });

    testWidgets('位址被清空：回到「無從登入」那一句', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(settings);
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: InMemorySessionPersistence(),
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);

      await settings.clear();
      await tester.pumpAndSettle();

      expect(find.byKey(SessionSummaryView.identityKey), findsNothing);
      expect(statusLine(tester), l10n.sessionNotConfiguredHint);
    });
  });

  group('導航一致性', () {
    testWidgets('前往登入只進本應用路由表：登入頁掛在根路由之上而非外部目標', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(settings);
      await mount(
        tester,
        settings: settings,
        api: api,
        session: SessionController(
          api: api,
          addresses: settings,
          mode: SessionTransportMode.web,
        )..restore(),
      );

      await tester.ensureVisible(find.byKey(SessionSummaryView.goLoginKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SessionSummaryView.goLoginKey));
      await tester.pumpAndSettle();
      final Navigator navigator = tester.widget<Navigator>(
        find.byType(Navigator).last,
      );
      expect(find.byKey(LoginPage.submitKey), findsOneWidget);
      expect(navigatorKeyMatches(navigator), isTrue);
    });
  });
}

/// 只驗導航器存在且可返回根路由（外部跳轉在 Flutter 層根本沒有通路，
/// 這裡釘住「返回目標白名單」適用的同一份路由登記）。
bool navigatorKeyMatches(Navigator navigator) {
  return AppRouter.routes.containsKey(kLoginRoute) &&
      AppRouter.guardedRouteNames.length == 4;
}
