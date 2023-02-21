/// 訪客進入合同（R2-016 後端發布的 `/auth/guest` 與 `account_type` 欄位）在前端的鏡像測試。
///
/// 釘的是「合同」而不是畫面：端點路徑與方法、請求本體只有暱稱一格（而且留空時那一格根本不發）、
/// 成功回應必填欄位與「秘密只能從 Set-Cookie 讀」、`account_type` 的嚴格解碼（缺席＝未知、
/// 表外值＝違例、Root 主體帶這一欄＝違例），以及三個可判別結論（2017／2006＋Retry-After／1004
/// 點名 nickname）→語意的對應。
/// 卡片何時才准寫入、連點只發一趟屬 guest_entry_view 的 widget 測試，不在本檔範圍。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 訪客進入成功回應本體（帳號是訪客、不帶任何憑據欄位）。
const String guestEnterBody =
    '{"subject_kind":"account","account_id":"01a0e000-0000-7000-8000-0000000000f0",'
    '"account_type":"guest","display_name":"夜訪的旅人",'
    '"device_id":"01a0e000-0000-7000-8000-0000000000f1",'
    '"expires_at":"2026-10-08T10:00:00.000Z",'
    '"request_id":"01a00000-0000-7000-8000-000000000001"}';

/// 解一份 JSON 回應本體。
Map<String, Object?> jsonMapOf(String body) =>
    json.decode(body) as Map<String, Object?>;

/// 一則指定狀態碼與標頭的 JSON 回應。
http.Response reply(
  String body, {
  int status = 200,
  Map<String, String>? headers,
}) {
  return http.Response(
    body,
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
      ...?headers,
    },
  );
}

void main() {
  group('guestEnter 請求形態', () {
    test('帶暱稱時發 POST，本體只有 nickname 一格', () async {
      final List<http.Request> seen = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        seen.add(request);
        return reply(guestEnterBody);
      });

      final LoginExchange exchange = await api.guestEnter(
        nickname: '  夜訪的旅人  ',
      );

      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, kAuthGuestPath);
      expect(seen.single.headers['content-type'], contains('application/json'));
      expect(jsonMapOf(seen.single.body), <String, Object?>{
        'nickname': '夜訪的旅人',
      });
      // 本體沒有一格能把訪客昇格，也沒有可自報的登入名／帳戶標識。
      expect(seen.single.body, isNot(contains('role')));
      expect(seen.single.body, isNot(contains('account_type')));
      expect(seen.single.body, isNot(contains('login_name')));
      expect(exchange.report.isGuest, isTrue);
    });

    test('留空或只有空白時根本不發 nickname 格（由伺服器產生臨時編號）', () async {
      final List<http.Request> seen = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        seen.add(request);
        return reply(guestEnterBody);
      });

      await api.guestEnter();
      await api.guestEnter(nickname: '   ');

      expect(seen, hasLength(2));
      for (final http.Request request in seen) {
        expect(jsonMapOf(request.body), isEmpty);
        // 空本體仍是合法 JSON 物件：後端 decodeJSON 認得 {},而不會把「缺席」讀成「填了空字串」。
        expect(request.body, '{}');
      }
    });

    test('回應不帶任何憑據材料；秘密只能從 Set-Cookie 讀（原生場景）', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return reply(
          guestEnterBody,
          headers: <String, String>{
            'set-cookie': 'evernight_session=tok-guest-1; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600',
          },
        );
      });

      final LoginExchange exchange = await api.guestEnter(nickname: '夜訪');
      expect(exchange.sessionSecret, 'tok-guest-1');
      expect(jsonMapOf(guestEnterBody).containsKey('secret'), isFalse);
      expect(jsonMapOf(guestEnterBody).containsKey('password'), isFalse);
    });

    test('讀不到 Set-Cookie 時秘密為 null（不謊報有一枚憑據）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => reply(guestEnterBody),
      );
      final LoginExchange exchange = await api.guestEnter();
      expect(exchange.sessionSecret, isNull);
    });
  });

  group('guestEnter 失敗結論', () {
    Future<ApiError> failureOf(int code, {int status = 403}) async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => reply(
          '{"code":$code,"message":"server text","request_id":"r-guest"}',
          status: status,
        ),
      );
      try {
        await api.guestEnter(nickname: '夜訪');
      } on ApiError catch (error) {
        return error;
      }
      throw StateError('訪客進入的失敗路徑必須拋出 ApiError');
    }

    test('2017（策略此刻不開放訪客）可判別、不可重試', () async {
      final ApiError error = await failureOf(2017);
      expect(error.machineCode, ApiMachineCode.accountCreationDisabled.value);
      expect(error.knownCode, ApiMachineCode.accountCreationDisabled);
      // 與「你被登出了」分開：他本來就沒有會話，處置是等 Root 打開開關。
      expect(error.kind, ApiErrorKind.httpStatus);
      expect(error.retryable, isFalse);
    });

    test('2006（來源被限流）可判別且標為可重試（處置是等一會兒）', () async {
      final ApiError error = await failureOf(2006, status: 429);
      expect(error.machineCode, ApiMachineCode.loginThrottled.value);
      // Retry-After 的秒數由伺服器標頭攜帶；本層只釘「這條值得稍後重試」，
      // 不把標頭值折進模型（界面沒有倒數顯示，多一格狀態就多一处可能過期的答案）。
      expect(error.retryable, isTrue);
    });

    test('1004 點名 nickname 時是可判別的表單問題，不混成策略結論', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => reply(
          '{"code":1004,"message":"server text",'
          '"details":{"invalid_field":"nickname"},"request_id":"r-guest"}',
          status: 400,
        ),
      );
      try {
        await api.guestEnter(nickname: '超長' * 40);
        fail('不合規暱稱必須拋出 ApiError');
      } on ApiError catch (error) {
        expect(error.machineCode, ApiMachineCode.invalidBody.value);
        expect(error.details?['invalid_field'], 'nickname');
        // 與 2017 分開：一個要人改寫法，另一個改寫法換不來任何結果。
        expect(
          error.machineCode,
          isNot(ApiMachineCode.accountCreationDisabled.value),
        );
      }
    });
  });

  group('account_type 嚴格解碼', () {
    test('guest 讀出訪客身分，standard 讀出普通帳戶', () {
      final LoginReport guest = LoginReport.decode(jsonMapOf(guestEnterBody));
      expect(guest.accountType, AuthAccountType.guest);
      expect(guest.isGuest, isTrue);
      expect(guest.isRoot, isFalse);
      // 訪客不帶授予：合同沒有 roles 欄位時解碼為空清單，而不是猜一個。
      expect(guest.roles, isEmpty);
      expect(guest.mustChangePassword, isFalse);

      final LoginReport standard = LoginReport.decode(
        jsonMapOf(guestEnterBody)
          ..['account_type'] = 'standard'
          ..remove('display_name'),
      );
      expect(standard.accountType, AuthAccountType.standard);
      expect(standard.isGuest, isFalse);
    });

    test('欄位缺席時是「未知」而不是普通帳戶', () {
      final LoginReport legacy = LoginReport.decode(
        jsonMapOf(guestEnterBody)..remove('account_type'),
      );
      expect(legacy.accountType, isNull);
      expect(legacy.isGuest, isFalse);
    });

    test('表外值一律判合同違例（不把第三類主體猜成任一已知類）', () {
      expect(
        () => LoginReport.decode(
          jsonMapOf(guestEnterBody)..['account_type'] = 'operator',
        ),
        throwsA(isA<ApiResponseShapeException>()),
      );
      expect(
        () => LoginReport.decode(
          jsonMapOf(guestEnterBody)..['account_type'] = true,
        ),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('Root 主體帶 account_type 即違例（他不在 accounts 表裡）', () {
      expect(
        () => LoginReport.decode(<String, Object?>{
          'subject_kind': 'root',
          'account_type': 'standard',
          'device_id': 'device-77',
          'expires_at': '2026-10-08T10:00:00.000Z',
          'request_id': 'r-1',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('當前會話回應同樣讀得出訪客（刷新後界面還說得對）', () {
      final Map<String, Object?> sessionJson = <String, Object?>{
        'subject_kind': 'account',
        'account_id': '01a0e000-0000-7000-8000-0000000000f0',
        'account_type': 'guest',
        'device_id': '01a0e000-0000-7000-8000-0000000000f1',
        'rotation_seq': 0,
        'created_at': '2026-10-08T09:00:00.000Z',
        'last_active_at': '2026-10-08T09:30:00.000Z',
        'expires_at': '2026-10-08T10:00:00.000Z',
        'request_id': 'r-2',
      };
      final CurrentSessionReport report = CurrentSessionReport.decode(
        sessionJson,
      );
      expect(report.isGuest, isTrue);
      expect(report.roles, isEmpty);

      // 未知欄位一律容忍（合同只增不刪）：這一版讀不到的新欄位不該讓整份回應失效。
      final CurrentSessionReport withExtra = CurrentSessionReport.decode(
        sessionJson..['some_future_field'] = 1,
      );
      expect(withExtra.isGuest, isTrue);
    });
  });
}
