/// 「管理員建立普通帳戶」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：路徑、方法、請求欄位集合（沒有也不准出現角色／類型／
/// 狀態／活動標識欄位）、回應必填欄位與「沒有 roles 這一格」的形態、未知新欄位的
/// 容忍，以及機器碼 2017 與 2018 的數值對應。口令只進請求、永不進回應——斷言同時確認
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
      // 已發布碼各歸各：2015 仍是 Root 管理員目錄那句「已被刪除」，
      // 普通帳戶目錄不複用它（那本目錄按定義不列刪除態，出局就是 1001）。
      expect(ApiMachineCode.fromValue(2015), ApiMachineCode.adminDeleted);
    });
  });

  group('普通帳戶登入狀態子資源端點', () {
    test('狀態路徑是父路徑下的 /status，標識經編碼不越界', () async {
      expect(
        adminAccountStatusPath(_firstId),
        '$kAdminAccountsPath/$_firstId/status',
      );
      // 呼叫端塞進路徑段 separator 時不產生第二條路由（轉義不是修飾）。
      expect(adminAccountStatusPath('a/b'), '$kAdminAccountsPath/a%2Fb/status');

      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(_statusBody, 200, headers: _jsonHeaders);
      });
      await api.updateStandardAccountStatus(
        accountId: _firstId,
        status: 'disabled',
        expectedStatus: 'active',
      );
      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, adminAccountStatusPath(_firstId));
    });

    test('狀態本體恰好兩欄：顯示名、憑據、類型、角色與活動都沒有格子', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(_statusBody, 200, headers: _jsonHeaders);
      });
      await api.updateStandardAccountStatus(
        accountId: _firstId,
        status: 'active',
        expectedStatus: 'disabled',
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'status', 'expected_status'});
      for (final String forbidden in <String>[
        'display_name',
        'expected_display_name',
        'password',
        'password_hash',
        'account_type',
        'must_change_password',
        'roles',
        'subject_kind',
        'account_id',
        'activity_id',
        'reason',
        'purge',
      ]) {
        expect(body, isNot(contains(forbidden)));
      }
    });

    test('撤銷數量是必填合同欄：缺席判違例，不降級成 0', () {
      // 「這次讓幾臺裝置重新登入」是影響範圍的陳述，讀成 0 等於謊報沒人受影響。
      expect(
        () => StandardAccountStatusReport.decode(
          jsonDecode(
            '{"account":{'
            '"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
            '"login_name":"alpha.player","display_name":"阿爾法",'
            '"account_type":"standard","status":"disabled",'
            '"must_change_password":false,'
            '"created_at":"2026-10-02T08:00:00.000Z"},'
            '"request_id":"r-s"}',
          ) as Map<String, Object?>,
        ),
        throwsA(isA<ApiResponseShapeException>()),
      );
      // 未知新欄位容忍（只增不刪），而 account 缺席仍是違例。
      final String tolerantBody =
          '${_statusBody.substring(0, _statusBody.length - 1)},"future_field":{"a":1}}';
      final StandardAccountStatusReport tolerant =
          StandardAccountStatusReport.decode(
            jsonDecode(tolerantBody) as Map<String, Object?>,
          );
      expect(tolerant.revokedSessions, 3);
      expect(tolerant.account.status, 'disabled');
      expect(tolerant.account.disabledAt, isNotNull);
      expect(tolerant.account.isDisabled, isTrue);
      expect(tolerant.account.isActive, isFalse);
      expect(
        () => StandardAccountStatusReport.decode(
          jsonDecode('{"revoked_sessions":1,"request_id":"r"}')
              as Map<String, Object?>,
        ),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('狀態那一側不新增機器碼：衝突複用 2014，2018 由憑據重置那一步認領', () async {
      final ServerApi stale = apiWithHandler(
        (http.Request request) async => http.Response(
          '{"code":2014,"message":"x","request_id":"r-s"}',
          409,
          headers: _jsonHeaders,
        ),
      );
      final ApiError conflict = await captureCreateFailure(
        () => stale.updateStandardAccountStatus(
          accountId: _firstId,
          status: 'disabled',
          expectedStatus: 'active',
        ),
      );
      expect(conflict.machineCode, 2014);
      expect(conflict.knownCode, ApiMachineCode.adminStatusConflict);
      // 2018 不是「無人認領」了：它是憑據重置那條通路對訪戶目標的獨立結論，
      // 由下一組測試認領；這裡只確認狀態那一側仍然只有 2014 那一句。
      expect(
        ApiMachineCode.fromValue(2018),
        ApiMachineCode.guestUpgradeRequired,
      );
      expect(
        ApiMachineCode.fromValue(2019),
        ApiMachineCode.selfRegisterNameTaken,
      );
    });
  });

  group('憑據重置子資源端點', () {
    test('adminAccountPasswordPath 落在普通帳戶那條路徑族且轉義標識', () {
      expect(
        adminAccountPasswordPath(_firstId),
        '$kAdminAccountsPath/$_firstId/password',
      );
      // 與管理員那條同形但分屬兩組端點：前綴必須是 /admin/accounts，不是 /root/admins。
      expect(
        adminAccountPasswordPath(_firstId),
        isNot(equals(rootAdminPasswordPath(_firstId))),
      );
      expect(
        adminAccountPasswordPath('a/b'),
        '$kAdminAccountsPath/a%2Fb/password',
      );
    });

    test('resetStandardAccountPassword 發 PUT，本體恰好 password 一欄', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(_resetBody, 200, headers: _jsonHeaders);
      });
      final StandardAccountPasswordResetReport report = await api
          .resetStandardAccountPassword(
            accountId: _firstId,
            password: '一次性重置口令',
          );
      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, adminAccountPasswordPath(_firstId));
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'password'});
      // 刻意沒有依據值：也沒有狀態、旗標、類型、角色與活動的格子。
      for (final String forbidden in <String>[
        'expected_password',
        'expected_status',
        'status',
        'display_name',
        'must_change_password',
        'account_type',
        'roles',
        'subject_kind',
        'account_id',
        'activity_id',
        'reason',
        'password_hash',
      ]) {
        expect(body, isNot(contains(forbidden)));
      }
      expect(report.revokedSessions, 2);
      expect(report.account.mustChangePassword, isTrue);
      expect(report.account.status, 'active');
    });

    test('撤銷數量是必填合同欄：缺席判違例，未知新欄位容忍', () {
      // 缺席讀成 0 等於對操作者謊報「沒有別人因此被登出」，而那正是重置最要緊的一半效果。
      expect(
        () => StandardAccountPasswordResetReport.decode(
          jsonDecode(
            '{"account":{'
            '"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
            '"login_name":"alpha.player","display_name":"阿爾法",'
            '"account_type":"standard","status":"active",'
            '"must_change_password":true,'
            '"created_at":"2026-10-02T08:00:00.000Z"},'
            '"request_id":"r-p"}',
          ) as Map<String, Object?>,
        ),
        throwsA(isA<ApiResponseShapeException>()),
      );
      final String tolerantBody =
          '${_resetBody.substring(0, _resetBody.length - 1)},"future_field":{"a":1}}';
      final StandardAccountPasswordResetReport tolerant =
          StandardAccountPasswordResetReport.decode(
            jsonDecode(tolerantBody) as Map<String, Object?>,
          );
      expect(tolerant.revokedSessions, 2);
      expect(tolerant.requestId, 'r-reset');
      expect(
        () => StandardAccountPasswordResetReport.decode(
          jsonDecode('{"revoked_sessions":1,"request_id":"r"}')
              as Map<String, Object?>,
        ),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('2018 有自己的語意：它不是 1001、不是 1004、也不是 2011', () async {
      final ServerApi guest = apiWithHandler(
        (http.Request request) async => http.Response(
          '{"code":2018,"message":"x","request_id":"r-g"}',
          403,
          headers: _jsonHeaders,
        ),
      );
      final ApiError refused = await captureCreateFailure(
        () => guest.resetStandardAccountPassword(
          accountId: _firstId,
          password: '一次性重置口令',
        ),
      );
      expect(refused.machineCode, 2018);
      expect(refused.knownCode, ApiMachineCode.guestUpgradeRequired);
      expect(refused.knownCode, isNot(ApiMachineCode.notFound));
      expect(refused.knownCode, isNot(ApiMachineCode.permissionDenied));

      // 口令不合規走 1004 並點名 password：那句話的處置是改口令，不是等升級通路。
      final ServerApi invalid = apiWithHandler(
        (http.Request request) async => http.Response(
          '{"code":1004,"message":"x","details":{"invalid_field":"password"},'
          '"request_id":"r-b"}',
          400,
          headers: _jsonHeaders,
        ),
      );
      final ApiError bad = await captureCreateFailure(
        () => invalid.resetStandardAccountPassword(
          accountId: _firstId,
          password: '',
        ),
      );
      expect(bad.knownCode, ApiMachineCode.invalidBody);
      expect(bad.details?['invalid_field'], 'password');
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

/// 狀態變更成功的合同樣本：account 是「變更後」的現值（disabled 帶停用時刻），
/// revoked_sessions 必填（缺席即合同違例，見對應測試）。
const String _statusBody =
    '{"account":{"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"login_name":"alpha.player","display_name":"服務端的現在顯示名",'
    '"account_type":"standard","status":"disabled","must_change_password":true,'
    '"created_at":"2026-10-02T08:00:00.000Z",'
    '"disabled_at":"2026-10-03T09:30:00.000Z"},'
    '"revoked_sessions":3,"request_id":"r-status"}';

/// 憑據重置成功的合同樣本：account 是「重置之後」的現值（must_change_password 恆為真、
/// status 保持原樣），revoked_sessions 必填。回應裡沒有任何口令格子。
const String _resetBody =
    '{"account":{"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"login_name":"alpha.player","display_name":"服務端的現在顯示名",'
    '"account_type":"standard","status":"active","must_change_password":true,'
    '"created_at":"2026-10-02T08:00:00.000Z"},'
    '"revoked_sessions":2,"request_id":"r-reset"}';
