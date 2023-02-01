/// 管理員端「建立普通帳戶」的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何真實憑據。測試問的是幾件事：
///   1. 沒填齊時一趟請求都不發（擋在本地，不是擋在按鈕看不見）；
///   2. 成功後只呈現伺服器回傳的事實，並把「尚未加入活動」講在第一線；
///   3. 2017（策略未開放）與 2012（登入名已佔用）各轉述成對應那一句，
///      不合併成「操作失敗」，也不謊報成成功；
///   4. 界面上任何一處都不出現那個一次性口令；
///   5. 提交進行中按鈕停用，不會發出第二趟。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/admin_console_page.dart';
import 'package:evernightrealm/features/admin/standard_account_provision_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');
const String _oneTimePassword = 'only-used-once-口令';
const String _createdAccountBody =
    '{"account_id":"01a0e000-0000-7000-8000-0000000000ee",'
    '"login_name":"New.Player","display_name":"新玩家",'
    '"status":"active","must_change_password":true,'
    '"created_at":"2026-10-03T09:00:00.000Z","request_id":"r-std-create"}';

/// 一頁假傳輸：按狀態碼與本體回應，並記錄發出的請求。
class _Fixture {
  _Fixture({this.status = 201, this.body = _createdAccountBody});

  final int status;
  final String body;

  /// 發出過的請求（斷言「只發一趟」「本體三欄」的證據）。
  final List<http.Request> requests = <http.Request>[];

  bool _holdNext = false;

  /// 讓下一趟回應延後四十毫秒（夠泵一次 frame 斷言按鈕停用）。
  void holdNext() => _holdNext = true;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        requests.add(request);
        if (_holdNext) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        return http.Response(
          body,
          status,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );
  }
}

void main() {
  late ServerAddressSettings settings;

  setUp(() async {
    settings = await buildAddressSettings(
      storedUrl: reachableUrl,
      reachable: <String>[reachableUrl],
    );
  });

  /// 把頁面掛上必要的作用域後泵入（宿主與 AppShell 內容區同形，DEC-020）。
  Future<void> pump(WidgetTester tester, _Fixture fixture) async {
    final ServerApi api = fixture.api(settings);
    await tester.pumpWidget(
      AppScope(
        dependencies: AppDependencies(api: api),
        child: MaterialApp(
          locale: _locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SingleChildScrollView(child: const AdminConsolePage()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    String? login,
    String? display,
    String? password,
  }) async {
    if (login != null) {
      await tester.enterText(
        find.byKey(StandardAccountProvisionCard.loginNameKey),
        login,
      );
    }
    if (display != null) {
      await tester.enterText(
        find.byKey(StandardAccountProvisionCard.displayNameKey),
        display,
      );
    }
    if (password != null) {
      await tester.enterText(
        find.byKey(StandardAccountProvisionCard.passwordKey),
        password,
      );
    }
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(StandardAccountProvisionCard.submitKey));
    await tester.pumpAndSettle();
  }

  /// 取當前上下文的地介面字串：斷言比對的是 ARB 值本身，不是測試另抄的一份。
  String textOf(WidgetTester tester, String Function(AppLocalizations) pick) =>
      pick(AppLocalizations.of(tester.element(find.byType(AdminConsolePage))));

  testWidgets('管理員端已接線：卡、策略說明與如實收尾都在場', (tester) async {
    await pump(tester, _Fixture());
    expect(
      find.text(textOf(tester, (l) => l.stdAccountProvisionTitle)),
      findsOneWidget,
    );
    expect(
      find.text(textOf(tester, (l) => l.stdAccountProvisionPolicyNotice)),
      findsOneWidget,
    );
    expect(find.byKey(StandardAccountProvisionCard.submitKey), findsOneWidget);
    expect(
      find.text(textOf(tester, (l) => l.adminConsoleRemainingNotice)),
      findsOneWidget,
    );
  });

  testWidgets('沒填齊時一趟請求都不發', (tester) async {
    final fixture = _Fixture();
    await pump(tester, fixture);
    await fill(tester, login: 'only.login');
    await submit(tester);
    expect(fixture.requests, isEmpty);
    expect(
      find.text(textOf(tester, (l) => l.adminProvisionFormIncompleteNotice)),
      findsOneWidget,
    );
  });

  testWidgets('成功只講伺服器的事實，並明說尚未加入活動', (tester) async {
    final fixture = _Fixture();
    await pump(tester, fixture);
    await fill(
      tester,
      login: 'New.Player',
      display: '新玩家',
      password: _oneTimePassword,
    );
    await submit(tester);

    final http.Request sent = fixture.requests.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, kAdminAccountsPath);
    expect(
      (jsonDecode(sent.body) as Map<String, Object?>).keys.toSet(),
      <String>{'login_name', 'display_name', 'password'},
    );

    // 「帳號 New.Player 已建立。」點名的是伺服器回傳的登入名原值。
    expect(
      find.text(
        textOf(tester, (l) => l.stdAccountProvisionCreatedTitle('New.Player')),
      ),
      findsOneWidget,
    );
    // 「已建立」不等於「已加入活動」：空狀態那句必須同時在場。
    expect(
      find.byKey(StandardAccountProvisionCard.noActivityKey),
      findsOneWidget,
    );
    // 口令不出現在界面任何一處；輸入欄成功後已清空。
    expect(find.text(_oneTimePassword), findsNothing);
    final TextField passwordField = tester.widget(
      find.byKey(StandardAccountProvisionCard.passwordKey),
    );
    expect(passwordField.controller!.text, isEmpty);
  });

  testWidgets('2017 策略未開放轉述成自己的那一句，不謊報成功', (tester) async {
    final fixture = _Fixture(
      status: 403,
      body: '{"code":2017,"message":"x","request_id":"r-err"}',
    );
    await pump(tester, fixture);
    await fill(
      tester,
      login: 'gated.player',
      display: '會被擋',
      password: _oneTimePassword,
    );
    await submit(tester);

    expect(
      find.text(textOf(tester, (l) => l.errorCodeAccountCreationDisabled)),
      findsOneWidget,
    );
    expect(find.byKey(StandardAccountProvisionCard.createdKey), findsNothing);
    // 失敗不清空輸入：人要能照著同一份意圖改一個欄位再交一次。
    final TextField loginField = tester.widget(
      find.byKey(StandardAccountProvisionCard.loginNameKey),
    );
    expect(loginField.controller!.text, 'gated.player');
  });

  testWidgets('2012 登入名已佔用是另一句話，不與策略未開放互混', (tester) async {
    final fixture = _Fixture(
      status: 409,
      body: '{"code":2012,"message":"x","request_id":"r-err"}',
    );
    await pump(tester, fixture);
    await fill(
      tester,
      login: 'dup.player',
      display: '重複',
      password: _oneTimePassword,
    );
    await submit(tester);

    expect(
      find.text(textOf(tester, (l) => l.errorCodeLoginNameTaken)),
      findsOneWidget,
    );
    expect(
      find.text(textOf(tester, (l) => l.errorCodeAccountCreationDisabled)),
      findsNothing,
    );
  });

  testWidgets('提交進行中按鈕停用，不會發出第二趟', (tester) async {
    final fixture = _Fixture()..holdNext();
    await pump(tester, fixture);
    await fill(
      tester,
      login: 'slow.player',
      display: '慢回應',
      password: _oneTimePassword,
    );
    await tester.tap(find.byKey(StandardAccountProvisionCard.submitKey));
    await tester.pump(); // 進入 submitting，回應還掛著。
    final FilledButton button = tester.widget(
      find.byKey(StandardAccountProvisionCard.submitKey),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(StandardAccountProvisionCard.submitKey));
    await tester.pumpAndSettle();
    expect(fixture.requests.length, 1);
  });
}
