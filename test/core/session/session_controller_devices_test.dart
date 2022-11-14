/// 會話控制器的「我的裝置」入口測試：列舉與定向撤銷的每一種結局都要落對狀態。
///
/// 全部走真實控制器＋假傳輸＋記憶體安全儲存：要釘的是「伺服器回什麼 → 本機憑據與
/// 狀態怎麼變」，尤其是撤自己這臺必須真的進入退出態、撤別人不能動本機憑據、
/// 2009（列表陳舊）不能被誤當失效、連不上不能被講成沒登入。
library;

import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/core/session/session_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';
import '../../support/test_server.dart';
import '../../support/test_session.dart';

const String _deviceSelf = '019e0000-0000-7000-8000-0000000000aa';
const String _deviceOther = '019e0000-0000-7000-8000-0000000000bb';

String _listBody({
  String selfStatus = 'active',
  bool includeOther = true,
  String otherStatus = 'active',
}) {
  final String self =
      '{"device_id":"$_deviceSelf","created_at":"2026-09-30T03:04:05.000Z",'
      '"last_active_at":"2026-09-30T03:05:05.000Z",'
      '"expires_at":"2026-10-02T03:04:05.000Z","status":"$selfStatus","current":true}';
  final String other =
      '{"device_id":"$_deviceOther","created_at":"2026-09-30T02:04:05.000Z",'
      '"last_active_at":"2026-09-30T02:40:05.000Z",'
      '"expires_at":"2026-10-02T02:04:05.000Z","status":"$otherStatus","current":false}';
  final List<String> items = includeOther
      ? <String>[self, other]
      : <String>[self];
  return '{"devices":[${items.join(',')}],"request_id":"r-list"}';
}

http.Response _revokeBody({
  required bool revoked,
  required bool current,
}) => http.Response(
  '{"device_id":"${current ? _deviceSelf : _deviceOther}","revoked":$revoked,'
  '"current":$current,"request_id":"r-rev"}',
  200,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

ServerApi _api({
  required ServerAddressSettings settings,
  Future<http.Response> Function(http.Request)? onDevices,
  Future<http.Response> Function(http.Request)? onRevoke,
}) {
  return ServerApi(
    config: ServerApiConfig(source: settings),
    client: MockClient((http.Request request) async {
      switch (request.url.path) {
        case kAuthDevicesPath:
          return onDevices == null
              ? jsonOk(_listBody())
              : await onDevices(request);
        case kAuthDeviceRevokePath:
          return onRevoke == null
              ? http.Response('{}', 500)
              : await onRevoke(request);
        default:
          return jsonOk('{}');
      }
    }),
  );
}

void main() {
  late ServerAddressSettings settings;
  late InMemorySessionPersistence store;

  setUp(() async {
    settings = await buildAddressSettings(
      storedUrl: reachableUrl,
      reachable: <String>[reachableUrl],
    );
    store = InMemorySessionPersistence();
  });

  Future<SessionController> signIn() => signedInSession(
    api: _api(settings: settings),
    addresses: settings,
    persistence: store,
    exchange: rootExchange(),
  );

  group('列舉我的裝置', () {
    testWidgets('loaded：回清單、狀態仍是已登入', (WidgetTester tester) async {
      final SessionController session = await signIn();
      final SessionDeviceListResult result = await session.listMyDevices();
      expect(result.outcome, SessionDeviceListOutcome.loaded);
      expect(result.devices.length, 2);
      expect(result.devices.first.current, isTrue);
      expect(session.status, SessionStatus.signedIn);
    });

    testWidgets('未登入：不發請求，回 notSignedIn', (WidgetTester tester) async {
      final SessionController session = nativeSession(
        api: _api(settings: settings),
        addresses: settings,
        persistence: store,
      );
      final SessionDeviceListResult result = await session.listMyDevices();
      expect(result.outcome, SessionDeviceListOutcome.notSignedIn);
    });

    testWidgets('失效（2003）：清憑據、狀態轉為 expired', (WidgetTester tester) async {
      final SessionController session2 = await signedInSession(
        api: _api(
          settings: settings,
          onDevices: (_) async => jsonError(401, 2003, 'r'),
        ),
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      final SessionDeviceListResult r2 = await session2.listMyDevices();
      expect(r2.outcome, SessionDeviceListOutcome.expired);
      expect(session2.status, SessionStatus.expired);
      expect(store.secrets.containsKey(reachableUrl), isFalse);
    });

    testWidgets('查不了（連不上）：停在 signedIn、回 unavailable', (
      WidgetTester tester,
    ) async {
      final SessionController session = await signedInSession(
        api: _api(
          settings: settings,
          onDevices: (_) async => throw http.ClientException('down'),
        ),
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      final SessionDeviceListResult result = await session.listMyDevices();
      expect(result.outcome, SessionDeviceListOutcome.unavailable);
      expect(session.status, SessionStatus.signedIn);
    });
  });

  group('定向撤銷我的裝置', () {
    testWidgets('撤別臺：revoked、本機憑據與狀態不變', (WidgetTester tester) async {
      final SessionController session = await signedInSession(
        api: _api(
          settings: settings,
          onRevoke: (_) async => _revokeBody(revoked: true, current: false),
        ),
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      final SessionDeviceRevokeOutcome outcome = await session.revokeMyDevice(
        _deviceOther,
      );
      expect(outcome, SessionDeviceRevokeOutcome.revoked);
      expect(session.status, SessionStatus.signedIn);
      expect(store.secrets.containsKey(reachableUrl), isTrue);
    });

    testWidgets('撤自己這臺：revokedCurrent、進入 signedOut、清除憑據', (
      WidgetTester tester,
    ) async {
      final SessionController session = await signedInSession(
        api: _api(
          settings: settings,
          onRevoke: (_) async => _revokeBody(revoked: true, current: true),
        ),
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      final SessionDeviceRevokeOutcome outcome = await session.revokeMyDevice(
        _deviceSelf,
      );
      expect(outcome, SessionDeviceRevokeOutcome.revokedCurrent);
      expect(session.status, SessionStatus.signedOut);
      expect(store.secrets.containsKey(reachableUrl), isFalse);
    });

    testWidgets('冪等（目標早已失效）：alreadyInactive、狀態不變', (WidgetTester tester) async {
      final SessionController session = await signedInSession(
        api: _api(
          settings: settings,
          onRevoke: (_) async => _revokeBody(revoked: false, current: false),
        ),
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      final SessionDeviceRevokeOutcome outcome = await session.revokeMyDevice(
        _deviceOther,
      );
      expect(outcome, SessionDeviceRevokeOutcome.alreadyInactive);
      expect(session.status, SessionStatus.signedIn);
    });

    testWidgets('列表陳舊（2009）：staleList、不動憑據', (WidgetTester tester) async {
      final SessionController session = await signedInSession(
        api: _api(
          settings: settings,
          onRevoke: (_) async => jsonError(404, 2009, 'r'),
        ),
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      final SessionDeviceRevokeOutcome outcome = await session.revokeMyDevice(
        _deviceOther,
      );
      expect(outcome, SessionDeviceRevokeOutcome.staleList);
      expect(session.status, SessionStatus.signedIn);
      expect(store.secrets.containsKey(reachableUrl), isTrue);
    });

    testWidgets('查不了（連不上）：unavailable、不謊報已撤銷也未登出', (WidgetTester tester) async {
      final SessionController session = await signedInSession(
        api: _api(
          settings: settings,
          onRevoke: (_) async => throw http.ClientException('down'),
        ),
        addresses: settings,
        persistence: store,
        exchange: rootExchange(),
      );
      final SessionDeviceRevokeOutcome outcome = await session.revokeMyDevice(
        _deviceOther,
      );
      expect(outcome, SessionDeviceRevokeOutcome.unavailable);
      expect(session.status, SessionStatus.signedIn);
    });
  });
}

http.Response jsonError(int status, int code, String requestId) =>
    http.Response(
      '{"code":$code,"message":"server text","request_id":"$requestId"}',
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
