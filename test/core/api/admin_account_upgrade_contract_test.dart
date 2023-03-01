/// 「訪戶原地升級」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：路徑與方法、請求欄位集合（只有 login_name 與 password，
/// 沒有也不准出現類型／角色／狀態／旗標／顯示名／依據值欄位）、回應的必填欄位、
/// 撤銷數量缺席判合同違例而不降級成 0、未知新欄位的容忍，以及機器碼 2024 的數值
/// 對應與「不可重試」。口令只進請求、永不進回應——斷言同時確認模型層也沒有格子可以存它。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 升級成功的回應本體（account 是轉正後的現值；與後端
/// standardAccountUpgradeResponse 同源）。
const String upgradeReportBody =
    '{"account":{"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"login_name":"Real.Upgrade.One","display_name":"保留名旅人",'
    '"account_type":"standard","status":"active","must_change_password":true,'
    '"created_at":"2026-10-02T08:00:00.000Z",'
    '"last_login_at":"2026-10-03T07:15:00.000Z"},'
    '"revoked_sessions":2,"request_id":"r-upgrade"}';

Future<ApiError> captureUpgradeFailure(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiError catch (error) {
    return error;
  }
  throw StateError('預期抛出 ApiError，卻拿到一次成功升級');
}

void main() {
  group('訪戶升級端點', () {
    test(
      'upgradeGuestAccount 發 PUT /admin/accounts/{id}/upgrade、本體恰好兩欄',
      () async {
        final List<http.Request> sent = <http.Request>[];
        final ServerApi api = apiWithHandler((http.Request request) async {
          sent.add(request);
          return http.Response(
            upgradeReportBody,
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        });

        final StandardAccountUpgradeReport report = await api
            .upgradeGuestAccount(
              accountId: '01a0e000-0000-7000-8000-0000000000aa',
              loginName: 'Real.Upgrade.One',
              password: '一次性升級口令',
            );

        expect(sent.single.method, 'PUT');
        expect(
          sent.single.url.path,
          adminAccountUpgradePath('01a0e000-0000-7000-8000-0000000000aa'),
        );
        final Map<String, Object?> body =
            jsonDecode(sent.single.body) as Map<String, Object?>;
        expect(body.keys.toSet(), <String>{'login_name', 'password'});
        expect(body['login_name'], 'Real.Upgrade.One');
        // 「升成哪一類主體」由端點決定：本體裡沒有也不准有多餘的宣稱格子。
        for (final String forbidden in <String>[
          'role',
          'roles',
          'account_type',
          'subject_kind',
          'status',
          'must_change_password',
          'display_name',
          'expected',
          'activity_id',
          'account_id',
        ]) {
          expect(sent.single.body, isNot(contains(forbidden)));
        }

        expect(
          report.account.accountId,
          '01a0e000-0000-7000-8000-0000000000aa',
        );
        expect(report.account.accountType, 'standard');
        expect(report.account.mustChangePassword, isTrue);
        expect(report.account.isGuest, isFalse);
        expect(report.revokedSessions, 2);
        expect(report.requestId, 'r-upgrade');
      },
    );

    test('回應合同沒有口令格子：模型讀得到轉正現值，卻無處存放憑據', () {
      final Map<String, Object?> json =
          jsonDecode(upgradeReportBody) as Map<String, Object?>;
      expect(json.keys, isNot(contains('password')));
      expect(json.keys, isNot(contains('password_hash')));
      expect(json.keys, isNot(contains('roles')));
      final StandardAccountUpgradeReport report =
          StandardAccountUpgradeReport.decode(json);
      expect(report.toString(), isNot(contains('一次性升級口令')));
      // 升級保留標識與顯示名（原地轉正的兩句正面陳述）。
      expect(report.account.displayName, '保留名旅人');
    });

    test('revoked_sessions 缺席判合同違例，不降級成 0', () async {
      final Map<String, Object?> missing =
          jsonDecode(upgradeReportBody) as Map<String, Object?>
            ..remove('revoked_sessions');
      final ServerApi harsh = apiWithHandler(
        (http.Request request) async => http.Response(
          jsonEncode(missing),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      final ApiError error = await captureUpgradeFailure(
        () => harsh.upgradeGuestAccount(
          accountId: '01a0e000-0000-7000-8000-0000000000aa',
          loginName: 'harsh.one',
          password: '一次性升級口令',
        ),
      );
      expect(error.kind, ApiErrorKind.invalidResponse);
    });

    test('未知新欄位容忍（只增不刪）', () async {
      final Map<String, Object?> withExtra =
          jsonDecode(upgradeReportBody) as Map<String, Object?>;
      withExtra['future_field'] = '日後後端多發的欄位不得讓整份解码失敗';
      final ServerApi tolerant = apiWithHandler(
        (http.Request request) async => http.Response(
          jsonEncode(withExtra),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      final StandardAccountUpgradeReport report = await tolerant
          .upgradeGuestAccount(
            accountId: '01a0e000-0000-7000-8000-0000000000aa',
            loginName: 'tolerant.one',
            password: '一次性升級口令',
          );
      expect(report.account.loginName, 'Real.Upgrade.One');
    });

    test('2024 有自己的碼：它是 2024，不是 2018、也不是 1001 那句「換目標」', () async {
      expect(ApiMachineCode.fromValue(2024), ApiMachineCode.guestNotUpgradable);
      expect(ApiMachineCode.guestNotUpgradable.value, 2024);
      // 2018 與 2024 是相反方向的兩句話，數值必須各自穩定。
      expect(ApiMachineCode.guestUpgradeRequired.value, 2018);

      final ServerApi api = apiWithHandler(
        (http.Request request) async => http.Response(
          '{"code":2024,"message":"not upgradable","request_id":"r-2024"}',
          409,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      final ApiError error = await captureUpgradeFailure(
        () => api.upgradeGuestAccount(
          accountId: '01a0e000-0000-7000-8000-0000000000aa',
          loginName: 'again.one',
          password: '一次性升級口令',
        ),
      );
      expect(error.knownCode, ApiMachineCode.guestNotUpgradable);
      // 原樣重發不會讓 2024 變好：它不屬於可重試的一族。
      expect(error.retryable, isFalse);
    });

    test('2012 走重名句：與 2024 分開，兩個處置不互換', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => http.Response(
          '{"code":2012,"message":"taken","request_id":"r-2012"}',
          409,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      final ApiError error = await captureUpgradeFailure(
        () => api.upgradeGuestAccount(
          accountId: '01a0e000-0000-7000-8000-0000000000aa',
          loginName: 'taken.name',
          password: '一次性升級口令',
        ),
      );
      expect(error.knownCode, ApiMachineCode.loginNameTaken);
      expect(error.retryable, isFalse);
    });
  });
}
