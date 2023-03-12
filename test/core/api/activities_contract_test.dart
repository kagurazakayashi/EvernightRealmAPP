/// 「活動生命週期管理」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：六條端點的方法與路徑、每條白名單**恰好**哪些欄位
/// （建立不帶狀態與建立者、資料編輯帶兩個依據值、狀態轉換不帶依據值、
/// 指派只帶一個帳戶標識、撤銷什麼都不帶），成功回應的必填欄位，
/// 兩個「缺席」的語意（Root 建的活動沒有建立者標識、未歸檔的活動沒有歸檔時刻），
/// 以及 2029～2032 四枚新碼在前端各自成一個值（不退成 1000、也不併進 2013／2014）。
/// 未知新欄位一律容忍（後端只增不刪），但必填欄位缺席必須失敗而不是補一個假值。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

const String _activityId = '01a1b000-0000-7000-8000-0000000000a1';
const String _otherActivityId = '01a1b000-0000-7000-8000-0000000000a2';
const String _accountId = '01a1b000-0000-7000-8000-0000000000b1';

/// 一筆活動的可展示事實。[rootCreated] 時刻意不出現建立者欄位（合同以缺席表達），
/// [archivedAt] 為 null 時同理不出現歸檔時刻。
String _activityJson({
  String status = 'draft',
  bool rootCreated = false,
  String? archivedAt,
  int managerCount = 1,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"name":"秋夜長談"',
    '"description":"第一段描述"',
    '"status":"$status"',
    if (!rootCreated) '"created_by_account_id":"$_accountId"',
    '"manager_count":$managerCount',
    '"created_at":"2026-10-10T03:00:00.000Z"',
    '"updated_at":"2026-10-10T04:00:00.000Z"',
    if (archivedAt != null) '"archived_at":"$archivedAt"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

String _detailBody({
  String status = 'draft',
  bool rootCreated = false,
  String? archivedAt,
  int managerCount = 1,
  String? extraField,
}) {
  final String activity = _activityJson(
    status: status,
    rootCreated: rootCreated,
    archivedAt: archivedAt,
    managerCount: managerCount,
    extraField: extraField,
  );
  return '{"activity":$activity,"request_id":"r-act"}';
}

String _managerJson({
  String displayName = '目錄上的管理員',
  String accountStatus = 'active',
}) {
  return '{"account_id":"$_accountId","display_name":"$displayName",'
      '"account_status":"$accountStatus","granted_at":"2026-10-10T03:00:00.000Z"}';
}

String _rosterBody(List<String> rows) {
  return '{"managers":[${rows.join(',')}],"request_id":"r-roster"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('活動建立與目錄', () {
    test('createActivity 發 POST、本體恰好兩個欄位', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_detailBody(), 201);
      });

      final ActivityDetailReport report = await api.createActivity(
        name: '秋夜長談',
        description: '第一段描述',
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, kAdminActivitiesPath);
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      // 沒有 status／id／created_by／archived_at 的格子：新建一律草稿、建立者來自憑據、
      // 標識與時刻各有唯一產生點。介面若在這裡多塞一欄，就是在替不存在的選項假造出口。
      expect(body.keys.toSet(), <String>{'name', 'description'});
      expect(report.activity.status, 'draft');
      expect(report.activity.managerCount, 1);
      expect(report.requestId, 'r-act');
    });

    test('Root 建的活動：建立者欄位缺席讀成 null，不補一個假標識', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_detailBody(rootCreated: true), 201),
      );
      final ActivityDetailReport report = await api.createActivity(
        name: 'Root 的活動',
        description: '',
      );
      expect(report.activity.createdByAccountId, isNull);
      expect(report.activity.archivedAt, isNull);
    });

    test('歸檔時刻只在歸檔後出現；未知新欄位容忍（後端只增不刪）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _detailBody(
            status: 'archived',
            archivedAt: '2026-10-10T05:00:00.000Z',
            extraField: '"next_season_field":42',
          ),
          200,
        ),
      );
      final ActivityDetailReport report = await api.activityDetail(
        activityId: _activityId,
      );
      expect(report.activity.isArchived, isTrue);
      expect(report.activity.archivedAt, isNotNull);
    });

    test('描述與狀態是必填：缺席判合同違例而不是降級成空值', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"activity":{"activity_id":"$_activityId","name":"缺欄",'
          '"manager_count":1,"created_at":"2026-10-10T03:00:00.000Z",'
          '"updated_at":"2026-10-10T03:00:00.000Z"},"request_id":"r-x"}',
          200,
        ),
      );
      expect(
        () => api.activityDetail(activityId: _activityId),
        throwsA(isA<ApiError>()),
      );
    });

    test('目錄發 GET 並帶三個查詢參數；空關鍵字不發 q', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(
          '{"activities":[${_activityJson()}],"page":2,"page_size":5,'
          '"total":6,"request_id":"r-dir"}',
          200,
        );
      });

      final ActivityDirectoryReport report = await api.activitiesDirectory(
        page: 2,
        pageSize: 5,
        status: 'active',
        query: '  ',
      );

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, kAdminActivitiesPath);
      expect(sent.single.url.queryParameters['page'], '2');
      expect(sent.single.url.queryParameters['page_size'], '5');
      expect(sent.single.url.queryParameters['status'], 'active');
      expect(sent.single.url.queryParameters.containsKey('q'), isFalse);
      expect(report.total, 6);
      expect(report.totalPages, 2);
      expect(report.hasMore, isFalse);
      expect(report.activities.single.name, '秋夜長談');
    });

    test('總數不為零而本頁為空時仍有頁數可言（空頁不是錯誤）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"activities":[],"page":7,"page_size":20,"total":3,"request_id":"r-dir"}',
          200,
        ),
      );
      final ActivityDirectoryReport report = await api.activitiesDirectory(
        page: 7,
      );
      expect(report.activities, isEmpty);
      expect(report.total, 3);
      expect(report.hasMore, isFalse);
    });
  });

  group('活動資料編輯與狀態轉換', () {
    test('updateActivityProfile 發 PUT 到詳情父路徑，本體是兩欄資料加兩個依據值', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_detailBody(status: 'active'), 200);
      });

      await api.updateActivityProfile(
        activityId: _activityId,
        name: '改過的名字',
        description: '改過的描述',
        expectedName: '秋夜長談',
        expectedDescription: '第一段描述',
      );

      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, adminActivityItemPath(_activityId));
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'name',
        'description',
        'expected_name',
        'expected_description',
      });
      // 狀態不在這條通路的白名單裡：混進來就會讓一次改名可以順手把歸檔的活動改回開放。
      expect(body.containsKey('status'), isFalse);
      expect(body.containsKey('activity_id'), isFalse);
    });

    test('updateActivityStatus 發 PUT 到 /status 子資源，本體只有目標狀態', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_detailBody(status: 'archived'), 200);
      });

      await api.updateActivityStatus(
        activityId: _activityId,
        status: 'archived',
      );

      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, adminActivityStatusPath(_activityId));
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      // 刻意不帶依據值：正當性錨在帶 WHERE 的單向更新上，現值已變由服務端答覆（2030）。
      expect(body.keys.toSet(), <String>{'status'});
    });

    test('活動標識進路徑時按 URL 規則編碼', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_detailBody(), 200);
      });
      await api.activityDetail(activityId: _otherActivityId);
      expect(sent.single.url.path.endsWith(_otherActivityId), isTrue);
    });
  });

  group('活動管理人名冊', () {
    test('名冊讀法打 /admin 那條子路徑，空清單是合法事實', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_rosterBody(<String>[]), 200);
      });

      final ActivityManagerRosterReport roster = await api.activityManagers(
        activityId: _activityId,
      );

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, adminActivityManagersPath(_activityId));
      expect(roster.managers, isEmpty);
      expect(roster.requestId, 'r-roster');
    });

    test('名冊行讀得出顯示名與帳戶現狀（終態仍列，界面據此標示只讀）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _rosterBody(<String>[
            _managerJson(),
            _managerJson(displayName: '', accountStatus: 'deleted'),
          ]),
          200,
        ),
      );
      final ActivityManagerRosterReport roster = await api.activityManagers(
        activityId: _activityId,
      );
      expect(roster.managers, hasLength(2));
      expect(roster.managers.first.accountStatus, 'active');
      expect(roster.managers.last.displayName, isEmpty);
      expect(roster.managers.last.accountStatus, 'deleted');
    });

    test('assignActivityManager 發 POST 到 /root，本體只有帳戶標識', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_detailBody(managerCount: 2), 200);
      });

      await api.assignActivityManager(
        activityId: _activityId,
        accountId: _accountId,
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, rootActivityManagersPath(_activityId));
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      // 沒有 role／granted_at／操作者的格子：誰在指派由那枚 Root 憑據決定。
      expect(body.keys.toSet(), <String>{'account_id'});
    });

    test('revokeActivityManager 發 DELETE、目標在路徑裡、本體為空', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_detailBody(managerCount: 0), 200);
      });

      await api.revokeActivityManager(
        activityId: _activityId,
        accountId: _accountId,
      );

      expect(sent.single.method, 'DELETE');
      expect(
        sent.single.url.path,
        rootActivityManagerItemPath(_activityId, _accountId),
      );
      expect(sent.single.body, isEmpty);
    });

    test('managers 不是一張清單就判合同違例（不降級成空名冊）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json('{"managers":"oops","request_id":"r-x"}', 200),
      );
      expect(
        () => api.activityManagers(activityId: _activityId),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('四枚新機器碼在前端各自成值', () {
    test('2029～2032 都收錄，且不退成未分類、也不與 2013／2014 混用', () {
      expect(ApiMachineCode.fromValue(2029), ApiMachineCode.activityArchived);
      expect(
        ApiMachineCode.fromValue(2030),
        ApiMachineCode.activityStatusConflict,
      );
      expect(
        ApiMachineCode.fromValue(2031),
        ApiMachineCode.activityTransitionInvalid,
      );
      expect(
        ApiMachineCode.fromValue(2032),
        ApiMachineCode.activityManagerTaken,
      );
      expect(ApiMachineCode.fromValue(2013), ApiMachineCode.profileConflict);
      expect(
        ApiMachineCode.fromValue(2014),
        ApiMachineCode.adminStatusConflict,
      );
    });

    test('失敗信封帶著 2029 時原樣保留碼值（界面才點得出是哪一句拒絕）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"code":2029,"message":"archived","request_id":"r-fail"}',
          409,
        ),
      );
      final Object? failure = await api
          .activityDetail(activityId: _activityId)
          .then<Object?>((_) => null)
          .catchError((Object? error) => error);
      expect(failure, isA<ApiError>());
      final ApiError error = failure! as ApiError;
      expect(error.knownCode, ApiMachineCode.activityArchived);
      expect(error.retryable, isFalse);
    });
  });
}
