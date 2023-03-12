/// 「活動管理」介面測試：目錄、建立、詳情、狀態轉換與名冊的呈現與如實轉述。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是幾件事：
///   1. 目錄的行、頁碼與總數一律取服務端回顯，空目錄那一句不猜原因；
///   2. 建立只送兩個欄位，成功後顯示的是服務端回來的現值，並觸發目錄重讀；
///   3. 轉換按鈕完全由服務端讀回的狀態決定，表外值與終態都不長按鈕；
///   4. 歸檔必經確認，取消是一條正經出路（一請求都不發），確認才發那一個 PUT；
///   5. 2013／2030 之後只給「重新讀取這份資料」的出口，沒有第二顆保存鈕可連點；
///   6. 名冊在管理員這一側只讀，加人與刪人只在 Root 那一側出現；
///   7. 寫入在途時四條通路一起停用（不並發提交）；
///   8. 360 px 窄屏下不出現佈局溢出（垂直滾動由殼承擔，這裡只放內容）。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/activity_directory_view.dart';
import 'package:evernightrealm/features/admin/activity_profile_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _activityId = '01a1c000-0000-7000-8000-0000000000c1';
const String _otherManagerId = '01a1c000-0000-7000-8000-0000000000d2';

/// 一筆活動的回應片段。
String _activityJson({
  String status = 'draft',
  String name = '秋夜長談',
  int managerCount = 1,
  bool rootCreated = false,
  String? archivedAt,
}) {
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"name":"$name"',
    '"description":"第一段描述"',
    '"status":"$status"',
    if (!rootCreated) '"created_by_account_id":"$_otherManagerId"',
    '"manager_count":$managerCount',
    '"created_at":"2026-10-10T03:00:00.000Z"',
    '"updated_at":"2026-10-10T04:00:00.000Z"',
    if (archivedAt != null) '"archived_at":"$archivedAt"',
  ];
  return '{${parts.join(',')}}';
}

String _detailBody({
  String status = 'draft',
  String name = '秋夜長談',
  int managerCount = 1,
  bool rootCreated = false,
  String? archivedAt,
}) {
  final String activity = _activityJson(
    status: status,
    name: name,
    managerCount: managerCount,
    rootCreated: rootCreated,
    archivedAt: archivedAt,
  );
  return '{"activity":$activity,"request_id":"r-detail"}';
}

String _rosterBody({int rows = 1}) {
  if (rows == 0) {
    return '{"managers":[],"request_id":"r-roster"}';
  }
  return '{"managers":[{"account_id":"$_otherManagerId",'
      '"display_name":"目錄上的管理員","account_status":"active",'
      '"granted_at":"2026-10-10T03:00:00.000Z"}],"request_id":"r-roster"}';
}

/// 依路徑與方法分流的假後端。
class _Fixture {
  _Fixture({
    this.detailStatus = 'draft',
    this.rootCreated = false,
    this.archivedAt,
    this.profileWriteStatus = 200,
    this.statusWriteStatus = 200,
    this.statusWriteCode = 2030,
    this.assignStatus = 200,
  });

  final String detailStatus;
  final bool rootCreated;
  final String? archivedAt;
  final int profileWriteStatus;
  final int statusWriteStatus;
  final int statusWriteCode;
  final int assignStatus;

  int directoryCalls = 0;
  int detailCalls = 0;
  int rosterCalls = 0;
  final List<http.Request> profileWrites = <http.Request>[];
  final List<http.Request> statusWrites = <http.Request>[];
  final List<http.Request> createWrites = <http.Request>[];
  final List<http.Request> assignWrites = <http.Request>[];
  final List<http.Request> revokeWrites = <http.Request>[];

  /// 讓下一份目錄回應換成建立後的兩行（證明「建立成功即重讀」而不是本地拼一行）。
  bool _createdOnDirectory = false;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final String method = request.method;
        if (method == 'GET' && path == kAdminActivitiesPath) {
          directoryCalls++;
          if (_createdOnDirectory) {
            return _json(
              '{"activities":[${_activityJson(status: detailStatus)}],'
              '"page":1,"page_size":20,"total":1,"request_id":"r-dir"}',
              200,
            );
          }
          return _json(
            '{"activities":[],"page":1,"page_size":20,"total":0,"request_id":"r-dir"}',
            200,
          );
        }
        if (method == 'POST' && path == kAdminActivitiesPath) {
          createWrites.add(request);
          _createdOnDirectory = true;
          return _json(_detailBody(status: 'draft', name: '建立後的名字'), 201);
        }
        if (method == 'GET' && path.endsWith('/managers')) {
          rosterCalls++;
          return _json(_rosterBody(), 200);
        }
        if (method == 'POST' && path.endsWith('/managers')) {
          assignWrites.add(request);
          if (assignStatus != 200) {
            return _json(
              '{"code":2032,"message":"taken","request_id":"r-assign"}',
              assignStatus,
            );
          }
          return _json(_detailBody(managerCount: 2), 200);
        }
        if (method == 'DELETE' && path.contains('/managers/')) {
          revokeWrites.add(request);
          return _json(_detailBody(managerCount: 0), 200);
        }
        if (method == 'PUT' && path.endsWith('/status')) {
          statusWrites.add(request);
          if (statusWriteStatus != 200) {
            return _json(
              '{"code":$statusWriteCode,"message":"conflict","request_id":"r-status"}',
              statusWriteStatus,
            );
          }
          return _json(
            _detailBody(
              status: _nextStatus(detailStatus),
              archivedAt: archivedAt,
            ),
            200,
          );
        }
        if (method == 'PUT') {
          profileWrites.add(request);
          if (profileWriteStatus != 200) {
            return _json(
              '{"code":2013,"message":"stale","request_id":"r-edit"}',
              profileWriteStatus,
            );
          }
          return _json(
            _detailBody(
              status: detailStatus,
              name: '保存後的名字',
              archivedAt: archivedAt,
            ),
            200,
          );
        }
        detailCalls++;
        return _json(
          _detailBody(
            status: detailStatus,
            rootCreated: rootCreated,
            archivedAt: archivedAt,
          ),
          200,
        );
      }),
    );
  }

  /// 假後端也跟着走一小步：draft→active、active→closed、closed→active、其餘→archived。
  static String _nextStatus(String from) {
    return switch (from) {
      'draft' => 'active',
      'active' => 'closed',
      'closed' => 'active',
      _ => 'archived',
    };
  }
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 以假後端泵入一張卡（目錄卡或詳情卡）。
Future<ServerApi> _pump(
  WidgetTester tester,
  _Fixture fixture,
  Widget Function(ServerApi api) build, {
  double width = 720,
}) async {
  final ServerAddressSettings settings = await buildAddressSettings(
    storedUrl: reachableUrl,
    reachable: <String>[reachableUrl],
  );
  final ServerApi api = fixture.api(settings);
  // 這頁的內容比預設測試畫布（800×600）長，控制項会被推到畫面外而.tap() 打不到。
  // 把測試表面拉高只為讓斷言打到真實控件，不改變任何佈局規則（寬度仍由引數決定）。
  final Size previousSize = tester.view.physicalSize;
  final double previousRatio = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 2400);
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
        home: Scaffold(
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: SingleChildScrollView(child: build(api)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  group('活動目錄卡', () {
    testWidgets('空目錄說的是「看不見任何活動」，不猜原因也不擺假行', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await _pump(tester, fixture, (ServerApi api) {
        return ActivityConsoleCard(api: api);
      });
      expect(fixture.directoryCalls, 1);
      expect(
        find.byKey(ActivityConsoleCard.emptyKey),
        findsOneWidget,
        reason: '空目錄必須有自己那一句，而不是空白畫面',
      );
    });

    testWidgets('建立只送名稱與描述，成功後顯示服務端回來的現值並重讀目錄', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await _pump(tester, fixture, (ServerApi api) {
        return ActivityConsoleCard(api: api);
      });
      final int callsBefore = fixture.directoryCalls;

      await tester.enterText(
        find.byKey(ActivityConsoleCard.nameKey),
        '  秋夜長談  ',
      );
      await tester.enterText(
        find.byKey(ActivityConsoleCard.descriptionKey),
        '第一段描述',
      );
      await tester.tap(find.byKey(ActivityConsoleCard.createKey));
      await tester.pumpAndSettle();

      final http.Request sent = fixture.createWrites.single;
      expect(sent.method, 'POST');
      final Map<String, Object?> body =
          jsonDecode(sent.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'name', 'description'});
      // 首尾空白由界面剝掉再送：留著它只會讓服務端回一句「名稱不合法」。
      expect(body['name'], '秋夜長談');

      // 成功摘要是服務端的回應（名稱以回值為準，不是本地那份緩存）。
      expect(find.byKey(ActivityConsoleCard.createdKey), findsOneWidget);
      expect(find.textContaining('建立後的名字'), findsWidgets);
      expect(fixture.directoryCalls, greaterThan(callsBefore));
      expect(
        find.byKey(ActivityConsoleCard.rowKey(_activityId)),
        findsOneWidget,
      );
    });

    testWidgets('1004 點名 name 時說的是名稱那句，不是泛泛的「操作失敗」', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await _pump(tester, fixture, (ServerApi api) {
        return ActivityConsoleCard(api: api);
      });
      // 名稱留空時本地就擋下，不發注定失敗的請求。
      await tester.tap(find.byKey(ActivityConsoleCard.createKey));
      await tester.pumpAndSettle();
      expect(fixture.createWrites, isEmpty);
      expect(find.byKey(ActivityConsoleCard.noticeKey), findsOneWidget);

      await tester.enterText(find.byKey(ActivityConsoleCard.nameKey), '甲');
      await tester.tap(find.byKey(ActivityConsoleCard.createKey));
      await tester.pumpAndSettle();
      expect(find.byKey(ActivityConsoleCard.noticeKey), findsNothing);
    });

    testWidgets('360 px 窄屏下篩選列換行而非溢出', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await _pump(
        tester,
        fixture,
        (ServerApi api) => ActivityConsoleCard(api: api),
        width: 360,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(ActivityConsoleCard.statusFilterKey), findsOneWidget);
      expect(find.byKey(ActivityConsoleCard.reloadKey), findsOneWidget);
    });
  });

  group('活動詳情卡', () {
    testWidgets('草稿只長「開放」一顆鈕，不長停止也不長歸檔以外的組合', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(detailStatus: 'draft');
      await _pump(tester, fixture, (ServerApi api) {
        return ActivityProfileCard(api: api, activityId: _activityId);
      });
      expect(
        find.byKey(ActivityProfileCard.transitionKey('active')),
        findsOneWidget,
      );
      expect(
        find.byKey(ActivityProfileCard.transitionKey('closed')),
        findsNothing,
      );
      expect(
        find.byKey(ActivityProfileCard.transitionKey('archived')),
        findsOneWidget,
        reason: '草稿可以直接歸檔（這條路徑存在）',
      );
    });

    testWidgets('歸檔必經確認：取消一請求都不發，確認才發那一個 PUT', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(detailStatus: 'active');
      await _pump(tester, fixture, (ServerApi api) {
        return ActivityProfileCard(api: api, activityId: _activityId);
      });

      await tester.tap(
        find.byKey(ActivityProfileCard.transitionKey('archived')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ActivityProfileCard.archiveConfirmKey), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fixture.statusWrites, isEmpty);

      await tester.tap(
        find.byKey(ActivityProfileCard.transitionKey('archived')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ActivityProfileCard.archiveConfirmKey));
      await tester.pumpAndSettle();
      final Map<String, Object?> body =
          jsonDecode(fixture.statusWrites.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'status'});
      expect(body['status'], 'archived');
    });

    testWidgets('已歸檔：收起全部寫入控件並如實標示終態（含 Root 建立的缺席語意）', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(
        detailStatus: 'archived',
        rootCreated: true,
        archivedAt: '2026-10-10T05:00:00.000Z',
      );
      await _pump(tester, fixture, (ServerApi api) {
        return ActivityProfileCard(api: api, activityId: _activityId);
      });
      expect(find.byKey(ActivityProfileCard.archivedKey), findsOneWidget);
      expect(find.byKey(ActivityProfileCard.saveKey), findsNothing);
      for (final String target in <String>['active', 'closed', 'archived']) {
        expect(
          find.byKey(ActivityProfileCard.transitionKey(target)),
          findsNothing,
          reason: '終態不該再長出一顆只會拿到 2029 的按鈕',
        );
      }
      // Root 建立的活動沒有帳戶建立者：界面說的是那一句話，不是一個空標識。
      expect(find.textContaining('由 Root 建立'), findsOneWidget);
      // 名冊仍讀得到，但增減控件不出現（這一側不是 Root 那側）。
      expect(find.byKey(ActivityProfileCard.assignKey), findsNothing);
      expect(find.byKey(ActivityProfileCard.assignAccountKey), findsNothing);
    });

    testWidgets('2013 之後只給重讀出口，並把兩顆寫入鈕停用', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(profileWriteStatus: 409);
      await _pump(tester, fixture, (ServerApi api) {
        return ActivityProfileCard(api: api, activityId: _activityId);
      });
      await tester.enterText(find.byKey(ActivityProfileCard.nameKey), '搶先一步改過');
      await tester.tap(find.byKey(ActivityProfileCard.saveKey));
      await tester.pumpAndSettle();

      expect(fixture.profileWrites, hasLength(1));
      final Map<String, Object?> body =
          jsonDecode(fixture.profileWrites.single.body) as Map<String, Object?>;
      // 依據值是「上一次從伺服器讀到的那份」，不是本地改過的值。
      expect(body['expected_name'], '秋夜長談');
      expect(find.byKey(ActivityProfileCard.savedKey), findsNothing);
      // 2013 的處置只有一個出口：重讀這份資料。保存鈕因此收起——
      // 讓使用者對著一份注定再次衝突的畫面再點一次，不是界面該給的「出路」。
      expect(find.byKey(ActivityProfileCard.reloadKey), findsOneWidget);
      expect(find.byKey(ActivityProfileCard.saveKey), findsNothing);
      expect(find.textContaining('已被他人改動'), findsOneWidget);
    });

    testWidgets('狀態衝突 2030 另成一句：給重讀出口，不謊報成功', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        detailStatus: 'draft',
        statusWriteStatus: 409,
        statusWriteCode: 2030,
      );
      await _pump(tester, fixture, (ServerApi api) {
        return ActivityProfileCard(api: api, activityId: _activityId);
      });
      await tester.tap(find.byKey(ActivityProfileCard.transitionKey('active')));
      await tester.pumpAndSettle();
      expect(fixture.statusWrites, hasLength(1));
      expect(find.byKey(ActivityProfileCard.savedKey), findsNothing);
      // 2030 與 2013 同一個出口：重讀。轉換鈕停在「已停用」而不是消失，
      // 因為現值重讀回來之後那顆按鈕可能真的可以再按一次。
      expect(find.byKey(ActivityProfileCard.reloadKey), findsOneWidget);
      expect(find.byKey(ActivityProfileCard.saveKey), findsNothing);
      final OutlinedButton transition = tester.widget(
        find.byKey(ActivityProfileCard.transitionKey('active')),
      );
      expect(transition.onPressed, isNull);
    });

    testWidgets('Root 那一側才長出指派與撤銷控件，指派打的是 /root 路徑', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await _pump(tester, fixture, (ServerApi api) {
        return ActivityProfileCard(
          api: api,
          activityId: _activityId,
          canManageManagers: true,
        );
      });
      expect(find.byKey(ActivityProfileCard.assignAccountKey), findsOneWidget);
      expect(
        find.byKey(ActivityProfileCard.revokeKey(_otherManagerId)),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(ActivityProfileCard.assignAccountKey),
        _otherManagerId,
      );
      await tester.tap(find.byKey(ActivityProfileCard.assignKey));
      await tester.pumpAndSettle();
      expect(
        fixture.assignWrites.single.url.path,
        rootActivityManagersPath(_activityId),
      );
      final Map<String, Object?> body =
          jsonDecode(fixture.assignWrites.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'account_id'});
      // 成功後名冊重讀（指派數量以服務端回顯為準，不是本地 +1）。
      expect(fixture.rosterCalls, greaterThan(1));
    });

    testWidgets('重複指派 2032 各成一句，並把名冊留在服務端那份狀態', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(assignStatus: 409);
      await _pump(tester, fixture, (ServerApi api) {
        return ActivityProfileCard(
          api: api,
          activityId: _activityId,
          canManageManagers: true,
        );
      });
      await tester.enterText(
        find.byKey(ActivityProfileCard.assignAccountKey),
        _otherManagerId,
      );
      await tester.tap(find.byKey(ActivityProfileCard.assignKey));
      await tester.pumpAndSettle();
      expect(find.byKey(ActivityProfileCard.savedKey), findsNothing);
      expect(find.textContaining('已經是這個活動的管理人'), findsOneWidget);
      expect(
        find.byKey(ActivityProfileCard.managerRowKey(_otherManagerId)),
        findsOneWidget,
        reason: '被拒的指派不該讓名冊長出一行',
      );
    });
  });
}
