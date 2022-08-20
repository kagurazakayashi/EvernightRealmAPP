/// Root 初始化狀態端點的合同測試：路徑、欄位型別、失敗形態，以及「只讀」這件事。
///
/// 全部走 `package:http` 的 MockClient：請求仍經 ApiClient 的真實解碼與合同判定，
/// 但不碰網路，也不碰任何真實服務。
library;

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 取回一次失敗：拿不到值本身就是斷言，否則測試等於默許「失敗也回一份狀態」。
Future<ApiError> captureInitStatusFailure(ServerApi api) async {
  try {
    await api.initStatus();
  } on ApiError catch (error) {
    return error;
  }
  throw StateError('預期抛出 ApiError，卻拿到一份狀態');
}

void main() {
  group('初始化狀態端點', () {
    test('走 /root/init-status，並把三個布林如實讀回', () async {
      final List<String> asked = <String>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        asked.add(request.url.path);
        return jsonOk(
          '{"config_exists":true,"root_initialized":false,'
          '"env_override":true,"request_id":"r-42"}',
        );
      });

      final InitStatusReport report = await api.initStatus();

      expect(asked, <String>[kRootInitStatusPath]);
      expect(report.configExists, isTrue);
      expect(report.rootInitialized, isFalse);
      expect(report.envOverride, isTrue);
      expect(report.requestId, 'r-42');
    });

    test('請求不帶本體也不帶任何憑據：這條路上沒有口令可送', () async {
      final List<String?> bodies = <String?>[];
      final List<String> methods = <String>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        methods.add(request.method);
        bodies.add(request.body.isEmpty ? null : request.body);
        return jsonOk(
          '{"config_exists":true,"root_initialized":true,"env_override":false,'
          '"request_id":"r-1"}',
        );
      });

      await api.initStatus();

      expect(methods, <String>['GET']);
      expect(bodies, <String?>[null]);
    });

    test('欄位型別不符即判為失敗，不猜成「尚未初始化」', () async {
      // 把 root_initialized 寫成字串 "true"：型別一不符就沒有可靠真假可言，
      // 任何猜法都可能對一個已經有 Root 的部署建議去初始化（或反過來說「已初始化」
      // 而其實沒有）；失敗比猜測安全，這裡要的就是失敗。
      final ServerApi api = apiWithHandler(
        (_) async => jsonOk(
          '{"config_exists":true,"root_initialized":"true","request_id":"r-2"}',
        ),
      );

      final ApiError error = await captureInitStatusFailure(api);

      expect(error.kind, ApiErrorKind.invalidResponse);
    });

    test('必要欄位缺席一樣是失敗', () async {
      final ServerApi api = apiWithHandler(
        (_) async => jsonOk('{"config_exists":true,"request_id":"r-3"}'),
      );

      expect(
        (await captureInitStatusFailure(api)).kind,
        ApiErrorKind.invalidResponse,
      );
    });

    test('回應中的未知新欄位被容忍（後端只增不刪）', () async {
      final ServerApi api = apiWithHandler(
        (_) async => jsonOk(
          '{"config_exists":true,"root_initialized":true,"env_override":false,'
          '"request_id":"r-5","some_future_field":"x"}',
        ),
      );

      final InitStatusReport report = await api.initStatus();

      expect(report.rootInitialized, isTrue);
    });

    test('伺服器查不出來時回的是失敗，不是一份未初始化', () async {
      final ServerApi api = apiWithHandler(
        (_) async => http.Response(
          '{"code":1000,"message":"Something went wrong.","request_id":"r-6"}',
          500,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final ApiError error = await captureInitStatusFailure(api);

      expect(error.kind, ApiErrorKind.httpStatus);
      expect(error.machineCode, ApiMachineCode.internalError.value);
      // 伺服器原文只留在診斷欄位（介面顯示一律另經 ARB），這裡釘住它確實被保留、
      // 也釘住關聯 ID 抓得到——操作者回報時靠的就是這一個。
      expect(error.serverMessage, 'Something went wrong.');
      expect(error.requestId, 'r-6');
    });

    test('端點還沒上線（舊版服務）時是 1001 失敗，不是「未初始化」', () async {
      final ServerApi api = apiWithHandler(
        (_) async => http.Response(
          '{"code":1001,"message":"not found","request_id":"r-7"}',
          404,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final ApiError error = await captureInitStatusFailure(api);

      expect(error.knownCode, ApiMachineCode.notFound);
    });
  });
}
