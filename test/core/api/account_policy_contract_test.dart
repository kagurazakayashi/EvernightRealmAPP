/// 帳戶建立策略端點的合同測試：路徑、方法、本體欄位白名單、巢狀 `entry` 的必填性，
/// 以及「策略值與對外答案各是各的欄位」這件事在解碼層是否真的分開。
///
/// 全部走 `package:http` 的 MockClient：請求仍經 ApiClient 的真實解碼與合同判定，
/// 但不碰網路，也不碰任何真實服務。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 一份完整的策略回應：三個值＋時刻＋巢狀 entry＋關聯 ID。
String _policyBody({
  bool adminCreate = false,
  String mode = 'closed',
  bool guest = false,
  String? updatedAt = '2026-10-03T09:00:00.000Z',
  bool signUpOpen = false,
  bool guestOpen = false,
}) {
  final Map<String, Object?> body = <String, Object?>{
    'admin_create_standard': adminCreate,
    'self_register_mode': mode,
    'guest_enabled': guest,
    'entry': <String, Object?>{
      'sign_up_open': signUpOpen,
      'guest_open': guestOpen,
    },
    'request_id': 'r-policy',
  };
  // 欄位要「缺席」而不是 null：後端的 updated_at 是 omitempty，
  // 測試本體得重現同一種形狀，否則讀成 null 與讀不到欄位兩件事在這裡會被混起來。
  if (updatedAt != null) {
    body['updated_at'] = updatedAt;
  }
  return jsonEncode(body);
}

/// 取回一次失敗：拿不到值本身就是斷言，否則測試等於默許「失敗也回一份策略」。
Future<ApiError> capturePolicyFailure(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiError catch (error) {
    return error;
  }
  throw StateError('預期抛出 ApiError，卻拿到一份策略');
}

void main() {
  group('帳戶建立策略端點', () {
    test('現讀走 /root/account-policy，並把三個值與對外答案分開讀回', () async {
      final List<String> asked = <String>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        asked.add(request.url.path);
        return jsonOk(_policyBody());
      });

      final AccountPolicyReport report = await api.accountPolicy();

      expect(asked, <String>[kRootAccountPolicyPath]);
      expect(report.adminCreateStandard, isFalse);
      expect(report.selfRegisterMode, 'closed');
      expect(report.guestEnabled, isFalse);
      expect(report.updatedAt, isNotNull);
      expect(report.entry.signUpOpen, isFalse);
      expect(report.entry.guestOpen, isFalse);
      expect(report.requestId, 'r-policy');
    });

    test('updated_at 缺席讀成 null（那是「從未修改」的事實，不是查不到時刻）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => jsonOk(_policyBody(updatedAt: null)),
      );

      final AccountPolicyReport report = await api.accountPolicy();

      expect(report.updatedAt, isNull);
    });

    test('模式原字保留：未知名字不降級成 closed，並被標為本版本不可選', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => jsonOk(_policyBody(mode: 'approval')),
      );

      final AccountPolicyReport report = await api.accountPolicy();

      expect(report.selfRegisterMode, 'approval');
      expect(report.isKnownMode, isTrue);
      expect(report.isWritableMode, isFalse);
    });

    test('回應裡多出界面還不認得的欄位要容忍（後端合同只增不刪）', () async {
      final Map<String, Object?> body =
          jsonDecode(_policyBody(mode: 'invite')) as Map<String, Object?>;
      body['future_switch'] = true;
      final ServerApi api = apiWithHandler(
        (http.Request request) async => jsonOk(jsonEncode(body)),
      );

      final AccountPolicyReport report = await api.accountPolicy();

      expect(report.selfRegisterMode, 'invite');
      expect(report.isKnownMode, isTrue);
    });

    test('保存走同一條路徑的 PUT，本體恰好三個欄位', () async {
      final List<String> methods = <String>[];
      final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        methods.add(request.method);
        sent.add(jsonDecode(request.body) as Map<String, Object?>);
        return jsonOk(
          _policyBody(
            adminCreate: true,
            mode: 'open',
            guest: false,
            updatedAt: '2026-10-03T09:30:00.000Z',
          ),
        );
      });

      final AccountPolicyReport report = await api.updateAccountPolicy(
        adminCreateStandard: true,
        selfRegisterMode: 'open',
        guestEnabled: false,
      );

      expect(methods, <String>['PUT']);
      expect(sent.single.keys, <String>{
        'admin_create_standard',
        'self_register_mode',
        'guest_enabled',
      });
      expect(sent.single['self_register_mode'], 'open');
      // 本體沒有任何依據值欄位：這是一份單例文件的整份 PUT。
      expect(sent.single.containsKey('expected_mode'), isFalse);
      expect(report.adminCreateStandard, isTrue);
    });

    test('保存成功的回應仍是合同物件：entry 缺席判違例而不降級成「全關」', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        expect(request.method, 'PUT');
        return jsonOk(
          '{"admin_create_standard":true,"self_register_mode":"open",'
          '"guest_enabled":true,"request_id":"r-policy"}',
        );
      });

      final ApiError error = await capturePolicyFailure(
        () => api.updateAccountPolicy(
          adminCreateStandard: true,
          selfRegisterMode: 'open',
          guestEnabled: true,
        ),
      );

      expect(error.kind, ApiErrorKind.invalidResponse);
    });

    test('必填布林缺席不降級成 false：合同違例要作為失敗抛出', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return jsonOk(
          '{"self_register_mode":"open","entry":{"sign_up_open":false,'
          '"guest_open":false},"request_id":"r-policy"}',
        );
      });

      final ApiError error = await capturePolicyFailure(api.accountPolicy);

      expect(error.kind, ApiErrorKind.invalidResponse);
    });

    test('2016 有自己的碼：它不是 1004 那句「格式不對」', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => http.Response(
          '{"code":2016,"message":"x","request_id":"r-err"}',
          400,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final ApiError error = await capturePolicyFailure(
        () => api.updateAccountPolicy(
          adminCreateStandard: true,
          selfRegisterMode: 'approval',
          guestEnabled: true,
        ),
      );

      expect(error.machineCode, 2016);
      expect(error.knownCode, ApiMachineCode.accountPolicyModeUnavailable);
    });

    test('2016 的數值在錯誤碼表裡唯一且可判別', () {
      expect(
        ApiMachineCode.fromValue(2016),
        ApiMachineCode.accountPolicyModeUnavailable,
      );
      expect(ApiMachineCode.accountPolicyModeUnavailable.value, 2016);
    });

    test('對外入口端點走 /auth/capabilities，只有兩個布林加關聯 ID', () async {
      final List<String> asked = <String>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        asked.add(request.url.path);
        return jsonOk(
          '{"sign_up_open":false,"guest_open":false,"request_id":"r-entry"}',
        );
      });

      final EntryCapabilitiesReport report = await api.entryCapabilities();

      expect(asked, <String>[kAuthCapabilitiesPath]);
      expect(report.entry.signUpOpen, isFalse);
      expect(report.entry.guestOpen, isFalse);
      expect(report.requestId, 'r-entry');
    });

    test('對外端點查不出來時抛出錯誤，不降級成一份「全關」的答案', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => http.Response(
          '{"code":1000,"message":"x","request_id":"r-err"}',
          500,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final ApiError error = await capturePolicyFailure(api.entryCapabilities);

      expect(error.machineCode, 1000);
      expect(error.knownCode, ApiMachineCode.internalError);
    });
  });
}
