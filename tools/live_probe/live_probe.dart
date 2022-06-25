/// 以真實網路對實際啟動的服務走同一份存取層程式碼，驗證成功讀取與失敗判定。
///
/// 用途：單元測試用假傳輸覆蓋了每一條分支，這裡補的是「真的開連線、真的收
/// 伺服器回的信」這一層證據，以及三件單元測試給不了的事：
/// 1. 對真實服務的 `/health`、`/ready`、`/time` 讀到符合合同的數值；
/// 2. 未知路徑與未就緒時，後端的錯誤信封確實轉成機器碼與關聯 ID；
/// 3. 連不上、逾時、以及「HTTP 200 但內容抵觸合同」時，呼叫端拿不到任何值。
///
/// 執行：`dart run tools/live_probe/live_probe.dart http://127.0.0.1:5299`
/// 全部案例只讀不寫，並會在本行程內起兩個假服務（假合同與假遲鈍），結束時關閉。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evernight_realm/core/api/api_client.dart';
import 'package:evernight_realm/core/api/api_error.dart';
import 'package:evernight_realm/core/api/server_address.dart';
import 'package:evernight_realm/core/api/server_api.dart';
import 'package:evernight_realm/core/api/server_models.dart';

/// 通過的檢查數。
int _passed = 0;

/// 失敗的檢查名稱。
final List<String> _failures = <String>[];

/// 記錄一項檢查的結果。
void _check(String name, bool ok, [String detail = '']) {
  final String suffix = detail.isEmpty ? '' : ' — $detail';
  if (ok) {
    _passed++;
    stdout.writeln('[PASS] $name$suffix');
  } else {
    _failures.add(name);
    stdout.writeln('[FAIL] $name$suffix');
  }
}

/// 執行 [run]，回傳它抛出的 [ApiError]；正常回傳時回傳 `null`。
Future<ApiError?> _capture(Future<Object?> Function() run) async {
  try {
    await run();
    return null;
  } on ApiError catch (error) {
    return error;
  }
}

/// 以真實連線建立端點介面（刻意不注入假傳輸）。
ServerApi _live(String baseUrl, {Duration? timeout}) {
  return ServerApi(
    config: ServerApiConfig(
      baseUrl: baseUrl,
      requestTimeout: timeout ?? const Duration(seconds: 5),
    ),
  );
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tools/live_probe/live_probe.dart <服務位址>');
    exitCode = 2;
    return;
  }
  final String serverUrl = args.first;

  stdout.writeln('== 讀取真實服務：$serverUrl');
  await _readLiveEndpoints(serverUrl);
  await _mapRealErrors(serverUrl);
  await _rejectBadContract();
  await _hitClosedPort();
  await _timeOut();
  await _rejectBadAddress();

  stdout.writeln('');
  stdout.writeln('結果: $_passed 項通過，${_failures.length} 項失敗');
  for (final String name in _failures) {
    stdout.writeln('  失敗: $name');
  }
  exitCode = _failures.isEmpty ? 0 : 1;
}

/// 把 HH:mm:ss 由 UTC 加上偏移，作為獨立算出的期望值。
String _wallClock(DateTime utc, int offsetSeconds) {
  final DateTime shifted = utc.add(Duration(seconds: offsetSeconds));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(shifted.hour)}:${two(shifted.minute)}:${two(shifted.second)}';
}

/// 讀三個基礎端點，逐欄位比對後端發布的合同。
Future<void> _readLiveEndpoints(String baseUrl) async {
  final ServerApi api = _live(baseUrl);

  final HealthReport health = await api.health(acceptLanguage: 'zh-CN');
  _check('/health 讀到存活報告', health.reportsOk, 'status=${health.status}');
  _check(
    '/health 的服務名與版本非空',
    health.service.isNotEmpty && health.version.isNotEmpty,
    '${health.service} ${health.version}',
  );

  final ReadinessReport ready = await api.ready(acceptLanguage: 'zh-CN');
  _check('/ready 讀到就緒報告', ready.reportsReady, 'status=${ready.status}');

  final ServerTimeReport time = await api.time(acceptLanguage: 'zh-CN');
  _check(
    '/time 原文為 24 字元且以 Z 結尾',
    time.timeText.length == 24 && time.timeText.endsWith('Z'),
    time.timeText,
  );
  _check('/time 解析後為 UTC', time.time.isUtc, time.time.toIso8601String());
  final Duration drift = time.time.difference(DateTime.now().toUtc()).abs();
  _check(
    '/time 與本機 UTC 相差不到 5 秒',
    drift.inSeconds < 5,
    '漂移 ${drift.inMilliseconds} 毫秒',
  );
  _check(
    '/time 的牆鐘時間與偏移一致',
    time.displayClock == _wallClock(time.time, time.utcOffsetSeconds),
    '${time.displayClock} @ ${time.timezone} ${time.utcOffsetText}',
  );
  _check('/time 帶回 36 字元的關聯 ID', time.requestId.length == 36, time.requestId);

  // 連續兩次取值：時間不倒退、格式恆定（合同要求毫秒恆為三位）。
  final ServerTimeReport again = await api.time();
  _check(
    '連續取值格式恆定且不倒退',
    again.timeText.length == 24 && !again.time.isBefore(time.time),
    '${time.timeText} -> ${again.timeText}',
  );
}

/// 對真實服務製造 404 與四語言原文，驗證錯誤轉換與「介面文案不取伺服器原文」的前提。
Future<void> _mapRealErrors(String baseUrl) async {
  final ApiClient client = ApiClient(config: ServerApiConfig(baseUrl: baseUrl));
  const String missing = '/step051-live-probe-does-not-exist';

  final ApiError? fallback = await _capture(
    () => client.get(missing, decode: HealthReport.decode),
  );
  _check(
    '未知路徑轉為 404 + 機器碼 1001',
    fallback != null &&
        fallback.kind == ApiErrorKind.httpStatus &&
        fallback.httpStatus == 404 &&
        fallback.machineCode == 1001 &&
        fallback.knownCode == ApiMachineCode.notFound &&
        !fallback.retryable,
    fallback?.toString() ?? '竟然回傳了值',
  );
  _check(
    '未帶 Accept-Language 時伺服器原文回退英文',
    (fallback?.serverMessage ?? '').contains('does not exist'),
    fallback?.serverMessage ?? '',
  );

  final Map<String, String> expected = const <String, String>{
    'zh-CN': '不存在',
    'zh-TW': '不存在',
    'ja-JP': '存在しません',
    'en-US': 'does not exist',
  };
  for (final MapEntry<String, String> entry in expected.entries) {
    final ApiError? localized = await _capture(
      () => client.get(
        missing,
        decode: HealthReport.decode,
        acceptLanguage: entry.key,
      ),
    );
    _check(
      'Accept-Language ${entry.key} 拿到對應語言的原文',
      localized != null &&
          (localized.serverMessage ?? '').contains(entry.value) &&
          localized.machineCode == 1001,
      localized?.serverMessage ?? '',
    );
  }

  // 關聯 ID 要能同時由標頭與信封取得，否則日誌串不起來。
  final ServerAddress? address = ServerAddress.tryParse(baseUrl);
  final HttpClient raw = HttpClient();
  try {
    final HttpClientRequest request = await raw.getUrl(
      address!.resolve(missing),
    );
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 5),
    );
    final String headerId = response.headers.value('x-request-id') ?? '';
    final String body = await utf8.decoder.bind(response).join();
    final String envelopeId =
        RegExp('"request_id"\\s*:\\s*"([^"]+)"').firstMatch(body)?.group(1) ??
        '';
    _check(
      '標頭與信封的 request_id 同源',
      headerId.isNotEmpty && headerId == envelopeId,
      headerId,
    );
  } finally {
    raw.close(force: true);
  }
}

/// 起了假服務回 HTTP 200 但內容抵觸合同，呼叫端必須拿不到值。
Future<void> _rejectBadContract() async {
  final HttpServer fake = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  fake.listen((HttpRequest request) {
    void send(int status, String body, ContentType type) {
      request.response
        ..statusCode = status
        ..headers.contentType = type
        ..write(body);
      request.response.close();
    }

    switch (request.uri.path) {
      case '/missing-fields':
        // 200 但缺少 version 與 request_id：最容易蒙混過關的一種失敗。
        send(
          200,
          '{"status":"ok","service":"evernight-server"}',
          ContentType.json,
        );
      case '/not-json':
        send(200, 'ok', ContentType.text);
      case '/json-array':
        send(200, '["ok"]', ContentType.json);
      case '/empty':
        send(200, '', ContentType.json);
      case '/naive-time':
        send(
          200,
          '{"time":"2026-09-25T09:33:32.614","timezone":"Asia/Shanghai",'
          '"utc_offset_seconds":28800,"request_id":"r"}',
          ContentType.json,
        );
      case '/text-200-json-body':
        send(200, '{"status":"ok"}', ContentType.text);
      case '/error-envelope':
        send(
          503,
          '{"code":1007,"message":"服務尚未就緒，請稍後重試。",'
          '"request_id":"r-from-body"}',
          ContentType.json,
        );
      case '/plain-500':
        send(500, 'boom', ContentType.text);
      case '/offset-time':
        send(
          200,
          '{"time":"2026-09-25T17:33:32.614+08:00","timezone":"Asia/Shanghai",'
          '"utc_offset_seconds":28800,"request_id":"r"}',
          ContentType.json,
        );
      default:
        send(404, 'not found', ContentType.text);
    }
  });

  final String base = 'http://127.0.0.1:${fake.port}';
  final ApiClient client = ApiClient(config: ServerApiConfig(baseUrl: base));

  Future<void> expectInvalid(
    String path,
    String label, {
    ResponseDecoder<Object?> decode = HealthReport.decode,
    String? expectCause,
  }) async {
    final ApiError? error = await _capture(
      () => client.get(path, decode: decode),
    );
    _check(
      '$label 不視為成功',
      error != null && error.kind == ApiErrorKind.invalidResponse,
      error == null ? '竟然回傳了值' : '${error.kind.name} / ${error.cause}',
    );
    if (expectCause != null) {
      _check(
        '$label 的原因指向 $expectCause',
        error != null && '${error.cause}'.contains(expectCause),
        '${error?.cause}',
      );
    }
  }

  await expectInvalid('/missing-fields', '200 缺必要欄位');
  await expectInvalid('/not-json', '200 本體不是 JSON');
  await expectInvalid('/text-200-json-body', '200 內容型別不是 JSON');
  await expectInvalid('/json-array', '200 頂層不是物件');
  await expectInvalid('/empty', '200 本體為空');
  await expectInvalid(
    '/naive-time',
    '時間缺少時區標記',
    decode: ServerTimeReport.decode,
    expectCause: '缺少時區標記',
  );

  // 帶偏移的時間屬合法輸入：必須解析為同一瞬間。
  final ServerTimeReport offset = await client.get(
    '/offset-time',
    decode: ServerTimeReport.decode,
  );
  _check(
    '帶 +08:00 偏移的時間解析為同一瞬間',
    offset.time == DateTime.utc(2026, 9, 25, 9, 33, 32, 614) &&
        offset.displayClock == '17:33:32',
    '${offset.timeText} -> ${offset.time.toIso8601String()}',
  );

  // 503 信封：走 ServerApi 的 /ready 需要路徑相符，這裡直接打同名路徑。
  final ApiError? envelope = await _capture(
    () => client.get('/error-envelope', decode: ReadinessReport.decode),
  );
  _check(
    '503 信封轉為機器碼 1007 且可重試',
    envelope != null &&
        envelope.kind == ApiErrorKind.httpStatus &&
        envelope.machineCode == 1007 &&
        envelope.knownCode == ApiMachineCode.notReady &&
        envelope.retryable &&
        envelope.requestId == 'r-from-body',
    envelope?.toString() ?? '竟然回傳了值',
  );

  final ApiError? plain = await _capture(
    () => client.get('/plain-500', decode: HealthReport.decode),
  );
  _check(
    '500 純文字無信封仍判為失敗且可重試',
    plain != null &&
        plain.kind == ApiErrorKind.httpStatus &&
        plain.machineCode == null &&
        plain.serverResponded &&
        plain.retryable,
    plain?.toString() ?? '竟然回傳了值',
  );
  _check(
    '錯誤描述不漏出基準位址',
    plain != null && !plain.toString().contains('127.0.0.1'),
    plain?.toString() ?? '',
  );

  await fake.close(force: true);
}

/// 連到沒有監聽的埠：歸為不可達，且不得宣稱服務有回應。
Future<void> _hitClosedPort() async {
  final ServerSocket probe = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final int port = probe.port;
  await probe.close();

  final ApiError? error = await _capture(
    () => _live('http://127.0.0.1:$port').health(),
  );
  _check(
    '連到未監聽的埠時歸為不可達',
    error != null &&
        error.kind == ApiErrorKind.unreachable &&
        !error.serverResponded &&
        error.httpStatus == null,
    error?.toString() ?? '竟然回傳了值',
  );
}

/// 超過期限沒有回應時歸為逾時。
Future<void> _timeOut() async {
  final HttpServer slow = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  slow.listen((HttpRequest request) {
    // 故意不回，讓客戶端自己到期限。
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3)).whenComplete(() async {
        try {
          await request.response.close();
        } catch (_) {
          // 連線可能已被客戶端結束，忽略。
        }
      }),
    );
  });

  final ApiError? error = await _capture(
    () => _live(
      'http://127.0.0.1:${slow.port}',
      timeout: const Duration(milliseconds: 300),
    ).time(),
  );
  _check(
    '沒有回應的伺服器被判為逾時',
    error != null && error.kind == ApiErrorKind.timeout && error.retryable,
    error?.toString() ?? '竟然回傳了值',
  );

  await slow.close(force: true);
}

/// 位址格式不合格時等同未設定：請求不該發出。
Future<void> _rejectBadAddress() async {
  final ApiError? error = await _capture(
    () => _live('http://root:sekret@127.0.0.1:5299').health(),
  );
  _check(
    '帶憑證的位址被拒且歸為未設定',
    error != null && error.kind == ApiErrorKind.notConfigured,
    error?.toString() ?? '竟然回傳了值',
  );
  _check(
    '不合格位址不會出現在錯誤描述裡',
    error != null && !error.toString().contains('sekret'),
    error?.toString() ?? '',
  );
}
