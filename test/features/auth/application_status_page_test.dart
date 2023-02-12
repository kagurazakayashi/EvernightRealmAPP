/// 本人申請狀態頁的介面測試（R2-012）：每一次查詢都重新交憑據、成功也不簽發會話，
/// 三種結局各成一句，而認不得的結果不猜成「還在等」也不猜成「已批准」。
///
/// 全部走注入的假傳輸（MockClient）：測試期間不碰網路、不碰任何真實資料目錄；
/// 表裡的口令一律是測試專用假值，斷言只確認它不會出現在任何結論行、提示文字或 URL 上。
library;

import 'dart:async';
import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/app_router.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/core/session/session_status.dart';
import 'package:evernightrealm/features/auth/application_status_page.dart';
import 'package:evernightrealm/features/auth/login_page.dart';
import 'package:evernightrealm/features/auth/register_page.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';
import '../../support/test_language.dart';
import '../../support/test_server.dart';

/// 測試固定以繁體中文呈現；斷言用的期望文字取自同一份資源。
const Locale _locale = Locale('zh', 'TW');

/// 測試專用的假憑據：斷言只確認它不外洩，從不把它寫進結論。
const String _fakePassword = 'sekret-申請口令';

/// 測試用的申請人登入名。
const String _applicant = 'Apply.One';

/// pending 的回應本體（合同上沒有決定時刻那一欄）。
const String pendingBody =
    '{"outcome":"pending",'
    '"submitted_at":"2026-10-03T09:00:00.000Z",'
    '"request_id":"r-status-pending"}';

/// approved 的回應本體（帶決定時刻）。
const String approvedBody =
    '{"outcome":"approved",'
    '"submitted_at":"2026-10-03T09:00:00.000Z",'
    '"reviewed_at":"2026-10-04T11:30:00.000Z",'
    '"request_id":"r-status-approved"}';

/// rejected 的回應本體（不帶任何理由欄位）。
const String rejectedBody =
    '{"outcome":"rejected",'
    '"submitted_at":"2026-10-03T09:00:00.000Z",'
    '"reviewed_at":"2026-10-04T12:00:00.000Z",'
    '"request_id":"r-status-rejected"}';

/// 待審批的註冊回應（status 為 pending，合同其餘欄位與開放模式同形）。
const String registerPendingBody =
    '{"account_id":"01a0e000-0000-7000-8000-0000000000ae",'
    '"login_name":"Apply.One",'
    '"display_name":"申請人一",'
    '"status":"pending",'
    '"must_change_password":false,'
    '"created_at":"2026-10-03T09:00:00.000Z",'
    '"request_id":"r-register-pending"}';

/// 統一錯誤信封（可選帶 details 點名欄位）。
String envelope(int code, String requestId, [Map<String, Object?>? details]) {
  final Map<String, Object?> body = <String, Object?>{
    'code': code,
    'message': 'server text',
    'request_id': requestId,
  };
  if (details != null) {
    body['details'] = details;
  }
  return jsonEncode(body);
}

/// 一則由路徑決定的回應設定。
typedef StubResponse = ({int status, String body, Map<String, String> headers});

/// 一臺隨測試擺佈的假狀態查詢伺服器，記錄每一趟被提交的請求。
class _Fixture {
  _Fixture({required this.reply, this.storedUrl = reachableUrl});

  final Future<http.Response> Function(http.Request request) reply;
  final String storedUrl;

  final List<http.Request> requests = <http.Request>[];
  late SessionController session;

  /// 依路徑決定回應：健康／校時保持正常讓畫面中立，其餘查表。
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

  List<http.Request> to(String path) =>
      requests.where((http.Request r) => r.url.path == path).toList();

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
    // 這一頁不簽發會話：以瀏覽器形態的空會話控制器組裝，
    // 斷言「查到了結果也仍然是未登入」。
    session = SessionController(
      api: api,
      addresses: settings,
      mode: SessionTransportMode.web,
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

  final Map<String, StubResponse> noStub = const <String, StubResponse>{};

  StubResponse okBody(String body) =>
      (status: 200, body: body, headers: <String, String>{});

  StubResponse failing(int status, String body) =>
      (status: status, body: body, headers: <String, String>{});

  Future<void> pump(WidgetTester tester, _Fixture fixture) async {
    await tester.pumpWidget(await fixture.mount());
    await tester.pumpAndSettle();
  }

  /// 進入狀態頁（走應用真實導航：這一頁在門外，不需要會話）。
  Future<void> gotoStatus(WidgetTester tester) async {
    final NavigatorState navigator = tester.state<NavigatorState>(
      find.byType(Navigator).last,
    );
    navigator.pushNamed(kApplicationStatusRoute);
    await tester.pumpAndSettle();
  }

  /// 填齊兩欄。
  Future<void> fillCredentials(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(ApplicationStatusPage.loginNameKey),
      _applicant,
    );
    await tester.enterText(
      find.byKey(ApplicationStatusPage.passwordKey),
      _fakePassword,
    );
    await tester.pump();
  }

  /// 按下查詢但不等結果落畫：進行中的斷言要用這一步。
  Future<void> pressQuery(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(ApplicationStatusPage.submitKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ApplicationStatusPage.submitKey));
    await tester.pump();
  }

  /// 按下查詢並等回話落畫：多數斷言要用這一步。
  Future<void> tapQuery(WidgetTester tester) async {
    await pressQuery(tester);
    await tester.pumpAndSettle();
  }

  String noticeLine(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(ApplicationStatusPage.noticeKey)).data ??
      '';

  /// 一路走到「送出查詢」之後，回傳畫面現況供斷言。
  Future<void> queryOnce(WidgetTester tester, _Fixture fixture) async {
    await pump(tester, fixture);
    await gotoStatus(tester);
    await fillCredentials(tester);
    await tapQuery(tester);
  }

  group('頁面形態', () {
    testWidgets('只有登入名與口令兩欄：口令掩碼、沒有申請編號那種格子', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(reply: _Fixture.ok(noStub));
      await pump(tester, fixture);
      await gotoStatus(tester);

      expect(find.byKey(ApplicationStatusPage.loginNameKey), findsOneWidget);
      expect(find.byKey(ApplicationStatusPage.passwordKey), findsOneWidget);
      final TextField password = tester.widget<TextField>(
        find.byKey(ApplicationStatusPage.passwordKey),
      );
      expect(password.obscureText, isTrue);
      // 沒有「輸入申請編號」「輸入帳戶標識」那類控件：協定層就沒有那種格子。
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text(l10n.applicationStatusSummary), findsOneWidget);
      // 這一頁不自動查：沒有人交憑據就不該發一趟校驗。
      expect(fixture.to(kAuthRegistrationStatusPath), isEmpty);
    });

    testWidgets('沒有位址時查詢停用', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        storedUrl: '',
        reply: _Fixture.ok(noStub),
      );
      await pump(tester, fixture);
      await gotoStatus(tester);
      await fillCredentials(tester);

      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(ApplicationStatusPage.submitKey),
      );
      expect(button.onPressed, isNull);
      expect(fixture.to(kAuthRegistrationStatusPath), isEmpty);
    });

    testWidgets('本地只擋明顯沒填：缺口令時零請求', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(reply: _Fixture.ok(noStub));
      await pump(tester, fixture);
      await gotoStatus(tester);
      await tester.enterText(
        find.byKey(ApplicationStatusPage.loginNameKey),
        _applicant,
      );
      await tester.pump();
      await tapQuery(tester);

      expect(noticeLine(tester), l10n.applicationStatusIncompleteNotice);
      expect(fixture.to(kAuthRegistrationStatusPath), isEmpty);
    });
  });

  group('查詢結果的說法', () {
    testWidgets('pending：如實說還在等，且不擺一個決定時刻', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: okBody(pendingBody),
        }),
      );
      await queryOnce(tester, fixture);

      expect(find.byKey(ApplicationStatusPage.resultKey), findsOneWidget);
      expect(find.text(l10n.applicationStatusPendingNote), findsOneWidget);
      expect(
        find.textContaining(l10n.applicationStatusSubmittedLabel),
        findsOneWidget,
      );
      expect(
        find.textContaining(l10n.applicationStatusDecidedLabel),
        findsNothing,
      );
      // 待審批的人沒有「前往登入」的出口：那是一條注定失敗的路。
      expect(find.byKey(ApplicationStatusPage.goSignInKey), findsNothing);
      // 也沒有任何一句把等待講成可用。
      expect(find.text(l10n.registerUsableNowNote), findsNothing);
      expect(find.text(l10n.applicationStatusApprovedNote), findsNothing);
    });

    testWidgets('approved：講已批准、帶出決定時刻，並給出去登入的出口', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: okBody(approvedBody),
        }),
      );
      await queryOnce(tester, fixture);

      expect(find.text(l10n.applicationStatusApprovedNote), findsOneWidget);
      expect(
        find.textContaining(l10n.applicationStatusDecidedLabel),
        findsOneWidget,
      );
      expect(find.byKey(ApplicationStatusPage.goSignInKey), findsOneWidget);
    });

    testWidgets('rejected：只說被退回，不編造理由、不顯示審核人', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: okBody(rejectedBody),
        }),
      );
      await queryOnce(tester, fixture);

      expect(find.text(l10n.applicationStatusRejectedNote), findsOneWidget);
      expect(_anyTextContains(tester, 'reason'), isFalse);
      expect(_anyTextContains(tester, '審核人'), isFalse);
      expect(find.byKey(ApplicationStatusPage.goSignInKey), findsNothing);
    });

    testWidgets('認不得的結局既不猜成等待也不猜成批准', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: okBody(
            pendingBody.replaceFirst('"pending"', '"on_hold"'),
          ),
        }),
      );
      await queryOnce(tester, fixture);

      expect(find.text(l10n.applicationStatusUnknownNote), findsOneWidget);
      expect(find.text(l10n.applicationStatusPendingNote), findsNothing);
      expect(find.text(l10n.applicationStatusApprovedNote), findsNothing);
      expect(find.byKey(ApplicationStatusPage.goSignInKey), findsNothing);
    });

    testWidgets('結果卡只講自己的事：不出現別人的名字或編號', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: okBody(pendingBody),
        }),
      );
      await queryOnce(tester, fixture);

      final String rendered = _allText(tester);
      // 後端合同裡這一格都沒有：界面更不該憑空生出一個帳戶標識或顯示名。
      expect(rendered, isNot(contains('account_id')));
      expect(rendered, isNot(contains('01a0e000')));
    });
  });

  group('查詢不是登入', () {
    testWidgets('查到已批准後，會話層仍是未登入', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: okBody(approvedBody),
        }),
      );
      await queryOnce(tester, fixture);

      expect(fixture.session.status, isNot(SessionStatus.signedIn));
      expect(
        fixture.to(kAuthRegistrationStatusPath).single.headers['cookie'],
        isNull,
      );
    });

    testWidgets('「前往登入」只是導航：不會自動送出登入請求', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: okBody(approvedBody),
        }),
      );
      await queryOnce(tester, fixture);

      await tester.tap(find.byKey(ApplicationStatusPage.goSignInKey));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(fixture.to(kAuthLoginPath), isEmpty);
      expect(fixture.session.status, isNot(SessionStatus.signedIn));
    });
  });

  group('失敗各成一句', () {
    Future<String> noticeFor(WidgetTester tester, _Fixture fixture) async {
      await queryOnce(tester, fixture);
      return noticeLine(tester);
    }

    _Fixture withStatus(StubResponse reply) => _Fixture(
      reply: _Fixture.ok(<String, StubResponse>{
        kAuthRegistrationStatusPath: reply,
      }),
    );

    testWidgets('2001 憑據無效：與登入同一句，不透露名字存不存在', (WidgetTester tester) async {
      final String line = await noticeFor(
        tester,
        withStatus(failing(401, envelope(2001, 'r-2001'))),
      );
      expect(line, l10n.errorCodeInvalidCredentials);
      expect(line, isNot(contains('server text')));
      expect(line, isNot(l10n.errorCodeNotAnApplication));
    });

    testWidgets('2020 不是申請：處置是去登入，與「憑據無效」「策略關著」都可判別', (
      WidgetTester tester,
    ) async {
      final String line = await noticeFor(
        tester,
        withStatus(failing(403, envelope(2020, 'r-2020'))),
      );
      expect(line, l10n.errorCodeNotAnApplication);
      expect(line, isNot(l10n.errorCodeInvalidCredentials));
      expect(line, isNot(l10n.errorCodeAccountCreationDisabled));
      expect(line, isNot(l10n.errorCodePermissionDenied));
    });

    testWidgets('2006 限流：說的是等一會兒', (WidgetTester tester) async {
      final String line = await noticeFor(
        tester,
        withStatus(failing(429, envelope(2006, 'r-2006'))),
      );
      expect(line, l10n.errorCodeLoginThrottled);
    });

    testWidgets('1004 點名登入名：與「憑據無效」不同句', (WidgetTester tester) async {
      final String line = await noticeFor(
        tester,
        withStatus(
          failing(
            400,
            envelope(1004, 'r-1004', <String, Object?>{
              'invalid_field': 'login_name',
            }),
          ),
        ),
      );
      expect(line, l10n.registerInvalidLoginNameNotice);
    });

    testWidgets('失敗後不擺結果卡、不留任何成功痕跡', (WidgetTester tester) async {
      final _Fixture fixture = withStatus(
        failing(403, envelope(2020, 'r-2020b')),
      );
      await queryOnce(tester, fixture);

      expect(find.byKey(ApplicationStatusPage.resultKey), findsNothing);
      expect(noticeLine(tester), isNot(contains(_fakePassword)));
      expect(fixture.session.status, isNot(SessionStatus.signedIn));
    });

    testWidgets('連不上：說無法與伺服器確認，不假裝查到了什麼', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: (http.Request request) async {
          if (request.url.path == kAuthRegistrationStatusPath) {
            throw http.ClientException('connection refused');
          }
          return _Fixture.ok(noStub)(request);
        },
      );
      final String line = await noticeFor(tester, fixture);
      expect(line, l10n.errorKindUnreachable);
      expect(find.byKey(ApplicationStatusPage.resultKey), findsNothing);
    });
  });

  group('請求形態與憑據留痕', () {
    testWidgets('一趟查詢恰好一個 POST、本體只有兩欄、路徑不帶查詢字串', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: okBody(pendingBody),
        }),
      );
      await queryOnce(tester, fixture);

      final List<http.Request> sent = fixture.to(kAuthRegistrationStatusPath);
      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      // 秘密不進 URL：查詢字串必須是空的。
      expect(sent.single.url.query, isEmpty);
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'login_name', 'password'});
    });

    testWidgets('進行中連點只產生一趟請求', (WidgetTester tester) async {
      final Completer<http.Response> gate = Completer<http.Response>();
      final _Fixture fixture = _Fixture(
        reply: (http.Request request) async {
          if (request.url.path == kAuthRegistrationStatusPath) {
            return gate.future;
          }
          return _Fixture.ok(noStub)(request);
        },
      );
      await pump(tester, fixture);
      await gotoStatus(tester);
      await fillCredentials(tester);
      // 這一步刻意不 settle：要釘的就是「請求還在進行中」那段窗口。
      await pressQuery(tester);

      expect(
        tester
            .widget<FilledButton>(find.byKey(ApplicationStatusPage.submitKey))
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(ApplicationStatusPage.submitKey),
        warnIfMissed: false,
      );
      await tester.tap(
        find.byKey(ApplicationStatusPage.submitKey),
        warnIfMissed: false,
      );
      await tester.pump();
      gate.complete(
        http.Response(
          pendingBody,
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(fixture.to(kAuthRegistrationStatusPath), hasLength(1));
    });

    testWidgets('成功後口令不回填，畫面任何一處都不現形', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: okBody(pendingBody),
        }),
      );
      await queryOnce(tester, fixture);

      final TextField password = tester.widget<TextField>(
        find.byKey(ApplicationStatusPage.passwordKey),
      );
      expect(password.controller!.text, isEmpty);
      expect(_anyTextContains(tester, _fakePassword), isFalse);
    });

    testWidgets('失敗後口令同樣不回填：這條通路沒有一份可複用的憑據狀態', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: failing(401, envelope(2001, 'r-2001c')),
        }),
      );
      await queryOnce(tester, fixture);

      final TextField password = tester.widget<TextField>(
        find.byKey(ApplicationStatusPage.passwordKey),
      );
      expect(password.controller!.text, isEmpty);
      expect(_anyTextContains(tester, _fakePassword), isFalse);
    });

    testWidgets('再查一次要重新打口令：畫面不保存上一次交過的憑據', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegistrationStatusPath: okBody(pendingBody),
        }),
      );
      await queryOnce(tester, fixture);

      // 第二次不填口令直接按：本地就擋住，說明界面沒留著剛才那枚憑據。
      await tapQuery(tester);
      expect(noticeLine(tester), l10n.applicationStatusIncompleteNotice);
      expect(fixture.to(kAuthRegistrationStatusPath), hasLength(1));
    });
  });

  group('與註冊頁的接縫', () {
    testWidgets('待審批的提交摘要改口並導向這一頁，且那張卡上沒有「前往登入」', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegisterPath: (
            status: 201,
            body: registerPendingBody,
            headers: <String, String>{},
          ),
          kAuthRegistrationStatusPath: okBody(pendingBody),
        }),
      );
      await pump(tester, fixture);
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      navigator.pushNamed(kRegisterRoute);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(RegisterPage.loginNameKey), _applicant);
      await tester.enterText(find.byKey(RegisterPage.displayNameKey), '申請人一');
      await tester.enterText(
        find.byKey(RegisterPage.passwordKey),
        _fakePassword,
      );
      await tester.ensureVisible(find.byKey(RegisterPage.submitKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RegisterPage.submitKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.registerPendingTitle(_applicant)), findsOneWidget);
      expect(find.text(l10n.registerPendingNote), findsOneWidget);
      expect(find.text(l10n.registerUsableNowNote), findsNothing);
      expect(find.byKey(RegisterPage.goSignInKey), findsNothing);
      expect(find.byKey(RegisterPage.checkStatusKey), findsOneWidget);

      await tester.tap(find.byKey(RegisterPage.checkStatusKey));
      await tester.pumpAndSettle();
      expect(find.byType(ApplicationStatusPage), findsOneWidget);
      // 導航本身不發任何查詢請求：這一頁不替人交憑據。
      expect(fixture.to(kAuthRegistrationStatusPath), isEmpty);
    });

    testWidgets('開放模式的摘要照舊是「可用」與「前往登入」', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthRegisterPath: (
            status: 201,
            body: registerSuccessBody,
            headers: <String, String>{},
          ),
        }),
      );
      await pump(tester, fixture);
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      navigator.pushNamed(kRegisterRoute);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(RegisterPage.loginNameKey), 'Std.One');
      await tester.enterText(find.byKey(RegisterPage.displayNameKey), '甲');
      await tester.enterText(
        find.byKey(RegisterPage.passwordKey),
        _fakePassword,
      );
      await tester.ensureVisible(find.byKey(RegisterPage.submitKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RegisterPage.submitKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.registerUsableNowNote), findsOneWidget);
      expect(find.byKey(RegisterPage.goSignInKey), findsOneWidget);
      expect(find.byKey(RegisterPage.checkStatusKey), findsNothing);
    });
  });
}

/// 開放模式（active）的註冊回應：既有測試沿用的同一份樣板。
const String registerSuccessBody =
    '{"account_id":"01a0e000-0000-7000-8000-0000000000ad",'
    '"login_name":"Std.One",'
    '"display_name":"甲",'
    '"status":"active",'
    '"must_change_password":false,'
    '"created_at":"2026-10-03T09:00:00.000Z",'
    '"request_id":"r-register-active"}';

/// 遍歷當前樹上所有 Text，判斷是否有任一處含給定子串（憑據不外洩的粗篩）。
bool _anyTextContains(WidgetTester tester, String needle) {
  for (final Element element in find.byType(Text).evaluate()) {
    final String? data = (element.widget as Text).data;
    if (data != null && data.contains(needle)) {
      return true;
    }
  }
  return false;
}

/// 當前樹上所有 Text 串成一段文字（「這頁沒寫某種東西」的斷言用）。
String _allText(WidgetTester tester) {
  final StringBuffer buffer = StringBuffer();
  for (final Element element in find.byType(Text).evaluate()) {
    buffer.writeln((element.widget as Text).data ?? '');
  }
  return buffer.toString();
}
