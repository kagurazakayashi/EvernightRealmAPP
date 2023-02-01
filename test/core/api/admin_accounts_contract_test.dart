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
}
