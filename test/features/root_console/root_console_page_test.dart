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
import 'package:evernightrealm/features/root_console/account_policy_view.dart';
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

/// 重置交付用的測試口令：只活在測試進程，斷言對象是「它不出現在界面任何一處」。
const String _resetTempPassword = 'reset-temporary-口令';
const String _acct1 = '01a0e000-0000-7000-8000-0000000000aa';
const String _acct2 = '01a0e000-0000-7000-8000-0000000000bb';

/// 目錄一頁的回應（第二項從未登入；行不帶 roles）。
///
/// 用 jsonEncode 而不是手拼字串：可選欄位（last_login_at／deleted_at）的有無
/// 由地圖本身表達，不會因為多一個逗號就產出後端永遠不會給的畸形本體。
String _directoryBody({
  int page = 1,
  int total = 2,
  int rows = 2,
  String status = 'all',
  String secondStatus = 'active',
}) {
  final bool secondDeleted = secondStatus == 'deleted';
  final List<Map<String, Object?>> items = <Map<String, Object?>>[
    <String, Object?>{
      'account_id': _acct1,
      'login_name': 'Ops.Primary',
      'display_name': '首任管理員',
      'status': 'active',
      'must_change_password': true,
      'created_at': '2026-10-02T09:00:00.000Z',
      'granted_at': '2026-10-02T09:00:00.000Z',
      'last_login_at': '2026-10-02T09:30:00.000Z',
    },
    <String, Object?>{
      'account_id': _acct2,
      'login_name': 'Ops.Second',
      // 刪除態下服務端回的是佔位名，不是原本那個：界面要顯示的是回應。
      'display_name': secondDeleted ? 'DEL_20261002_次任管理員' : '次任管理員',
      'status': secondStatus,
      'must_change_password': false,
      'created_at': '2026-10-02T09:10:00.000Z',
      'granted_at': '2026-10-02T09:10:00.000Z',
      if (secondDeleted) 'deleted_at': '2026-10-02T11:00:00.000Z',
    },
  ];
  return jsonEncode(<String, Object?>{
    'admins': items.take(rows).toList(),
    'page': page,
    'page_size': 20,
    'total': total,
    'request_id': 'r-list',
  });
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

/// 詳情回應的可變狀態形態：停用／刪除／表外值都要有真的行可讀。
String _detailBody({
  String status = 'active',
  String? disabledAt,
  String? deletedAt,
  String display = '首任管理員',
}) {
  return '{"admin":{"account_id":"$_acct1",'
      '"login_name":"Ops.Primary","display_name":"$display",'
      '"status":"$status","must_change_password":true,'
      '"created_at":"2026-10-02T09:00:00.000Z",'
      '"granted_at":"2026-10-02T09:00:00.000Z",'
      '${disabledAt == null ? '' : '"disabled_at":"$disabledAt",'}'
      '${deletedAt == null ? '' : '"deleted_at":"$deletedAt",'}'
      '"roles":["server_admin"]},"request_id":"r-profile"}';
}

/// 狀態變更成功的回應本體：admin 與詳情同形，外加撤銷數量。
String _statusBody({required String status, int revoked = 0}) {
  final bool disabled = status == 'disabled';
  final Map<String, Object?> admin = <String, Object?>{
    'account_id': _acct1,
    'login_name': 'Ops.Primary',
    'display_name': '首任管理員',
    'status': status,
    'must_change_password': true,
    'created_at': '2026-10-02T09:00:00.000Z',
    'granted_at': '2026-10-02T09:00:00.000Z',
    'roles': <String>['server_admin'],
    if (disabled) 'disabled_at': '2026-10-02T10:00:00.000Z',
  };
  return jsonEncode(<String, Object?>{
    'admin': admin,
    'revoked_sessions': revoked,
    'request_id': 'r-status',
  });
}

/// 憑據重置成功的回應本體：admin 與詳情同形，外加撤銷數量；不含任何口令材料。
String _passwordResetBody({int revoked = 0, required String status}) {
  final Map<String, Object?> admin = <String, Object?>{
    'account_id': _acct1,
    'login_name': 'Ops.Primary',
    'display_name': '首任管理員',
    'status': status,
    'must_change_password': true,
    'created_at': '2026-10-02T09:00:00.000Z',
    'granted_at': '2026-10-02T09:00:00.000Z',
    'roles': <String>['server_admin'],
    if (status == 'disabled') 'disabled_at': '2026-10-02T10:00:00.000Z',
  };
  return jsonEncode(<String, Object?>{
    'admin': admin,
    'revoked_sessions': revoked,
    'request_id': 'r-reset',
  });
}

/// 刪除成功的回應本體：admin 已是刪除態現值（佔位顯示名＋刪除時刻），外加撤銷數量。
String _deleteBody({int revoked = 0, String display = 'DEL_20261002_首任管理員'}) {
  final Map<String, Object?> admin = <String, Object?>{
    'account_id': _acct1,
    'login_name': 'Ops.Primary',
    'display_name': display,
    'status': 'deleted',
    'must_change_password': true,
    'created_at': '2026-10-02T09:00:00.000Z',
    'granted_at': '2026-10-02T09:00:00.000Z',
    'deleted_at': '2026-10-02T11:00:00.000Z',
    'roles': <String>['server_admin'],
  };
  return jsonEncode(<String, Object?>{
    'admin': admin,
    'revoked_sessions': revoked,
    'request_id': 'r-delete',
  });
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
    this.statusUpdateStatus = 200,
    this.statusUpdateErrorCode,
    this.statusUpdateBody,
    this.passwordResetStatus = 200,
    this.passwordResetErrorCode,
    this.passwordResetBody,
    this.deleteStatus = 200,
    this.deleteErrorCode,
    this.secondStatus = 'active',
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
  final int statusUpdateStatus;

  /// 狀態變更失敗時信封裡的業務碼（409 這一態對應的合同碼是 2014）；
  /// 不與 HTTP 態混寫成一個數——界面分流讀的是前者。
  final int? statusUpdateErrorCode;
  final String? statusUpdateBody;

  final int passwordResetStatus;

  /// 憑據重置失敗時信封裡的業務碼（本步只有 1004／1001／2011 這一類，無衝突碼）。
  final int? passwordResetErrorCode;
  final String? passwordResetBody;

  final int deleteStatus;

  /// 刪除失敗時信封裡的業務碼（2015 才是「已被刪除」那句，404 是「不在目錄」）。
  final int? deleteErrorCode;

  /// 目錄第二行的狀態原字串（用於「已刪除」這一行怎麼呈現）。
  final String secondStatus;

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

  /// 發出的 PUT /status 請求（狀態子資源與資料編輯各位一條通路）。
  final List<http.Request> statusUpdates = <http.Request>[];

  /// 發出的 PUT /password 請求（憑據子資源是第三條通路）。
  final List<http.Request> passwordResets = <http.Request>[];

  /// 發出的 DELETE 請求（刪除是第四條、也是唯一不可逆的通路）。
  final List<http.Request> deletes = <http.Request>[];

  /// GET /root/account-policy 被問了幾趟（策略卡接線與「只讀一趟」的斷言用）。
  int policyReads = 0;

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
              secondStatus: secondStatus,
            ),
            200,
          );
        }
        if (path.startsWith('$kRootAdminsPath/')) {
          if (request.method == 'PUT' && path.endsWith('/status')) {
            statusUpdates.add(request);
            if (statusUpdateStatus != 200) {
              return _json(
                '{"code":${statusUpdateErrorCode ?? statusUpdateStatus},'
                '"message":"x","request_id":"r-status"}',
                statusUpdateStatus,
              );
            }
            return _json(
              statusUpdateBody ?? _statusBody(status: 'disabled', revoked: 2),
              200,
            );
          }
          if (request.method == 'PUT' && path.endsWith('/password')) {
            passwordResets.add(request);
            if (passwordResetStatus != 200) {
              return _json(
                passwordResetBody ??
                    '{"code":${passwordResetErrorCode ?? passwordResetStatus},'
                        '"message":"x","request_id":"r-reset"}',
                passwordResetStatus,
              );
            }
            return _json(
              passwordResetBody ??
                  _passwordResetBody(revoked: 2, status: 'active'),
              200,
            );
          }
          if (request.method == 'DELETE') {
            // 刪除打在單筆路徑上，沒有自己的子路徑：目標在地址裡，本體什麼都不帶。
            deletes.add(request);
            if (deleteStatus != 200) {
              return _json(
                '{"code":${deleteErrorCode ?? deleteStatus},'
                '"message":"x","request_id":"r-delete"}',
                deleteStatus,
              );
            }
            return _json(_deleteBody(revoked: 2), 200);
          }
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
        if (path == kRootAccountPolicyPath) {
          // 策略卡自己按 contract 讀一次：頁面測試只確認它接上了線，
          // 卡內的分流由 account_policy_view_test.dart 逐條取證。
          policyReads++;
          return _json(
            '{"admin_create_standard":false,"self_register_mode":"closed",'
            '"guest_enabled":false,'
            '"entry":{"sign_up_open":false,"guest_open":false},'
            '"request_id":"r-policy"}',
            200,
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

    testWidgets('「已刪除」是第四個篩選取值：問服務端要 deleted，不自己排本地行', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      await tapVisible(tester, AdminDirectoryCard.filterDeletedKey);

      expect(fixture.listCalls, 2);
      expect(fixture.lastListQuery['status'], 'deleted');
      // 切篩選照例回第一頁：帶著舊頁碼換條件會翻出一頁不存在的東西。
      expect(fixture.lastListQuery['page'], '1');
    });

    testWidgets('目錄把刪除態如實標出來，並顯示服務端給的佔位名', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(secondStatus: 'deleted');
      await pump(tester, fixture);

      expect(
        find.descendant(
          of: find.byKey(AdminDirectoryCard.rowKey(_acct2)),
          matching: find.text(
            l10n.labelValuePair(
              l10n.adminListStatusLabel,
              l10n.adminStatusDeleted,
            ),
          ),
        ),
        findsOneWidget,
      );
      // 名字是回應給的佔位值：界面不自己拼、也不設法還原原本那個。
      expect(
        find.descendant(
          of: find.byKey(AdminDirectoryCard.rowKey(_acct2)),
          matching: find.textContaining('DEL_20261002_次任管理員'),
        ),
        findsOneWidget,
      );
      // 人已不在，但行還在目錄裡——入口也還在（詳情要讀得回來）。
      expect(find.byKey(AdminDirectoryCard.actionKey(_acct2)), findsOneWidget);
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

  group('停用與恢復', () {
    testWidgets('現狀決定按鈕：active 只給停用', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      expect(find.byKey(AdminProfileCard.disableKey), findsOneWidget);
      expect(find.byKey(AdminProfileCard.restoreKey), findsNothing);
    });

    testWidgets('disabled 只給恢復，且如實顯示停用時刻', (WidgetTester tester) async {
      // 每條用例各自泵一棵新樹：頁面 State 在同一樹位置會被複用，
      // 複用時詳情卡已打開，第二份 fixture 根本輪不到發詳情請求。
      final _Fixture fixture = _Fixture(
        detailBody: _detailBody(
          status: 'disabled',
          disabledAt: '2026-10-02T10:00:00.000Z',
        ),
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      expect(find.byKey(AdminProfileCard.disableKey), findsNothing);
      expect(find.byKey(AdminProfileCard.restoreKey), findsOneWidget);
      // 停用時刻是服務端現值：界面要講得出「幾時停的」。
      expect(
        find.textContaining(l10n.adminStatusDisabledAtLabel),
        findsOneWidget,
      );
      expect(find.textContaining('2026-10-02 10:00 UTC'), findsOneWidget);
    });

    testWidgets('確認對話框把目標、影響與「不是刪除」一次讀完；取消一請求都不發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await tapVisible(tester, AdminProfileCard.disableKey);

      expect(
        find.text(l10n.adminStatusConfirmDisableBody('Ops.Primary')),
        findsOneWidget,
      );
      expect(find.text(l10n.adminStatusConfirmTitleDisable), findsOneWidget);

      await tapVisible(tester, AdminProfileCard.confirmCancelKey);
      expect(fixture.statusUpdates, isEmpty);
      // 取消後界面停在上一份伺服器真相：狀態仍是 active，沒有半套變化。
      expect(find.byKey(AdminProfileCard.disableKey), findsOneWidget);
    });

    testWidgets('確認停用：本體恰好兩欄、回應換掉現值、句裡帶撤銷數量、目錄跟著重讀', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      final int listsBefore = fixture.listCalls;

      await tapVisible(tester, AdminProfileCard.disableKey);
      await tapVisible(tester, AdminProfileCard.confirmKey);

      final http.Request sent = fixture.statusUpdates.single;
      expect(sent.method, 'PUT');
      expect(sent.url.path, '$kRootAdminsPath/$_acct1/status');
      final Map<String, Object?> body =
          jsonDecode(sent.body) as Map<String, Object?>;
      expect(body, <String, Object?>{
        'status': 'disabled',
        // 依據值是「上一次從伺服器讀到的現狀」，不是輸入框或本地印象。
        'expected_status': 'active',
      });

      expect(find.text(l10n.adminStatusDisabledNotice(2)), findsOneWidget);
      // 展示換成回應：狀態已 disable，按鈕就此翻面成「恢復登入」。
      expect(find.byKey(AdminProfileCard.restoreKey), findsOneWidget);
      expect(find.byKey(AdminProfileCard.disableKey), findsNothing);
      // 目錄重讀一趟：清單與詳情不各留一份舊真相。
      expect(fixture.listCalls, listsBefore + 1);
    });

    testWidgets('確認恢復：句子如實「只恢復新登入能力」，展示換成回應的 active', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(
        detailBody: _detailBody(
          status: 'disabled',
          disabledAt: '2026-10-02T10:00:00.000Z',
        ),
        statusUpdateBody: _statusBody(status: 'active', revoked: 0),
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      await tapVisible(tester, AdminProfileCard.restoreKey);
      expect(
        find.text(l10n.adminStatusConfirmRestoreBody('Ops.Primary')),
        findsOneWidget,
      );
      await tapVisible(tester, AdminProfileCard.confirmKey);

      final Map<String, Object?> body =
          jsonDecode(fixture.statusUpdates.single.body) as Map<String, Object?>;
      expect(body, <String, Object?>{
        'status': 'active',
        'expected_status': 'disabled',
      });
      expect(find.text(l10n.adminStatusRestoredNotice), findsOneWidget);
      expect(find.byKey(AdminProfileCard.disableKey), findsOneWidget);
      // 恢復不撤任何會話，也不該出现带数量的停用句。
      expect(
        find.textContaining(l10n.adminStatusDisabledNotice(0)),
        findsNothing,
      );
    });

    testWidgets('2014：一句「狀態已改變」＋重讀出口，界面停在上一份伺服器真相', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(
        statusUpdateStatus: 409,
        statusUpdateErrorCode: 2014,
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      await tapVisible(tester, AdminProfileCard.disableKey);
      await tapVisible(tester, AdminProfileCard.confirmKey);

      expect(find.text(l10n.adminStatusConflictNotice), findsOneWidget);
      // 沒有「成功」的那一句，按鈕也沒翻面：操作一件都沒發生。
      expect(
        find.textContaining(l10n.adminStatusDisabledNotice(0)),
        findsNothing,
      );
      expect(find.byKey(AdminProfileCard.disableKey), findsOneWidget);

      final int detailsBefore = fixture.detailCalls;
      await tapVisible(tester, AdminProfileCard.reloadKey);
      expect(fixture.detailCalls, detailsBefore + 1);
    });

    testWidgets('表外狀態：不長任何按鈕，只如實說一句', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        detailBody: _detailBody(status: 'frozen'),
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      expect(find.byKey(AdminProfileCard.disableKey), findsNothing);
      expect(find.byKey(AdminProfileCard.restoreKey), findsNothing);
      expect(find.byKey(AdminProfileCard.statusUnknownKey), findsOneWidget);
      expect(
        find.text(l10n.adminStatusUnsupportedNotice('frozen')),
        findsOneWidget,
      );
      expect(fixture.statusUpdates, isEmpty);
    });
  });

  group('憑據重置', () {
    /// 在重置欄填入暫時口令（欄位在狀態區下方，先滾進視口）。
    Future<void> fillReset(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(AdminProfileCard.resetFieldKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(AdminProfileCard.resetFieldKey),
        _resetTempPassword,
      );
      await tester.pump();
    }

    testWidgets('active 目標同樣長重置區：不按狀態分岔（disabled 由下方用例單獨釘）', (
      WidgetTester tester,
    ) async {
      final _Fixture activeFixture = _Fixture();
      await pump(tester, activeFixture);
      await openProfile(tester, activeFixture);
      expect(find.byKey(AdminProfileCard.resetFieldKey), findsOneWidget);
      expect(find.byKey(AdminProfileCard.resetActionKey), findsOneWidget);
    });

    testWidgets('未填口令時一請求都不發，也不開對話框', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      await tapVisible(tester, AdminProfileCard.resetActionKey);
      expect(fixture.passwordResets, isEmpty);
      expect(find.text(l10n.adminResetFormIncompleteNotice), findsOneWidget);
      expect(find.text(l10n.adminResetConfirmTitle), findsNothing);
    });

    testWidgets('確認對話框講完目標、三件效果與「不是解除停用／不是刪除」；取消一請求都不發', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await fillReset(tester);

      await tapVisible(tester, AdminProfileCard.resetActionKey);
      expect(find.text(l10n.adminResetConfirmTitle), findsOneWidget);
      expect(
        find.text(l10n.adminResetConfirmBody('Ops.Primary')),
        findsOneWidget,
      );

      await tapVisible(tester, AdminProfileCard.resetConfirmCancelKey);
      expect(fixture.passwordResets, isEmpty);
      // 取消後界面停在上一份伺服器真相：沒有成功句，也沒有半套變化。
      expect(find.byKey(AdminProfileCard.resetNoticeKey), findsNothing);
    });

    testWidgets('確認重置：本體恰好一欄、欄位即刻清空、展示換回應、目錄重讀、口令不再現', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      final int listsBefore = fixture.listCalls;
      await fillReset(tester);

      await tapVisible(tester, AdminProfileCard.resetActionKey);
      await tapVisible(tester, AdminProfileCard.resetConfirmKey);

      final http.Request sent = fixture.passwordResets.single;
      expect(sent.method, 'PUT');
      expect(sent.url.path, '$kRootAdminsPath/$_acct1/password');
      final Map<String, Object?> body =
          jsonDecode(sent.body) as Map<String, Object?>;
      // 白名單只有口令一欄：沒有 expected_*、沒有狀態、沒有旗標的格子。
      expect(body.keys.toSet(), <String>{'password'});
      expect(body['password'], _resetTempPassword);

      // 送出即清空：輸入框不再持有交付物。
      expect(
        tester
            .widget<TextField>(find.byKey(AdminProfileCard.resetFieldKey))
            .controller!
            .text,
        isEmpty,
      );
      // 界面任何一處都不再出現口令（含成功句與遮罩欄）。
      final Iterable<Text> visible = tester.widgetList<Text>(find.byType(Text));
      expect(
        visible.any((Text t) => (t.data ?? '').contains(_resetTempPassword)),
        isFalse,
      );
      // 成功句的撤銷數量來自回應（fixture 給 2）。
      expect(find.text(l10n.adminResetSuccessNotice(2)), findsOneWidget);
      expect(find.byKey(AdminProfileCard.resetNoticeKey), findsOneWidget);
      expect(fixture.listCalls, listsBefore + 1);
    });

    testWidgets('停用目標重置：回應仍 disabled，展示與停用時刻都不變', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        detailBody: _detailBody(
          status: 'disabled',
          disabledAt: '2026-10-02T10:00:00.000Z',
        ),
        passwordResetBody: _passwordResetBody(revoked: 0, status: 'disabled'),
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await fillReset(tester);

      await tapVisible(tester, AdminProfileCard.resetActionKey);
      await tapVisible(tester, AdminProfileCard.resetConfirmKey);

      expect(find.text(l10n.adminResetSuccessNotice(0)), findsOneWidget);
      // 「重置不是解除停用」：恢復按鈕仍在、停用時刻仍是服務端那份。
      expect(find.byKey(AdminProfileCard.restoreKey), findsOneWidget);
      expect(find.textContaining('2026-10-02 10:00 UTC'), findsOneWidget);
    });

    testWidgets('1004 點名 password 給單獨一句，沒有成功句', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        passwordResetStatus: 400,
        passwordResetErrorCode: 1004,
        passwordResetBody: '{"code":1004,"message":"bad","details":{"invalid_field":"password"},"request_id":"r-bad"}',
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await fillReset(tester);

      await tapVisible(tester, AdminProfileCard.resetActionKey);
      await tapVisible(tester, AdminProfileCard.resetConfirmKey);

      expect(find.text(l10n.adminResetInvalidPasswordNotice), findsOneWidget);
      expect(find.byKey(AdminProfileCard.resetNoticeKey), findsNothing);
      // 失敗也不把口令留在欄位裡：本地草稿同樣是秘密的落點。
      expect(
        tester
            .widget<TextField>(find.byKey(AdminProfileCard.resetFieldKey))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('2011 講成權限不足而不是被登出', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        passwordResetStatus: 403,
        passwordResetErrorCode: 2011,
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await fillReset(tester);

      await tapVisible(tester, AdminProfileCard.resetActionKey);
      await tapVisible(tester, AdminProfileCard.resetConfirmKey);

      expect(find.text(l10n.adminProfileDeniedNotice), findsOneWidget);
      expect(find.text(l10n.errorCodeSessionInvalid), findsNothing);
    });

    testWidgets('結果不明（5xx）不自動重發：一次提交就是一趟請求', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        passwordResetStatus: 500,
        passwordResetErrorCode: 1000,
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await fillReset(tester);

      await tapVisible(tester, AdminProfileCard.resetActionKey);
      await tapVisible(tester, AdminProfileCard.resetConfirmKey);

      // 重置沒有依據值：「再點一次」不是重試而是又做一次真實重置，
      // 所以界面对失敗絕不自動補發，成功句也不許出現。
      expect(fixture.passwordResets, hasLength(1));
      expect(find.byKey(AdminProfileCard.resetNoticeKey), findsNothing);
    });
  });

  group('刪除', () {
    testWidgets('還沒被刪的目標長刪除入口（第四條寫入通路）', (WidgetTester tester) async {
      final _Fixture live = _Fixture();
      await pump(tester, live);
      await openProfile(tester, live);
      expect(find.byKey(AdminProfileCard.deleteKey), findsOneWidget);
      expect(find.text(l10n.adminDeleteZoneHint), findsOneWidget);
    });

    testWidgets('已刪除的詳情一律不給寫入控件，只列服務端回的現值', (WidgetTester tester) async {
      // 同一個人從伺服器讀回來已是刪除態時：四條寫入通路（改名、停用/恢復、
      // 重置、刪除）全部消失。留著按鈕對著一個不再接受寫入的對象，
      // 比少一顆按鈕更容易讓人以為還做得動。
      final _Fixture deleted = _Fixture(
        detailBody: _detailBody(
          status: 'deleted',
          deletedAt: '2026-10-02T11:00:00.000Z',
          display: 'DEL_20261002_首任管理員',
        ),
      );
      await pump(tester, deleted);
      await openProfile(tester, deleted);
      expect(find.byKey(AdminProfileCard.deleteKey), findsNothing);
      expect(find.byKey(AdminProfileCard.submitKey), findsNothing);
      expect(find.byKey(AdminProfileCard.displayNameKey), findsNothing);
      expect(find.byKey(AdminProfileCard.resetFieldKey), findsNothing);
      expect(find.byKey(AdminProfileCard.resetActionKey), findsNothing);
      expect(find.byKey(AdminProfileCard.disableKey), findsNothing);
      expect(find.byKey(AdminProfileCard.restoreKey), findsNothing);
      expect(find.byKey(AdminProfileCard.statusUnknownKey), findsNothing);
      // 「表外狀態」那一句不該用在一個明明認識的狀態上。
      expect(
        find.text(l10n.adminStatusUnsupportedNotice('deleted')),
        findsNothing,
      );
      expect(
        find.text(l10n.adminProfileDeletedBannerAt('2026-10-02 11:00 UTC')),
        findsOneWidget,
      );
      // 佔位顯示名由回應列出：活的投影現在長這樣，這件事要看得見。
      expect(
        find.byKey(AdminProfileCard.deletedDisplayNameKey),
        findsOneWidget,
      );
      expect(find.textContaining('DEL_20261002_首任管理員'), findsOneWidget);
      expect(find.byKey(AdminProfileCard.identityKeptKey), findsOneWidget);
    });

    testWidgets('確認對話框講完目標、三件效果與「不是停用／沒有回頭路」；取消一請求都不發', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      await tapVisible(tester, AdminProfileCard.deleteKey);
      expect(find.text(l10n.adminDeleteConfirmTitle), findsOneWidget);
      expect(
        find.text(l10n.adminDeleteConfirmBody('Ops.Primary')),
        findsOneWidget,
      );

      await tapVisible(tester, AdminProfileCard.deleteConfirmCancelKey);
      expect(fixture.deletes, isEmpty);
      expect(find.byKey(AdminProfileCard.deleteNoticeKey), findsNothing);
      // 取消之後人還在原地：寫入控件仍舊在（沒被一次沒發生的操作改掉）。
      expect(find.byKey(AdminProfileCard.deleteKey), findsOneWidget);
    });

    testWidgets('確認刪除：DELETE 打在單筆路徑上、不帶本體、成功句帶回應的撤銷數量', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      final int listsBefore = fixture.listCalls;

      await tapVisible(tester, AdminProfileCard.deleteKey);
      await tapVisible(tester, AdminProfileCard.deleteConfirmKey);

      final http.Request sent = fixture.deletes.single;
      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/root/admins/$_acct1');
      // 本體是空的：刪除不選欄位，也沒有依據值可交。
      expect(sent.body, isEmpty);
      expect(
        fixture.deletes.map((http.Request r) => r.url.path),
        isNot(contains('/delete')),
      );

      expect(find.text(l10n.adminDeleteSuccessNotice(2)), findsOneWidget);
      expect(fixture.listCalls, listsBefore + 1);
    });

    testWidgets('刪除成功即退出編輯態：底稿清空、四個寫入控件消失、展示換成回應', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      // 先在改名框留一半草稿：刪除之後它不該繼續出現在畫面上。
      await tester.enterText(
        find.byKey(AdminProfileCard.displayNameKey),
        '改到一半',
      );
      await tester.pump();

      await tapVisible(tester, AdminProfileCard.deleteKey);
      await tapVisible(tester, AdminProfileCard.deleteConfirmKey);

      expect(find.byKey(AdminProfileCard.displayNameKey), findsNothing);
      expect(find.text('改到一半'), findsNothing);
      expect(find.byKey(AdminProfileCard.submitKey), findsNothing);
      expect(find.byKey(AdminProfileCard.resetFieldKey), findsNothing);
      expect(find.byKey(AdminProfileCard.deleteKey), findsNothing);
      // 顯示名換成回應給的佔位值，不是本地那半份草稿。
      expect(find.textContaining('DEL_20261002_首任管理員'), findsOneWidget);
      expect(
        find.text(l10n.adminProfileDeletedBannerAt('2026-10-02 11:00 UTC')),
        findsOneWidget,
      );
    });

    testWidgets('2015（他早被刪過了）：一句「什麼都沒發生」，不謊報成第二次成功', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(
        deleteStatus: 409,
        deleteErrorCode: 2015,
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      await tapVisible(tester, AdminProfileCard.deleteKey);
      await tapVisible(tester, AdminProfileCard.deleteConfirmKey);

      expect(fixture.deletes.length, 1);
      expect(find.text(l10n.adminDeleteAlreadyNotice), findsOneWidget);
      expect(
        find.textContaining(l10n.adminDeleteSuccessNotice(0)),
        findsNothing,
      );
      // 失敗不改形態：人還在原地，控件仍舊在（下一次要問的是目錄，不是再點一次）。
      expect(find.byKey(AdminProfileCard.deleteKey), findsOneWidget);
    });

    testWidgets('2015 打在停用/恢復通路上時，說的是「不再接受任何寫入」', (WidgetTester tester) async {
      // 真實形態是競爭：畫面開著時他已被另一位 Root 刪掉，本地還留著按鈕。
      final _Fixture fixture = _Fixture(
        statusUpdateStatus: 409,
        statusUpdateErrorCode: 2015,
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await tapVisible(tester, AdminProfileCard.disableKey);
      await tapVisible(tester, AdminProfileCard.confirmKey);
      expect(find.text(l10n.adminProfileDeletedNotice), findsOneWidget);
      // 不是 2014 那句「現狀已改變，重讀再確認」：刪除沒有「再來一次」這條出路。
      expect(find.text(l10n.adminStatusConflictNotice), findsNothing);
    });

    testWidgets('2015 打在重置通路上時，同一句話而不是「改改口令再試」', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        passwordResetStatus: 409,
        passwordResetErrorCode: 2015,
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await tester.enterText(
        find.byKey(AdminProfileCard.resetFieldKey),
        _resetTempPassword,
      );
      await tester.pump();
      await tapVisible(tester, AdminProfileCard.resetActionKey);
      await tapVisible(tester, AdminProfileCard.resetConfirmKey);
      expect(find.text(l10n.adminProfileDeletedNotice), findsOneWidget);
      expect(find.byKey(AdminProfileCard.resetNoticeKey), findsNothing);
    });

    testWidgets('2015 打在改名通路上時不冒充 2013，也不給重發舊草稿的出口', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(
        updateStatus: 409,
        updateBody: '{"code":2015,"message":"x","request_id":"r-edit"}',
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);
      await tester.enterText(
        find.byKey(AdminProfileCard.displayNameKey),
        '刪掉之後還想改名',
      );
      await tester.pump();
      await tapVisible(tester, AdminProfileCard.submitKey);
      expect(find.text(l10n.adminProfileDeletedNotice), findsOneWidget);
      // 2013 那句「有人改過了，重讀再決定」在這裡是謊話：沒有現值可再改。
      expect(find.text(l10n.adminProfileConflictNotice), findsNothing);
      expect(find.byKey(AdminProfileCard.savedKey), findsNothing);
    });

    testWidgets('1004（本體塞了欄位）：一句「刪除不帶欄位」，沒有成功句', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        deleteStatus: 400,
        deleteErrorCode: 1004,
      );
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      await tapVisible(tester, AdminProfileCard.deleteKey);
      await tapVisible(tester, AdminProfileCard.deleteConfirmKey);
      expect(find.text(l10n.adminDeleteNoFieldNotice), findsOneWidget);
      expect(find.byKey(AdminProfileCard.deleteNoticeKey), findsNothing);
    });

    testWidgets('結果不明（5xx）不自動補發：一次確認就是一趟請求', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(deleteStatus: 500);
      await pump(tester, fixture);
      await openProfile(tester, fixture);

      await tapVisible(tester, AdminProfileCard.deleteKey);
      await tapVisible(tester, AdminProfileCard.deleteConfirmKey);
      await tester.pump(const Duration(seconds: 2));

      expect(fixture.deletes.length, 1);
      expect(find.byKey(AdminProfileCard.deleteNoticeKey), findsNothing);
      expect(
        find.text(l10n.adminDeleteSuccessNotice(0).split('{').first),
        findsNothing,
      );
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

  testWidgets('策略卡接在頁面上，且進頁只現讀一趟', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await pump(tester, fixture);

    expect(find.byKey(AccountPolicyCard.titleKey), findsOneWidget);
    expect(find.byKey(AccountPolicyCard.submitKey), findsOneWidget);
    expect(fixture.policyReads, 1);
    // 卡上的對外答案列要出現：Root 在同一張畫面上看見「存了 open 也還沒上線」，
    // 而不是自己推算功能是不是壞了。
    expect(find.byKey(AccountPolicyCard.entryKey), findsOneWidget);
  });
}
