/// 匿名自註冊頁的介面測試（R2-011）：每一句失敗提示都必須對得上伺服器真的回了那個機器碼，
/// 每一次提交只准產生一趟請求，成功摘要只准來自伺服器回應、且絕不簽發會話。
///
/// 全部走注入的假傳輸（MockClient）：測試期間不碰網路、不碰任何真實資料目錄；
/// 表裡的口令一律是測試專用假值，斷言不把它抄進任何結論行、也不讓它出現在任何提示文字裡。
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

/// 測試專用的假自選口令：斷言只確認它不會外洩，從不把它寫進結論。
const String _fakePassword = 'sekret-自選口令';

/// 註冊成功的回應本體（標準／active／無需改密；合同上不含任何口令或會話材料）。
const String registerSuccessBody =
    '{"account_id":"01a0e000-0000-7000-8000-0000000000ad",'
    '"login_name":"Std.First.Sign.In",'
    '"display_name":"首个自註冊帳戶",'
    '"status":"active",'
    '"must_change_password":false,'
    '"created_at":"2026-10-03T09:00:00.000Z",'
    '"request_id":"r-register-ok"}';

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

/// 一臺隨測試擺佈的假註冊伺服器，記錄每一趟被提交的請求。
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
    // 註冊通路本身不簽發會話：以瀏覽器形態的空會話控制器組裝，斷言「註冊成功後仍是未登入」。
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

/// 匯總目前畫面上所有 Text 的文字，供「不得出現某串」的掃描。
String _allText(WidgetTester tester) {
  final StringBuffer buffer = StringBuffer();
  for (final Text widget in tester.widgetList<Text>(find.byType(Text))) {
    buffer.write(widget.data ?? '');
    buffer.write('\n');
  }
  return buffer.toString();
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  Future<void> pump(WidgetTester tester, _Fixture fixture) async {
    await tester.pumpWidget(await fixture.mount());
    await tester.pumpAndSettle();
  }

  /// 進入註冊頁（走應用真實導航）。
  Future<void> gotoRegister(WidgetTester tester) async {
    final NavigatorState navigator = tester.state<NavigatorState>(
      find.byType(Navigator).last,
    );
    navigator.pushNamed(kRegisterRoute);
    await tester.pumpAndSettle();
  }

  /// 填齊三個欄位。
  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(RegisterPage.loginNameKey),
      'Std.First.Sign.In',
    );
    await tester.enterText(find.byKey(RegisterPage.displayNameKey), '首个自註冊帳戶');
    await tester.enterText(find.byKey(RegisterPage.passwordKey), _fakePassword);
    await tester.pump();
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(RegisterPage.submitKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RegisterPage.submitKey));
    await tester.pump();
  }

  String noticeLine(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(RegisterPage.noticeKey)).data ?? '';

  Map<String, StubResponse> noStub = const <String, StubResponse>{};

  group('頁面形態', () {
    testWidgets('只有三個白名單欄：口令掩碼、預留空、無任何角色控件', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(reply: _Fixture.ok(noStub));
      await pump(tester, fixture);
      await gotoRegister(tester);

      expect(find.byKey(RegisterPage.loginNameKey), findsOneWidget);
      expect(find.byKey(RegisterPage.displayNameKey), findsOneWidget);
      expect(find.byKey(RegisterPage.passwordKey), findsOneWidget);
      final TextField password = tester.widget<TextField>(
        find.byKey(RegisterPage.passwordKey),
      );
      expect(password.obscureText, isTrue);
      expect(password.controller!.text, isEmpty);
      // 這一頁放不出「把自己註冊成管理員」的控件：協定層就沒有那個格子。
      expect(find.text(l10n.registerSummary), findsOneWidget);
    });

    testWidgets('沒有位址時提交停用', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        storedUrl: '',
        reply: _Fixture.ok(noStub),
      );
      await pump(tester, fixture);
      await gotoRegister(tester);

      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(RegisterPage.submitKey),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('邀請碼模式形態', () {
    // 一則「要求帶碼」的入口能力回應：只有 invite_code_required 被點亮時表單才多一格。
    const StubResponse capsInviteRequired = (
      status: 200,
      body:
          '{"sign_up_open":true,"invite_code_required":true,'
          '"guest_open":false,"request_id":"r-caps"}',
      headers: <String, String>{},
    );
    const StubResponse registerOk = (
      status: 201,
      body: registerSuccessBody,
      headers: <String, String>{},
    );
    const String invitePlaintext = 'AbCdEfGhIjKlMnOpQrStUv';

    testWidgets('要求帶碼時才出現邀請碼欄；提交把它放進本體、成功後清空且不回顯', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthCapabilitiesPath: capsInviteRequired,
          kAuthRegisterPath: registerOk,
        }),
      );
      await pump(tester, fixture);
      await gotoRegister(tester);
      // post-frame 現讀入口答案回來後才決定要不要顯示這一格。
      await tester.pumpAndSettle();

      expect(find.byKey(RegisterPage.inviteCodeKey), findsOneWidget);

      await tester.enterText(
        find.byKey(RegisterPage.loginNameKey),
        'inv.it.ee',
      );
      await tester.enterText(find.byKey(RegisterPage.displayNameKey), '受邀者');
      await tester.enterText(
        find.byKey(RegisterPage.passwordKey),
        _fakePassword,
      );
      await tester.enterText(
        find.byKey(RegisterPage.inviteCodeKey),
        invitePlaintext,
      );
      await tester.tap(find.byKey(RegisterPage.submitKey));
      await tester.pumpAndSettle();

      final List<http.Request> posts = fixture.to(kAuthRegisterPath);
      expect(posts, hasLength(1));
      final Map<String, Object?> sent =
          jsonDecode(posts.single.body) as Map<String, Object?>;
      expect(sent['invite_code'], invitePlaintext);

      // 成功摘要出現；明文碼既不在任何提示文字、也不在被顯示的摘要裡。
      expect(find.byKey(RegisterPage.createdKey), findsOneWidget);
      final String notice = _allText(tester);
      expect(notice, isNot(contains(invitePlaintext)));
      // 成功後整張表單退出編輯態、換成摘要：邀請碼欄不再挂载，明文碼因此不會留在畫面上任何一處。
      expect(find.byKey(RegisterPage.inviteCodeKey), findsNothing);
    });

    testWidgets('入口能力沒點亮要求碼時不出現這一格，提交也不發 invite_code', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(
        reply: _Fixture.ok(<String, StubResponse>{
          kAuthCapabilitiesPath: const (
            status: 200,
            body:
                '{"sign_up_open":true,"invite_code_required":false,'
                '"guest_open":false,"request_id":"r-caps"}',
            headers: <String, String>{},
          ),
          kAuthRegisterPath: registerOk,
        }),
      );
      await pump(tester, fixture);
      await gotoRegister(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(RegisterPage.inviteCodeKey), findsNothing);

      await tester.enterText(
        find.byKey(RegisterPage.loginNameKey),
        'open.user',
      );
      await tester.enterText(find.byKey(RegisterPage.displayNameKey), '開放者');
      await tester.enterText(
        find.byKey(RegisterPage.passwordKey),
        _fakePassword,
      );
      await tester.tap(find.byKey(RegisterPage.submitKey));
      await tester.pumpAndSettle();

      expect(
        fixture.to(kAuthRegisterPath).single.body,
        isNot(contains('invite_code')),
      );
    });
  });

  group('提交攔截與請求形態', () {
    testWidgets('沒填齊時本地攔截，一個註冊請求都不發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(reply: _Fixture.ok(noStub));
      await pump(tester, fixture);
      await gotoRegister(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(noticeLine(tester), l10n.registerFormIncompleteNotice);
      expect(fixture.to(kAuthRegisterPath), isEmpty);
    });

    testWidgets('提交只送三個欄到 /auth/register，本體不含角色欄', (WidgetTester tester) async {
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
      await gotoRegister(tester);
      await fillForm(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      final List<http.Request> reqs = fixture.to(kAuthRegisterPath);
      expect(reqs.length, 1);
      expect(reqs.single.method, 'POST');
      final Map<String, Object?> sent =
          jsonDecode(reqs.single.body) as Map<String, Object?>;
      expect(sent.keys.toSet(), <String>{
        'login_name',
        'display_name',
        'password',
      });
      expect(sent['login_name'], 'Std.First.Sign.In');
      expect(fixture.to(kAuthLoginPath), isEmpty);
    });
  });

  group('成功：摘要取自伺服器且絕不簽發會話', () {
    testWidgets('摘要顯示可展示事實、清空三個欄、停在未登入', (WidgetTester tester) async {
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
      await gotoRegister(tester);
      await fillForm(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      // 表單收起、摘要出現。
      expect(find.byKey(RegisterPage.loginNameKey), findsNothing);
      expect(find.byKey(RegisterPage.createdKey), findsOneWidget);
      expect(
        find.text(l10n.registerCreatedTitle('Std.First.Sign.In')),
        findsOneWidget,
      );
      // 「現在就能登入」與「還沒有活動」講在第一線。
      expect(find.text(l10n.registerUsableNowNote), findsOneWidget);
      expect(find.text(l10n.registerNoActivityNotice), findsOneWidget);
      // 註冊不簽發會話：會話仍停在未登入，這一頁不複製第二套憑據分發。
      expect(fixture.session.status, isNot(SessionStatus.signedIn));
      // 摘要與任何提示都不含口令明文。
      expect(_anyTextContains(tester, _fakePassword), isFalse);
    });

    testWidgets('「前往登入」導向既有登入通路', (WidgetTester tester) async {
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
      await gotoRegister(tester);
      await fillForm(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(RegisterPage.goSignInKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RegisterPage.goSignInKey));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('防重複提交', () {
    testWidgets('進行中連點只產生一趟請求', (WidgetTester tester) async {
      final Completer<http.Response> gate = Completer<http.Response>();
      final _Fixture fixture = _Fixture(
        reply: (http.Request request) async {
          if (request.url.path == kAuthRegisterPath) {
            return gate.future;
          }
          return _Fixture.ok(noStub)(request);
        },
      );
      await pump(tester, fixture);
      await gotoRegister(tester);
      await fillForm(tester);
      await tapSubmit(tester);

      expect(
        tester
            .widget<FilledButton>(find.byKey(RegisterPage.submitKey))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(RegisterPage.submitKey), warnIfMissed: false);
      await tester.tap(find.byKey(RegisterPage.submitKey), warnIfMissed: false);
      await tester.pump();

      gate.complete(
        http.Response(
          registerSuccessBody,
          201,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(fixture.to(kAuthRegisterPath).length, 1);
    });
  });

  group('失敗：各機器碼各成一句、不偽造成功', () {
    Future<String> noticeFor(WidgetTester tester, _Fixture fixture) async {
      await pump(tester, fixture);
      await gotoRegister(tester);
      await fillForm(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      return noticeLine(tester);
    }

    _Fixture failing(int status, String body) => _Fixture(
      reply: _Fixture.ok(<String, StubResponse>{
        kAuthRegisterPath: (
          status: status,
          body: body,
          headers: <String, String>{},
        ),
      }),
    );

    testWidgets('2019 重名專屬句，不同於故障與限流', (WidgetTester tester) async {
      final String line = await noticeFor(
        tester,
        failing(409, envelope(2019, 'r-409')),
      );
      expect(line, l10n.errorCodeSelfRegisterNameTaken);
      expect(line, isNot(l10n.errorCodeLoginThrottled));
      expect(line, isNot(contains('server text')));
    });

    testWidgets('2017 策略未開放專屬句', (WidgetTester tester) async {
      final String line = await noticeFor(
        tester,
        failing(403, envelope(2017, 'r-403')),
      );
      expect(line, l10n.errorCodeAccountCreationDisabled);
    });

    testWidgets('2016 模式未落地專屬句，與 2017 可判別', (WidgetTester tester) async {
      final String line = await noticeFor(
        tester,
        failing(400, envelope(2016, 'r-400')),
      );
      expect(line, l10n.errorCodeAccountPolicyModeUnavailable);
      expect(line, isNot(l10n.errorCodeAccountCreationDisabled));
    });

    testWidgets('2006 限流的稍後再試，不是「名字被佔用」', (WidgetTester tester) async {
      final String line = await noticeFor(
        tester,
        failing(429, envelope(2006, 'r-429')),
      );
      expect(line, l10n.errorCodeLoginThrottled);
    });

    testWidgets('1004 依點名欄位各成一句', (WidgetTester tester) async {
      final Map<String, String> want = <String, String>{
        'password': l10n.registerInvalidPasswordNotice,
        'login_name': l10n.registerInvalidLoginNameNotice,
        'display_name': l10n.registerInvalidDisplayNameNotice,
      };
      for (final MapEntry<String, String> entry in want.entries) {
        final String line = await noticeFor(
          tester,
          failing(
            400,
            envelope(1004, 'r-1004', <String, Object?>{
              'invalid_field': entry.key,
            }),
          ),
        );
        expect(line, entry.value, reason: '欄位 ${entry.key}');
      }
    });

    testWidgets('失敗後表單留住、無成功摘要、提示不含口令明文', (WidgetTester tester) async {
      final _Fixture fixture = failing(409, envelope(2019, 'r-409'));
      await pump(tester, fixture);
      await gotoRegister(tester);
      await fillForm(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(RegisterPage.loginNameKey), findsOneWidget);
      expect(find.byKey(RegisterPage.createdKey), findsNothing);
      expect(noticeLine(tester), isNot(contains(_fakePassword)));
      expect(fixture.session.status, isNot(SessionStatus.signedIn));
    });

    testWidgets('連不上：說無法與伺服器確認，不是「註冊成功」', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        reply: (http.Request request) async {
          if (request.url.path == kAuthRegisterPath) {
            throw http.ClientException('connection refused');
          }
          return _Fixture.ok(noStub)(request);
        },
      );
      final String line = await noticeFor(tester, fixture);
      expect(line, l10n.errorKindUnreachable);
      expect(find.byKey(RegisterPage.createdKey), findsNothing);
    });
  });
}

/// 遍歷當前樹上所有 Text，判斷是否有任一處含給定子串（口令不外洩的粗篩）。
///
/// 取用群樹上的 `Text` 走的是測試綁定，`tester` 只為呼叫端對稱而留。
bool _anyTextContains(WidgetTester tester, String needle) {
  for (final Element element in find.byType(Text).evaluate()) {
    final String? data = (element.widget as Text).data;
    if (data != null && data.contains(needle)) {
      return true;
    }
  }
  return false;
}
