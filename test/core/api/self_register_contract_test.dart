/// 匿名自註冊合同（R2-011 後端發布的 `/auth/register` 與 `/auth/capabilities` 形態）
/// 在前端的鏡像測試。
///
/// 釘的是「合同」而不是畫面：成功回應必填欄位與取捨、請求本體只有三欄（沒有能把自註冊
/// 昇格成管理員的格子）、可判別機器碼→語意的對應（2019／2017／2016／2006／1004 點名欄位）、
/// 「成功不帶會話材料」這條既定語意，以及入口能力 sign_up_open 的嚴格解碼。
/// 頁面與狀態管理屬 register_page／register_entry_view 的 widget 測試，不在本檔範圍。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 註冊成功回應本體（標準／active／無需改密）。
const String registerSuccessBody =
    '{"account_id":"01a0e000-0000-7000-8000-0000000000ad",'
    '"login_name":"Std.First.Sign.In",'
    '"display_name":"首个自註冊帳戶",'
    '"status":"active",'
    '"must_change_password":false,'
    '"created_at":"2026-10-03T09:00:00.000Z",'
    '"request_id":"01a00000-0000-7000-8000-000000000001"}';

/// 一則指定狀態碼的 JSON 回應。
http.Response jsonStatus(String body, int status) {
  return http.Response(
    body,
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

void main() {
  group('SelfRegisterReport 嚴格解碼', () {
    test('成功回應全欄位可讀，must_change_password 恆 false', () {
      final SelfRegisterReport report = SelfRegisterReport.decode(
        jsonMapOf(registerSuccessBody),
      );
      expect(report.accountId, '01a0e000-0000-7000-8000-0000000000ad');
      expect(report.loginName, 'Std.First.Sign.In');
      expect(report.displayName, '首个自註冊帳戶');
      expect(report.status, 'active');
      expect(report.mustChangePassword, isFalse);
      expect(report.createdAt, DateTime.utc(2026, 10, 3, 9));
    });

    test('缺必填欄位即合同違例，不降級成預設值', () {
      final Map<String, Object?> missing = jsonMapOf(registerSuccessBody)
        ..remove('account_id');
      expect(
        () => SelfRegisterReport.decode(missing),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('must_change_password 非布林即違例（不把字串当成布爾）', () {
      final Map<String, Object?> odd = jsonMapOf(registerSuccessBody)
        ..['must_change_password'] = 'false';
      expect(
        () => SelfRegisterReport.decode(odd),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('created_at 缺時區標記即違例（大整數／時刻含糊不得被猜成有效）', () {
      final Map<String, Object?> naive = jsonMapOf(registerSuccessBody)
        ..['created_at'] = '2026-10-03T09:00:00';
      expect(
        () => SelfRegisterReport.decode(naive),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('未知新欄位被容忍（後端只增不刪）', () {
      final SelfRegisterReport report = SelfRegisterReport.decode(
        jsonMapOf(registerSuccessBody)..['future_field'] = 1,
      );
      expect(report.status, 'active');
    });
  });

  group('register 端點存取', () {
    test('POST /auth/register：三欄本體、無角色欄，201 只回報告', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        // 即使伺服器端硬塞一枚 Cookie，register() 走的也是非 captureCookie 那條：
        // 回傳型別只有 SelfRegisterReport，沒有任何會話秘密欄位能被交回呼叫端。
        return http.Response(
          registerSuccessBody,
          201,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
            'set-cookie':
                '$kSessionCookieName=should-be-ignored; Path=/; HttpOnly',
          },
        );
      });

      final SelfRegisterReport report = await api.register(
        loginName: 'Std.First.Sign.In',
        displayName: '首个自註冊帳戶',
        password: 'selfregister-自選口令',
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, kAuthRegisterPath);
      expect(sent.single.body, contains('"login_name":"Std.First.Sign.In"'));
      expect(sent.single.body, contains('"display_name"'));
      expect(sent.single.body, contains('"password"'));
      // 「建的是哪一類主體」由打到哪個端點決定：本體不得自報角色／類型。
      expect(sent.single.body, isNot(contains('role')));
      expect(sent.single.body, isNot(contains('account_type')));
      expect(report.mustChangePassword, isFalse);
      expect(report.status, 'active');
    });

    test('本體恰為三個白名單欄位，不含任何隱藏欄位', () async {
      late String capturedBody;
      final ServerApi api = apiWithHandler((http.Request request) async {
        capturedBody = request.body;
        return jsonStatus(registerSuccessBody, 201);
      });
      await api.register(loginName: 'a.b', displayName: 'AB', password: 'pw');

      final Map<String, Object?> decoded = jsonMapOf(capturedBody);
      expect(decoded.keys.toSet(), <String>{
        'login_name',
        'display_name',
        'password',
      });
    });

    test('invite 模式帶碼：本體多一格 invite_code 且原值遞交', () async {
      late String capturedBody;
      final ServerApi api = apiWithHandler((http.Request request) async {
        capturedBody = request.body;
        return jsonStatus(registerSuccessBody, 201);
      });
      await api.register(
        loginName: 'inv.it.ee',
        displayName: '受邀者',
        password: 'pw12345678',
        inviteCode: 'AbCdEfGhIjKlMnOpQrStUv',
      );

      final Map<String, Object?> decoded = jsonMapOf(capturedBody);
      expect(decoded.keys.toSet(), <String>{
        'login_name',
        'display_name',
        'password',
        'invite_code',
      });
      expect(decoded['invite_code'], 'AbCdEfGhIjKlMnOpQrStUv');
    });

    test('不帶碼（開放／核准）：缺席就不發這一格，而非發一個空字串', () async {
      late String capturedBody;
      final ServerApi api = apiWithHandler((http.Request request) async {
        capturedBody = request.body;
        return jsonStatus(registerSuccessBody, 201);
      });
      await api.register(
        loginName: 'open.user',
        displayName: '開放者',
        password: 'pw12345678',
        inviteCode: '',
      );

      final Map<String, Object?> decoded = jsonMapOf(capturedBody);
      expect(
        decoded.containsKey('invite_code'),
        isFalse,
        reason: '空字串等於不帶碼：不該把一個 invite_code 空格送進本體',
      );
      expect(
        capturedBody,
        isNot(contains('invite_code')),
        reason: '明文邀请码不得出现在不帶碼的本體裡',
      );
    });
  });

  group('register 錯誤對映', () {
    Future<ApiError> failure(int status, String envelope) {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => jsonStatus(envelope, status),
      );
      return captureApiError(
        () => api.register(
          loginName: 'a.b',
          displayName: 'AB',
          password: 'pw12345678',
        ),
      );
    }

    test('2019 重名 → selfRegisterNameTaken，可判別且不標為可重試', () async {
      final ApiError error = await failure(
        409,
        '{"code":2019,"message":"...","request_id":"r"}',
      );
      expect(error.machineCode, 2019);
      expect(error.knownCode, ApiMachineCode.selfRegisterNameTaken);
      // 重名的處置是「換名字」，不是「等一會兒再打同一個名字」——故不可重試。
      expect(error.retryable, isFalse);
    });

    test('2017 策略未開放 → accountCreationDisabled（非權限、非寫法）', () async {
      final ApiError error = await failure(
        403,
        '{"code":2017,"message":"...","request_id":"r"}',
      );
      expect(error.knownCode, ApiMachineCode.accountCreationDisabled);
      expect(error.retryable, isFalse);
    });

    test('2016 模式未落地 → accountPolicyModeUnavailable，與 2017 可判別', () async {
      final ApiError error = await failure(
        400,
        '{"code":2016,"message":"...","request_id":"r"}',
      );
      expect(error.knownCode, ApiMachineCode.accountPolicyModeUnavailable);
      expect(error.knownCode, isNot(ApiMachineCode.accountCreationDisabled));
    });

    test(
      '2023 invite 碼被拒 → inviteCodeRejected，與 2017/2019/2022 都可判別且不可重試',
      () async {
        final ApiError error = await failure(
          403,
          '{"code":2023,"message":"...","request_id":"r"}',
        );
        expect(error.machineCode, 2023);
        expect(error.knownCode, ApiMachineCode.inviteCodeRejected);
        // 四個 403／業務碼各成一句：准入被策略關（2017）、名字被佔（2019）、Root 撤銷（2022）
        // 都不是「你帶的碼不對」這一句。
        expect(error.knownCode, isNot(ApiMachineCode.accountCreationDisabled));
        expect(error.knownCode, isNot(ApiMachineCode.selfRegisterNameTaken));
        expect(error.knownCode, isNot(ApiMachineCode.inviteAlreadyRevoked));
        // 原樣重發同一枚無效碼不會變好——處置是去要一枚新的有效碼，故不可重試。
        expect(error.retryable, isFalse);
      },
    );

    test('2006 限流 → loginThrottled，標為可重試（處置是等一會兒）', () async {
      final ApiError error = await failure(
        429,
        '{"code":2006,"message":"...","request_id":"r"}',
      );
      expect(error.knownCode, ApiMachineCode.loginThrottled);
      expect(error.retryable, isTrue);
    });

    test('1004 點名欄位 → invalidBody，details 透傳 invalid_field', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => jsonStatus(
          '{"code":1004,"message":"...",'
          '"details":{"invalid_field":"password"},"request_id":"r"}',
          400,
        ),
      );
      final ApiError error = await captureApiError(
        () => api.register(loginName: 'a.b', displayName: 'AB', password: '短'),
      );
      expect(error.knownCode, ApiMachineCode.invalidBody);
      expect(error.details, isNotNull);
      expect(error.details!['invalid_field'], 'password');
    });

    test('2012（需已認證主體）與 2019（匿名）各是一枚碼，不互相冒充', () {
      expect(
        ApiMachineCode.fromValue(2019),
        ApiMachineCode.selfRegisterNameTaken,
      );
      expect(ApiMachineCode.fromValue(2012), ApiMachineCode.loginNameTaken);
      expect(
        ApiMachineCode.fromValue(2019),
        isNot(ApiMachineCode.loginNameTaken),
      );
    });
  });

  group('登入前入口能力 sign_up_open', () {
    test('GET /auth/capabilities 只讀三個布林', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return jsonOk(
          '{"sign_up_open":true,"invite_code_required":true,'
          '"guest_open":false,"request_id":"r"}',
        );
      });

      final EntryCapabilitiesReport report = await api.entryCapabilities();
      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, kAuthCapabilitiesPath);
      expect(report.entry.signUpOpen, isTrue);
      expect(report.entry.inviteCodeRequired, isTrue);
      expect(report.entry.guestOpen, isFalse);
    });

    test('缺任一布林即合同違例（界面不得猜一個入口答案）', () {
      expect(
        () => EntryCapabilitiesReport.decode(<String, Object?>{
          'sign_up_open': true,
          'guest_open': false,
          'request_id': 'r',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });
  });
}

/// 便於測試直接從 JSON 文字取可變 map。
Map<String, Object?> jsonMapOf(String body) {
  return jsonDecode(body) as Map<String, Object?>;
}

/// 執行一次預期失敗的請求並取回結構化錯誤；正常回傳時直接讓測試失敗。
Future<ApiError> captureApiError(Future<Object?> Function() run) async {
  try {
    await run();
  } on ApiError catch (error) {
    return error;
  }
  return fail('預期拋出 ApiError，卻正常取得回傳值');
}
