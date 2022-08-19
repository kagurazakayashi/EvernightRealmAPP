/// 統一存取層的測試：逐條走過每個失敗路徑，斷言它們都不可能被當成成功。
///
/// 完成判斷是「網路錯誤不顯示為成功」，因此這裡的重點不是「回傳了什麼」，
/// 而是「失敗時有沒有回傳值」：反面案例一律以 [captureApiError] 收斂，
/// 並檢查轉出來的結構化欄位足以讓介面選對文案、讓日誌對上同一筆請求。
library;

import 'dart:async';

import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_address.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_server.dart';

/// 執行一次預期失敗的請求並取回結構化錯誤；正常回傳時直接讓測試失敗。
///
/// 「不顯示為成功」最硬的保證就是拿不到值：本函式不給任何竄改空間。
Future<ApiError> captureApiError(Future<Object?> Function() run) async {
  try {
    await run();
  } on ApiError catch (error) {
    return error;
  }
  return fail('預期拋出 ApiError，卻正常取得回傳值');
}

void main() {
  group('正常讀取', () {
    test('/health 回傳已驗證的存活報告', () async {
      final HealthReport report = await stubApi().health();

      expect(report.status, 'ok');
      expect(report.service, 'evernight-server');
      expect(report.version, '0.1.0-dev');
      expect(report.requestId, '01a0cd4d-227f-7b42-b091-e501ecf197c1');
      expect(report.reportsOk, isTrue);
    });

    test('/ready 回傳已驗證的就緒報告', () async {
      final ReadinessReport report = await stubApi().ready();

      expect(report.status, 'ready');
      expect(report.reportsReady, isTrue);
    });

    test('/time 原樣保留伺服器時間文字並正規化為 UTC', () async {
      final ServerTimeReport report = await stubApi().time();

      expect(report.timeText, '2026-09-25T09:33:32.614Z');
      expect(report.time, DateTime.utc(2026, 9, 25, 9, 33, 32, 614));
      expect(report.time.isUtc, isTrue);
      expect(report.timezone, 'Asia/Shanghai');
      expect(report.utcOffsetSeconds, 28800);
      expect(report.utcOffsetText, '+08:00');
      expect(report.displayClock, '17:33:32');
    });

    test('帶偏移寫法的時間換算後仍指向同一瞬間', () async {
      final ServerTimeReport report = await stubApi(
        overrides: <String, String>{
          kTimePath:
              '{"time":"2026-09-25T17:33:32.614+08:00","timezone":"Asia/Shanghai",'
              '"utc_offset_seconds":28800,"request_id":"01a0d7e9-b446-72b2-a1e8-87a33231cd7a"}',
        },
      ).time();

      expect(report.time, DateTime.utc(2026, 9, 25, 9, 33, 32, 614));
      expect(report.displayClock, '17:33:32');
    });

    test('請求打到驗證過的基準位址與端點路徑', () async {
      final List<Uri> requested = <Uri>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        requested.add(request.url);
        return jsonOk(healthBody);
      });

      await api.health();

      expect(requested.single.toString(), '$testBaseUrl/health');
    });

    test('帶路徑前綴的定位仍接到正確的端點', () async {
      final List<Uri> requested = <Uri>[];
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed('http://10.0.0.5:80/evernight'),
        client: MockClient((http.Request request) async {
          requested.add(request.url);
          return jsonOk(timeBody);
        }),
      );

      await api.time();

      expect(requested.single.path, '/evernight/time');
    });

    test('送出介面語言給伺服器，未給時不帶該標頭', () async {
      final List<String?> sent = <String?>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request.headers['accept-language']);
        return jsonOk(healthBody);
      });

      await api.health(acceptLanguage: 'zh-TW');
      await api.health();

      expect(sent, <String?>['zh-TW', null]);
    });

    test('回應多出合同未列的欄位時照常解析（版本規則是只增不刪）', () async {
      final HealthReport report = await stubApi(
        overrides: <String, String>{
          kHealthPath:
              '{"status":"ok","service":"evernight-server","version":"0.1.0-dev",'
              '"request_id":"01a0cd4d-227f-7b42-b091-e501ecf197c1",'
              '"future_field":{"nested":true}}',
        },
      ).health();

      expect(report.service, 'evernight-server');
    });
  });

  group('失敗一律拋出，不回傳值', () {
    test('基準位址未設定時不發出任何請求', () async {
      int requests = 0;
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed(''),
        client: MockClient((http.Request request) async {
          requests++;
          return jsonOk(healthBody);
        }),
      );

      final ApiError error = await captureApiError(api.health);

      expect(error.kind, ApiErrorKind.notConfigured);
      expect(error.serverResponded, isFalse);
      expect(error.retryable, isFalse);
      expect(requests, 0, reason: '沒有位址就不該碰傳輸層');
      expect(api.isConfigured, isFalse);
    });

    test('位址格式不合格時等同未設定', () async {
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed('http://user:pass@10.0.0.1'),
      );

      expect(
        (await captureApiError(api.time)).kind,
        ApiErrorKind.notConfigured,
      );
      expect(ServerAddress.tryParse('http://user:pass@10.0.0.1'), isNull);
    });

    test('連不上時歸類為不可達，且不宣稱伺服器有回應', () async {
      final ServerApi api = apiWithHandler((_) async {
        throw http.ClientException('Failed to host localhost');
      });

      final ApiError error = await captureApiError(api.ready);

      expect(error.kind, ApiErrorKind.unreachable);
      expect(error.serverResponded, isFalse);
      expect(error.retryable, isTrue);
      expect(error.httpStatus, isNull);
    });

    test('底層拋出未預期異常時仍歸為失敗，不外洩原始例外', () async {
      final ServerApi api = apiWithHandler(
        (_) async => throw StateError('boom'),
      );

      final ApiError error = await captureApiError(api.health);

      expect(error.kind, ApiErrorKind.unreachable);
      expect(error.serverResponded, isFalse);
    });

    test('超過期限沒有回應時歸類為逾時', () async {
      final Completer<http.Response> never = Completer<http.Response>();
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed(
          testBaseUrl,
          requestTimeout: Duration(milliseconds: 30),
        ),
        client: MockClient((_) => never.future),
      );

      final ApiError error = await captureApiError(api.time);

      expect(error.kind, ApiErrorKind.timeout);
      expect(error.retryable, isTrue);
    });

    test('HTTP 200 但本體不是 JSON 時不視為成功', () async {
      final ApiError error = await captureApiError(
        stubApi(overrides: <String, String>{kHealthPath: 'ok'}).health,
      );

      expect(error.kind, ApiErrorKind.invalidResponse);
      expect(error.httpStatus, 200);
    });

    test('HTTP 200 但內容型別不是 JSON 時不視為成功', () async {
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed(testBaseUrl),
        client: MockClient(
          (_) async => http.Response(
            healthBody,
            200,
            headers: <String, String>{
              'content-type': 'text/plain; charset=utf-8',
            },
          ),
        ),
      );

      expect(
        (await captureApiError(api.health)).kind,
        ApiErrorKind.invalidResponse,
      );
    });

    test('HTTP 200 但本體為空時不視為成功', () async {
      final ApiError error = await captureApiError(
        stubApi(overrides: <String, String>{kHealthPath: ''}).health,
      );

      expect(error.kind, ApiErrorKind.invalidResponse);
    });

    test('HTTP 200 但頂層不是物件時不視為成功', () async {
      final ApiError error = await captureApiError(
        stubApi(overrides: <String, String>{kHealthPath: '["ok"]'}).health,
      );

      expect(error.kind, ApiErrorKind.invalidResponse);
    });

    test('必要欄位缺失時不猜預設值', () async {
      final ApiError error = await captureApiError(
        stubApi(
          overrides: <String, String>{
            kHealthPath: '{"status":"ok","service":"evernight-server"}',
          },
        ).health,
      );

      expect(error.kind, ApiErrorKind.invalidResponse);
      expect(error.httpStatus, 200);
      expect(error.cause, contains('version'));
    });

    test('欄位型別不符時不視為成功', () async {
      final ApiError error = await captureApiError(
        stubApi(
          overrides: <String, String>{
            kTimePath:
                '{"time":"2026-09-25T09:33:32.614Z","timezone":"Asia/Shanghai",'
                '"utc_offset_seconds":"28800","request_id":"x"}',
          },
        ).time,
      );

      expect(error.kind, ApiErrorKind.invalidResponse);
      expect(error.cause, contains('utc_offset_seconds'));
    });

    test('時間缺少時區標記時不推測為本機時區', () async {
      final ApiError error = await captureApiError(
        stubApi(
          overrides: <String, String>{
            kTimePath:
                '{"time":"2026-09-25T09:33:32.614","timezone":"Asia/Shanghai",'
                '"utc_offset_seconds":28800,"request_id":"x"}',
          },
        ).time,
      );

      expect(error.cause, contains('缺少時區標記'));
    });

    test('存活端點回報非 ok 狀態時如實呈現，不自行改判', () async {
      final HealthReport report = await stubApi(
        overrides: <String, String>{
          kHealthPath:
              '{"status":"draining","service":"evernight-server","version":"0",'
              '"request_id":"x"}',
        },
      ).health();

      expect(report.reportsOk, isFalse);
      expect(report.status, 'draining');
    });
  });

  group('非 2xx 的結構化轉換', () {
    test('404 帶信封時轉為已知錯誤碼', () async {
      final ApiError error = await captureApiError(
        stubApi(
          overrides: <String, String>{
            kHealthPath: '{"code":1001,"message":"nope","request_id":"r-404"}',
          },
          statuses: <String, int>{kHealthPath: 404},
        ).health,
      );

      expect(error.kind, ApiErrorKind.httpStatus);
      expect(error.httpStatus, 404);
      expect(error.machineCode, 1001);
      expect(error.knownCode, ApiMachineCode.notFound);
      expect(error.requestId, 'r-404');
      expect(error.serverResponded, isTrue);
      expect(error.retryable, isFalse);
    });

    test('503 未就緒可重試', () async {
      final ApiError error = await captureApiError(
        stubApi(
          overrides: <String, String>{
            kReadyPath:
                '{"code":1007,"message":"not ready","request_id":"r-503"}',
          },
          statuses: <String, int>{kReadyPath: 503},
        ).ready,
      );

      expect(error.knownCode, ApiMachineCode.notReady);
      expect(error.retryable, isTrue);
    });

    test('400 的可公開判定依據原樣保留', () async {
      final ApiError error = await captureApiError(
        stubApi(
          overrides: <String, String>{
            kHealthPath: '{"code":1004,"message":"bad","details":{"field":"now"},"request_id":"r"}',
          },
          statuses: <String, int>{kHealthPath: 400},
        ).health,
      );

      expect(error.details, <String, Object?>{'field': 'now'});
      expect(error.retryable, isFalse);
    });

    test('500 回純文字沒有信封時仍判為失敗且可重試', () async {
      final ApiError error = await captureApiError(
        stubApi(
          overrides: <String, String>{kHealthPath: 'internal error'},
          statuses: <String, int>{kHealthPath: 500},
        ).health,
      );

      expect(error.kind, ApiErrorKind.httpStatus);
      expect(error.machineCode, isNull);
      expect(error.serverResponded, isTrue);
      expect(error.retryable, isTrue);
    });

    test('信封缺 request_id 時退回標頭帶回的關聯 ID', () async {
      final ApiError error = await captureApiError(
        stubApi(
          overrides: <String, String>{kTimePath: '{"code":1000,"message":"e"}'},
          statuses: <String, int>{kTimePath: 500},
        ).time,
      );

      expect(error.requestId, stubRequestId);
    });

    test('信封欄位型別不符時不放棄失敗判定', () async {
      final ApiError error = await captureApiError(
        stubApi(
          overrides: <String, String>{
            kHealthPath: '{"code":"1001","message":"e","request_id":"r"}',
          },
          statuses: <String, int>{kHealthPath: 404},
        ).health,
      );

      expect(error.kind, ApiErrorKind.httpStatus);
      expect(error.machineCode, isNull);
      expect(error.httpStatus, 404);
    });

    test('未收錄的錯誤碼保留原數值供診斷', () async {
      // 樣本取自「尚未發布」的號段：借用已發布區段裡的空缺（例如 1008 之於 1xxx）
      // 會讓本測試在日後補上該碼時無聲失真，故固定用不可能成為正式碼的高位數。
      const int unlistedMachineCode = 9999;
      expect(ApiMachineCode.fromValue(unlistedMachineCode), isNull);

      final ApiError error = await captureApiError(
        stubApi(
          overrides: <String, String>{
            kHealthPath:
                '{"code":$unlistedMachineCode,"message":"e","request_id":"r"}',
          },
          statuses: <String, int>{kHealthPath: 403},
        ).health,
      );

      expect(error.machineCode, unlistedMachineCode);
      expect(error.knownCode, isNull);
      expect(error.retryable, isFalse);
    });
  });

  group('錯誤物件本身', () {
    test('描述不含基準位址，只含路徑與關聯資訊', () async {
      // 注入假傳輸：這支測試要驗的是錯誤描述會不會漏出主機，不該真的去連它。
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed('http://10.0.0.9:5206/private'),
        client: MockClient(
          (_) async => http.Response(
            '{"code":1001,"message":"nope","request_id":"r-9999"}',
            404,
            headers: <String, String>{'content-type': 'application/json'},
          ),
        ),
      );

      final ApiError error = await captureApiError(api.health);

      expect(error.toString(), isNot(contains('10.0.0.9')));
      expect(error.toString(), isNot(contains('/private')));
      expect(error.toString(), contains('path=/health'));
      expect(error.toString(), contains('code=1001'));
      expect(error.toString(), contains('r-9999'));
    });

    test('機器碼到已知枚舉的對應逐一走到', () {
      for (final ApiMachineCode code in ApiMachineCode.values) {
        expect(ApiMachineCode.fromValue(code.value), code);
      }
      expect(ApiMachineCode.fromValue(9999), isNull);
    });
  });
}
