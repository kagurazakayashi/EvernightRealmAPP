/// 連線探測的狀態持有者：把「上次探測發生了什麼」集中成一處可訂閱的事實。
///
/// 狀態條與探測區都讀同一個 [ConnectionTracker]，因此畫面上不會出現
/// 「探測區寫失敗、狀態條還顯示正常」這種互相矛盾的判斷。
///
/// 刻意不保存本機時間戳：探測成功時顯示的是伺服器回傳的 UTC 時間（DEC-015），
/// 「何時探測過」在沒有伺服器依據的情況下不是一個值得宣稱的事實。
library;

import 'package:flutter/foundation.dart';

import 'api_error.dart';
import 'server_api.dart';
import 'server_models.dart';

/// 連線探測所處的階段。
///
/// 每個值都對應一個真實存在的依據：沒有依據時寧可顯示「尚未探測」，
/// 也不預先列舉「已連線」「已斷線」這類需要持續監測才講得通的狀態。
enum ServerConnectionPhase {
  /// 基準位址未設定或格式不合格，請求無法發出。
  notConfigured,

  /// 已有可用位址，但這次啟動還沒有做過探測。
  notProbed,

  /// 探測請求進行中。
  probing,

  /// 上次探測成功：三個端點都回傳了符合合同的回應。
  probeSucceeded,

  /// 上次探測失敗：原因見 [ConnectionTracker.error]。
  probeFailed,
}

/// 一次成功探測收集到的回應。
class ServerProbeResult {
  /// 以已驗證的回應建立探測結果。
  const ServerProbeResult({required this.health, required this.time});

  /// `/health` 的存活回應。
  final HealthReport health;

  /// `/time` 的校時回應。
  final ServerTimeReport time;
}

/// 連線探測狀態（可訂閱）。
class ConnectionTracker extends ChangeNotifier {
  /// 以統一存取介面建立追蹤器；起點階段由組態決定，不預先假裝已探測過。
  ConnectionTracker(this.api)
    : _phase = api.isConfigured
          ? ServerConnectionPhase.notProbed
          : ServerConnectionPhase.notConfigured;

  /// 探測所用的端點存取介面。
  final ServerApi api;

  ServerConnectionPhase _phase = ServerConnectionPhase.notConfigured;
  ServerProbeResult? _result;
  ApiError? _error;
  Future<void>? _inFlight;

  /// 目前階段。
  ServerConnectionPhase get phase => _phase;

  /// 上次成功探測的回應；尚未成功過時為 `null`。
  ServerProbeResult? get result => _result;

  /// 上次探測失敗的原因；上次沒有失敗時為 `null`。
  ApiError? get error => _error;

  /// 是否正在探測。
  bool get isProbing => _phase == ServerConnectionPhase.probing;

  /// 位址是否可用（由端點的組態判定，不由畫面自行宣稱）。
  bool get isConfigured => api.isConfigured;

  /// 實際使用的基準位址文字；未設定或不合法時為 `null`。
  String? get addressDisplay => api.addressDisplay;

  /// 依序探測存活與校時端點，把結果或失敗原因寫回狀態並通知訂閱者。
  ///
  /// 同一時間只會有一趟探測：進行中的重複呼叫沿用同一個 Future，
  /// 避免連點按鈕時出現兩趟交錯的請求而後寫入的覆蓋先寫入的。
  /// 本方法**不拋例外**——失敗以 [error] 與 [phase] 呈現，讓介面不必
  /// 各自決定如何處理未捕捉的異常。
  Future<void> probe({String? acceptLanguage}) {
    final Future<void>? running = _inFlight;
    if (running != null) {
      return running;
    }
    if (!api.isConfigured) {
      _phase = ServerConnectionPhase.notConfigured;
      _result = null;
      notifyListeners();
      return Future<void>.value();
    }

    late final Future<void> task;
    task = _runProbe(acceptLanguage).whenComplete(() {
      if (identical(_inFlight, task)) {
        _inFlight = null;
      }
    });
    _inFlight = task;
    return task;
  }

  /// 實際執行探測；任何失敗都收斂為狀態，不外洩例外。
  Future<void> _runProbe(String? acceptLanguage) async {
    _phase = ServerConnectionPhase.probing;
    _error = null;
    notifyListeners();

    try {
      final HealthReport health = await api.health(
        acceptLanguage: acceptLanguage,
      );
      final ServerTimeReport time = await api.time(
        acceptLanguage: acceptLanguage,
      );
      _result = ServerProbeResult(health: health, time: time);
      _error = null;
      _phase = ServerConnectionPhase.probeSucceeded;
    } on ApiError catch (error) {
      // 失敗時一併清掉上次的成功回應：狀態條與探測區不會出現「已失敗」
      // 卻還掛著舊數值的矛盾畫面。要保留舊數值的呈現屬後續能力。
      _result = null;
      _error = error;
      _phase = ServerConnectionPhase.probeFailed;
    }
    notifyListeners();
  }
}
