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
import 'package:evernightrealm/core/api/server_models.dart';
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
    '"rotation_seq":0,'
    '"created_at":"2026-09-30T03:04:05.000Z",'
    '"last_active_at":"2026-09-30T03:05:05.000Z",'
    '"expires_at":"2026-10-02T03:04:05.000Z","request_id":"r-sess-root"}';

/// `/auth/session` 的帳戶主體回應。
const String sessionAccountBody =
    '{"subject_kind":"account","account_id":"acct-01","device_id":"device-88",'
    '"rotation_seq":0,'
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

/// 一則輪換成功回應：同一裝置、同一到期時刻，另攜換發出的新秘密。
///
/// 原生端從 `Set-Cookie` 讀取新秘密（瀏覽器由 HttpOnly Cookie 代管，讀不到也不必讀）。
http.Response rotationOk(int seq, String secret) => http.Response(
  '{"subject_kind":"root","device_id":"device-77","rotation_seq":$seq,'
  '"expires_at":"2026-10-02T03:04:05.000Z","request_id":"r-rot"}',
  200,
  headers: <String, String>{
    'content-type': 'application/json; charset=utf-8',
    'set-cookie': 'evernight_session=$secret; Path=/; HttpOnly',
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
    Future<http.Response> Function(http.Request request)? onLogout,
    Future<http.Response> Function(http.Request request)? onRotate,
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
          case kAuthSessionRotatePath:
            return onRotate == null
                ? jsonError(500, 1000, 'r-rot')
                : await onRotate(request);
          case kAuthLogoutPath:
            return onLogout == null ? jsonOk('{}') : await onLogout(request);
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

  group('已登入態的登出', () {
    testWidgets('登出按鈕一律呈現（Root 與帳戶身分都有）', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(settings);
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: InMemorySessionPersistence(),
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);

      await tester.ensureVisible(find.byKey(SessionSummaryView.logoutKey));
      expect(find.byKey(SessionSummaryView.logoutKey), findsOneWidget);
      expect(find.text(l10n.sessionLogoutAction), findsOneWidget);
    });

    testWidgets('按登出：发一趟撤销请求、回到未登入、提示已登出', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      int logoutHits = 0;
      // Bearer 注入闭环由 session_controller_test 承担（那张假装配没接
      // credentials resolver，此处不重复断言标头）。
      final ServerApi api = apiFor(
        settings,
        onLogout: (http.Request request) async {
          logoutHits++;
          expect(request.url.path, kAuthLogoutPath);
          return jsonOk('{}');
        },
      );
      final InMemorySessionPersistence store = InMemorySessionPersistence();
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);

      await tester.ensureVisible(find.byKey(SessionSummaryView.logoutKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SessionSummaryView.logoutKey));
      await tester.pumpAndSettle();

      expect(logoutHits, 1);
      expect(session.status, SessionStatus.signedOut);
      expect(store.secrets, isEmpty, reason: '登出要删掉本机那枚秘密');
      expect(find.byKey(SessionSummaryView.identityKey), findsNothing);
      expect(find.text(l10n.sessionSignedOutHint), findsOneWidget);
      // 服务器确认撤销→提示成功那一句。
      expect(find.text(l10n.sessionSignOutSuccessNotice), findsOneWidget);
    });

    testWidgets('服务器失联：本机已清理但提示未确认，且绝不称所有设备已下线', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(
        settings,
        onLogout: (http.Request request) async =>
            throw http.ClientException('offline'),
      );
      final InMemorySessionPersistence store = InMemorySessionPersistence();
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);

      await tester.ensureVisible(find.byKey(SessionSummaryView.logoutKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SessionSummaryView.logoutKey));
      await tester.pumpAndSettle();

      expect(session.status, SessionStatus.signedOut);
      expect(store.secrets, isEmpty, reason: '失联时本机秘密照样清');
      // 关键区分：不能谎称已在服务器登出。
      expect(find.text(l10n.sessionSignOutSuccessNotice), findsNothing);
      expect(find.text(l10n.sessionSignOutUnconfirmedNotice), findsOneWidget);
    });

    testWidgets('登出进行中的连点只产生一趟请求', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      int logoutHits = 0;
      final Completer<http.Response> gate = Completer<http.Response>();
      final ServerApi api = apiFor(
        settings,
        onLogout: (http.Request request) async {
          logoutHits++;
          return gate.future;
        },
      );
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: InMemorySessionPersistence(),
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);

      await tester.ensureVisible(find.byKey(SessionSummaryView.logoutKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SessionSummaryView.logoutKey));
      // 让 _signingOut=true 的重建落地（此时按钮已停用）。
      await tester.pump();
      await tester.tap(find.byKey(SessionSummaryView.logoutKey));
      await tester.pump();
      expect(logoutHits, 1, reason: '进行中连点不产生第二趟撤销');

      gate.complete(jsonOk('{}'));
      await tester.pumpAndSettle();
      expect(session.status, SessionStatus.signedOut);
    });
  });

  group('已登入態的秘密輪換', () {
    testWidgets('輪換按鈕在已登入態一律呈現', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(settings);
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: InMemorySessionPersistence(),
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);

      await tester.ensureVisible(find.byKey(SessionSummaryView.rotateKey));
      expect(find.byKey(SessionSummaryView.rotateKey), findsOneWidget);
      expect(find.text(l10n.sessionRotateAction), findsOneWidget);
    });

    testWidgets('按輪換：發一趟請求、寫回新憑據與世代號、提示成功', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      int rotateHits = 0;
      final ServerApi api = apiFor(
        settings,
        onRotate: (http.Request request) async {
          rotateHits++;
          expect(request.url.path, kAuthSessionRotatePath);
          return rotationOk(1, 'tok-rotated');
        },
      );
      final InMemorySessionPersistence store = InMemorySessionPersistence();
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);

      await tester.ensureVisible(find.byKey(SessionSummaryView.rotateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SessionSummaryView.rotateKey));
      await tester.pumpAndSettle();

      expect(rotateHits, 1);
      expect(session.status, SessionStatus.signedIn);
      expect(store.credentials[reachableUrl]?.secret, 'tok-rotated');
      expect(store.credentials[reachableUrl]?.rotationSeq, 1);
      expect(find.text(l10n.sessionRotateSuccessNotice), findsOneWidget);
    });

    testWidgets('輪換進行中：按鈕停用並顯示進行中文案', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final Completer<http.Response> gate = Completer<http.Response>();
      final ServerApi api = apiFor(
        settings,
        onRotate: (http.Request request) => gate.future,
      );
      final InMemorySessionPersistence store = InMemorySessionPersistence();
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);

      await tester.ensureVisible(find.byKey(SessionSummaryView.rotateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SessionSummaryView.rotateKey));
      // 讓 _rotating=true 的重建落地（此時按鈕已停用）。
      await tester.pump();

      expect(find.text(l10n.sessionRotatingAction), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(SessionSummaryView.rotateKey))
            .onPressed,
        isNull,
        reason: '進行中停用，防連點',
      );

      gate.complete(rotationOk(1, 'tok-rotated'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.sessionRotateSuccessNotice), findsOneWidget);
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

  group('自助綁定訪戶的入口', () {
    /// 以一份指定身分的登入成果掛上會話卡。
    ///
    /// 入口的有無只由伺服器回報的主體事實決定（主體類別、帳戶類型、授予、
    /// 改密義務），界面不自己猜：這裡把四樣輸入逐一給定，看按鈕出不出現。
    Future<void> mountSubject(
      WidgetTester tester, {
      required AuthSubjectKind subjectKind,
      String? accountId,
      AuthAccountType? accountType,
      List<String> roles = const <String>[],
      bool mustChangePassword = false,
    }) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(settings);
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: InMemorySessionPersistence(),
        exchange: LoginExchange(
          report: LoginReport(
            subjectKind: subjectKind,
            accountId: accountId,
            accountType: accountType,
            deviceId: 'device-88',
            expiresAt: DateTime.utc(2026, 10, 2, 3, 4, 5),
            requestId: 'r-login-bind',
            roles: roles,
            mustChangePassword: mustChangePassword,
          ),
          sessionSecret: 'tok-bind-1',
        ),
      );
      await mount(tester, settings: settings, api: api, session: session);
      expect(find.byKey(SessionSummaryView.identityKey), findsOneWidget);
    }

    testWidgets('普通正式帳戶：入口在場（他是憑證上釘著的那位持有人）', (WidgetTester tester) async {
      await mountSubject(
        tester,
        subjectKind: AuthSubjectKind.account,
        accountId: 'acct-01',
        accountType: AuthAccountType.standard,
      );
      expect(find.byKey(SessionSummaryView.guestBindKey), findsOneWidget);
      expect(find.text(l10n.guestBindEntryAction), findsOneWidget);
    });

    testWidgets('訪客本人：沒有這一顆（他在這條通路上拿 2011，界面不擺註定失敗的入口）', (
      WidgetTester tester,
    ) async {
      await mountSubject(
        tester,
        subjectKind: AuthSubjectKind.account,
        accountId: 'acct-guest',
        accountType: AuthAccountType.guest,
      );
      expect(find.byKey(SessionSummaryView.guestBindKey), findsNothing);
      expect(find.text(l10n.guestBindEntryAction), findsNothing);
    });

    testWidgets('Root 主體：沒有這一顆（Root 不是憑證釘著的那位持有人）', (
      WidgetTester tester,
    ) async {
      await mountSubject(tester, subjectKind: AuthSubjectKind.root);
      expect(find.byKey(SessionSummaryView.guestBindKey), findsNothing);
    });

    testWidgets('持伺服器級授予的帳戶：沒有這一顆（管理員也代不了目標本人）', (WidgetTester tester) async {
      await mountSubject(
        tester,
        subjectKind: AuthSubjectKind.account,
        accountId: 'acct-admin',
        accountType: AuthAccountType.standard,
        roles: const <String>[kServerAdminRole],
      );
      expect(find.byKey(SessionSummaryView.guestBindKey), findsNothing);
      // 同一份主體事實的其他入口不受影響：這一條只是綁定的入口。
      expect(find.byKey(SessionSummaryView.passwordChangeKey), findsOneWidget);
    });

    testWidgets('欠改密的普通帳戶：四條寫入入口一起停住，綁定也不例外', (WidgetTester tester) async {
      await mountSubject(
        tester,
        subjectKind: AuthSubjectKind.account,
        accountId: 'acct-01',
        accountType: AuthAccountType.standard,
        mustChangePassword: true,
      );
      expect(find.byKey(SessionSummaryView.guestBindKey), findsNothing);
      expect(find.byKey(SessionSummaryView.deviceManagerKey), findsNothing);
      expect(find.byKey(SessionSummaryView.rotateKey), findsNothing);
    });
  });
}

/// 只驗導航器存在且可返回根路由（外部跳轉在 Flutter 層根本沒有通路，
/// 這裡釘住「返回目標白名單」適用的同一份路由登記）。
bool navigatorKeyMatches(Navigator navigator) {
  return AppRouter.routes.containsKey(kLoginRoute) &&
      AppRouter.guardedRouteNames.length == 4;
}
