/// 待審批申請的受限狀態查詢合同（R2-012 後端發布的 `/auth/registration-status` 形態）
/// 在前端的鏡像測試。
///
/// 釘的是「合同」而不是畫面：成功回應必填與可缺席欄位的取捨、請求本體只有兩欄
/// （沒有「申請編號」「帳戶標識」這類能指向別人的格子）、可判別機器碼→語意的對應
/// （2001／2020／2006／1004）、以及「驗證憑據但刻意不簽發會話」這條本步最要緊的語意。
/// 頁面與交互屬 application_status_page 的 widget 測試，不在本檔範圍。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 待審批的成功回應本體（沒有決定時刻那一欄）。
const String pendingStatusBody =
    '{"outcome":"pending",'
    '"submitted_at":"2026-10-03T09:00:00.000Z",'
    '"request_id":"01a00000-0000-7000-8000-000000000002"}';

/// 已批准的成功回應本體（帶決定時刻）。
const String approvedStatusBody =
    '{"outcome":"approved",'
    '"submitted_at":"2026-10-03T09:00:00.000Z",'
    '"reviewed_at":"2026-10-04T11:30:00.000Z",'
    '"request_id":"01a00000-0000-7000-8000-000000000003"}';

/// 一則指定狀態碼的 JSON 回應。
http.Response statusJson(String body, int status) {
  return http.Response(
    body,
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

/// 把 JSON 本體解成可斷言、也可改寫的欄位表。
Map<String, Object?> jsonMapOf(String body) =>
    jsonDecode(body) as Map<String, Object?>;

/// 取得一次預期失敗的 [ApiError]（合同測試的通用取證）。
Future<ApiError> captureApiError(Future<Object?> Function() run) async {
  try {
    await run();
  } on ApiError catch (error) {
    return error;
  }
  throw StateError('預期抛出 ApiError，實際卻成功了');
}

void main() {
  group('ApplicationStatusReport 嚴格解碼', () {
    test('pending 回應可讀，reviewed_at 缺席就是「還沒有決定」', () {
      final ApplicationStatusReport report = ApplicationStatusReport.decode(
        jsonMapOf(pendingStatusBody),
      );
      expect(report.outcome, 'pending');
      expect(report.submittedAt, DateTime.utc(2026, 10, 3, 9));
      // 缺席不冒充零值：界面拿 null 決定「不擺這一行」，而不是顯示 1970 年。
      expect(report.reviewedAt, isNull);
      expect(report.requestId, '01a00000-0000-7000-8000-000000000002');
    });

    test('approved 回應帶得出決定時刻', () {
      final ApplicationStatusReport report = ApplicationStatusReport.decode(
        jsonMapOf(approvedStatusBody),
      );
      expect(report.outcome, 'approved');
      expect(report.reviewedAt, DateTime.utc(2026, 10, 4, 11, 30));
    });

    test('缺 outcome 即合同違例（結局不能未知）', () {
      final Map<String, Object?> missing = jsonMapOf(approvedStatusBody)
        ..remove('outcome');
      expect(
        () => ApplicationStatusReport.decode(missing),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('缺 submitted_at 即合同違例（不拿當前時刻湊一個提交時刻）', () {
      final Map<String, Object?> missing = jsonMapOf(pendingStatusBody)
        ..remove('submitted_at');
      expect(
        () => ApplicationStatusReport.decode(missing),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('reviewed_at 帶著但缺時區標記仍判違例（含糊時刻不得被猜成有效）', () {
      final Map<String, Object?> naive = jsonMapOf(approvedStatusBody)
        ..['reviewed_at'] = '2026-10-04T11:30:00';
      expect(
        () => ApplicationStatusReport.decode(naive),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('未知的結局原字串保留（後端只增不刪，前端不先緊收成枚舉）', () {
      final ApplicationStatusReport report = ApplicationStatusReport.decode(
        jsonMapOf(pendingStatusBody)..['outcome'] = 'on_hold',
      );
      expect(report.outcome, 'on_hold');
    });

    test('未知新欄位被容忍', () {
      final ApplicationStatusReport report = ApplicationStatusReport.decode(
        jsonMapOf(pendingStatusBody)..['future_field'] = 1,
      );
      expect(report.outcome, 'pending');
    });
  });

  group('applicationStatus 端點存取', () {
    test('POST /auth/registration-status：兩欄本體、路徑不帶查詢字串', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        // 即使伺服器端硬塞一枚 Cookie，本方法走的也是非 captureCookie 那條：
        // 回傳型別只有 ApplicationStatusReport，沒有會話秘密能被交回呼叫端。
        return http.Response(
          pendingStatusBody,
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
            'set-cookie':
                '$kSessionCookieName=should-be-ignored; Path=/; HttpOnly',
          },
        );
      });

      final ApplicationStatusReport report = await api.applicationStatus(
        loginName: 'Apply.One',
        password: '申請人自選口令',
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, kAuthRegistrationStatusPath);
      // 秘密不進 URL：查詢字串必須是空的。
      expect(sent.single.url.query, isEmpty);
      expect(report.outcome, 'pending');
    });

    test('本體恰為兩個白名單欄位，不含任何指向別人的格子', () async {
      late String capturedBody;
      final ServerApi api = apiWithHandler((http.Request request) async {
        capturedBody = request.body;
        return statusJson(pendingStatusBody, 200);
      });
      await api.applicationStatus(loginName: 'a.b', password: 'pw');

      final Map<String, Object?> decoded = jsonMapOf(capturedBody);
      expect(decoded.keys.toSet(), <String>{'login_name', 'password'});
      // 「申請編號」「帳戶標識」都不在協議上：可猜測的編號等於一條不必出示憑據的旁路。
      expect(decoded.containsKey('account_id'), isFalse);
      expect(decoded.containsKey('application_id'), isFalse);
      // 口令只在本體裡，不在路徑或標頭。
      expect(capturedBody, contains('password'));
    });

    test('查詢不經會話層：請求不附帶 Cookie，回應裡也沒有會話材料', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return statusJson(approvedStatusBody, 200);
      });
      final ApplicationStatusReport report = await api.applicationStatus(
        loginName: 'Apply.One',
        password: 'pw',
      );

      expect(sent.single.headers['cookie'], isNull);
      // 回報的東西被模型收在結局與兩個時刻裡：沒有任何可被存進會話層的欄位，
      // 也沒有 token／set-cookie 的容身之處（合同就沒有那一欄）。
      expect(report.outcome, 'approved');
      expect(report.reviewedAt, isNotNull);
    });
  });

  group('applicationStatus 錯誤對映', () {
    Future<ApiError> failure(int status, String envelope) {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => statusJson(envelope, status),
      );
      return captureApiError(
        () => api.applicationStatus(loginName: 'a.b', password: 'pw12345678'),
      );
    }

    test('2001 憑據無效 → invalidCredentials，與登入同一語意且不可重試', () async {
      final ApiError error = await failure(
        401,
        '{"code":2001,"message":"...","request_id":"r"}',
      );
      expect(error.machineCode, 2001);
      expect(error.knownCode, ApiMachineCode.invalidCredentials);
      // 查無此名／口令不符在這一條上同形：處置都是「核對自己的憑據」。
      expect(error.retryable, isFalse);
    });

    test('2020 不是申請 → notAnApplication，與 2001／2017 判然可分', () async {
      final ApiError error = await failure(
        403,
        '{"code":2020,"message":"...","request_id":"r"}',
      );
      expect(error.machineCode, 2020);
      expect(error.knownCode, ApiMachineCode.notAnApplication);
      expect(error.retryable, isFalse);
      // 2020 不能被判成「沒權限」或「策略關著」：那兩句的處置都不是「去登入」。
      expect(error.knownCode, isNot(ApiMachineCode.permissionDenied));
      expect(error.knownCode, isNot(ApiMachineCode.accountCreationDisabled));
    });

    test('2006 限流 → loginThrottled 且可重試（等的是冷卻，不是改寫法）', () async {
      final ApiError error = await failure(
        429,
        '{"code":2006,"message":"...","request_id":"r"}',
      );
      expect(error.knownCode, ApiMachineCode.loginThrottled);
      expect(error.retryable, isTrue);
    });

    test('1004 點名登入名 → invalidBody，並帶著 invalid_field', () async {
      final ApiError error = await failure(
        400,
        '{"code":1004,"message":"...","details":{"invalid_field":"login_name"},"request_id":"r"}',
      );
      expect(error.knownCode, ApiMachineCode.invalidBody);
      expect(error.details?['invalid_field'], 'login_name');
    });

    test('2019 與 2020 是兩枚不同的碼（重名與「不是申請」不得互冒充）', () async {
      final ApiError taken = await failure(
        409,
        '{"code":2019,"message":"...","request_id":"r"}',
      );
      final ApiError notApplication = await failure(
        403,
        '{"code":2020,"message":"...","request_id":"r"}',
      );
      expect(taken.knownCode, ApiMachineCode.selfRegisterNameTaken);
      expect(notApplication.knownCode, ApiMachineCode.notAnApplication);
    });
  });
}
