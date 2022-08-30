/// 傳輸層的憑據注入與平台分支測試：把「誰該帶憑據、帶哪一台的憑據」變成可執行約束。
///
/// 完成判斷有兩條要在這裡釘死：
/// 1. 原生形态按「本筆請求實際打去的正規化伺服器身份」向來源索取秘密並注入 Bearer；
///    身份對不上就拿不到秘密——從源頭杜絕把甲伺服器憑據發給乙伺服器。
/// 2. 瀏覽器形态永不注入 Bearer（會話由 HttpOnly Cookie 代管），來源甚至不會被呼叫。
library;

import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_server.dart';

/// 只回 `status/service/version/request_id` 的最小健康回應（注入測試不關心內容）。
const String minimalHealth =
    '{"status":"ok","service":"s","version":"v","request_id":"r"}';

/// 合法的「當前會話」回應本體，供 `currentSession` 成功解码。
const String sessionBody =
    '{"subject_kind":"account","account_id":"acc-1","device_id":"dev-1",'
    '"created_at":"2026-09-30T00:00:00.000Z",'
    '"last_active_at":"2026-09-30T00:00:00.000Z",'
    '"expires_at":"2026-10-01T00:00:00.000Z","request_id":"r"}';

const Map<String, String> _jsonHeader = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};

void main() {
  /// 以指定傳輸形态與憑據來源建一個記錄請求標頭與身份呼叫的端點。
  ({ServerApi api, List<String?> authHeaders, List<String?> identities})
  instrumented({
    required SessionTransportMode mode,
    required Map<String, String> secretsByServer,
    String baseUrl = testBaseUrl,
  }) {
    final List<String?> authHeaders = <String?>[];
    final List<String?> identities = <String?>[];
    final ServerApiConfig config = ServerApiConfig.fixed(
      baseUrl,
      transportMode: mode,
      credentials: (String serverIdentity) {
        identities.add(serverIdentity);
        return secretsByServer[serverIdentity];
      },
    );
    final ServerApi api = ServerApi(
      config: config,
      client: MockClient((http.Request request) async {
        authHeaders.add(request.headers['authorization']);
        return http.Response(
          minimalHealth,
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    return (api: api, authHeaders: authHeaders, identities: identities);
  }

  group('原生形态注入', () {
    test('请求打向已保存秘密的伺服器時帶上 Bearer', () async {
      final String identity = ServerAddress.tryParse(testBaseUrl)!.displayText;
      final box = instrumented(
        mode: SessionTransportMode.native,
        secretsByServer: <String, String>{identity: 'SECRET-A'},
      );

      await box.api.health();

      expect(box.identities.single, identity, reason: '取證鍵必須是請求自身的身份');
      expect(box.authHeaders.single, 'Bearer SECRET-A');
    });

    test('请求打向没有秘密的伺服器時不帶任何 authorization', () async {
      final box = instrumented(
        mode: SessionTransportMode.native,
        // 來源裡存的是另一台伺服器的秘密。
        secretsByServer: <String, String>{
          'http://other.invalid:5206': 'SECRET-OTHER',
        },
      );

      await box.api.health();

      // 來源以請求身份被问过一次，但对不上，故回 null → 不注入。
      expect(box.authHeaders.single, isNull);
    });

    test('取證鍵等於請求實際打去的位址，而非組態裡的其他值', () async {
      const String other = 'http://10.0.0.7:5206';
      final String target = ServerAddress.tryParse(testBaseUrl)!.displayText;
      final box = instrumented(
        mode: SessionTransportMode.native,
        secretsByServer: <String, String>{other: 'SECRET'},
      );

      await box.api.health();

      expect(box.identities.single, isNot(other));
      expect(box.identities.single, target);
    });

    test('带路径前缀的身份按规范化文字取證', () async {
      const String base = 'http://10.0.0.9:5206/evernight';
      final String identity = ServerAddress.tryParse(base)!.displayText;
      final box = instrumented(
        mode: SessionTransportMode.native,
        secretsByServer: <String, String>{identity: 'S'},
        baseUrl: base,
      );

      await box.api.health();

      expect(box.identities.single, 'http://10.0.0.9:5206/evernight');
      expect(box.authHeaders.single, 'Bearer S');
    });
  });

  group('浏览器形态永不注入', () {
    test('web 模式不调用凭据来源、不带 authorization', () async {
      final String identity = ServerAddress.tryParse(testBaseUrl)!.displayText;
      final box = instrumented(
        mode: SessionTransportMode.web,
        // 即便「假装」有秘密，web 也不该取用——Cookie 才是浏览器的承載。
        secretsByServer: <String, String>{identity: 'SECRET-A'},
      );

      await box.api.health();

      expect(box.identities, isEmpty, reason: 'web 不应触碰 Bearer 来源');
      expect(box.authHeaders.single, isNull);
    });
  });

  group('显式凭据优先', () {
    test('呼叫端交出 Bearer 时直接采用，不经来源', () async {
      final List<String?> authHeaders = <String?>[];
      bool resolverCalled = false;
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed(
          testBaseUrl,
          transportMode: SessionTransportMode.native,
          credentials: (String _) {
            resolverCalled = true;
            return 'FROM-STORE';
          },
        ),
        client: MockClient((http.Request request) async {
          authHeaders.add(request.headers['authorization']);
          return http.Response(sessionBody, 200, headers: _jsonHeader);
        }),
      );

      await api.currentSession(bearerToken: 'EXPLICIT');

      expect(authHeaders.single, 'Bearer EXPLICIT');
      expect(resolverCalled, isFalse);
    });

    test('该伺服器没有已存秘密时来源被问但不命中、不加标头', () async {
      final box = instrumented(
        mode: SessionTransportMode.native,
        secretsByServer: <String, String>{},
      );

      await box.api.health();

      // 来源仍按请求身份被问过一次（这是隔离键的正常查询），但对不上任何秘密。
      expect(box.identities, hasLength(1));
      expect(box.authHeaders.single, isNull);
    });
  });
}
