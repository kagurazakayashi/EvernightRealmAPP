/// 連線探測狀態的測試：階段轉換、訂閱通知，以及「失敗不留下成功數值」。
library;

import 'dart:async';

import 'package:evernight_realm/core/api/api_client.dart';
import 'package:evernight_realm/core/api/api_error.dart';
import 'package:evernight_realm/core/api/connection_tracker.dart';
import 'package:evernight_realm/core/api/server_address.dart';
import 'package:evernight_realm/core/api/server_address_settings.dart';
import 'package:evernight_realm/core/api/server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';
import '../../support/test_server.dart';

/// 記錄每次請求的路徑，並依 [respond] 決定回應。
class _Recorder {
  final List<String> paths = <String>[];

  MockClient client(Future<http.Response> Function(http.Request) respond) {
    return MockClient((http.Request request) async {
      paths.add(request.url.path);
      return respond(request);
    });
  }
}

/// 建立探測用的端點與追蹤器。
(ConnectionTracker, _Recorder) tracked({
  String baseUrl = testBaseUrl,
  Future<http.Response> Function(http.Request)? respond,
}) {
  final _Recorder recorder = _Recorder();
  final ServerApi api = ServerApi(
    config: ServerApiConfig.fixed(baseUrl),
    client: recorder.client(
      respond ??
          (http.Request request) async =>
              jsonOk(request.url.path == kTimePath ? timeBody : healthBody),
    ),
  );
  return (ConnectionTracker(api), recorder);
}

void main() {
  group('起點階段', () {
    test('未注入位址時為未設定，不預先假裝能探測', () {
      final ConnectionTracker tracker = tracked(baseUrl: '').$1;

      expect(tracker.phase, ServerConnectionPhase.notConfigured);
      expect(tracker.isConfigured, isFalse);
      expect(tracker.addressDisplay, isNull);
      expect(tracker.result, isNull);
    });

    test('已有位址但尚未探測', () {
      final ConnectionTracker tracker = tracked().$1;

      expect(tracker.phase, ServerConnectionPhase.notProbed);
      expect(tracker.addressDisplay, testBaseUrl);
      expect(tracker.result, isNull);
      expect(tracker.error, isNull);
    });
  });

  group('探測成功', () {
    test('讀到存活與校時兩份回應並通知訂閱者', () async {
      final (ConnectionTracker tracker, _Recorder recorder) = tracked();
      int notifications = 0;
      tracker.addListener(() => notifications++);

      await tracker.probe(acceptLanguage: 'ja-JP');

      expect(tracker.phase, ServerConnectionPhase.probeSucceeded);
      expect(tracker.error, isNull);
      expect(tracker.result!.health.service, 'evernight-server');
      expect(tracker.result!.time.utcOffsetSeconds, 28800);
      expect(recorder.paths, <String>[kHealthPath, kTimePath]);
      // 開始與結束各通知一次。
      expect(notifications, 2);
    });

    test('探測中為 probing 階段，結束後才落定', () async {
      final Completer<http.Response> pending = Completer<http.Response>();
      final (ConnectionTracker tracker, _) = tracked(
        respond: (_) => pending.future,
      );

      final Future<void> running = tracker.probe();
      expect(tracker.phase, ServerConnectionPhase.probing);
      expect(tracker.isProbing, isTrue);

      pending.complete(jsonOk(healthBody));
      await running;
      expect(tracker.phase, ServerConnectionPhase.probeFailed);
    });
  });

  group('探測失敗', () {
    test('連不上時記錄原因且清空成功數值', () async {
      final (ConnectionTracker tracker, _) = tracked(
        respond: (_) async => throw http.ClientException('no route to host'),
      );

      await tracker.probe();

      expect(tracker.phase, ServerConnectionPhase.probeFailed);
      expect(tracker.result, isNull, reason: '失敗後不得還掛著上一次的數值');
      expect(tracker.error!.kind, ApiErrorKind.unreachable);
    });

    test('校時端點回 503 時整趟探測判為失敗', () async {
      final (ConnectionTracker tracker, _) = tracked(
        respond: (http.Request request) async {
          if (request.url.path == kTimePath) {
            return http.Response(
              '{"code":1007,"message":"not ready","request_id":"r"}',
              503,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return jsonOk(healthBody);
        },
      );

      await tracker.probe();

      expect(tracker.phase, ServerConnectionPhase.probeFailed);
      expect(tracker.error!.knownCode, ApiMachineCode.notReady);
      expect(tracker.error!.retryable, isTrue);
    });

    test('探測不外洩例外，失敗只以狀態呈現', () async {
      final (ConnectionTracker tracker, _) = tracked(
        respond: (_) async => throw StateError('unexpected'),
      );

      await expectLater(tracker.probe(), completes);
      expect(tracker.phase, ServerConnectionPhase.probeFailed);
    });

    test('位址未設定時探測不發請求也不改變階段', () async {
      final (ConnectionTracker tracker, _Recorder recorder) = tracked(
        baseUrl: '',
      );

      await tracker.probe();

      expect(recorder.paths, isEmpty);
      expect(tracker.phase, ServerConnectionPhase.notConfigured);
    });
  });

  group('併發', () {
    test('探測進行中的重複呼叫沿用同一趟，不會交錯兩份結果', () async {
      final Completer<http.Response> gate = Completer<http.Response>();
      final List<String> paths = <String>[];
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed(testBaseUrl),
        client: MockClient((http.Request request) async {
          paths.add(request.url.path);
          return request.url.path == kHealthPath
              ? gate.future
              : jsonOk(timeBody);
        }),
      );
      final ConnectionTracker tracker = ConnectionTracker(api);

      final Future<void> a = tracker.probe();
      final Future<void> b = tracker.probe();
      expect(identical(a, b), isTrue, reason: '第二次呼叫應沿用同一趟任務');

      gate.complete(jsonOk(healthBody));
      await a;

      expect(paths, <String>[kHealthPath, kTimePath], reason: '重複呼叫不該多發一輪');
      expect(tracker.phase, ServerConnectionPhase.probeSucceeded);
    });

    test('一趟結束後可以再探測', () async {
      final (ConnectionTracker tracker, _Recorder recorder) = tracked();

      await tracker.probe();
      await tracker.probe();

      expect(recorder.paths, <String>[
        kHealthPath,
        kTimePath,
        kHealthPath,
        kTimePath,
      ]);
      expect(tracker.phase, ServerConnectionPhase.probeSucceeded);
    });
  });

  group('語言標識', () {
    test('探測把介面語言送給伺服器', () async {
      final List<String?> sent = <String?>[];
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed(testBaseUrl),
        client: MockClient((http.Request request) async {
          sent.add(request.headers['accept-language']);
          return jsonOk(request.url.path == kTimePath ? timeBody : healthBody);
        }),
      );
      final ConnectionTracker tracker = ConnectionTracker(api);

      await tracker.probe(acceptLanguage: 'zh-TW');

      expect(sent, <String?>['zh-TW', 'zh-TW']);
    });
  });

  group('位址可變時的結果歸屬', () {
    /// 以「位址設定」當來源建立端點與追蹤器：這才是接入使用者輸入後的真實接法。
    ///
    /// 驗證器刻意共用同一個假傳輸，保存前那趟驗證與探測區探測因此記錄在同一份
    /// 請求清單上，「沿用結果、不多發請求」才真的可被斷言。
    Future<(ConnectionTracker, ServerAddressSettings, List<String>)> wired({
      String? storedUrl,
      Future<http.Response> Function(http.Request)? respond,
    }) async {
      final List<String> paths = <String>[];
      final MockClient client = MockClient((http.Request request) async {
        paths.add('${request.url.host}${request.url.path}');
        // 測試可自行決定回應（例如把 /health 掛住），未指定時給正常回應。
        if (respond != null) {
          return respond(request);
        }
        return jsonOk(request.url.path == kTimePath ? timeBody : healthBody);
      });

      final ServerAddressSettings settings = ServerAddressSettings(
        InMemoryServerAddressPersistence(storedUrl),
        preferInjected: false,
        verifier: (ServerAddress address, {String? acceptLanguage}) =>
            probeServerConnectivity(
              ServerApi(
                config: ServerApiConfig.fixed(address.displayText),
                client: client,
              ),
              acceptLanguage: acceptLanguage,
            ),
      );
      await settings.restore();

      final ServerApi api = ServerApi(
        config: ServerApiConfig(source: settings),
        client: client,
      );
      return (ConnectionTracker(api, addresses: settings), settings, paths);
    }

    test('換位址後舊探測結果立即作廢，不掛著另一台伺服器的數值', () async {
      const String other = 'http://10.0.0.77:5206';
      final (ConnectionTracker tracker, ServerAddressSettings settings, _) =
          await wired(storedUrl: testBaseUrl);

      await tracker.probe();
      expect(tracker.phase, ServerConnectionPhase.probeSucceeded);
      expect(tracker.result, isNotNull);

      await settings.save(other);

      expect(
        tracker.phase,
        ServerConnectionPhase.notProbed,
        reason: '地址已換，上一台的結果不能留著',
      );
      expect(tracker.result, isNull);
      expect(tracker.addressDisplay, other);
    });

    test('保存時那趟驗證的結果可直接沿用，不必再發一次請求', () async {
      const String other = 'http://10.0.0.77:5206';
      final (
        ConnectionTracker tracker,
        ServerAddressSettings settings,
        List<String> paths,
      ) = await wired(
        storedUrl: testBaseUrl,
      );
      int notifications = 0;
      tracker.addListener(() => notifications++);

      final ServerAddressSaveResult result = await settings.save(other);
      final int pathsAfterSave = paths.length;
      tracker.adopt(result.probe!);

      expect(result.isSaved, isTrue);
      expect(pathsAfterSave, greaterThanOrEqualTo(2), reason: '保存前確實探過');
      expect(tracker.phase, ServerConnectionPhase.probeSucceeded);
      expect(tracker.result?.time.timezone, 'Asia/Shanghai');
      expect(paths.length, pathsAfterSave, reason: 'adopt 不該再發出請求');
      expect(notifications, greaterThanOrEqualTo(2), reason: '作廢一次、沿用一次');
    });

    test('探測期間位址被換掉時丟棄該筆結果', () async {
      final Completer<http.Response> gate = Completer<http.Response>();
      const String other = 'http://10.0.0.77:5206';
      final (
        ConnectionTracker tracker,
        ServerAddressSettings settings,
        _,
      ) = await wired(
        storedUrl: testBaseUrl,
        respond: (http.Request request) async => request.url.path == kHealthPath
            ? await gate.future
            : jsonOk(timeBody),
      );

      final Future<void> probing = tracker.probe();
      expect(tracker.phase, ServerConnectionPhase.probing);

      // 請求還沒回來就換了地址：完成後這筆結果描述的已不是目前這台伺服器。
      final Future<ServerAddressSaveResult> pendingSave = settings.save(other);
      gate.complete(jsonOk(healthBody));
      await pendingSave;
      await probing;

      expect(tracker.addressDisplay, other);
      expect(tracker.phase, ServerConnectionPhase.notProbed);
      expect(tracker.result, isNull);
    });

    test('位址未變時不多餘作廢', () async {
      final (ConnectionTracker tracker, ServerAddressSettings settings, _) =
          await wired(storedUrl: testBaseUrl);

      await tracker.probe();
      final ServerProbeResult? before = tracker.result;
      int notifications = 0;
      tracker.addListener(() => notifications++);

      // 重新載入同一個值並通知（其他設定變更也會走到）：位址相同就不該動結果。
      await settings.restore();

      expect(tracker.phase, ServerConnectionPhase.probeSucceeded);
      expect(tracker.result, same(before));
      expect(notifications, 0);
    });

    test('未接入位址設定時行為不變（工具與既有測試的路徑）', () async {
      final ConnectionTracker tracker = tracked().$1;

      await tracker.probe();

      expect(tracker.phase, ServerConnectionPhase.probeSucceeded);
    });
  });
}
