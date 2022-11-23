/// Root 控制台「開設管理員」的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何真實憑據。測試問的是四件事：
///   1. 沒填齊時一趟請求都不發（擋在本地，不是擋在按鈕看不見）；
///   2. 每一次失敗都轉述成對應的那一句（2012 不是「格式錯誤」、
///      1004 要點出是哪個欄位、2011 不被人誤讀成「你被登出了」）；
///   3. 成功後只呈現伺服器回傳的事實，並重讀一次確認清單；
///   4. 界面上任何一處都不出現那個一次性口令。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/root_console/admin_provision_view.dart';
import 'package:evernightrealm/features/root_console/root_console_page.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';
import '../../support/test_server.dart';

const Locale _locale = Locale('zh', 'TW');
const String _initialPassword = 'only-used-once-口令';

/// 一筆管理員的清單回應（第二項從未登入）。
String _listBody({int rows = 2}) {
  if (rows == 0) {
    return '{"admins":[],"request_id":"r-list"}';
  }
  final List<String> items = <String>[
    '{"account_id":"acct-1","login_name":"Ops.Primary","display_name":"首任管理員",'
        '"status":"active","must_change_password":true,'
        '"created_at":"2026-10-02T09:00:00.000Z",'
        '"last_login_at":"2026-10-02T09:30:00.000Z"}',
    if (rows > 1)
      '{"account_id":"acct-2","login_name":"Ops.Second","display_name":"次任管理員",'
          '"status":"active","must_change_password":false,'
          '"created_at":"2026-10-02T09:10:00.000Z"}',
  ];
  return '{"admins":[${items.join(',')}],"request_id":"r-list"}';
}

/// 開設成功的回應本體。
const String _createdBody =
    '{"account_id":"acct-3","login_name":"Ops.Third","display_name":"第三任",'
    '"status":"active","must_change_password":true,"roles":["server_admin"],'
    '"created_at":"2026-10-02T09:20:00.000Z","request_id":"r-create"}';

/// 一台隨測試擺佈的假伺服器，順帶記錄發出去了几趟請求。
class _Fixture {
  _Fixture({
    this.createStatus = 201,
    this.createBody = _createdBody,
    this.listStatus = 200,
    this.rows = 2,
  });

  final int createStatus;
  final String createBody;
  final int listStatus;
  final int rows;

  /// GET /root/admins 被問了幾趟。
  int listCalls = 0;

  /// 發出的 POST 請求本體（最多一趟；超过一条就该由断言报出来）。
  final List<http.Request> creates = <http.Request>[];

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        if (request.url.path != kRootAdminsPath) {
          return jsonOk('{}');
        }
        if (request.method == 'POST') {
          creates.add(request);
          return http.Response(
            createBody,
            createStatus,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        listCalls++;
        return http.Response(
          listCalls == 1 && listStatus != 200
              ? '{"code":$listStatus,"message":"x","request_id":"r-list"}'
              : _listBody(rows: rows),
          listCalls == 1 && listStatus != 200 ? listStatus : 200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );
  }
}

void main() {
  late AppLocalizations l10n;
  late ServerAddressSettings settings;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  setUp(() async {
    settings = await buildAddressSettings(
      storedUrl: reachableUrl,
      reachable: <String>[reachableUrl],
    );
  });

  /// 把頁面掛上必要的作用域後泵入（頁面只需 AppScope 提供的端點介面）。
  Future<void> pump(WidgetTester tester, _Fixture fixture) async {
    final ServerApi api = fixture.api(settings);
    await tester.pumpWidget(
      AppScope(
        dependencies: AppDependencies(api: api),
        child: MaterialApp(
          locale: _locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // 宿主必須與 AppShell 的內容區同形：Material 祖先＋SafeArea＋內文寬度上限＋
          // 唯一到滿的垂直滾動。頁面自己不准再放滾動容器（DEC-020），所以「裝得下多少」
          // 由這裡決定；先前只給裸 Scaffold 時整頁 Column 溢出 176px，測試把這件事喊了出來。
          home: Scaffold(
            body: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SingleChildScrollView(child: const RootConsolePage()),
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
        find.byKey(AdminProvisionCard.loginNameKey),
        login,
      );
    }
    if (display != null) {
      await tester.enterText(
        find.byKey(AdminProvisionCard.displayNameKey),
        display,
      );
    }
    if (password != null) {
      await tester.enterText(
        find.byKey(AdminProvisionCard.passwordKey),
        password,
      );
    }
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(AdminProvisionCard.submitKey));
    await tester.pumpAndSettle();
  }

  group('確認清單', () {
    testWidgets('讀到的每一行只轉述伺服器給的事實', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      expect(find.byKey(AdminListCard.rowKey('acct-1')), findsOneWidget);
      expect(find.text('Ops.Primary'), findsOneWidget);
      // 「尚未登入過」被 labelValuePair 包進整句，不是獨立一行文字；斷言要對著組出來的
      // 整句，否則它永遠找不到，而我們真正想釘的是「從未登入那筆不會被填上時刻」。
      expect(
        find.text(
          l10n.labelValuePair(
            l10n.adminListLastLoginLabel,
            l10n.adminListNeverLoggedInValue,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.adminListMustChangeBadge), findsOneWidget);
      expect(fixture.listCalls, 1);
    });

    testWidgets('一位都還沒有時如實說明只有 Root', (WidgetTester tester) async {
      await pump(tester, _Fixture(rows: 0));
      expect(find.byKey(AdminListCard.emptyKey), findsOneWidget);
      expect(find.text(l10n.adminListEmptyNotice), findsOneWidget);
    });

    testWidgets('讀不到時說「查不了」並留一條重試，重試只多問一趟', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(listStatus: 500);
      await pump(tester, fixture);
      expect(find.byKey(AdminListCard.failedKey), findsOneWidget);
      expect(find.text(l10n.adminListUnavailableNotice), findsOneWidget);

      await tester.tap(find.byKey(AdminListCard.retryKey));
      await tester.pumpAndSettle();
      expect(fixture.listCalls, 2);
      expect(find.byKey(AdminListCard.rowKey('acct-1')), findsOneWidget);
    });
  });

  group('開設表单', () {
    testWidgets('沒填齊時一請求都不發，只给本地那一句', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      await fill(tester, login: 'Ops.New', display: '新任');
      await submit(tester);

      expect(fixture.creates, isEmpty);
      expect(
        find.text(l10n.adminProvisionFormIncompleteNotice),
        findsOneWidget,
      );
      expect(find.byKey(AdminProvisionCard.createdKey), findsNothing);
    });

    testWidgets('成功後顯示摘要、清空三個欄位並重讀清單', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      await fill(
        tester,
        login: 'Ops.Third',
        display: '第三任',
        password: _initialPassword,
      );
      await submit(tester);

      expect(fixture.creates, hasLength(1));
      final Map<String, Object?> sent =
          jsonDecode(fixture.creates.single.body) as Map<String, Object?>;
      expect(sent.keys.toSet(), <String>{
        'login_name',
        'display_name',
        'password',
      });
      expect(sent['login_name'], 'Ops.Third');

      expect(find.byKey(AdminProvisionCard.createdKey), findsOneWidget);
      expect(
        find.text(l10n.adminProvisionCreatedTitle('Ops.Third')),
        findsOneWidget,
      );
      // 欄位清空：留著登入名只會讓下一次點按變成同一個名字的重復提交。
      expect(
        tester
            .widget<TextField>(find.byKey(AdminProvisionCard.loginNameKey))
            .controller!
            .text,
        isEmpty,
      );
      expect(fixture.listCalls, 2);
    });

    testWidgets('界面上任何一处都不出現那個一次性口令', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await fill(
        tester,
        login: 'Ops.Third',
        display: '第三任',
        password: _initialPassword,
      );
      await submit(tester);

      // 遮罩輸入框＋不顯示摘要：文字樹裡找不到它，請求本體裡才有（合同要求交給伺服器）。
      expect(find.text(_initialPassword), findsNothing);
      final Iterable<Text> visible = tester.widgetList<Text>(find.byType(Text));
      expect(
        visible.any((Text t) => (t.data ?? '').contains(_initialPassword)),
        isFalse,
      );
      expect(fixture.creates.single.body, contains(_initialPassword));
    });

    testWidgets('2012 只說已被佔用，不顯示摘要也不清欄位', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        createStatus: 409,
        createBody: '{"code":2012,"message":"taken","request_id":"r-dup"}',
      );
      await pump(tester, fixture);
      await fill(
        tester,
        login: 'Ops.Primary',
        display: '重複',
        password: _initialPassword,
      );
      await submit(tester);

      expect(find.text(l10n.errorCodeLoginNameTaken), findsOneWidget);
      expect(find.byKey(AdminProvisionCard.createdKey), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(AdminProvisionCard.loginNameKey))
            .controller!
            .text,
        'Ops.Primary',
      );
      // 衝突那次不該重讀清單（沒有東西落地）。
      expect(fixture.listCalls, 1);
    });

    testWidgets('1004 按 invalid_field 點出是哪個欄位', (WidgetTester tester) async {
      for (final MapEntry<String, String> tc in <MapEntry<String, String>>[
        MapEntry<String, String>(
          'login_name',
          l10n.adminProvisionInvalidLoginNameNotice,
        ),
        MapEntry<String, String>(
          'display_name',
          l10n.adminProvisionInvalidDisplayNameNotice,
        ),
        MapEntry<String, String>(
          'password',
          l10n.adminProvisionInvalidPasswordNotice,
        ),
      ]) {
        final _Fixture fixture = _Fixture(
          createStatus: 400,
          createBody:
              '{"code":1004,"message":"bad","details":{"invalid_field":"${tc.key}"},"request_id":"r-bad"}',
        );
        await pump(tester, fixture);
        await fill(
          tester,
          login: 'bad name',
          display: '不合規',
          password: _initialPassword,
        );
        await submit(tester);
        expect(find.text(tc.value), findsOneWidget, reason: tc.key);
        expect(find.byKey(AdminProvisionCard.createdKey), findsNothing);
      }
    });

    testWidgets('2011 講成權限不足，不被人誤讀成「你被登出了」', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        createStatus: 403,
        createBody: '{"code":2011,"message":"nope","request_id":"r-forbid"}',
      );
      await pump(tester, fixture);
      await fill(
        tester,
        login: 'Ops.X',
        display: '越權',
        password: _initialPassword,
      );
      await submit(tester);

      expect(find.text(l10n.errorCodePermissionDenied), findsOneWidget);
      expect(find.text(l10n.errorCodeSessionInvalid), findsNothing);
    });
  });

  testWidgets('頁面如實說明其餘 Root 域能力尚未接線', (WidgetTester tester) async {
    await pump(tester, _Fixture());
    expect(
      find.byKey(const ValueKey<String>('root-console-remaining-notice')),
      findsOneWidget,
    );
    expect(find.text(l10n.rootConsoleRemainingNotice), findsOneWidget);
  });
}
