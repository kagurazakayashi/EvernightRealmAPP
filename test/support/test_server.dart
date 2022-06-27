/// 端點存取測試的共用助手：假傳輸與固定回應，讓失敗路徑可被逐條斷言。
///
/// 刻意以 `package:http/testing.dart` 的 MockClient 取代自寫假客戶端：
/// 它走的是同一套 `Client` 協定，測試因此仍然經過存取層的真實程式碼。
library;

import 'package:evernight_realm/core/api/api_client.dart';
import 'package:evernight_realm/core/api/server_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 測試用的基準位址：`.invalid` 是保留域名，即使假客戶端失效也不會碰到網路。
const String testBaseUrl = 'http://server.invalid:5206';

/// `/health` 的正常回應本體。
const String healthBody =
    '{"status":"ok","service":"evernight-server","version":"0.1.0-dev",'
    '"request_id":"01a0cd4d-227f-7b42-b091-e501ecf197c1"}';

/// `/ready` 的正常回應本體。
const String readyBody =
    '{"status":"ready","service":"evernight-server",'
    '"request_id":"01a0d7e9-b43f-7b9c-aef1-1d51cab2e2f7"}';

/// `/time` 的正常回應本體（Asia/Shanghai 全年 +08:00）。
const String timeBody =
    '{"time":"2026-09-25T09:33:32.614Z","timezone":"Asia/Shanghai",'
    '"utc_offset_seconds":28800,'
    '"request_id":"01a0d7e9-b446-72b2-a1e8-87a33231cd7a"}';

/// 測試回應攜帶的關聯 ID（標頭與信封都用它）。
const String stubRequestId = '01a00000-0000-7000-8000-000000000001';

/// 依路徑回傳預設的三份正常回應；[overrides]/[statuses] 可覆寫單一路徑。
ServerApi stubApi({
  Map<String, String> overrides = const <String, String>{},
  Map<String, int> statuses = const <String, int>{},
}) {
  final Map<String, String> bodies = <String, String>{
    kHealthPath: healthBody,
    kReadyPath: readyBody,
    kTimePath: timeBody,
  }..addAll(overrides);

  return ServerApi(
    config: ServerApiConfig.fixed(testBaseUrl),
    client: MockClient((http.Request request) async {
      return http.Response(
        bodies[request.url.path] ?? '{}',
        statuses[request.url.path] ?? 200,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
          'x-request-id': stubRequestId,
        },
      );
    }),
  );
}

/// 以自訂處理器建立假端點：既可回正常回應，也可製造連不上、逾時等傳輸級失敗。
ServerApi apiWithHandler(Future<http.Response> Function(http.Request) handler) {
  return ServerApi(
    config: ServerApiConfig.fixed(testBaseUrl),
    client: MockClient(handler),
  );
}

/// 一則 200 的 JSON 回應。
http.Response jsonOk(String body) {
  return http.Response(
    body,
    200,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}
