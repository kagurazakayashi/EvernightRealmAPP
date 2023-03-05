/// 「訪戶綁定預檢」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：路徑與方法（POST 只評估一對輸入）、請求欄位集合
/// （恰好 target_account_id 一格，沒有也不准出現口令／角色／類型／依據值欄位）、
/// 回應的必填欄位（blockers／impacts 缺席判違例不降級成空、source_open_sessions
/// 與 schema_version 必填、consent_mode 表外值判違例不靜默放行）、
/// 未知新欄位與未知記號的前進相容，以及「不可綁定是 200 而不是錯誤信封」
/// 這條本步最要釘住的合同方向。預覽是純只讀的：模型裡沒有、也不可能有
/// 任何可以被當成「綁定憑據」的格子。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 可執行預覽的回應本體（與後端 standardAccountBindPreflightResponse 同源）。
const String bindPreflightOkBody =
    '{"source":{"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"login_name":"guest_9f2c1a","display_name":"待綁旅人",'
    '"account_type":"guest","status":"active","must_change_password":false,'
    '"created_at":"2026-10-02T08:00:00.000Z",'
    '"last_login_at":"2026-10-03T07:15:00.000Z"},'
    '"target":{"account_id":"01a0e000-0000-7000-8000-0000000000bb",'
    '"login_name":"Already.Real","display_name":"正式受體",'
    '"account_type":"standard","status":"active","must_change_password":false,'
    '"created_at":"2026-09-01T00:00:00.000Z"},'
    '"executable":true,"blockers":[],'
    '"impacts":["revoke_source_sessions","retire_source_account",'
    '"keep_history_references","transfer_future_attribution","target_unchanged"],'
    '"source_open_sessions":2,"schema_version":10,'
    '"consent_mode":"target_self_initiated","request_id":"r-preflight"}';

/// 被阻止預覽的回應本體：同一個 200 通道，只是 blockers 帶記號、impacts 清空。
const String bindPreflightBlockedBody =
    '{"source":{"account_id":"01a0e000-0000-7000-8000-0000000000aa",'
    '"login_name":"guest_9f2c1a","display_name":"待綁旅人",'
    '"account_type":"guest","status":"active","must_change_password":false,'
    '"created_at":"2026-10-02T08:00:00.000Z"},'
    '"target":{"account_id":"01a0e000-0000-7000-8000-0000000000cc",'
    '"login_name":"guest_77ab02","display_name":"另一位旅人",'
    '"account_type":"guest","status":"active","must_change_password":false,'
    '"created_at":"2026-10-04T08:00:00.000Z"},'
    '"executable":false,"blockers":["target_not_standard"],"impacts":[],'
    '"source_open_sessions":1,"schema_version":10,'
    '"consent_mode":"target_self_initiated","request_id":"r-blocked"}';

Future<ApiError> capturePreflightFailure(
  Future<Object?> Function() call,
) async {
  try {
    await call();
  } on ApiError catch (error) {
    return error;
  }
  throw StateError('預期抛出 ApiError，卻拿到一次成功預檢');
}

http.Response jsonResponse(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('綁定預檢端點合同', () {
    test(
      'guestBindPreflight 發 POST /admin/accounts/{id}/bind-preflight、本體恰好一欄',
      () async {
        final List<http.Request> sent = <http.Request>[];
        final ServerApi api = apiWithHandler((http.Request request) async {
          sent.add(request);
          return jsonResponse(bindPreflightOkBody, 200);
        });

        final StandardAccountBindPreflightReport report = await api
            .guestBindPreflight(
              accountId: '01a0e000-0000-7000-8000-0000000000aa',
              targetAccountId: '01a0e000-0000-7000-8000-0000000000bb',
            );

        expect(sent.single.method, 'POST');
        expect(
          sent.single.url.path,
          adminAccountBindPreflightPath('01a0e000-0000-7000-8000-0000000000aa'),
        );
        final Map<String, Object?> body =
            jsonDecode(sent.single.body) as Map<String, Object?>;
        expect(body.keys.toSet(), <String>{'target_account_id'});
        // 本體裡沒有也不准有多餘的宣稱格子：這條通路不寫任何东西，
        // 也沒有「代替目標同意」的欄位可以填。
        for (final String forbidden in <String>[
          'password',
          'role',
          'roles',
          'account_type',
          'status',
          'expected',
          'consent',
          'activity_id',
        ]) {
          expect(sent.single.body, isNot(contains(forbidden)));
        }

        expect(report.executable, isTrue);
        expect(report.blockers, isEmpty);
        expect(report.impacts, hasLength(5));
        expect(report.source.accountId, '01a0e000-0000-7000-8000-0000000000aa');
        expect(report.source.isGuest, isTrue);
        expect(report.target.accountType, 'standard');
        expect(report.sourceOpenSessions, 2);
        expect(report.schemaVersion, 10);
        expect(
          report.consentMode,
          kBindPreflightConsentModeTargetSelfInitiated,
        );
        expect(report.requestId, 'r-preflight');
      },
    );

    test('不可綁定是 200 預覽而不是錯誤信封：blockers 帶記號、impacts 清空', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            jsonResponse(bindPreflightBlockedBody, 200),
      );
      final StandardAccountBindPreflightReport report = await api
          .guestBindPreflight(
            accountId: '01a0e000-0000-7000-8000-0000000000aa',
            targetAccountId: '01a0e000-0000-7000-8000-0000000000cc',
          );
      expect(report.executable, isFalse);
      expect(report.blockers, <String>['target_not_standard']);
      expect(report.impacts, isEmpty);
      // 被阻止的預覽仍如實報出現場事實（源會話數與版本不是只在成功時才給）。
      expect(report.sourceOpenSessions, 1);
      expect(report.schemaVersion, 10);
    });

    test('blockers 或 impacts 缺席判合同違例，不降級成空清單', () async {
      for (final String field in <String>['blockers', 'impacts']) {
        final Map<String, Object?> missing =
            jsonDecode(bindPreflightOkBody) as Map<String, Object?>
              ..remove(field);
        final ServerApi harsh = apiWithHandler(
          (http.Request request) async =>
              jsonResponse(jsonEncode(missing), 200),
        );
        final ApiError error = await capturePreflightFailure(
          () => harsh.guestBindPreflight(
            accountId: '01a0e000-0000-7000-8000-0000000000aa',
            targetAccountId: '01a0e000-0000-7000-8000-0000000000bb',
          ),
        );
        expect(
          error.kind,
          ApiErrorKind.invalidResponse,
          reason: '$field 缺席必須被點名',
        );
      }
    });

    test('source_open_sessions 與 schema_version 必填：缺席不降級成 0', () async {
      for (final String field in <String>[
        'source_open_sessions',
        'schema_version',
        'source',
        'target',
        'consent_mode',
      ]) {
        final Map<String, Object?> missing =
            jsonDecode(bindPreflightOkBody) as Map<String, Object?>
              ..remove(field);
        final ServerApi harsh = apiWithHandler(
          (http.Request request) async =>
              jsonResponse(jsonEncode(missing), 200),
        );
        final ApiError error = await capturePreflightFailure(
          () => harsh.guestBindPreflight(
            accountId: '01a0e000-0000-7000-8000-0000000000aa',
            targetAccountId: '01a0e000-0000-7000-8000-0000000000bb',
          ),
        );
        expect(error.kind, ApiErrorKind.invalidResponse, reason: field);
      }
    });

    test('consent_mode 表外值判合同違例：新同意形態抵达时旧界面不静默放行', () async {
      final Map<String, Object?> changed =
          jsonDecode(bindPreflightOkBody) as Map<String, Object?>;
      changed['consent_mode'] = 'admin_can_do_it_for_them';
      final ServerApi api = apiWithHandler(
        (http.Request request) async => jsonResponse(jsonEncode(changed), 200),
      );
      final ApiError error = await capturePreflightFailure(
        () => api.guestBindPreflight(
          accountId: '01a0e000-0000-7000-8000-0000000000aa',
          targetAccountId: '01a0e000-0000-7000-8000-0000000000bb',
        ),
      );
      expect(error.kind, ApiErrorKind.invalidResponse);
    });

    test('blockers 裡未來新增的記號原樣保留成字串：整份解碼不因此失敗', () async {
      final Map<String, Object?> future =
          jsonDecode(bindPreflightOkBody) as Map<String, Object?>;
      future['blockers'] = <String>['future_blocker_v9'];
      future['executable'] = false;
      future['impacts'] = <String>[];
      final ServerApi api = apiWithHandler(
        (http.Request request) async => jsonResponse(jsonEncode(future), 200),
      );
      final StandardAccountBindPreflightReport report = await api
          .guestBindPreflight(
            accountId: '01a0e000-0000-7000-8000-0000000000aa',
            targetAccountId: '01a0e000-0000-7000-8000-0000000000bb',
          );
      expect(report.blockers, <String>['future_blocker_v9']);
    });

    test('回應合同沒有憑據格子：模型讀得到兩側現值，卻無處存放秘密', () {
      final Map<String, Object?> json =
          jsonDecode(bindPreflightOkBody) as Map<String, Object?>;
      expect(json.keys, isNot(contains('password')));
      expect(json.keys, isNot(contains('password_hash')));
      expect(json.keys, isNot(contains('token')));
      expect(json.keys, isNot(contains('roles')));
      final StandardAccountBindPreflightReport report =
          StandardAccountBindPreflightReport.decode(json);
      // 未知新欄位容忍（只增不刪）。
      final Map<String, Object?> withExtra =
          jsonDecode(bindPreflightOkBody) as Map<String, Object?>;
      withExtra['future_field'] = 42;
      expect(
        StandardAccountBindPreflightReport.decode(withExtra).executable,
        isTrue,
      );
      // 預覽不是綁定：模型沒有任何「已生效」形態的欄位。
      expect(json.keys, isNot(contains('bound')));
      expect(json.keys, isNot(contains('binding_id')));
      expect(report.source.displayName, '待綁旅人');
    });

    test('拒絕只走既有碼：1004 點名欄位、1001 與 2011 各自可判別，預檢本身不發新碼', () async {
      final Map<String, ApiMachineCode> probes = <String, ApiMachineCode>{
        '{"code":1004,"message":"bad","details":{"invalid_field":"target_account_id"},'
                '"request_id":"r-1004"}':
            ApiMachineCode.invalidBody,
        '{"code":1001,"message":"gone","request_id":"r-1001"}':
            ApiMachineCode.notFound,
        '{"code":2011,"message":"denied","request_id":"r-2011"}':
            ApiMachineCode.permissionDenied,
      };
      for (final MapEntry<String, ApiMachineCode> probe in probes.entries) {
        final ServerApi api = apiWithHandler(
          (http.Request request) async => jsonResponse(probe.key, 400),
        );
        final ApiError error = await capturePreflightFailure(
          () => api.guestBindPreflight(
            accountId: '01a0e000-0000-7000-8000-0000000000aa',
            targetAccountId: '01a0e000-0000-7000-8000-0000000000bb',
          ),
        );
        expect(error.knownCode, probe.value);
      }
      // 純只讀的預檢今天仍然只用既有碼：它不簽憑證，所以那兩枚新碼（2025／2026）
      // 不屬於這一條通路的回答。碼本身已隨著簽發與執行那一步收錄，這裡釘的是
      // 「預檢不發新碼」這條界線，而不是代碼表。
      expect(
        probes.values.toSet(),
        isNot(contains(ApiMachineCode.bindTicketInvalid)),
      );
      expect(
        probes.values.toSet(),
        isNot(contains(ApiMachineCode.bindPlanStale)),
      );
      expect(ApiMachineCode.fromValue(2025), ApiMachineCode.bindTicketInvalid);
      expect(ApiMachineCode.fromValue(2026), ApiMachineCode.bindPlanStale);
    });
  });
}
