/// 「玩家業務狀態定義」管理卡與名冊狀態變更的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是幾件事：
///   1. 目錄不自動載入：按下「讀取狀態定義」才發 GET，七個內建鍵逐字列出，
///      沒有覆蓋那一格讀成「走四語言預設文案」而不是「名稱是空的」；
///   2. 改顯示名稱的本體恰好兩欄（新值加依據值），「恢復預設」必經確認框，
///      確認句把「不會刪除狀態」唸出來；取消零請求；
///   3. 建立自訂狀態的本體只有一欄，成功後列表讀回「出生即可用」；
///   4. 停用與重新啟用都發同一條 PUT 白名單，只翻可用性，其餘帶著現值原樣送回；
///      確認句逐字說出「既有成員保留原狀態」；界面沒有刪除那颗按鈕；
///   5. 自訂名稱與顯示名稱都是純文字：含尖括號的名稱只以文字出現在畫面上；
///   6. 2042 與 2013 各自轉述成自己那一句；2013 之後只留重讀出口；
///   7. 名冊那一行的狀態列取服務端回讀值；變更狀態的對話框先讀目錄才長出選項，
///      custom 沒挑定義時本地先擋（完全不發請求），提交時帶著兩個依據值；
///      冪等重送唸「什麼都沒改變」而不是「已更新」；
///   8. 停止態仍可準備定義、歸檔收起全部寫入控件；「業務狀態不是連線狀態」與
///      「狀態不帶未批准的副作用」兩句常驻在卡下方；
///   9. 360 px 窄屏下不出現佈局溢出。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/activity_members_view.dart';
import 'package:evernightrealm/features/admin/activity_player_status_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _activityId = '01a1d000-0000-7000-8000-0000000000e1';
const String _memberId = '01a1d000-0000-7000-8000-0000000000m1';
const String _statusId = '01a1d000-0000-7000-8000-0000000000s1';
const String _accountId = '01a1d000-0000-7000-8000-0000000000b1';

/// 七個內建鍵（與後端目錄同序）。
const List<String> _builtinKeys = <String>[
  'normal',
  'suspended',
  'eliminated',
  'dead',
  'arrested',
  'offline',
  'custom',
];

String _builtinJson(String statusKey, {String displayName = ''}) {
  final String usesDefault = displayName.isEmpty ? 'true' : 'false';
  return '{"status_key":"$statusKey","display_name":"$displayName",'
      '"uses_default_display_name":$usesDefault}';
}

String _catalogBody({
  Map<String, String> overrides = const <String, String>{},
  List<String> custom = const <String>[],
}) {
  final List<String> rows = <String>[
    for (final String key in _builtinKeys)
      _builtinJson(key, displayName: overrides[key] ?? ''),
  ];
  return '{"builtin_statuses":[${rows.join(',')}],'
      '"custom_statuses":[${custom.join(',')}],"request_id":"r-catalog"}';
}

String _customJson({
  String name = '失蹤中',
  bool available = true,
  String id = _statusId,
}) {
  final String availableText = available ? 'true' : 'false';
  return '{"custom_status_id":"$id","name":"$name","available":$availableText,'
      '"created_at":"2026-10-10T03:00:00.000Z",'
      '"updated_at":"2026-10-10T04:00:00.000Z"}';
}

String _memberJson({
  String businessStatus = 'normal',
  String customStatusId = '',
  String customStatusName = '',
  String statusDisplayName = '',
  bool statusAvailable = true,
}) {
  final String availableText = statusAvailable ? 'true' : 'false';
  return '{"member_id":"$_memberId","activity_id":"$_activityId",'
      '"account_id":"$_accountId","nickname":"夜行者","faction_id":"",'
      '"display_name":"玩家甲","account_status":"active",'
      '"directory_visibility":"inherit","admin_identity":false,'
      '"business_status":"$businessStatus",'
      '"custom_status_id":"$customStatusId",'
      '"custom_status_name":"$customStatusName",'
      '"status_display_name":"$statusDisplayName",'
      '"status_available":$availableText,'
      '"restrict_login":false,"restrict_chat":false,"restrict_private_chat":false,"restrict_trade":false,"restrict_transfer":false,"restrict_item_use":false,'
      '"joined_at":"2026-10-10T03:00:00.000Z",'
      '"updated_at":"2026-10-10T04:00:00.000Z"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 依路徑與方法分流的假後端。
///
/// 目錄與名冊都可腳本化為「寫入成功後換一份」，於是界面的結果句只能讀回應回讀的現值，
/// 讀不到請求裡的意圖；被拒的寫入則讓現值停留在原本那一份。
class _Fixture {
  _Fixture({
    this.activityStatus = 'active',
    this.labelStatus = 200,
    this.labelCode = 0,
    this.createStatus = 201,
    this.createCode = 0,
    this.customStatus = 200,
    this.customCode = 0,
    this.memberStatusStatus = 200,
    this.memberStatusCode = 0,
    this.catalogCustom = const <String>[],
    this.overrides = const <String, String>{},
  });

  final String activityStatus;
  final int labelStatus;
  final int labelCode;
  final int createStatus;
  final int createCode;
  final int customStatus;
  final int customCode;
  final int memberStatusStatus;
  final int memberStatusCode;

  /// 目錄第一份讀回時自訂那一組的內容（演「已有一行定義」與「空清單」兩種形態）。
  final List<String> catalogCustom;

  /// 目錄第一份讀回時內建狀態的覆蓋現值（改名對話框的預填與依據值只能取自這裡）。
  final Map<String, String> overrides;

  int catalogCalls = 0;
  int rosterCalls = 0;
  final List<http.Request> labelWrites = <http.Request>[];
  final List<http.Request> createWrites = <http.Request>[];
  final List<http.Request> customWrites = <http.Request>[];
  final List<http.Request> memberStatusWrites = <http.Request>[];

  /// 只有成功的寫入才換第二份現值：被拒時界面讀回的東西不該已經改了。
  bool _written = false;

  String _failureBody(int code) =>
      '{"code":$code,"message":"rejected","request_id":"r-status-fail"}';

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final String method = request.method;

        if (method == 'GET' && path.endsWith('/player-statuses')) {
          catalogCalls++;
          return _json(
            _catalogBody(
              overrides: _written
                  ? <String, String>{'offline': '寫入後的名稱'}
                  : overrides,
              custom: _written
                  ? <String>[_customJson(name: '寫入後的名字')]
                  : catalogCustom,
            ),
            200,
          );
        }
        if (method == 'POST' && path.endsWith('/player-statuses')) {
          createWrites.add(request);
          if (createStatus != 201) {
            return _json(_failureBody(createCode), createStatus);
          }
          _written = true;
          final String createdRow = _customJson(name: '寫入後的名字');
          return _json(
            '{"custom_status":$createdRow,"request_id":"r-create"}',
            201,
          );
        }
        if (method == 'PUT' && path.contains('/player-status-labels/')) {
          labelWrites.add(request);
          if (labelStatus != 200) {
            return _json(_failureBody(labelCode), labelStatus);
          }
          final Map<String, Object?> sent =
              jsonDecode(request.body) as Map<String, Object?>;
          _written = true;
          final String displayName = sent['display_name']! as String;
          final String builtinRow = _builtinJson(
            'offline',
            displayName: displayName,
          );
          return _json(
            '{"builtin_status":$builtinRow,"request_id":"r-label"}',
            200,
          );
        }
        if (method == 'PUT' && path.contains('/player-statuses/')) {
          customWrites.add(request);
          if (customStatus != 200) {
            return _json(_failureBody(customCode), customStatus);
          }
          final Map<String, Object?> sent =
              jsonDecode(request.body) as Map<String, Object?>;
          _written = true;
          final String editedRow = _customJson(
            name: sent['name']! as String,
            available: sent['available']! as bool,
          );
          return _json(
            '{"custom_status":$editedRow,"request_id":"r-custom"}',
            200,
          );
        }
        if (method == 'GET' && path.endsWith('/members')) {
          rosterCalls++;
          // 寫入落地後名冊讀回的是「帶著一個此刻已停用的自訂定義」那一行：
          // 既有歸屬保留，只有可用性這一格改口。
          final String body = _written
              ? _memberJson(
                  businessStatus: 'custom',
                  customStatusId: _statusId,
                  customStatusName: '寫入後的名字',
                  statusDisplayName: '寫入後的名字',
                  statusAvailable: false,
                )
              : _memberJson();
          return _json('{"members":[$body],"request_id":"r-roster"}', 200);
        }
        if (method == 'PUT' && path.endsWith('/business-status')) {
          memberStatusWrites.add(request);
          if (memberStatusStatus != 200) {
            return _json(_failureBody(memberStatusCode), memberStatusStatus);
          }
          final Map<String, Object?> sent =
              jsonDecode(request.body) as Map<String, Object?>;
          _written = true;
          // 回應回讀的是庫中現值：非 custom 時自訂那一組格子如實為空。
          final String status = sent['business_status']! as String;
          final String customId = sent['custom_status_id']! as String;
          final String memberRow = _memberJson(
            businessStatus: status,
            customStatusId: customId,
            customStatusName: customId.isEmpty ? '' : '寫入後的名字',
            statusDisplayName: customId.isEmpty ? '' : '寫入後的名字',
            // 目录裡那行定義此刻已停用時，既有歸屬保留、可用性改口：這一句靠這一格講。
            statusAvailable: customId.isEmpty,
          );
          return _json(
            '{"member":$memberRow,"request_id":"r-member-status"}',
            200,
          );
        }
        throw StateError('未預期的請求：$method $path');
      }),
    );
  }
}

Future<ServerApi> _api(_Fixture fixture) async {
  final ServerAddressSettings settings = await buildAddressSettings(
    storedUrl: reachableUrl,
    reachable: <String>[reachableUrl],
  );
  return fixture.api(settings);
}

/// 把一張卡掛進應用外殼。每一趟掛樹帶自己的 tag：同一個 runtimeType 在
/// pumpWidget 之間會共用 State，不區分就會帶著上一趟的編輯態與在途狀態。
Future<AppLocalizations> _pumpCard(
  WidgetTester tester, {
  required Widget Function(ServerApi api) card,
  required _Fixture fixture,
  double width = 720,
}) async {
  final ServerApi api = await _api(fixture);
  late AppLocalizations l10n;
  final Size previousSize = tester.view.physicalSize;
  final double previousRatio = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 3200);
  addTearDown(() {
    tester.view.physicalSize = previousSize;
    tester.view.devicePixelRatio = previousRatio;
  });
  await tester.pumpWidget(
    AppScope(
      dependencies: AppDependencies(api: api),
      child: MaterialApp(
        locale: _locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            l10n = AppLocalizations.of(context);
            return Scaffold(
              body: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width),
                    child: SingleChildScrollView(child: card(api)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

/// 狀態定義卡。
Widget Function(ServerApi api) _statusCard(
  String surfaceTag, {
  required _Fixture fixture,
}) {
  return (ServerApi api) => PlayerStatusConfigCard(
    key: ValueKey<String>('player-status-card-$surfaceTag'),
    api: api,
    activityId: _activityId,
    activityStatus: fixture.activityStatus,
  );
}

/// 名冊卡。
Widget Function(ServerApi api) _membersCard(String surfaceTag) {
  return (ServerApi api) => ActivityMembersCard(
    key: ValueKey<String>('activity-members-card-$surfaceTag'),
    api: api,
    activityId: _activityId,
    activityStatus: 'active',
  );
}

void main() {
  testWidgets('目錄不自動載入：按下讀取才發 GET，七格逐字列出', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pumpCard(
      tester,
      card: _statusCard('idle', fixture: fixture),
      fixture: fixture,
    );

    expect(fixture.catalogCalls, 0);
    expect(find.byKey(PlayerStatusConfigCard.loadKey), findsOneWidget);

    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();

    expect(fixture.catalogCalls, 1);
    for (final String key in _builtinKeys) {
      expect(
        find.byKey(PlayerStatusConfigCard.builtinRowKey(key)),
        findsOneWidget,
      );
    }
    // 沒有覆蓋時講的是「走預設文案」那句，而不是留一格空白。
    expect(find.text('離線（業務狀態）'), findsOneWidget);
    expect(find.text(l10n.statusDefaultLabelNotice), findsWidgets);
    // 自訂清單為空是事實而不是故障。
    expect(find.byKey(PlayerStatusConfigCard.emptyKey), findsOneWidget);
    // 四句邊界常驻：連線狀態、無副作用、無刪除、無快取。
    expect(find.byKey(PlayerStatusConfigCard.connectivityKey), findsOneWidget);
    expect(find.byKey(PlayerStatusConfigCard.sideEffectKey), findsOneWidget);
    expect(find.byKey(PlayerStatusConfigCard.noDeleteKey), findsOneWidget);
    expect(find.byKey(PlayerStatusConfigCard.noCacheKey), findsOneWidget);
    // 這一族沒有刪除通路：卡上不長出任何一顆刪除按鈕。
    expect(find.text('刪除'), findsNothing);
  });

  testWidgets('改顯示名稱：本體恰好兩欄，依據值取自已讀到的那一格', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(
      overrides: const <String, String>{'offline': '暫離現場'},
    );
    await _pumpCard(
      tester,
      card: _statusCard('rename', fixture: fixture),
      fixture: fixture,
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(PlayerStatusConfigCard.builtinRenameKey('offline')),
    );
    await tester.pumpAndSettle();
    // 預填的是服務端讀回的那一份覆蓋，不是空字串、也不是內部值。
    expect(
      tester
          .widget<TextField>(find.byKey(PlayerStatusConfigCard.editNameKey))
          .controller!
          .text,
      '暫離現場',
    );

    await tester.enterText(
      find.byKey(PlayerStatusConfigCard.editNameKey),
      '暫離現場二代',
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.editSaveKey));
    await tester.pumpAndSettle();

    expect(fixture.labelWrites, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.labelWrites.single.body) as Map<String, Object?>;
    expect(body.keys.toSet(), <String>{
      'display_name',
      'expected_display_name',
    });
    expect(body['display_name'], '暫離現場二代');
    expect(body['expected_display_name'], '暫離現場');
    expect(find.byKey(PlayerStatusConfigCard.savedKey), findsOneWidget);
  });

  testWidgets('恢復預設名稱要走確認框；取消零請求', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(
      overrides: const <String, String>{'offline': '暫離現場'},
    );
    final AppLocalizations l10n = await _pumpCard(
      tester,
      card: _statusCard('reset', fixture: fixture),
      fixture: fixture,
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(PlayerStatusConfigCard.builtinRenameKey('offline')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(PlayerStatusConfigCard.resetLabelKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.statusResetLabelConfirmBody), findsOneWidget);
    await tester.tap(find.byKey(PlayerStatusConfigCard.confirmCancelKey));
    await tester.pumpAndSettle();
    expect(fixture.labelWrites, isEmpty);

    await tester.tap(find.byKey(PlayerStatusConfigCard.resetLabelKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PlayerStatusConfigCard.confirmKey));
    await tester.pumpAndSettle();
    expect(fixture.labelWrites, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.labelWrites.single.body) as Map<String, Object?>;
    expect(body['display_name'], '');
    expect(body['expected_display_name'], '暫離現場');
  });

  testWidgets('建立自訂狀態：本體只有一欄，成功後讀回出生即可用', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pumpCard(
      tester,
      card: _statusCard('create', fixture: fixture),
      fixture: fixture,
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();

    // 空白名稱本地先擋：一個請求都不發。
    await tester.tap(find.byKey(PlayerStatusConfigCard.createSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.createWrites, isEmpty);
    expect(find.byKey(PlayerStatusConfigCard.noticeKey), findsOneWidget);

    await tester.enterText(
      find.byKey(PlayerStatusConfigCard.createNameKey),
      '  失蹤中  ',
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.createSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.createWrites, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.createWrites.single.body) as Map<String, Object?>;
    expect(body.keys.toSet(), <String>{'name'});
    expect(body['name'], '失蹤中');
    // 重讀回來的清單讀得到新建的那一行；名稱取回應而不是請求裡的原稿。
    expect(find.text('寫入後的名字'), findsWidgets);
    expect(
      find.byKey(PlayerStatusConfigCard.customToggleKey(_statusId)),
      findsOneWidget,
    );
    expect(
      find.byKey(PlayerStatusConfigCard.customRowKey(_statusId)),
      findsOneWidget,
    );
  });

  testWidgets('停用只翻可用性；確認句唸出「既有成員保留原狀態」', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(catalogCustom: <String>[_customJson()]);
    final AppLocalizations l10n = await _pumpCard(
      tester,
      card: _statusCard('disable', fixture: fixture),
      fixture: fixture,
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(PlayerStatusConfigCard.customToggleKey(_statusId)),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.statusDisableConfirmBody), findsOneWidget);
    await tester.tap(find.byKey(PlayerStatusConfigCard.confirmKey));
    await tester.pumpAndSettle();

    expect(fixture.customWrites, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.customWrites.single.body) as Map<String, Object?>;
    expect(body.keys.toSet(), <String>{
      'name',
      'available',
      'expected_name',
      'expected_available',
    });
    expect(body['available'], isFalse);
    expect(body['expected_available'], isTrue);
    expect(body['name'], '失蹤中');
  });

  testWidgets('自訂名稱與顯示名稱是純文字：含尖括號的名稱只以文字出現', (WidgetTester tester) async {
    const String hostile = '<img src=x onerror=alert(1)>';
    final _Fixture fixture = _Fixture(
      catalogCustom: <String>[_customJson(name: hostile)],
      overrides: const <String, String>{'dead': hostile},
    );
    await _pumpCard(
      tester,
      card: _statusCard('text', fixture: fixture),
      fixture: fixture,
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();

    // 畫面找的到這段字串，而且承擔它的是 Text：界面沒有把任何一格交給 HTML 通路。
    expect(find.text(hostile), findsWidgets);
    expect(find.byType(Text), findsWidgets);
  });

  testWidgets('2042 轉述成「已有同名的自訂狀態」那一句，且不落地', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(createStatus: 409, createCode: 2042);
    final AppLocalizations l10n = await _pumpCard(
      tester,
      card: _statusCard('taken', fixture: fixture),
      fixture: fixture,
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PlayerStatusConfigCard.createNameKey),
      '失蹤中',
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.createSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.createWrites, hasLength(1));
    // 提示列自己就是那颗 Text（按鍵掛在它身上），因此雨者各自斷言而不是找子節點。
    expect(find.byKey(PlayerStatusConfigCard.noticeKey), findsOneWidget);
    expect(find.text(l10n.errorCodePlayerStatusNameTaken), findsOneWidget);
    // 被拒的建立不落地：沒有成功句，列表仍是被拒前讀到的那一份（空的）。
    expect(find.byKey(PlayerStatusConfigCard.savedKey), findsNothing);
    expect(
      find.byKey(PlayerStatusConfigCard.customRowKey(_statusId)),
      findsNothing,
    );
  });

  testWidgets('現值過期（2013）後收起寫入控件，只留重讀出口', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(
      labelStatus: 409,
      labelCode: 2013,
      overrides: const <String, String>{'offline': '暫離現場'},
    );
    final AppLocalizations l10n = await _pumpCard(
      tester,
      card: _statusCard('stale', fixture: fixture),
      fixture: fixture,
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(PlayerStatusConfigCard.builtinRenameKey('offline')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PlayerStatusConfigCard.editNameKey),
      '又一個名字',
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.editSaveKey));
    await tester.pumpAndSettle();

    expect(find.text(l10n.statusStaleNotice), findsOneWidget);
    expect(find.byKey(PlayerStatusConfigCard.createSubmitKey), findsNothing);
    expect(
      find.byKey(PlayerStatusConfigCard.builtinRenameKey('offline')),
      findsNothing,
    );
    expect(find.byKey(PlayerStatusConfigCard.reloadKey), findsOneWidget);
  });

  testWidgets('歸檔收起全部寫入控件並說「這件事已結束」，但仍列可讀', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(
      activityStatus: 'archived',
      catalogCustom: <String>[_customJson()],
    );
    final AppLocalizations l10n = await _pumpCard(
      tester,
      card: _statusCard('archived', fixture: fixture),
      fixture: fixture,
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();

    expect(find.text(l10n.statusArchivedNotice), findsOneWidget);
    expect(
      find.byKey(PlayerStatusConfigCard.builtinRenameKey('offline')),
      findsNothing,
    );
    expect(
      find.byKey(PlayerStatusConfigCard.customToggleKey(_statusId)),
      findsNothing,
    );
    expect(find.byKey(PlayerStatusConfigCard.createSubmitKey), findsNothing);
    expect(find.text('失蹤中'), findsWidgets);
  });

  testWidgets('名冊那一行列出業務狀態，變更對話框先讀目錄才長出選項', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pumpCard(tester, card: _membersCard('status'), fixture: fixture);
    expect(fixture.rosterCalls, 1);
    // 那一列自己就是掛鍵的那顆 Text，因此「有這一列」與「它念的是哪個名字」分開斷言。
    expect(
      find.byKey(ActivityMembersCard.statusLabelKey(_memberId)),
      findsOneWidget,
    );
    expect(find.textContaining('正常'), findsWidgets);
    expect(fixture.catalogCalls, 0);

    await tester.tap(
      find.byKey(ActivityMembersCard.statusActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    // 對話框長出選項之前一定先讀過目錄：沒有底稿就沒有選項。
    expect(fixture.catalogCalls, 1);
    expect(find.byKey(ActivityMembersCard.statusTargetKey), findsOneWidget);
    // 「這不是連線狀態」那一句寫在按鈕上方，而不是藏在錯誤訊息裡。
    expect(find.byKey(ActivityMembersCard.statusNoticeKey), findsOneWidget);
  });

  testWidgets('名冊變更狀態：custom 沒挑定義時本地先擋，提交時帶兩個依據值', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(catalogCustom: <String>[_customJson()]);
    await _pumpCard(tester, card: _membersCard('custom'), fixture: fixture);

    await tester.tap(
      find.byKey(ActivityMembersCard.statusActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.statusTargetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自訂').last);
    await tester.pumpAndSettle();
    // 選到 custom 而沒挑定義：送出前先擋，一個請求都不發。
    await tester.tap(find.byKey(ActivityMembersCard.statusSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.memberStatusWrites, isEmpty);
    expect(find.textContaining('送出前先選'), findsWidgets);

    await tester.tap(find.byKey(ActivityMembersCard.statusCustomKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('失蹤中').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.statusSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.memberStatusWrites, hasLength(1));
    final Map<String, Object?> body = jsonDecode(
      fixture.memberStatusWrites.single.body,
    ) as Map<String, Object?>;
    expect(body.keys.toSet(), <String>{
      'business_status',
      'custom_status_id',
      'expected_business_status',
      'expected_custom_status_id',
    });
    expect(body['business_status'], 'custom');
    expect(body['custom_status_id'], _statusId);
    expect(body['expected_business_status'], 'normal');
    expect(body['expected_custom_status_id'], '');
    // 成功後重讀名冊：那一行的狀態取自回應，界面不本地蓋值。
    expect(
      find.descendant(
        of: find.byKey(ActivityMembersCard.statusLabelKey(_memberId)),
        matching: find.text('normal'),
      ),
      findsNothing,
    );
  });

  testWidgets('冪等重送（目標等於現值）唸「什麼都沒改變」而不是「已更新」', (WidgetTester tester) async {
    // 名冊回讀的是原本那一行（沒有翻轉）：界面據此換成「什麼都沒改變」那句。
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pumpCard(
      tester,
      card: _membersCard('idempotent'),
      fixture: fixture,
    );
    await tester.tap(
      find.byKey(ActivityMembersCard.statusActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    // 什麼都沒改就送出：這一筆提交的目標等於名冊讀回的現值。
    await tester.tap(find.byKey(ActivityMembersCard.statusSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.memberStatusWrites, hasLength(1));
    expect(find.byKey(ActivityMembersCard.savedKey), findsOneWidget);
    expect(find.text(l10n.memberStatusUnchangedNotice), findsOneWidget);
    expect(find.text(l10n.memberStatusSavedNotice), findsNothing);
  });

  testWidgets('名冊的狀態列也唸得出停用中的自訂定義（既有歸屬保留）', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(catalogCustom: <String>[_customJson()]);
    final AppLocalizations l10n = await _pumpCard(
      tester,
      card: _membersCard('unavailable'),
      fixture: fixture,
    );
    // 讓寫入先落地成 custom 那一行，再回來讀名冊。
    await tester.tap(
      find.byKey(ActivityMembersCard.statusActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.statusTargetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自訂').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.statusCustomKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('失蹤中').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.statusSubmitKey));
    await tester.pumpAndSettle();

    // 既有歸屬保留：那一行仍唸自訂名稱，而可用性那一格改口成「已停用新的選用」。
    expect(
      find.descendant(
        of: find.byKey(ActivityMembersCard.rowKey(_memberId)),
        matching: find.textContaining(l10n.playerStatusDisabledNotice),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ActivityMembersCard.rowKey(_memberId)),
        matching: find.byKey(ActivityMembersCard.statusLabelKey(_memberId)),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('寫入後的名字'), findsWidgets);
  });

  testWidgets('自訂定義的編輯落敗（2013）時現值一格不動，也只留重讀出口', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(
      customStatus: 409,
      customCode: 2013,
      catalogCustom: <String>[_customJson()],
    );
    final AppLocalizations l10n = await _pumpCard(
      tester,
      card: _statusCard('custom-stale', fixture: fixture),
      fixture: fixture,
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(PlayerStatusConfigCard.customToggleKey(_statusId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PlayerStatusConfigCard.confirmKey));
    await tester.pumpAndSettle();

    expect(fixture.customWrites, hasLength(1));
    expect(find.text(l10n.statusStaleNotice), findsOneWidget);
    // 被拒的停用不落地：那一行讀回来仍是「可用」，也沒有成功句。
    expect(
      find.descendant(
        of: find.byKey(PlayerStatusConfigCard.customRowKey(_statusId)),
        matching: find.textContaining(l10n.statusEnabledLabel),
      ),
      findsOneWidget,
    );
    expect(find.byKey(PlayerStatusConfigCard.savedKey), findsNothing);
  });

  testWidgets('選中已停用的自訂定義（2041）轉述成那一句，既有現值不動', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(
      memberStatusStatus: 409,
      memberStatusCode: 2041,
      catalogCustom: <String>[_customJson(available: false)],
    );
    final AppLocalizations l10n = await _pumpCard(
      tester,
      card: _membersCard('unavailable-write'),
      fixture: fixture,
    );
    await tester.tap(
      find.byKey(ActivityMembersCard.statusActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.statusTargetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自訂').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.statusCustomKey));
    await tester.pumpAndSettle();
    // 停用中的定義仍列在選項裡（帶著「（已停用）」後綴），由後端當場擋下新的選用。
    await tester.tap(find.text('失蹤中（已停用）').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.statusSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.memberStatusWrites, hasLength(1));
    expect(find.byKey(ActivityMembersCard.noticeKey), findsOneWidget);
    expect(find.text(l10n.errorCodePlayerStatusUnavailable), findsOneWidget);
    // 被拒的變更不落地：那一行讀回來仍是原本那個內建值。
    expect(
      find.byKey(ActivityMembersCard.statusLabelKey(_memberId)),
      findsOneWidget,
    );
    expect(find.textContaining('正常'), findsWidgets);
  });

  testWidgets('360 窄屏下狀態卡與名冊都不溢出', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(
      catalogCustom: <String>[_customJson(name: '很長的自訂狀態名稱給窄屏用')],
      overrides: const <String, String>{'offline': '很長的顯示名稱給窄屏用'},
    );
    await _pumpCard(
      tester,
      card: _statusCard('narrow-status', fixture: fixture),
      fixture: fixture,
      width: 360,
    );
    await tester.tap(find.byKey(PlayerStatusConfigCard.loadKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _pumpCard(
      tester,
      card: _membersCard('narrow-members'),
      fixture: fixture,
      width: 360,
    );
    await tester.tap(
      find.byKey(ActivityMembersCard.statusActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
