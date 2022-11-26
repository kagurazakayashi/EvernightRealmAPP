/// Root 控制台「開設／目錄／詳情／編輯」的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何真實憑據。測試問的是幾件事：
///   1. 沒填齊時一趟請求都不發（擋在本地，不是擋在按鈕看不見）；
///   2. 每一次失敗都轉述成對應的那一句（2012 不是「格式錯誤」、1004 要點出欄位、
///      2011 不被人誤讀成「你被登出了」、2013 說成「現值已過期」）；
///   3. 成功後只呈現伺服器回傳的事實，並重讀一次目錄；
///   4. 界面上任何一處都不出現那個一次性口令；
///   5. 分頁與篩選的每一次變動作廢舊結果並只發一趟新請求；
///   6. 詳情與編輯的當前資料只能來自服務端回應——沒有樂觀 UI 的窗口。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/root_console/admin_directory_view.dart';
import 'package:evernightrealm/features/root_console/admin_profile_view.dart';
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
const String _acct1 = '01a0e000-0000-7000-8000-0000000000aa';
const String _acct2 = '01a0e000-0000-7000-8000-0000000000bb';

/// 目錄一頁的回應（第二項從未登入；行不帶 roles）。
String _directoryBody({
  int page = 1,
  int total = 2,
  int rows = 2,
  String status = 'all',
}) {
  final List<String> items = <String>[
    '{"account_id":"$_acct1","login_name":"Ops.Primary","display_name":"首任管理員",'
        '"status":"active","must_change_password":true,'
        '"created_at":"2026-10-02T09:00:00.000Z",'
        '"granted_at":"2026-10-02T09:00:00.000Z",'
        '"last_login_at":"2026-10-02T09:30:00.000Z"}',
    if (rows > 1)
      '{"account_id":"$_acct2","login_name":"Ops.Second","display_name":"次任管理員",'
          '"status":"active","must_change_password":false,'
          '"created_at":"2026-10-02T09:10:00.000Z",'
          '"granted_at":"2026-10-02T09:10:00.000Z"}',
  ];
  return '{"admins":[${items.take(rows).join(',')}],'
      '"page":$page,"page_size":20,"total":$total,"request_id":"r-list"}';
}

/// 單筆詳情／編輯結果的回應本體。
String _profileBody({String display = '首任管理員', String? login}) {
  return '{"admin":{"account_id":"$_acct1",'
      '"login_name":"${login ?? 'Ops.Primary'}","display_name":"$display",'
      '"status":"active","must_change_password":true,'
      '"created_at":"2026-10-02T09:00:00.000Z",'
      '"granted_at":"2026-10-02T09:00:00.000Z",'
      '"roles":["server_admin"]},"request_id":"r-profile"}';
}

/// 開設成功的回應本體。
const String _createdBody =
    '{"account_id":"acct-3","login_name":"Ops.Third","display_name":"第三任",'
    '"status":"active","must_change_password":true,"roles":["server_admin"],'
    '"created_at":"2026-10-02T09:20:00.000Z","request_id":"r-create"}';

/// 一台隨測試擺佈的假伺服器，順帶記錄每一條通路發出去了几趟請求。
class _Fixture {
  _Fixture({
    this.createStatus = 201,
    this.createBody = _createdBody,
    this.listStatus = 200,
    this.rows = 2,
    this.total = 2,
    this.detailStatus = 200,
    this.detailBody,
    this.updateStatus = 200,
    this.updateBody,
  });

  final int createStatus;
  final String createBody;
  final int listStatus;
  final int rows;
  final int total;
  final int detailStatus;
  final String? detailBody;
  final int updateStatus;
  final String? updateBody;

  /// GET /root/admins 被問了幾趟。
  int listCalls = 0;

  /// 最近一次目錄 GET 的查詢參數（篩選與分頁斷言用）。
  Map<String, String> lastListQuery = <String, String>{};

  /// GET 單筆被問了幾趟。
  int detailCalls = 0;

  /// 發出的 POST 請求本體（最多一趟；超过一条就该由断言报出来）。
  final List<http.Request> creates = <http.Request>[];

  /// 發出的 PUT 請求。
  final List<http.Request> updates = <http.Request>[];

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        if (path == kRootAdminsPath) {
          if (request.method == 'POST') {
            creates.add(request);
            return _json(createBody, createStatus);
          }
          listCalls++;
          lastListQuery = request.url.queryParameters;
          if (listCalls == 1 && listStatus != 200) {
            return _json(
              '{"code":$listStatus,"message":"x","request_id":"r-list"}',
              listStatus,
            );
          }
          return _json(
            _directoryBody(
              page: int.parse(request.url.queryParameters['page'] ?? '1'),
              total: total,
              rows: rows,
              status: request.url.queryParameters['status'] ?? 'all',
            ),
            200,
          );
        }
        if (path.startsWith('$kRootAdminsPath/')) {
          if (request.method == 'PUT') {
            updates.add(request);
            return _json(
              updateBody ?? _profileBody(display: '新顯示名'),
              updateStatus,
            );
          }
          detailCalls++;
          // 失敗回應的「信封碼」與「HTTP 態」是兩件事：404 這一態對應的合同碼是 1001，
          // 界面分流必須讀前者，測試也不能把兩者混寫成一個數。
          return _json(
            detailStatus == 200
                ? (detailBody ?? _profileBody())
                : '{"code":1001,"message":"x","request_id":"r-detail"}',
            detailStatus,
          );
        }
        return jsonOk('{}');
      }),
    );
  }

  static http.Response _json(String body, int status) => http.Response(
    body,
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
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

  /// 先把目標滾進視口再點：宿主是單向滾動殼（DEC-020），目錄與詳情卡都在折疊線以下，
  /// 直接 tap 會落在視口外而靜默miss（這正是前一版測試的失敗形態）。
  Future<void> tapVisible(WidgetTester tester, Key key) async {
    final Finder finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 打開第一行的詳情並等單筆讀回。
  Future<void> openProfile(WidgetTester tester, _Fixture fixture) async {
    await tapVisible(tester, AdminDirectoryCard.actionKey(_acct1));
    expect(fixture.detailCalls, 1);
  }

  group('管理員目錄', () {
    testWidgets('讀到的每一行只轉述伺服器給的事實', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      expect(find.byKey(AdminDirectoryCard.rowKey(_acct1)), findsOneWidget);
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
      expect(fixture.lastListQuery['page'], '1');
      expect(fixture.lastListQuery['status'], 'all');
    });

    testWidgets('一位都還沒有時如實說明 Root 不是這裡的一行', (WidgetTester tester) async {
      await pump(tester, _Fixture(rows: 0, total: 0));
      expect(find.byKey(AdminDirectoryCard.emptyKey), findsOneWidget);
      expect(find.text(l10n.adminDirectoryEmptyNotice), findsOneWidget);
    });

    testWidgets('讀不到時說「查不了」並留一條重試，重試只多問一趟', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(listStatus: 500);
      await pump(tester, fixture);
      expect(find.byKey(AdminDirectoryCard.failedKey), findsOneWidget);
      expect(find.text(l10n.adminDirectoryUnavailableNotice), findsOneWidget);

      await tapVisible(tester, AdminDirectoryCard.retryKey);
      expect(fixture.listCalls, 2);
      expect(find.byKey(AdminDirectoryCard.rowKey(_acct1)), findsOneWidget);
    });

    testWidgets('切篩選回到第一頁並帶上新狀態重問', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      await tapVisible(tester, AdminDirectoryCard.filterDisabledKey);

      expect(fixture.listCalls, 2);
      expect(fixture.lastListQuery['status'], 'disabled');
      expect(fixture.lastListQuery['page'], '1');
    });

    testWidgets('下一页把伺服器回顯的邊界變成按鈕的可點性', (WidgetTester tester) async {
      // total=21、每頁 20：第 1 頁有後頁、第 2 頁沒有。
      final _Fixture fixture = _Fixture(total: 21);
      await pump(tester, fixture);

      expect(
        find.text(l10n.adminDirectoryPageSummary(1, 2, 21)),
        findsOneWidget,
      );

      await tapVisible(tester, AdminDirectoryCard.nextKey);
      expect(fixture.listCalls, 2);
      expect(fixture.lastListQuery['page'], '2');
      expect(
        find.text(l10n.adminDirectoryPageSummary(2, 2, 21)),
        findsOneWidget,
      );

      // 到界時下一頁按鈕停用，而不是發一趟注定為空的請求。
      final OutlinedButton next = tester.widget<OutlinedButton>(
        find.byKey(AdminDirectoryCard.nextKey),
      );
      expect(next.onPressed, isNull);
      expect(fixture.listCalls, 2);
    });
  });

  group('詳情與編輯', () {
    testWidgets('底稿按標識重讀單筆真相，不是拿目錄行代填', (WidgetTester tester) async {
      // 目錄行與詳情回應刻意給不同的顯示名：界面填的必須是後者。
      final _Fixture fixture = _Fixture(
        detailBody: _profileBody(display: '服務端的單筆真相'),
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      expect(find.text(l10n.adminProfileTitle('Ops.Primary')), findsOneWidget);
      final TextField field = tester.widget<TextField>(
        find.byKey(AdminProfileCard.displayNameKey),
      );
      expect(field.controller!.text, '服務端的單筆真相');
      // 詳情帶出服務端核實的角色與授予事實（目錄行裡沒有的那份）。
      expect(
        find.text(
          l10n.labelValuePair(l10n.adminProfileRolesLabel, 'server_admin'),
        ),
        findsOneWidget,
      );
      // 如實標註登入名不在編輯白名單內。
      expect(find.text(l10n.adminProfileLoginNameLockedHint), findsOneWidget);
    });

    testWidgets('保存成功：句子與欄位都換成回應裡的資料庫現值', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      await tester.ensureVisible(find.byKey(AdminProfileCard.displayNameKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(AdminProfileCard.displayNameKey),
        '我打算改的名字',
      );
      await tapVisible(tester, AdminProfileCard.submitKey);

      expect(fixture.updates, hasLength(1));
      final Map<String, Object?> body =
          jsonDecode(fixture.updates.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'display_name',
        'expected_display_name',
      });
      // CAS 依據值是「讀到的現值」，不是輸入框裡打算改的那份。
      expect(body['expected_display_name'], '首任管理員');
      expect(body['display_name'], '我打算改的名字');

      // 界面換成 PUT 回應（合同為保存後的現值「新顯示名」）：不是本地草稿的迴音。
      expect(find.text(l10n.adminProfileSavedNotice('新顯示名')), findsOneWidget);
      final TextField field = tester.widget<TextField>(
        find.byKey(AdminProfileCard.displayNameKey),
      );
      expect(field.controller!.text, '新顯示名');
      // 保存成功要讓目錄那頁重讀（行與詳情不各留一份舊真相）。
      expect(fixture.listCalls, 2);
    });

    testWidgets('2013：一句「現值已過期」＋重讀出口，且不動當前資料', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        updateStatus: 409,
        updateBody: '{"code":2013,"message":"stale","request_id":"r-conflict"}',
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      await tester.ensureVisible(find.byKey(AdminProfileCard.displayNameKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(AdminProfileCard.displayNameKey),
        '對著舊畫面的提交',
      );
      await tapVisible(tester, AdminProfileCard.submitKey);

      expect(find.text(l10n.adminProfileConflictNotice), findsOneWidget);
      expect(find.byKey(AdminProfileCard.savedKey), findsNothing);
      // 沒有樂觀成功：成功的句子不在，重讀出口在。
      expect(find.byKey(AdminProfileCard.reloadKey), findsOneWidget);

      await tapVisible(tester, AdminProfileCard.reloadKey);
      expect(fixture.detailCalls, 2);
    });

    testWidgets('1004 按 invalid_field 點出顯示名', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        updateStatus: 400,
        updateBody: '{"code":1004,"message":"bad","details":{"invalid_field":"display_name"},"request_id":"r-bad"}',
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await tester.ensureVisible(find.byKey(AdminProfileCard.displayNameKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(AdminProfileCard.displayNameKey),
        '不合規的名字',
      );
      await tapVisible(tester, AdminProfileCard.submitKey);
      expect(
        find.text(l10n.adminProfileInvalidDisplayNameNotice),
        findsOneWidget,
      );
      expect(find.byKey(AdminProfileCard.savedKey), findsNothing);
    });

    testWidgets('2011 講成權限不足而不是被登出', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        updateStatus: 403,
        updateBody: '{"code":2011,"message":"nope","request_id":"r-forbid"}',
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await tester.ensureVisible(find.byKey(AdminProfileCard.displayNameKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(AdminProfileCard.displayNameKey),
        '越權改名',
      );
      await tapVisible(tester, AdminProfileCard.submitKey);
      expect(find.text(l10n.adminProfileDeniedNotice), findsOneWidget);
      expect(find.text(l10n.errorCodeSessionInvalid), findsNothing);
    });

    testWidgets('詳情讀不回來時表單不打開，界面不憑印象湊', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(detailStatus: 404);
      await pump(tester, fixture);
      await tapVisible(tester, AdminDirectoryCard.actionKey(_acct1));

      expect(find.text(l10n.adminProfileNotFoundNotice), findsOneWidget);
      expect(find.byKey(AdminProfileCard.displayNameKey), findsNothing);
      expect(find.byKey(AdminProfileCard.submitKey), findsNothing);
      // 失敗態留有出口：可重讀、可關閉。
      expect(find.byKey(AdminProfileCard.reloadKey), findsOneWidget);
      expect(find.byKey(AdminProfileCard.closeKey), findsOneWidget);
    });

    testWidgets('沒填新顯示名時一請求都不發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await tester.ensureVisible(find.byKey(AdminProfileCard.displayNameKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(AdminProfileCard.displayNameKey),
        '   ',
      );
      await tapVisible(tester, AdminProfileCard.submitKey);

      expect(fixture.updates, isEmpty);
      expect(find.text(l10n.adminProfileFormIncompleteNotice), findsOneWidget);
    });

    testWidgets('關閉詳情後目錄仍在', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await tapVisible(tester, AdminProfileCard.closeKey);

      expect(find.byType(AdminProfileCard), findsNothing);
      expect(find.byKey(AdminDirectoryCard.rowKey(_acct1)), findsOneWidget);
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

    testWidgets('成功後顯示摘要、清空三個欄位並重讀目錄', (WidgetTester tester) async {
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
      // 衝突那次不該重讀目錄（沒有東西落地）。
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
