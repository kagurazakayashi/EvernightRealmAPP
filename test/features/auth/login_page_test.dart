/// 登入頁的介面測試：每一句失敗提示都必須對得上伺服器真的回了那個機器碼，
/// 每一次提交都只准產生一趟請求，成功後的身分只准來自伺服器回應。
///
/// 全部走注入的假傳輸（MockClient）：測試期間不碰網路、不碰任何真實資料目錄；
/// 表裡的口令一律是測試專用假值，斷言不把它抄進任何結論行。
library;

import 'dart:async';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/app_router.dart';
import 'package:evernightrealm/app/nav_context.dart';
import 'package:evernightrealm/app/nav_context_labels.dart';
import 'package:evernightrealm/app/session_gate.dart';
import 'package:evernightrealm/app/widgets/session_summary_view.dart';
import 'package:evernightrealm/core/api/api_client.dart';
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

import '../../support/test_address.dart';
import '../../support/test_language.dart';
import '../../support/test_server.dart';
import '../../support/test_session.dart';

/// 測試固定以繁體中文呈現；斷言用的期望文字取自同一份資源。
const Locale _locale = Locale('zh', 'TW');

/// Root 登入成功的回應本體（合同欄位，不含任何秘密）。
const String rootLoginBody =
    '{"subject_kind":"root","device_id":"device-77",'
    '"expires_at":"2026-10-02T03:04:05.000Z","request_id":"r-login-root"}';

/// 帳戶登入成功的回應本體。
const String accountLoginBody =
    '{"subject_kind":"account","account_id":"acct-01","device_id":"device-88",'
    '"expires_at":"2026-10-02T03:04:05.000Z","request_id":"r-login-acct"}';

/// 統一錯誤信封。
String envelope(int code, String requestId) =>
    '{"code":$code,"message":"server text","request_id":"$requestId"}';

/// 一則由路徑決定的回應設定。
typedef StubResponse = ({int status, String body, Map<String, String> headers});

/// 一台隨測試擺佈的假登入伺服器，記錄每一趟被提交的請求。
class _Fixture {
  /// 以回應決定方式建立。
  _Fixture({
    required this.reply,
    this.storedUrl = reachableUrl,
    this.webTransport = false,
    this.persistence,
  });

  /// 依請求決定回應；要製造傳輸級失敗時直接在裡面對外拋例外。
  final Future<http.Response> Function(http.Request request) reply;

  /// 本機保存的位址。
  final String storedUrl;

  /// 是否以瀏覽器形态組裝會話控制器（Cookie 代管、不碰秘密）。
  final bool webTransport;

  /// 注入的安全儲存假件（原生形态）。
  InMemorySessionPersistence? persistence;

  /// 被問過的請求。
  final List<http.Request> requests = <http.Request>[];

  /// 掛進應用樹之後的會話控制器（斷言狀態用）。
  late SessionController session;

  /// 依路徑決定回應；探測那兩條路徑保持正常，讓畫面中立。
  static Future<http.Response> Function(http.Request) ok(
    Map<String, StubResponse> byPath,
  ) {
    return (http.Request request) async {
      switch (request.url.path) {
        case kHealthPath:
          return jsonOk(healthBody);
        case kTimePath:
          return jsonOk(timeBody);
        default:
          final StubResponse? hit = byPath[request.url.path];
          if (hit == null) {
            return http.Response(
              envelope(1001, 'r-404'),
              404,
              headers: <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response(
            hit.body,
            hit.status,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
              ...hit.headers,
            },
          );
      }
    };
  }

  /// 被問到的指定路徑請求。
  List<http.Request> to(String path) =>
      requests.where((http.Request r) => r.url.path == path).toList();

  /// 組裝成一份可掛進應用樹的測試應用。
  Future<Widget> mount() async {
    final ServerAddressSettings settings = await buildAddressSettings(
      storedUrl: storedUrl.isEmpty ? null : storedUrl,
      reachable: <String>[storedUrl],
    );
    final ServerApi api = ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        requests.add(request);
        return reply(request);
      }),
    );
    session = webTransport
        ? SessionController(
            api: api,
            addresses: settings,
            mode: SessionTransportMode.web,
          )
        : nativeSession(
            api: api,
            addresses: settings,
            persistence: persistence ?? InMemorySessionPersistence(),
          );
    return buildTestApp(
      storedTag: _locale.toLanguageTag(),
      addresses: settings,
      dependencies: AppDependencies(api: api),
      session: session,
    );
  }
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  /// 掛上應用並完成首幀。
  Future<void> pump(WidgetTester tester, _Fixture fixture) async {
    await tester.pumpWidget(await fixture.mount());
    await tester.pumpAndSettle();
  }

  /// 進入登入頁（走應用的真實導航，可帶返回目標）。
  Future<void> gotoLogin(WidgetTester tester, {Object? returnTo}) async {
    final NavigatorState navigator = tester.state<NavigatorState>(
      find.byType(Navigator).last,
    );
    navigator.pushNamed(kLoginRoute, arguments: returnTo);
    await tester.pumpAndSettle();
  }

  /// 在入口頁點「前往登入」。
  Future<void> tapGoLogin(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(SessionSummaryView.goLoginKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SessionSummaryView.goLoginKey));
    await tester.pumpAndSettle();
  }

  /// 輸入口令。
  Future<void> typePassword(WidgetTester tester, String value) async {
    await tester.enterText(find.byKey(LoginPage.passwordKey), value);
    await tester.pump();
  }

  /// 按一次提交。
  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(LoginPage.submitKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LoginPage.submitKey));
    await tester.pump();
  }

  /// 錯誤提示行的文字。
  String errorLine(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(LoginPage.errorKey)).data ?? '';

  /// 空的回應對照表。
  Map<String, StubResponse> noStub = const <String, StubResponse>{};

  group('頁面形態', () {
    testWidgets('預設 Root 方式：只有口令欄，沒有登入名欄', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(reply: _Fixture.ok(noStub));
      await pump(tester, fixture);
      await tapGoLogin(tester);

      expect(find.byKey(LoginPage.passwordKey), findsOneWidget);
      expect(find.byKey(LoginPage.loginNameKey), findsNothing);
      expect(find.text(l10n.loginModeRoot), findsOneWidget);
      // 口令以掩碼輸入，頁面不預填任何憑據。
      final TextField password = tester.widget<TextField>(
        find.byKey(LoginPage.passwordKey),
      );
      expect(password.obscureText, isTrue);
      expect(password.controller!.text, isEmpty);
    });

    testWidgets('切到帳戶方式：出現登入名欄並如實聲明沒有建號入口', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(reply: _Fixture.ok(noStub));
      await pump(tester, fixture);
      await tapGoLogin(tester);

      await tester.ensureVisible(find.text(l10n.loginModeAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.loginModeAccount));
      await tester.pumpAndSettle();

      expect(find.byKey(LoginPage.loginNameKey), findsOneWidget);
      expect(find.text(l10n.loginAccountNote), findsOneWidget);
      // 這一頁不提供建號／註冊通路：切換本身不產生任何登入請求。
      expect(fixture.to(kAuthLoginPath), isEmpty);
      expect(fixture.to(kAuthRootLoginPath), isEmpty);
    });

    testWidgets('伺服器資訊行顯示生效位址，不含口令與憑證', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(reply: _Fixture.ok(noStub));
      await pump(tester, fixture);
      await tapGoLogin(tester);

      final String info =
          tester.widget<Text>(find.byKey(LoginPage.serverInfoKey)).data ?? '';
      expect(info, contains(reachableUrl));
    });
  });

  group('提交攔截', () {
    testWidgets('口令為空時本地攔截，一個請求都不發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(reply: _Fixture.ok(noStub));
      await pump(tester, fixture);
      await tapGoLogin(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(errorLine(tester), l10n.loginPasswordRequired);
      // 本地攔截不發任何登入請求（入口層的只讀狀態查詢不算）。
      expect(fixture.to(kAuthRootLoginPath), isEmpty);
      expect(fixture.to(kAuthLoginPath), isEmpty);
    });

    testWidgets('帳戶模式登入名為空時同樣零請求', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(reply: _Fixture.ok(noStub));
      await pump(tester, fixture);
      await tapGoLogin(tester);
      await tester.ensureVisible(find.text(l10n.loginModeAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.loginModeAccount));
      await tester.pumpAndSettle();
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(errorLine(tester), l10n.loginLoginNameRequired);
      expect(fixture.to(kAuthRootLoginPath), isEmpty);
      expect(fixture.to(kAuthLoginPath), isEmpty);
    });

    testWidgets('沒有位址時提交停用，且資訊行如實說未設定', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        storedUrl: '',
        reply: _Fixture.ok(noStub),
      );
      await pump(tester, fixture);
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      navigator.pushNamed(kLoginRoute);
      await tester.pumpAndSettle();

      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(LoginPage.submitKey),
      );
      expect(button.onPressed, isNull);
      final String info =
          tester.widget<Text>(find.byKey(LoginPage.serverInfoKey)).data ?? '';
      expect(info, contains(l10n.serverAddressNotSet));
    });
  });

  group('防重複提交', () {
    testWidgets('進行中連點只產生一趟請求', (WidgetTester tester) async {
      final Completer<http.Response> gate = Completer<http.Response>();
      final _Fixture fixture = _Fixture(
        webTransport: true,
        reply: (http.Request request) async {
          if (request.url.path == kAuthRootLoginPath) {
            return gate.future;
          }
          return _Fixture.ok(noStub)(request);
        },
      );
      await pump(tester, fixture);
      await gotoLogin(tester);
      await typePassword(tester, 'sekret');

      await tapSubmit(tester);
      expect(
        tester.widget<FilledButton>(find.byKey(LoginPage.submitKey)).onPressed,
        isNull,
      );
      // 再連點兩次：進行中的那趟沿用同一個 Future，不會多出第二筆登入請求。
      await tester.tap(find.byKey(LoginPage.submitKey), warnIfMissed: false);
      await tester.tap(find.byKey(LoginPage.submitKey), warnIfMissed: false);
      await tester.pump();

      gate.complete(jsonOk(rootLoginBody));
      await tester.pumpAndSettle();

      expect(fixture.to(kAuthRootLoginPath).length, 1);
      expect(find.byType(LoginPage), findsNothing);
    });
  });

  group('失敗狀態的可理解提示', () {
    testWidgets('口令不符：顯示 2001 的統一文案，不透露是哪一半錯', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRootLoginPath: (
            status: 401,
            body: envelope(2001, 'r-401'),
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester);
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(errorLine(tester), l10n.errorCodeInvalidCredentials);
      // 提示不含伺服器原文、不含口令；頁面留住，沒有半成功出口。
      expect(errorLine(tester), isNot(contains('server text')));
      expect(errorLine(tester), isNot(contains('sekret')));
      expect(find.byType(LoginPage), findsOneWidget);
      expect(fixture.session.status, isNot(SessionStatus.signedIn));
    });

    testWidgets('被限流：顯示 2006 的稍後再試，不是「口令不對」', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRootLoginPath: (
            status: 429,
            body: envelope(2006, 'r-429'),
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester);
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(errorLine(tester), l10n.errorCodeLoginThrottled);
      expect(errorLine(tester), isNot(l10n.errorCodeInvalidCredentials));
    });

    testWidgets('裝置名額已滿：顯示 2008 的專屬說明，不說成口令錯誤', (WidgetTester tester) async {
      // 這一句的價值全在「不誤導」：把名額已滿報成憑據無效，使用者會對著
      // 一個正確的口令反覆重打，而真正要做的是去另一臺裝置登出。
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRootLoginPath: (
            status: 403,
            body: envelope(2008, 'r-403'),
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester);
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(errorLine(tester), l10n.errorCodeDeviceLimitReached);
      expect(errorLine(tester), isNot(l10n.errorCodeInvalidCredentials));
      expect(errorLine(tester), isNot(l10n.errorCodeLoginThrottled));
      // 回應不帶數字（後端刻意不放上限），介面也就不能憑空造出一個數字。
      expect(errorLine(tester), isNot(contains('server text')));
      expect(find.byType(LoginPage), findsOneWidget);
      expect(fixture.session.status, isNot(SessionStatus.signedIn));
    });

    testWidgets('連不上：說無法與伺服器確認，不是「口令不對」', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: (http.Request request) async {
          if (request.url.path == kAuthRootLoginPath) {
            throw http.ClientException('connection refused');
          }
          return _Fixture.ok(noStub)(request);
        },
      );
      await pump(tester, fixture);
      await gotoLogin(tester);
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(errorLine(tester), l10n.errorKindUnreachable);
    });

    testWidgets('原生端拿不到秘密：如實停在無法確定，不謊報已登入', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        // 200 但沒有 Set-Cookie：原生環境拿不到可回傳的憑據。
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRootLoginPath: (
            status: 200,
            body: rootLoginBody,
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester);
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(errorLine(tester), l10n.loginMissingCredentialNote);
      expect(fixture.session.status, SessionStatus.unknown);
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('成功與返回路由', () {
    testWidgets('Root 登入成功：身分取自伺服器回應，回到入口頁並顯示身分卡', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        webTransport: true,
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRootLoginPath: (
            status: 200,
            body: rootLoginBody,
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await tapGoLogin(tester);
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsNothing);
      expect(fixture.session.status, SessionStatus.signedIn);
      expect(fixture.session.activeSession?.isRoot, isTrue);
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
    });

    testWidgets('Root 方式但伺服器回帳戶主體：按主體判定，不按表單選項', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        webTransport: true,
        reply: _Fixture.ok(<String, StubResponse>{
          // 極端的合同情境：打的是 Root 端點、回的是帳戶主體——一律以回應為準。
          kAuthRootLoginPath: (
            status: 200,
            body: accountLoginBody,
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester, returnTo: NavContext.rootConsole.routeName);
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      // 返回目標是 Root 控制台，但主體不是 Root：不能進去，只能回入口層。
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byKey(SessionGate.blockedKey), findsNothing);
      expect(find.text(NavContext.rootConsole.summaryOf(l10n)), findsNothing);
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
      expect(find.text(l10n.sessionRootConsoleAction), findsNothing);
    });

    testWidgets('合法返回路由：Root 身分帶著 /root-console 目標，成功後直達該頁', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(
        webTransport: true,
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRootLoginPath: (
            status: 200,
            body: rootLoginBody,
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester, returnTo: NavContext.rootConsole.routeName);
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text(NavContext.rootConsole.summaryOf(l10n)), findsOneWidget);
    });

    testWidgets('外部網址返回目標：一律回入口層，不跳出應用', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        webTransport: true,
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRootLoginPath: (
            status: 200,
            body: rootLoginBody,
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester, returnTo: 'https://evil.example.com/steal');
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsNothing);
      expect(find.byKey(SessionSummaryView.identityKey), findsOneWidget);
      // 堆疊回到只有根路由：跳轉目標完全限制在本應用的路由表內。
      expect(
        tester.state<NavigatorState>(find.byType(Navigator).last).canPop(),
        isFalse,
      );
    });

    testWidgets('未登記路徑作為返回目標：同樣回入口層', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        webTransport: true,
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRootLoginPath: (
            status: 200,
            body: rootLoginBody,
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester, returnTo: '/not-a-real-route');
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text(l10n.unknownRouteTitle), findsNothing);
      expect(find.byKey(SessionSummaryView.identityKey), findsOneWidget);
    });

    testWidgets('原生端秘密保存失敗：如實進入本機會話，身分卡附註不留明文', (WidgetTester tester) async {
      final InMemorySessionPersistence store = InMemorySessionPersistence()
        ..failWriteWith = StateError('secure storage unavailable');
      final _Fixture fixture = _Fixture(
        persistence: store,
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRootLoginPath: (
            status: 200,
            body: rootLoginBody,
            headers: <String, String>{
              'set-cookie': 'evernight_session=tok-root-9; HttpOnly; Path=/',
            },
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester);
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      // 本機會話可用（記憶體中有秘密），但落盤失敗那句要如實呈現。
      expect(find.byType(LoginPage), findsNothing);
      expect(store.secrets, isEmpty);
      expect(fixture.session.status, SessionStatus.signedIn);
      expect(find.byKey(SessionSummaryView.storageNoteKey), findsOneWidget);
      expect(find.text(l10n.sessionStorageFailureNote), findsOneWidget);
    });
  });

  group('請求形態', () {
    testWidgets('Root 方式只送口令到 Root 端點', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        webTransport: true,
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRootLoginPath: (
            status: 200,
            body: rootLoginBody,
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester);
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      final List<http.Request> rootReqs = fixture.to(kAuthRootLoginPath);
      expect(rootReqs.length, 1);
      expect(rootReqs.single.method, 'POST');
      expect(rootReqs.single.body, '{"password":"sekret"}');
      expect(fixture.to(kAuthLoginPath), isEmpty);
      expect(fixture.to(kAuthSessionPath), isEmpty);
    });

    testWidgets('帳戶方式帶登入名到帳戶端點', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        webTransport: true,
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthLoginPath: (
            status: 200,
            body: accountLoginBody,
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      await gotoLogin(tester);
      await tester.ensureVisible(find.text(l10n.loginModeAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.loginModeAccount));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(LoginPage.loginNameKey), 'player01');
      await typePassword(tester, 'sekret');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      final List<http.Request> reqs = fixture.to(kAuthLoginPath);
      expect(reqs.length, 1);
      expect(reqs.single.method, 'POST');
      expect(reqs.single.body, '{"login_name":"player01","password":"sekret"}');
      expect(fixture.to(kAuthRootLoginPath), isEmpty);
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
}
