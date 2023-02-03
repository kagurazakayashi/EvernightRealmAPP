/// 「管理員建立普通帳戶」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：路徑、方法、請求欄位集合（沒有也不准出現角色／類型／
/// 狀態／活動標識欄位）、回應必填欄位與「沒有 roles 這一格」的形態、未知新欄位的
/// 容忍，以及機器碼 2017 的數值對應。口令只進請求、永不進回應——斷言同時確認
/// 模型層也沒有格子可以存它。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 建立成功的回應本體（恰好七鍵；與後端 createdStandardAccountResponse 同源）。
const String createdStandardBody =
    '{"account_id":"01a0e000-0000-7000-8000-0000000000ee",'
    '"login_name":"New.Player","display_name":"新玩家",'
    '"status":"active","must_change_password":true,'
    '"created_at":"2026-10-03T09:00:00.000Z","request_id":"r-std-create"}';

Future<ApiError> captureCreateFailure(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiError catch (error) {
    return error;
  }
  throw StateError('預期抛出 ApiError，卻拿到一次成功建立');
}

void main() {
  group('建立普通帳戶端點', () {
    test('createStandardAccount 發 POST /admin/accounts、本體恰好三個欄位', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(
          createdStandardBody,
          201,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final CreatedStandardAccountReport report = await api
          .createStandardAccount(
            loginName: 'New.Player',
            displayName: '新玩家',
            password: '一次性初始口令',
          );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, kAdminAccountsPath);
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'login_name',
        'display_name',
        'password',
      });
      // 「建的是哪一類主體」由端點決定：本體裡沒有也不准有多餘的宣稱格子。
      for (final String forbidden in <String>[
        'role',
        'roles',
        'account_type',
        'subject_kind',
        'status',
        'must_change_password',
        'activity_id',
        'account_id',
      ]) {
        expect(sent.single.body, isNot(contains(forbidden)));
      }

      expect(report.accountId, '01a0e000-0000-7000-8000-0000000000ee');
      expect(report.loginName, 'New.Player');
      expect(report.displayName, '新玩家');
      expect(report.status, 'active');
      expect(report.mustChangePassword, isTrue);
      expect(report.createdAt, DateTime.utc(2026, 10, 3, 9));
      expect(report.requestId, 'r-std-create');
    });

    test('回應合同沒有 roles：建的帳戶恆無授予，模型也沒有格子可存', () {
      final Map<String, Object?> json =
          jsonDecode(createdStandardBody) as Map<String, Object?>;
      expect(json.keys, isNot(contains('roles')));
      expect(json.keys, isNot(contains('activity_id')));
      // 成功回應不含口令欄位（must_change_password 是旗標名，不是口令值本身）。
      expect(createdStandardBody, isNot(contains('"password"')));
      final CreatedStandardAccountReport report =
          CreatedStandardAccountReport.decode(json);
      expect(report.toString(), isNot(contains('一次性初始口令')));
    });

    test('未知新欄位容忍（只增不刪），必填欄位缺席判合同違例', () async {
      final Map<String, Object?> withExtra =
          jsonDecode(createdStandardBody) as Map<String, Object?>;
      withExtra['future_field'] = '日後後端多發的欄位不得讓整份解码失敗';
      final ServerApi tolerant = apiWithHandler(
        (http.Request request) async => http.Response(
          jsonEncode(withExtra),
          201,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      final CreatedStandardAccountReport report = await tolerant
          .createStandardAccount(
            loginName: 'tolerant.one',
            displayName: '容忍測試',
            password: '一次性初始口令',
          );
      expect(report.accountId, '01a0e000-0000-7000-8000-0000000000ee');

      final Map<String, Object?> missing = Map<String, Object?>.from(withExtra)
        ..remove('must_change_password');
      final ServerApi harsh = apiWithHandler(
        (http.Request request) async => http.Response(
          jsonEncode(missing),
          201,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      final ApiError error = await captureCreateFailure(
        () => harsh.createStandardAccount(
          loginName: 'harsh.one',
          displayName: '必填缺席',
          password: '一次性初始口令',
        ),
      );
      expect(error.kind, ApiErrorKind.invalidResponse);
    });

    test('2017 有自己的碼：它不是 2011，也不是 1004 那句「格式不對」', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => http.Response(
          '{"code":2017,"message":"x","request_id":"r-err"}',
          403,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      final ApiError error = await captureCreateFailure(
        () => api.createStandardAccount(
          loginName: 'gated.one',
          displayName: '會被擋',
          password: '一次性初始口令',
        ),
      );
      expect(error.machineCode, 2017);
      expect(error.knownCode, ApiMachineCode.accountCreationDisabled);
      expect(
        ApiMachineCode.fromValue(2017),
        ApiMachineCode.accountCreationDisabled,
      );
      // 數值不得與已發布碼相撞：2011／2016 仍是原本那兩句話。
      expect(ApiMachineCode.fromValue(2011), ApiMachineCode.permissionDenied);
      expect(
        ApiMachineCode.fromValue(2016),
        ApiMachineCode.accountPolicyModeUnavailable,
      );
    });

    test('路徑常量逐字等於後端登記：/admin/accounts', () {
      expect(kAdminAccountsPath, '/admin/accounts');
    });
  });

  group('普通帳戶目錄與資料編輯端點', () {
    test('目錄發 GET 並帶篩選參數，空關鍵字不帶 q', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(_directoryBody, 200, headers: _jsonHeaders);
      });

      await api.standardAccountsDirectory(
        page: 2,
        pageSize: 5,
        status: 'disabled',
        type: 'guest',
        query: '  ',
      );
      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, kAdminAccountsPath);
      final Map<String, String> query = Map<String, String>.from(
        sent.single.url.queryParameters,
      );
      expect(query['page'], '2');
      expect(query['page_size'], '5');
      expect(query['status'], 'disabled');
      expect(query['type'], 'guest');
      // 純空白等價於「沒帶」：不發一個注定全空的 q=，也不發一個空字串的 q=。
      expect(query.containsKey('q'), isFalse);

      await api.standardAccountsDirectory(query: '阿爾法%_');
      final Map<String, String> withKeyword = Map<String, String>.from(
        sent.last.url.queryParameters,
      );
      // 關鍵字原樣送達（編碼由 Uri 負責，萬用字元由後端按字面比對）。
      expect(withKeyword['q'], '阿爾法%_');
    });

    test('目錄回應恰好五鍵、行欄位是白名單，且沒有任何憑據格子', () {
      final Map<String, Object?> json =
          jsonDecode(_directoryBody) as Map<String, Object?>;
      expect(json.keys.toSet(), <String>{
        'accounts',
        'page',
        'page_size',
        'total',
        'request_id',
      });
      final StandardAccountDirectoryReport report =
          StandardAccountDirectoryReport.decode(json);
      expect(report.total, 2);
      expect(report.totalPages, 1);
      expect(report.hasMore, isFalse);
      final StandardAccountReport first = report.accounts.first;
      expect(first.accountId, _firstId);
      expect(first.accountType, 'standard');
      expect(first.isActive, isTrue);
      expect(first.lastLoginAt, isNull);
      final StandardAccountReport second = report.accounts.last;
      expect(second.isGuest, isTrue);
      expect(second.disabledAt, DateTime.utc(2026, 10, 2, 9, 30));

      // 這本目錄的定義就是「沒有伺服器級授予」：回應裡不該有授予與角色欄位，
      // 也不該有刪除時刻（那些行根本不在範圍內）。
      expect(_directoryBody, isNot(contains('granted_at')));
      expect(_directoryBody, isNot(contains('roles')));
      expect(_directoryBody, isNot(contains('deleted_at')));
      expect(_directoryBody, isNot(contains('password_hash')));
      expect(_directoryBody, isNot(contains('login_name_key')));
      expect(first.toString(), isNot(contains('argon2id')));
    });

    test('未知新欄位容忍、必填欄位缺席判合同違例（目錄與單筆同一取向）', () {
      final Map<String, Object?> tolerant =
          jsonDecode(_directoryBody) as Map<String, Object?>;
      final Map<String, Object?> row =
          (tolerant['accounts'] as List<Object?>).first as Map<String, Object?>;
      row['future_field'] = '後端日後多發的欄位不得讓整頁解碼失敗';
      expect(StandardAccountDirectoryReport.decode(tolerant).total, 2);

      final Map<String, Object?> missing =
          jsonDecode(_directoryBody) as Map<String, Object?>;
      final Map<String, Object?> missingRow =
          (missing['accounts'] as List<Object?>).first as Map<String, Object?>;
      missingRow.remove('account_type');
      expect(
        () => StandardAccountDirectoryReport.decode(missing),
        throwsA(isA<ApiResponseShapeException>()),
      );

      final Map<String, Object?> detail =
          jsonDecode(_detailBody) as Map<String, Object?>;
      (detail['account'] as Map<String, Object?>).remove('status');
      expect(
        () => StandardAccountDetailReport.decode(detail),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('單筆路徑把標識當路徑段：編碼後不越界，也不帶本體欄位', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(_detailBody, 200, headers: _jsonHeaders);
      });

      await api.standardAccountDetail(accountId: _firstId);
      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, '$kAdminAccountsPath/$_firstId');
      expect(adminAccountItemPath(_firstId), '/admin/accounts/$_firstId');
      // 企圖越界（路徑穿越與查詢串分隔符）被編碼進單一路徑段，不會多出一段。
      final String escaped = adminAccountItemPath('../../etc/x?q=1');
      expect(escaped.startsWith('/admin/accounts/'), isTrue);
      // 斜線與問號都被編碼進同一個路徑段：路徑仍是「/admin/accounts/<一段>」四段，
      // 不會多出第四個語意段，也不會開出一個查詢字串。
      expect(escaped.split('/').length, 4);
      expect(escaped, isNot(contains('?')));

      final StandardAccountDetailReport report = await api
          .standardAccountDetail(accountId: _firstId);
      expect(report.account.displayName, '服務端的現在顯示名');
      expect(report.requestId, 'r-detail');
    });

    test('編輯本體恰好兩欄：憑據、狀態、類型與活動都沒有格子', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(_detailBody, 200, headers: _jsonHeaders);
      });

      await api.updateStandardAccountProfile(
        accountId: _firstId,
        displayName: '新顯示名',
        expectedDisplayName: '服務端的現在顯示名',
      );
      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, '$kAdminAccountsPath/$_firstId');
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'display_name',
        'expected_display_name',
      });
      for (final String forbidden in <String>[
        'role',
        'roles',
        'account_type',
        'status',
        'subject_kind',
        'must_change_password',
        'password',
        'password_hash',
        'login_name',
        'activity_id',
        'account_id',
      ]) {
        expect(body, isNot(contains(forbidden)));
      }
    });

    test('本步不新增機器碼：併發衝突仍是 2013，目標不在目錄仍是 1001', () async {
      final ServerApi conflict = apiWithHandler(
        (http.Request request) async => http.Response(
          '{"code":2013,"message":"x","request_id":"r-c"}',
          409,
          headers: _jsonHeaders,
        ),
      );
      final ApiError profileConflict = await captureCreateFailure(
        () => conflict.updateStandardAccountProfile(
          accountId: _firstId,
          displayName: '再改一次',
          expectedDisplayName: '已過期的現值',
        ),
      );
      expect(profileConflict.machineCode, 2013);
      expect(profileConflict.knownCode, ApiMachineCode.profileConflict);
      expect(ApiMachineCode.fromValue(2013), ApiMachineCode.profileConflict);

      final ServerApi missing = apiWithHandler(
        (http.Request request) async => http.Response(
          '{"code":1001,"message":"x","request_id":"r-n"}',
          404,
          headers: _jsonHeaders,
        ),
      );
      final ApiError notFound = await captureCreateFailure(
        () => missing.standardAccountDetail(accountId: _firstId),
      );
      expect(notFound.knownCode, ApiMachineCode.notFound);
      // 已發布碼各歸各：2014／2015 仍是管理員那兩句話，本步沒有複用它們。
      expect(
        ApiMachineCode.fromValue(2014),
        ApiMachineCode.adminStatusConflict,
      );
      expect(ApiMachineCode.fromValue(2015), ApiMachineCode.adminDeleted);
    });
  });
}

/// JSON 內容型別標頭（假傳輸共用）。
const Map<String, String> _jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};

/// 目錄測試用的帳戶標識與一頁合同样本：一行普通帳戶、一行訪客帳戶（含 disabled_at）。
const String _firstId = '01a0e000-0000-7000-8000-0000000000aa';
const String _directoryBody =
    '{"accounts":['
    '{"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"login_name":"alpha.player","display_name":"阿爾法",'
    '"account_type":"standard","status":"active",'
    '"must_change_password":true,"created_at":"2026-10-02T08:00:00.000Z"},'
    '{"account_id":"01a0e000-0000-7000-8000-0000000000bb",'
    '"login_name":"beta.guest","display_name":"訪客乙","account_type":"guest",'
    '"status":"disabled","must_change_password":false,'
    '"created_at":"2026-10-01T08:00:00.000Z",'
    '"disabled_at":"2026-10-02T09:30:00.000Z"}],'
    '"page":1,"page_size":20,"total":2,"request_id":"r-dir"}';

/// 單筆詳情的合同样本（顯示名刻意與目錄行不同，供界面分流斷言）。
const String _detailBody =
    '{"account":{"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"login_name":"alpha.player","display_name":"服務端的現在顯示名",'
    '"account_type":"standard","status":"active","must_change_password":false,'
    '"created_at":"2026-10-02T08:00:00.000Z",'
    '"last_login_at":"2026-10-03T07:15:00.000Z"},"request_id":"r-detail"}';
