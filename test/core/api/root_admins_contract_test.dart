/// 「Root 管理員目錄與資料編輯」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：路徑、方法、請求欄位集合（沒有也不准出現角色／狀態／口令欄位）、
/// 回應必填欄位、可選欄位的缺席形態、分頁回顯的解碼，以及機器碼 2011／2012／2013 的
/// 數值對應。會話秘密與口令都不在這些回應裡——斷言同時確認模型層也沒有格子可以存它們。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 目錄行／詳情共用的單筆材料（granted_at 恆在；roles 只在單筆回應出現）。
Map<String, Object?> adminJson(
  String id,
  String login, {
  String display = '首任管理員',
  String status = 'active',
  bool mustChange = true,
  String? lastLogin,
  String? disabledAt,
  String? deletedAt,
  List<String>? roles,
}) {
  return <String, Object?>{
    'account_id': id,
    'login_name': login,
    'display_name': display,
    'status': status,
    'must_change_password': mustChange,
    'created_at': '2026-10-02T09:00:00.000Z',
    'granted_at': '2026-10-02T09:00:00.000Z',
    'last_login_at': ?lastLogin,
    'disabled_at': ?disabledAt,
    'deleted_at': ?deletedAt,
    'roles': ?roles,
  };
}

/// 開設成功的回應本體（全部可展示事實，沒有任何憑據欄位）。
const String createdAdminBody =
    '{"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"login_name":"Ops.Primary","display_name":"首任管理員",'
    '"status":"active","must_change_password":true,'
    '"roles":["server_admin"],'
    '"created_at":"2026-10-02T09:00:00.000Z","request_id":"r-create"}';

/// 目錄一頁的回應本體：第二項刻意不帶 last_login_at（從未登入）。
String directoryBody({
  int page = 2,
  int pageSize = 20,
  int total = 21,
  int rows = 2,
}) {
  final List<Map<String, Object?>> items = <Map<String, Object?>>[
    adminJson(
      '01a0e000-0000-7000-8000-0000000000aa',
      'Ops.Primary',
      lastLogin: '2026-10-02T09:30:00.000Z',
    ),
    adminJson('01a0e000-0000-7000-8000-0000000000bb', 'Ops.Second'),
  ];
  return jsonEncode(<String, Object?>{
    'admins': items.take(rows).toList(),
    'page': page,
    'page_size': pageSize,
    'total': total,
    'request_id': 'r-list',
  });
}

/// 單筆詳情／編輯結果的回應本體。
String profileBody({String display = '新顯示名', List<String>? roles}) {
  return jsonEncode(<String, Object?>{
    'admin': adminJson(
      '01a0e000-0000-7000-8000-0000000000aa',
      'Ops.Primary',
      display: display,
      roles: roles ?? <String>[kServerAdminRole],
    ),
    'request_id': 'r-profile',
  });
}

/// 登入成功回應（帶 roles 的形态）。
String loginBody({String? roles}) =>
    '{"subject_kind":"account","account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"device_id":"01a0e000-0000-7000-8000-0000000000cc",'
    '"expires_at":"2026-10-02T10:00:00.000Z",'
    '${roles == null ? '' : '"roles":$roles,'}'
    '"request_id":"r-login"}';

void main() {
  group('開設端點', () {
    test('createAdmin 發 POST、本體恰好三個欄位且沒有任何角色宣稱', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(
          createdAdminBody,
          201,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final CreatedAdminReport report = await api.createAdmin(
        loginName: 'Ops.Primary',
        displayName: '首任管理員',
        password: '一次性初始口令',
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, kRootAdminsPath);
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'login_name',
        'display_name',
        'password',
      });
      for (final String forbidden in <String>[
        'role',
        'roles',
        'account_type',
        'subject_kind',
        'status',
        'account_id',
      ]) {
        expect(sent.single.body, isNot(contains(forbidden)));
      }

      expect(report.accountId, '01a0e000-0000-7000-8000-0000000000aa');
      expect(report.mustChangePassword, isTrue);
      expect(report.roles, <String>[kServerAdminRole]);
      expect(report.createdAt, DateTime.utc(2026, 10, 2, 9));
      // 「回應裡沒有一個欄位裝得下口令」要看合同本身，而不是看模型的打印結果：
      // 後端回應的鍵集合就是這份證據，多出一個口令欄位時這條會紅。
      expect(
        (jsonDecode(createdAdminBody) as Map<String, Object?>).keys,
        unorderedEquals(<String>[
          'account_id',
          'login_name',
          'display_name',
          'status',
          'must_change_password',
          'roles',
          'created_at',
          'request_id',
        ]),
      );
    });
  });

  group('目錄端點', () {
    test('adminsDirectory 把分頁與篩選放在查詢串，並解碼伺服器回顯', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return jsonOk(directoryBody());
      });

      final AdminDirectoryReport report = await api.adminsDirectory(
        page: 2,
        status: 'disabled',
      );

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, kRootAdminsPath);
      expect(sent.single.url.queryParameters['page'], '2');
      expect(sent.single.url.queryParameters['status'], 'disabled');
      expect(report.admins, hasLength(2));
      expect(report.admins.first.loginName, 'Ops.Primary');
      expect(report.admins.first.lastLoginAt, DateTime.utc(2026, 10, 2, 9, 30));
      expect(report.admins.last.lastLoginAt, isNull);
      // 分頁三元組取伺服器回顯值，不是本地傳出去的那份（後端會收斂非法值）。
      expect(report.page, 2);
      expect(report.pageSize, 20);
      expect(report.total, 21);
      expect(report.totalPages, 2);
      expect(report.hasMore, isFalse);
      // 目錄行不重複攜帶角色：每行本來就是按授予查出來的。
      expect(report.admins.first.roles, isEmpty);
      expect(report.admins.first.grantedAt, DateTime.utc(2026, 10, 2, 9));
    });

    test('默認引數是 page=1、status=all，且本體不出現在 GET', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return jsonOk(directoryBody(page: 1, total: 0, rows: 0));
      });

      final AdminDirectoryReport report = await api.adminsDirectory();
      expect(sent.single.url.queryParameters['page'], '1');
      expect(sent.single.url.queryParameters['status'], 'all');
      expect(report.admins, isEmpty);
      // 零筆時第 1 頁仍是「空但存在」的頁：頁數至少 1、沒有後頁。
      expect(report.totalPages, 1);
      expect(report.hasMore, isFalse);
    });

    test('目錄形態不合時判合同違例，不降級成空清單', () {
      expect(
        () => AdminDirectoryReport.decode(<String, Object?>{
          'admins': 'not-a-list',
          'page': 1,
          'page_size': 20,
          'total': 0,
          'request_id': 'r',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
      // granted_at 在目錄行恆在：少了它就是合同抵觸，不靜默當「未知時刻」。
      expect(
        () => AdminAccountReport.decode(<String, Object?>{
          'account_id': 'a',
          'login_name': 'n',
          'display_name': 'd',
          'status': 'active',
          'must_change_password': false,
          'created_at': '2026-10-02T09:00:00.000Z',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
      expect(
        () => AdminDirectoryReport.decode(<String, Object?>{
          'admins': <Object?>[],
          'page': 1,
          'page_size': '20',
          'total': 0,
          'request_id': 'r',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('回應多出的未知欄位被容忍（只增不刪的兼容方向）', () {
      final AdminAccountReport row = AdminAccountReport.decode(
        <String, Object?>{
          ...adminJson('a', 'n'),
          'future_field': <String, Object?>{'nested': true},
        },
      );
      expect(row.accountId, 'a');
    });
  });

  group('單筆詳情與編輯端點', () {
    test('adminDetail 走 GET /root/admins/{id}，目標在路徑不在本體', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return jsonOk(profileBody(display: '首任管理員'));
      });

      final AdminDetailReport report = await api.adminDetail(
        accountId: '01a0e000-0000-7000-8000-0000000000aa',
      );
      expect(sent.single.method, 'GET');
      expect(
        sent.single.url.path,
        '$kRootAdminsPath/01a0e000-0000-7000-8000-0000000000aa',
      );
      expect(sent.single.body, isEmpty);
      expect(report.admin.displayName, '首任管理員');
      expect(report.admin.roles, <String>[kServerAdminRole]);
      expect(report.requestId, 'r-profile');
    });

    test('updateAdminProfile 發 PUT、本體恰好兩個欄位且無任何隱藏欄位格子', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return jsonOk(profileBody());
      });

      final AdminDetailReport report = await api.updateAdminProfile(
        accountId: '01a0e000-0000-7000-8000-0000000000aa',
        displayName: '新顯示名',
        expectedDisplayName: '首任管理員',
      );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        '$kRootAdminsPath/01a0e000-0000-7000-8000-0000000000aa',
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'display_name',
        'expected_display_name',
      });
      for (final String forbidden in <String>[
        'role',
        'roles',
        'status',
        'account_type',
        'subject_kind',
        'must_change_password',
        'password',
        'login_name',
        'account_id',
      ]) {
        expect(sent.single.body, isNot(contains(forbidden)));
      }
      // 成功句是「保存後的資料庫現值」：本測試的回應 displayName 與送出值同源，
      // 形態上模型只能從回應構造，沒有存放本地意圖的欄位。
      expect(report.admin.displayName, '新顯示名');
    });

    test('標識拼接經 URL 轉義：呼叫端塞進非法字串也改不了路徑結構', () {
      expect(rootAdminItemPath('a b/../c'), '$kRootAdminsPath/a%20b%2F..%2Fc');
    });

    test('1001（不存在與非成員同形）按機器碼取語意', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":1001,"message":"nope","request_id":"r-404"}',
          404,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      await expectLater(
        api.adminDetail(accountId: '01a0e000-0000-7000-8000-0000000000ff'),
        throwsA(
          predicate<ApiError>(
            (ApiError e) =>
                e.machineCode == ApiMachineCode.notFound.value &&
                e.httpStatus == 404,
          ),
        ),
      );
    });
  });

  group('狀態子資源端點', () {
    /// 狀態變更成功的回應本體：admin 與詳情同形，外加撤銷數量。
    String statusBody({
      String status = 'disabled',
      String? disabledAt = '2026-10-02T10:00:00.000Z',
      int revoked = 2,
    }) {
      final Map<String, Object?> admin = adminJson(
        '01a0e000-0000-7000-8000-0000000000aa',
        'Ops.Primary',
        status: status,
        roles: <String>[kServerAdminRole],
      );
      if (disabledAt != null) {
        admin['disabled_at'] = disabledAt;
      }
      return jsonEncode(<String, Object?>{
        'admin': admin,
        'revoked_sessions': revoked,
        'request_id': 'r-status',
      });
    }

    test('updateAdminStatus 發 PUT /status、本體恰好兩個欄位且沒有原因格子', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(
          statusBody(),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final AdminStatusReport report = await api.updateAdminStatus(
        accountId: '01a0e000-0000-7000-8000-0000000000aa',
        status: 'disabled',
        expectedStatus: 'active',
      );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        '$kRootAdminsPath/01a0e000-0000-7000-8000-0000000000aa/status',
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'status', 'expected_status'});
      for (final String forbidden in <String>[
        'reason',
        'display_name',
        'password',
        'must_change_password',
        'account_type',
        'account_id',
      ]) {
        expect(sent.single.body, isNot(contains(forbidden)));
      }

      expect(report.admin.status, 'disabled');
      expect(report.admin.disabledAt, DateTime.utc(2026, 10, 2, 10));
      expect(report.revokedSessions, 2);
      expect(report.requestId, 'r-status');
    });

    test('恢復形態：disabled_at 缺席讀成 null，撤銷數量如實解碼', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return http.Response(
          statusBody(status: 'active', disabledAt: null, revoked: 0),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final AdminStatusReport report = await api.updateAdminStatus(
        accountId: '01a0e000-0000-7000-8000-0000000000aa',
        status: 'active',
        expectedStatus: 'disabled',
      );
      expect(report.admin.status, 'active');
      expect(report.admin.disabledAt, isNull);
      expect(report.revokedSessions, 0);
    });

    test('狀態回應多出的未知欄位被容忍（只增不刪的兼容方向）', () {
      final Map<String, Object?> json =
          jsonDecode(statusBody()) as Map<String, Object?>;
      json['future_field'] = '不認識也要活著';
      (json['admin'] as Map<String, Object?>)['future_admin_field'] = 1;
      final AdminStatusReport report = AdminStatusReport.decode(json);
      expect(report.revokedSessions, 2);
    });

    test('revoked_sessions 缺席判合同違例，不降級成 0', () {
      final Map<String, Object?> json =
          jsonDecode(statusBody()) as Map<String, Object?>;
      json.remove('revoked_sessions');
      expect(
        () => AdminStatusReport.decode(json),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('標識經 URL 轉義後再拼 /status：路徑結構不受呼叫端內容影響', () {
      expect(
        rootAdminStatusPath('a b/../c'),
        '$kRootAdminsPath/a%20b%2F..%2Fc/status',
      );
    });

    test('2014 的數值對應不可漂走，且與 2013 各是各的碼', () {
      expect(
        ApiMachineCode.fromValue(2014),
        ApiMachineCode.adminStatusConflict,
      );
      expect(ApiMachineCode.adminStatusConflict.value, 2014);
      expect(
        ApiMachineCode.adminStatusConflict,
        isNot(ApiMachineCode.profileConflict),
      );
    });

    test('2014 按機器碼取語意，不靠 HTTP 狀態猜', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":2014,"message":"stale","request_id":"r-conflict"}',
          409,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      await expectLater(
        api.updateAdminStatus(
          accountId: '01a0e000-0000-7000-8000-0000000000aa',
          status: 'disabled',
          expectedStatus: 'active',
        ),
        throwsA(
          predicate<ApiError>(
            (ApiError e) =>
                e.knownCode == ApiMachineCode.adminStatusConflict &&
                e.httpStatus == 409,
          ),
        ),
      );
    });
  });

  group('憑據子資源端點', () {
    /// 憑據重置成功的回應本體：admin 與詳情同形，外加撤銷數量。
    String passwordResetBody({
      int revoked = 2,
      bool mustChange = true,
      String status = 'active',
    }) {
      final Map<String, Object?> admin = adminJson(
        '01a0e000-0000-7000-8000-0000000000ab',
        'Ops.Primary',
        status: status,
        mustChange: mustChange,
        roles: <String>[kServerAdminRole],
      );
      return jsonEncode(<String, Object?>{
        'admin': admin,
        'revoked_sessions': revoked,
        'request_id': 'r-reset',
      });
    }

    test('resetAdminPassword 發 PUT /password、本體恰好一個欄位且無依據值格子', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(
          passwordResetBody(),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final AdminPasswordResetReport report = await api.resetAdminPassword(
        accountId: '01a0e000-0000-7000-8000-0000000000ab',
        password: '一次性暫時口令',
      );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        '$kRootAdminsPath/01a0e000-0000-7000-8000-0000000000ab/password',
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      // 白名單只有口令一欄：沒有 expected_*、沒有狀態、沒有旗標的格子。
      expect(body.keys.toSet(), <String>{'password'});
      // 回應裡不許出現交付物：口令只在請求那一側出現一次。
      expect(sent.single.body, contains('一次性暫時口令'));
      expect(report.admin.mustChangePassword, isTrue);
      expect(report.revokedSessions, 2);
      expect(report.requestId, 'r-reset');
    });

    test('重置回應不含口令材料：解码面只有可展示事實', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return http.Response(
          passwordResetBody(revoked: 0, status: 'disabled'),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final AdminPasswordResetReport report = await api.resetAdminPassword(
        accountId: '01a0e000-0000-7000-8000-0000000000ab',
        password: 'x',
      );
      // 停用中的目標重置後仍停用（重置不是解除停用）；撤銷數量如實為 0。
      expect(report.admin.status, 'disabled');
      expect(report.revokedSessions, 0);
    });

    test('重置回應多出的未知欄位被容忍（只增不刪的兼容方向）', () {
      final Map<String, Object?> json =
          jsonDecode(passwordResetBody()) as Map<String, Object?>;
      json['future_field'] = '不認識也要活著';
      final AdminPasswordResetReport report = AdminPasswordResetReport.decode(
        json,
      );
      expect(report.revokedSessions, 2);
    });

    test('revoked_sessions 缺席判合同違例，不降級成 0', () {
      final Map<String, Object?> json =
          jsonDecode(passwordResetBody()) as Map<String, Object?>;
      json.remove('revoked_sessions');
      expect(
        () => AdminPasswordResetReport.decode(json),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('標識經 URL 轉義後再拼 /password：路徑結構不受呼叫端內容影響', () {
      expect(
        rootAdminPasswordPath('a b/../c'),
        '$kRootAdminsPath/a%20b%2F..%2Fc/password',
      );
    });

    test('1004 點名 password 由機器碼與 details 表達，不新造碼', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":1004,"message":"bad","details":{"invalid_field":"password"},"request_id":"r-bad"}',
          400,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      await expectLater(
        api.resetAdminPassword(
          accountId: '01a0e000-0000-7000-8000-0000000000ab',
          password: '',
        ),
        throwsA(
          predicate<ApiError>(
            (ApiError e) =>
                e.knownCode == ApiMachineCode.invalidBody &&
                e.details?['invalid_field'] == 'password',
          ),
        ),
      );
    });
  });

  group('刪除端點', () {
    /// 刪除成功的回應本體：admin 是刪除後的現值（佔位名＋刪除時刻），外加撤銷數量。
    String deleteBody({
      int revoked = 2,
      String status = 'deleted',
      String display = 'DEL_20261002_首任管理員',
      String? deletedAt = '2026-10-02T11:00:00.000Z',
    }) {
      return jsonEncode(<String, Object?>{
        'admin': adminJson(
          '01a0e000-0000-7000-8000-0000000000ab',
          'Ops.Primary',
          display: display,
          status: status,
          deletedAt: deletedAt,
          roles: <String>[kServerAdminRole],
        ),
        'revoked_sessions': revoked,
        'request_id': 'r-delete',
      });
    }

    test('deleteAdmin 發 DELETE 到單筆路徑、本體是空的（不選欄位也不交依據值）', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(
          deleteBody(),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final AdminDeleteReport report = await api.deleteAdmin(
        accountId: '01a0e000-0000-7000-8000-0000000000ab',
      );

      expect(sent.single.method, 'DELETE');
      expect(
        sent.single.url.path,
        '$kRootAdminsPath/01a0e000-0000-7000-8000-0000000000ab',
      );
      // 本體空著：刪除沒有欄位可填，也沒有 expected_* 那類格子。
      expect(sent.single.body, isEmpty);
      expect(report.admin.status, 'deleted');
      expect(report.admin.isDeleted, isTrue);
      expect(report.revokedSessions, 2);
      expect(report.requestId, 'r-delete');
    });

    test('刪除現值的三個欄位各自讀回：狀態、佔位名與刪除時刻不同源不成立', () async {
      final Map<String, Object?> json =
          jsonDecode(deleteBody()) as Map<String, Object?>;
      final AdminDeleteReport report = AdminDeleteReport.decode(json);
      expect(report.admin.isDeleted, isTrue);
      expect(report.admin.isActive, isFalse);
      expect(report.admin.displayName, 'DEL_20261002_首任管理員');
      // 登入名是歷史身份的承載者：它必須原樣還在，不是被佔位值替換的那一欄。
      expect(report.admin.loginName, 'Ops.Primary');
      expect(report.admin.deletedAt, isNotNull);
      expect(report.admin.deletedAt!.toUtc().hour, 11);
    });

    test('未刪除的行讀成「沒有刪除時刻」，不拿停用時刻或建立時刻冒充', () {
      final AdminAccountReport live = AdminAccountReport.decode(
        adminJson('01a0e000-0000-7000-8000-0000000000aa', 'Ops.Primary'),
      );
      expect(live.deletedAt, isNull);
      expect(live.isDeleted, isFalse);

      final AdminAccountReport stopped = AdminAccountReport.decode(
        adminJson(
          '01a0e000-0000-7000-8000-0000000000aa',
          'Ops.Primary',
          status: 'disabled',
          disabledAt: '2026-10-02T10:00:00.000Z',
        ),
      );
      // 停用不是刪除：兩個時刻各記各的事，isDeleted 只認狀態字串。
      expect(stopped.disabledAt, isNotNull);
      expect(stopped.deletedAt, isNull);
      expect(stopped.isDeleted, isFalse);
    });

    test('revoked_sessions 缺席判合同違例，不降級成 0', () {
      final Map<String, Object?> json =
          jsonDecode(deleteBody()) as Map<String, Object?>;
      json.remove('revoked_sessions');
      expect(
        () => AdminDeleteReport.decode(json),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('回應多出的未知欄位被容忍（只增不刪的兼容方向）', () {
      final Map<String, Object?> json =
          jsonDecode(deleteBody()) as Map<String, Object?>;
      json['future_field'] = '不認識也要活著';
      final AdminDeleteReport report = AdminDeleteReport.decode(json);
      expect(report.revokedSessions, 2);
    });

    test('標識經 URL 轉義：刪除目標不會被內容改寫成另一條路徑', () {
      expect(
        rootAdminItemPath('a/b?c'),
        '$kRootAdminsPath/${Uri.encodeComponent('a/b?c')}',
      );
      expect(rootAdminItemPath('a/b?c'), isNot(contains('a/b?c')));
    });

    test('2015 是 409 上的獨立語意，既不冒充 1001 也不冒充 2013／2014', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":2015,"message":"already deleted","request_id":"r-2015"}',
          409,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      await expectLater(
        api.deleteAdmin(accountId: '01a0e000-0000-7000-8000-0000000000ab'),
        throwsA(
          predicate<ApiError>(
            (ApiError e) =>
                e.knownCode == ApiMachineCode.adminDeleted &&
                e.machineCode == 2015 &&
                e.httpStatus == 409,
          ),
        ),
      );

      // 同一枚碼打在既有寫入通路上也是同一句話：介面分流不靠 HTTP 態猜。
      final ServerApi editApi = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":2015,"message":"already deleted","request_id":"r-2015b"}',
          409,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      await expectLater(
        editApi.updateAdminProfile(
          accountId: '01a0e000-0000-7000-8000-0000000000ab',
          displayName: '已刪除還想改名',
          expectedDisplayName: '首任管理員',
        ),
        throwsA(
          predicate<ApiError>(
            (ApiError e) => e.knownCode == ApiMachineCode.adminDeleted,
          ),
        ),
      );
    });
  });

  group('角色欄位', () {
    test('登入與當前會話讀到 roles 即認定管理員；欄位缺席即為空', () {
      final LoginReport withRole = LoginReport.decode(
        jsonDecode(loginBody(roles: '["server_admin"]'))
            as Map<String, Object?>,
      );
      expect(withRole.isServerAdmin, isTrue);
      expect(withRole.roles, <String>[kServerAdminRole]);

      final LoginReport withoutRole = LoginReport.decode(
        jsonDecode(loginBody()) as Map<String, Object?>,
      );
      expect(withoutRole.roles, isEmpty);
      expect(withoutRole.isServerAdmin, isFalse);
    });

    test('未來新增的角色值不讓整份回應解碼失敗', () {
      // 後端只增不刪：多發布一個角色時，前端該有的是「這一行我不認得」，
      // 而不是「連登入都進不去」。
      final LoginReport report = LoginReport.decode(
        jsonDecode(loginBody(roles: '["server_admin","activity_owner"]'))
            as Map<String, Object?>,
      );
      expect(report.roles, <String>[kServerAdminRole, 'activity_owner']);
      expect(report.isServerAdmin, isTrue);
    });
  });

  group('新增機器碼', () {
    test('2011、2012 與 2013 的數值對應不可漂走', () {
      expect(ApiMachineCode.fromValue(2011), ApiMachineCode.permissionDenied);
      expect(ApiMachineCode.fromValue(2012), ApiMachineCode.loginNameTaken);
      expect(ApiMachineCode.fromValue(2013), ApiMachineCode.profileConflict);
      expect(ApiMachineCode.permissionDenied.value, 2011);
      expect(ApiMachineCode.loginNameTaken.value, 2012);
      expect(ApiMachineCode.profileConflict.value, 2013);
      // 2015 是刪除終態的碼：它必須與 1001（不在目錄）、2013／2014（依據值過期）
      // 都不同——三者對介面的處置是三句話，混用任何一個都會把「別再寫他」說成別的事。
      expect(ApiMachineCode.fromValue(2015), ApiMachineCode.adminDeleted);
      expect(ApiMachineCode.adminDeleted.value, 2015);
      expect(
        ApiMachineCode.fromValue(1001),
        isNot(ApiMachineCode.adminDeleted),
      );
    });

    test('409 與 403 都按機器碼取語意，不靠 HTTP 狀態猜', () async {
      final ServerApi taken = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":2012,"message":"taken","request_id":"r-dup"}',
          409,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      await expectLater(
        taken.createAdmin(loginName: 'dup', displayName: '重複', password: '口令'),
        throwsA(
          predicate<ApiError>(
            (ApiError e) => e.machineCode == 2012 && e.httpStatus == 409,
          ),
        ),
      );

      final ServerApi conflict = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":2013,"message":"stale","request_id":"r-conflict"}',
          409,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      await expectLater(
        conflict.updateAdminProfile(
          accountId: '01a0e000-0000-7000-8000-0000000000aa',
          displayName: '再改一次',
          expectedDisplayName: '已經過期的現值',
        ),
        throwsA(
          predicate<ApiError>(
            (ApiError e) =>
                e.knownCode == ApiMachineCode.profileConflict &&
                e.httpStatus == 409,
          ),
        ),
      );

      final ServerApi denied = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":2011,"message":"denied","request_id":"r-403"}',
          403,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      await expectLater(
        denied.adminsDirectory(),
        throwsA(
          predicate<ApiError>(
            (ApiError e) => e.machineCode == 2011 && e.httpStatus == 403,
          ),
        ),
      );
    });
  });
}
