/// 連線探測狀態的測試：階段轉換、訂閱通知，以及「失敗不留下成功數值」。
library;

import 'dart:async';

import 'package:evernight_realm/core/api/api_client.dart';
import 'package:evernight_realm/core/api/api_error.dart';
import 'package:evernight_realm/core/api/connection_tracker.dart';
import 'package:evernight_realm/core/api/server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
    config: ServerApiConfig(baseUrl: baseUrl),
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
        config: const ServerApiConfig(baseUrl: testBaseUrl),
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
        config: const ServerApiConfig(baseUrl: testBaseUrl),
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
}
