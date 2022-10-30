/// 認證合同（R1-009 後端發布的登入端點形态）在前端的鏡像測試。
///
/// 這裡釘的是「合同」而不是畫面：端點路徑、請求欄位、回應必填欄位與未知欄位
/// 的取捨、機器碼→語意的對應、會話秘密只能從 Set-Cookie 讀取。
/// 頁面與會話狀態管理屬後續步驟，不在本檔範圍。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 登入成功回應本體（帳戶分支）。
const String loginAccountBody =
    '{"subject_kind":"account","account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"device_id":"01a0e000-0000-7000-8000-0000000000bb",'
    '"expires_at":"2026-09-29T13:00:00.000Z","request_id":"01a00000-0000-7000-8000-000000000001"}';

/// 登入成功回應本體（Root 分支：無 account_id）。
const String loginRootBody =
    '{"subject_kind":"root",'
    '"device_id":"01a0e000-0000-7000-8000-0000000000cc",'
    '"expires_at":"2026-09-29T13:00:00.000Z","request_id":"01a00000-0000-7000-8000-000000000001"}';

/// 當前會話回應本體。
const String sessionBody =
    '{"subject_kind":"account","account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"device_id":"01a0e000-0000-7000-8000-0000000000bb",'
    '"rotation_seq":0,'
    '"created_at":"2026-09-29T12:00:00.000Z","last_active_at":"2026-09-29T12:30:00.000Z",'
    '"expires_at":"2026-09-29T13:00:00.000Z","request_id":"01a00000-0000-7000-8000-000000000001"}';

void main() {
  group('模型嚴格解碼', () {
    test('帳戶登入回應全欄位可讀', () {
      final LoginReport report = LoginReport.decode(const <String, Object?>{
        'subject_kind': 'account',
        'account_id': '01a0e000-0000-7000-8000-0000000000aa',
        'device_id': '01a0e000-0000-7000-8000-0000000000bb',
        'expires_at': '2026-09-29T13:00:00.000Z',
        'request_id': 'req-1',
      });
      expect(report.subjectKind, AuthSubjectKind.account);
      expect(report.isRoot, isFalse);
      expect(report.deviceId, '01a0e000-0000-7000-8000-0000000000bb');
      expect(report.expiresAt, DateTime.utc(2026, 9, 29, 13));
    });

    test('Root 回應不帶 account_id；帳戶回應缺 account_id 即合同違例', () {
      final Map<String, Object?> root = (jsonMapOf(loginRootBody));
      expect(LoginReport.decode(root).isRoot, isTrue);

      expect(
        () => LoginReport.decode(<String, Object?>{
          'subject_kind': 'account',
          'device_id': 'x',
          'expires_at': '2026-09-29T13:00:00.000Z',
          'request_id': 'r',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );

      expect(
        () => LoginReport.decode(<String, Object?>{
          'subject_kind': 'root',
          'account_id': '不該出現',
          'device_id': 'x',
          'expires_at': '2026-09-29T13:00:00.000Z',
          'request_id': 'r',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('subject_kind 未知值一律判為失敗，不降級成帳戶', () {
      expect(
        () => LoginReport.decode(<String, Object?>{
          'subject_kind': 'superuser',
          'device_id': 'x',
          'expires_at': '2026-09-29T13:00:00.000Z',
          'request_id': 'r',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('回應中的未知新欄位被容忍（後端只增不刪）', () {
      final LoginReport report = LoginReport.decode(
        jsonMapOf(loginAccountBody)..['future_field'] = 42,
      );
      expect(report.deviceId, isNotEmpty);
    });

    test('當前會話報告要求建立、最近活動與輪換世代欄位', () {
      final CurrentSessionReport report = CurrentSessionReport.decode(
        jsonMapOf(sessionBody),
      );
      expect(report.lastActiveAt, DateTime.utc(2026, 9, 29, 12, 30));
      expect(report.rotationSeq, 0);
      // 缺 last_active_at：形狀不合。
      expect(
        () => CurrentSessionReport.decode(<String, Object?>{
          'subject_kind': 'account',
          'account_id': 'a',
          'device_id': 'd',
          'rotation_seq': 0,
          'created_at': '2026-09-29T12:00:00.000Z',
          'expires_at': '2026-09-29T13:00:00.000Z',
          'request_id': 'r',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
      // 缺 rotation_seq：同樣不合——世代號是對帳的基準，不能猜 0。
      expect(
        () => CurrentSessionReport.decode(<String, Object?>{
          'subject_kind': 'account',
          'account_id': 'a',
          'device_id': 'd',
          'created_at': '2026-09-29T12:00:00.000Z',
          'last_active_at': '2026-09-29T12:30:00.000Z',
          'expires_at': '2026-09-29T13:00:00.000Z',
          'request_id': 'r',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });
  });

  group('端點存取', () {
    test('login 發 POST、帶 JSON 本體並從 Set-Cookie 取得秘密（原生場景）', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(
          loginAccountBody,
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
            'set-cookie':
                '$kSessionCookieName=secret-value-43chars; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600',
          },
        );
      });

      final LoginExchange exchange = await api.login(
        loginName: 'alice',
        password: 'pw',
      );
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, kAuthLoginPath);
      expect(sent.single.body, contains('"login_name":"alice"'));
      expect(sent.single.body, isNot(contains('role')));
      expect(exchange.sessionSecret, 'secret-value-43chars');
      expect(exchange.report.isRoot, isFalse);
    });

    test('rootLogin 本體只有口令；瀏覽器環境讀不到 Set-Cookie 時秘密為 null', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return http.Response(
          loginRootBody,
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final LoginExchange exchange = await api.rootLogin(password: 'root-pw');
      expect(sent.single.url.path, kAuthRootLoginPath);
      expect(sent.single.body, '{"password":"root-pw"}');
      expect(exchange.report.isRoot, isTrue);
      expect(exchange.sessionSecret, isNull);
    });

    test('currentSession 以 Bearer 回傳秘密；未認證錯誤按機器碼判定', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi okApi = apiWithHandler((http.Request request) async {
        sent.add(request);
        return jsonOk(sessionBody);
      });
      final CurrentSessionReport report = await okApi.currentSession(
        bearerToken: 'native-secret',
      );
      expect(sent.single.headers['authorization'], 'Bearer native-secret');
      expect(report.deviceId, isNotEmpty);

      final ServerApi anonApi = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":2002,"message":"...","request_id":"r"}',
          401,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final ApiError error = await captureApiError(
        () => anonApi.currentSession(),
      );
      expect(error.knownCode, ApiMachineCode.notAuthenticated);
    });

    test('登入被拒的 2001 收斂為 invalidCredentials（外部不可區分帳戶）', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":2001,"message":"...","request_id":"r"}',
          401,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final ApiError error = await captureApiError(
        () => api.login(loginName: 'ghost', password: 'pw'),
      );
      expect(error.knownCode, ApiMachineCode.invalidCredentials);
      expect(error.retryable, isFalse);
    });

    test('裝置名額已滿的 2008 收斂為 deviceLimitReached，且不標為可重試', () async {
      // 2008 的存在意義就是「跟口令無關」：它必須是可判別的第三種結論，
      // 既不是 2001（重打口令也不會好），也不是 2006（重試現在沒有意義，
      // 要等別的裝置登出或會話到期），所以 retryable 必須是 false。
      final ServerApi api = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":2008,"message":"...","request_id":"r"}',
          403,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final ApiError error = await captureApiError(
        () => api.login(loginName: 'someone', password: 'pw'),
      );
      expect(error.knownCode, ApiMachineCode.deviceLimitReached);
      expect(error.retryable, isFalse);
      expect(error.machineCode, 2008);
    });
  });

  group('Set-Cookie 提取', () {
    test('單枚會話 Cookie 帶屬性也能取值', () {
      expect(
        extractSessionCookie(
          '$kSessionCookieName=abc123; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly',
        ),
        'abc123',
      );
    });

    test('多枚 Cookie 拼接時只認會話那枚', () {
      expect(
        extractSessionCookie(
          'other=x; Path=/, $kSessionCookieName=yy; Path=/, third=zz',
        ),
        'yy',
      );
    });

    test('讀不到、為空或刪除指令（空值）一律回 null', () {
      expect(extractSessionCookie(null), isNull);
      expect(extractSessionCookie(''), isNull);
      expect(extractSessionCookie('other=1'), isNull);
      expect(extractSessionCookie('$kSessionCookieName=; Max-Age=0'), isNull);
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
