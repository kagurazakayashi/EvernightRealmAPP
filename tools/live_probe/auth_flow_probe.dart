/// 以真實網路對實際啟動的服務演練「初始化後的标准登入閉環」：
/// Root 成功登入、口令錯誤、限流冷卻、重開應用式的會話恢復、跨伺服器時
/// 舊憑據如實失效。全部走與應用同一份存取層程式碼（`lib/core/api/`）。
///
/// 與 live_probe.dart 的分工：那份證「讀端點與錯誤轉換」，這一份證「寫端點的
///  externally 可見行為」——同一枚假設在單元測試裡被 MockClient 支撐，這裡補
/// 真伺服器回的證據。全部案例只對測試專用的臨時服務操作，口令由標準輸入
/// 傳入且永不回顯；結論行只印機器碼、狀態與長度，不印任何憑據內容。
///
/// 執行（服務與資料目錄由 tools/live_probe/run_auth_flow.sh 負責起停）：
///   口令經 stdin 傳入：
///   dart run tools/live_probe/auth_flow_probe.dart \
///     http://127.0.0.1:5288 http://127.0.0.1:5289 < password-file
/// 第二個位址可省略：省略時跳過跨伺服器（切換）兩項，其餘照常。
library;

import 'dart:convert';
import 'dart:io';

import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_address.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';

/// 通過的檢查數。
int _passed = 0;

/// 失敗的檢查名稱。
final List<String> _failures = <String>[];

/// 記錄一項檢查的結果；[detail] 只准放語言無關的判定依據，不得含憑據。
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

/// 執行 [run]，回傳它拋出的 [ApiError]；正常回傳時回傳 `null`。
Future<ApiError?> _capture(Future<Object?> Function() run) async {
  try {
    await run();
    return null;
  } on ApiError catch (error) {
    return error;
  }
}

/// 從標準輸入讀一次口令（不 echo，不進命令列，不寫入任何輸出）。
Future<String> _readPassword() async {
  final List<String> lines = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();
  if (lines.isEmpty || lines.first.isEmpty) {
    stderr.writeln('標準輸入沒有口令：本腳本拒絕在無口令下執行。');
    exit(2);
  }
  return lines.first;
}

/// 一台測試伺服器的存取介面（原生形态：從假設的「安全儲存」按身份注入憑據）。
class _ServerHarness {
  /// 以基準位址建立；[store] 模擬按伺服器身份保存秘密的安全儲存。
  _ServerHarness(this.baseUrl, this.store);

  /// 基準位址。
  final String baseUrl;

  /// 身份→秘密的記憶體假件（演練「重開應用」時讀的是同一份保存值）。
  final Map<String, String> store;

  /// 該台的已驗證位址。
  late final ServerAddress address = ServerAddress.tryParse(baseUrl)!;

  /// 不带任何憑據的介面（登入用）。
  ServerApi anonymous() {
    return ServerApi(config: ServerApiConfig.fixed(baseUrl));
  }

  /// 按正式裝配同一手法注入憑據的介面（恢复與會話請求用）。
  ServerApi withSecret() {
    return ServerApi(
      config: ServerApiConfig.fixed(
        baseUrl,
        credentials: (String identity) => store[identity],
      ),
    );
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      '用法: dart run tools/live_probe/auth_flow_probe.dart '
      '<服務A位址> [服務B位址] < 口令',
    );
    exitCode = 2;
    return;
  }
  final String password = await _readPassword();
  final _ServerHarness a = _ServerHarness(args[0], <String, String>{});
  final _ServerHarness? b = args.length > 1
      ? _ServerHarness(args[1], <String, String>{})
      : null;

  final String targets = b == null
      ? 'A: ${a.baseUrl}'
      : 'A: ${a.baseUrl}、B: ${b.baseUrl}';
  stdout.writeln('== 演練 Root 標準登入閉環（$targets）');

  await _wrongPassword(a, password);
  final LoginExchange login = await _rootLogin(a, password);
  await _sessionRoundTrips(a, login);
  await _unknownAccountRejected(a);
  await _throttle(a, password);
  if (b != null) {
    await _switchServer(b, password, a);
  }

  stdout.writeln('');
  stdout.writeln('結果: $_passed 項通過，${_failures.length} 項失敗');
  for (final String name in _failures) {
    stdout.writeln('  失敗: $name');
  }
  exitCode = _failures.isEmpty ? 0 : 1;
}

/// 錯誤口令：只拿到 2001，且不可重試——介面據此也只能顯示那一句同形文案。
Future<void> _wrongPassword(_ServerHarness a, String password) async {
  final ApiError? error = await _capture(
    () => a.anonymous().rootLogin(password: '$password-deliberately-wrong'),
  );
  _check(
    '錯誤口令回 2001 且不可重試',
    error != null &&
        error.kind == ApiErrorKind.httpStatus &&
        error.machineCode == 2001 &&
        !error.retryable,
    error?.toString() ?? '竟然回傳了值',
  );
}

/// 正確口令：簽發成功、秘密只進 Set-Cookie、主體是 Root 且不帶帳戶標識。
Future<LoginExchange> _rootLogin(_ServerHarness a, String password) async {
  final LoginExchange exchange = await a.anonymous().rootLogin(
    password: password,
    acceptLanguage: 'zh-TW',
  );
  _check(
    'Root 登入回報 root 主體且不帶 account_id',
    exchange.report.subjectKind == AuthSubjectKind.root &&
        exchange.report.accountId == null &&
        exchange.report.deviceId.isNotEmpty,
    'device=${exchange.report.deviceId}',
  );
  _check(
    '原生環境從 Set-Cookie 取到會話秘密',
    exchange.sessionSecret != null && exchange.sessionSecret!.isNotEmpty,
    '秘密長度=${exchange.sessionSecret?.length ?? 0}',
  );
  // 保存到「安全儲存」：之後所有步驟讀的都是這份，頁面與腳本都不再經手明文。
  a.store[a.address.displayText] = exchange.sessionSecret ?? '';
  return exchange;
}

/// 會話往返：顯式 Bearer 與「按身份注入」兩條路都要換回同一個 Root 主體；
/// 後者正是應用重開時 restore 走的那條路。
Future<void> _sessionRoundTrips(_ServerHarness a, LoginExchange login) async {
  final CurrentSessionReport explicit = await a.anonymous().currentSession(
    bearerToken: a.store[a.address.displayText],
  );
  _check(
    '顯式 Bearer 讀回 root 會話',
    explicit.subjectKind == AuthSubjectKind.root &&
        explicit.deviceId == login.report.deviceId,
    'device=${explicit.deviceId}',
  );

  // 演練「重開應用」：全新的存取介面與控制器讀同一份保存的秘密，
  // 由傳輸層按請求身份注入，不问伺服器就不該有任何本地可宣稱的身分。
  final _ServerHarness reopened = _ServerHarness(
    a.baseUrl,
    Map<String, String>.of(a.store),
  );
  final CurrentSessionReport injected = await reopened
      .withSecret()
      .currentSession();
  _check(
    '重開式恢復：注入閉環讀回同一枚 root 會話',
    injected.subjectKind == AuthSubjectKind.root &&
        injected.expiresAt == login.report.expiresAt,
    injected.expiresAt.toIso8601String(),
  );
}

/// 未知帳戶的普通端點登入：同一個 2001，不给枚舉留第二句。
Future<void> _unknownAccountRejected(_ServerHarness a) async {
  final ApiError? error = await _capture(
    () => a.anonymous().login(loginName: 'nobody-here-00', password: 'x'),
  );
  _check(
    '未知帳戶回同一個 2001',
    error != null && error.machineCode == 2001,
    error?.toString() ?? '竟然回傳了值',
  );
}

/// 限流演練：連續十次錯口令打滿配對視窗，第十一次被冷卻收斂為 2006/429。
///
/// 這一步会把這台測試伺服器的 Root 登入推入 15 分鐘冷卻（批准預設值），
/// 所以它排在 A 台所有正向檢查之後；測試服務跑完即棄，不留後遺。
Future<void> _throttle(_ServerHarness a, String password) async {
  int rejected2001 = 0;
  for (int i = 0; i < 10; i++) {
    final ApiError? error = await _capture(
      () => a.anonymous().rootLogin(password: '$password-wrong-$i'),
    );
    if (error?.machineCode == 2001) {
      rejected2001++;
    }
  }
  _check('十次錯口令依次回 2001', rejected2001 == 10, 'actual=$rejected2001');
  final ApiError? throttled = await _capture(
    () => a.anonymous().rootLogin(password: '$password-after-cap'),
  );
  _check(
    '打滿後被擋為 429 + 2006（與口令對錯無關，全目標同形）',
    throttled != null &&
        throttled.httpStatus == 429 &&
        throttled.machineCode == 2006 &&
        throttled.retryable,
    throttled?.toString() ?? '竟然回傳了值',
  );
  // 被冷卻的嘗試連正確口令也一樣被擋：这正是限流要證的那一半。
  final ApiError? evenCorrect = await _capture(
    () => a.anonymous().rootLogin(password: password),
  );
  _check(
    '冷卻中正確口令同樣被擋（不區分、不透露）',
    evenCorrect != null && evenCorrect.machineCode == 2006,
    evenCorrect?.toString() ?? '竟然被放行',
  );
}

/// 切換伺服器演練：B 台是另一份真實部署——同一枚口令在那边签發的是另一枚
/// 秘密；把 A 的秘密帶去 B，B 如實回「憑據無效」（2003），這既證跨伺服器
/// 隔離，也證客戶端在真環境裡拿得到的「會話失效」響應形態。
Future<void> _switchServer(
  _ServerHarness b,
  String password,
  _ServerHarness a,
) async {
  final LoginExchange onB = await b.anonymous().rootLogin(password: password);
  b.store[b.address.displayText] = onB.sessionSecret ?? '';
  _check(
    '同一口令在 B 台簽發另一枚會話',
    onB.report.subjectKind == AuthSubjectKind.root &&
        (onB.sessionSecret ?? '') != (a.store[a.address.displayText] ?? ''),
    'B 的秘密長度=${onB.sessionSecret?.length ?? 0}',
  );

  final ApiError? stale = await _capture(
    () => b.anonymous().currentSession(
      bearerToken: a.store[a.address.displayText],
    ),
  );
  _check(
    '把 A 的秘密帶去 B：回 2003 會話無效（不是「查不了」）',
    stale != null &&
        stale.machineCode == 2003 &&
        stale.kind == ApiErrorKind.httpStatus,
    stale?.toString() ?? '竟然回傳了值',
  );

  final CurrentSessionReport own = await b.withSecret().currentSession();
  _check(
    'B 台用本台秘密讀回自己的 root 會話',
    own.subjectKind == AuthSubjectKind.root &&
        own.deviceId == onB.report.deviceId,
    'device=${own.deviceId}',
  );
}
