/// 「Root 開設管理員」兩條端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：路徑、方法、請求欄位集合（沒有也不准出現角色欄位）、
/// 回應必填欄位、可選欄位的缺席形態，以及新增機器碼 2011／2012 的數值對應。
/// 會話秘密與口令都不在這些回應裡——斷言同時確認模型層也沒有格子可以存它們。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 開設成功的回應本體（全部可展示事實，沒有任何憑據欄位）。
const String createdAdminBody =
    '{"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"login_name":"Ops.Primary","display_name":"首任管理員",'
    '"status":"active","must_change_password":true,'
    '"roles":["server_admin"],'
    '"created_at":"2026-10-02T09:00:00.000Z","request_id":"r-create"}';

/// 確認清單的回應本體：第二項刻意不帶 last_login_at（從未登入）。
const String adminListBody =
    '{"admins":['
    '{"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"login_name":"Ops.Primary","display_name":"首任管理員","status":"active",'
    '"must_change_password":true,"created_at":"2026-10-02T09:00:00.000Z",'
    '"last_login_at":"2026-10-02T09:30:00.000Z"},'
    '{"account_id":"01a0e000-0000-7000-8000-0000000000bb",'
    '"login_name":"Ops.Second","display_name":"次任管理員","status":"active",'
    '"must_change_password":false,"created_at":"2026-10-02T09:10:00.000Z"}'
    '],"request_id":"r-list"}';

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

    test('admins 發 GET 並保留後端順序；从未登入那筆的時刻為 null', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return jsonOk(adminListBody);
      });

      final AdminListReport report = await api.admins();

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, kRootAdminsPath);
      expect(sent.single.url.query, isEmpty);
      expect(report.admins, hasLength(2));
      expect(report.admins.first.loginName, 'Ops.Primary');
      expect(report.admins.first.lastLoginAt, DateTime.utc(2026, 10, 2, 9, 30));
      expect(report.admins.last.lastLoginAt, isNull);
      expect(report.admins.last.isActive, isTrue);
    });

    test('清單形態不合時判合同違例，不降級成空清單', () {
      expect(
        () => AdminListReport.decode(<String, Object?>{
          'admins': 'not-a-list',
          'request_id': 'r',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
      expect(
        () => AdminAccountReport.decode(<String, Object?>{
          'account_id': 'a',
          'login_name': 'n',
          'display_name': 'd',
          'status': 'active',
          'must_change_password': 'yes',
          'created_at': '2026-10-02T09:00:00.000Z',
        }),
        throwsA(isA<ApiResponseShapeException>()),
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
    test('2011 與 2012 的數值對應不可漂走', () {
      expect(ApiMachineCode.fromValue(2011), ApiMachineCode.permissionDenied);
      expect(ApiMachineCode.fromValue(2012), ApiMachineCode.loginNameTaken);
      expect(ApiMachineCode.permissionDenied.value, 2011);
      expect(ApiMachineCode.loginNameTaken.value, 2012);
    });

    test('409 與 403 都按機器碼取語意，不靠 HTTP 狀態猜', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":2012,"message":"taken","request_id":"r-dup"}',
          409,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      await expectLater(
        api.createAdmin(loginName: 'dup', displayName: '重複', password: '口令'),
        throwsA(
          isA<ApiError>().having(
            (ApiError e) => e.knownCode,
            'knownCode',
            ApiMachineCode.loginNameTaken,
          ),
        ),
      );
    });
  });
}
