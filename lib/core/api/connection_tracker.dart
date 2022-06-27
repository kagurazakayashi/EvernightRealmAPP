/// 連線探測的狀態持有者：把「上次探測發生了什麼」集中成一處可訂閱的事實。
///
/// 狀態條與探測區都讀同一個 [ConnectionTracker]，因此畫面上不會出現
/// 「探測區寫失敗、狀態條還顯示正常」這種互相矛盾的判斷。
///
/// 刻意不保存本機時間戳：探測成功時顯示的是伺服器回傳的 UTC 時間（DEC-015），
/// 「何時探測過」在沒有伺服器依據的情況下不是一個值得宣稱的事實。
///
/// 位址可在執行期間被使用者改動，因此本追蹤器記錄「這筆結果是對哪個位址探測的」：
/// 位址一改，舊結果立刻作廢（改回尚未探測），否則狀態條會掛著另一台伺服器的
/// 時間卻顯示新地址，那是比「尚未探測」更糟的假象。
library;

import 'package:flutter/foundation.dart';

import 'api_error.dart';
import 'server_address_settings.dart';
import 'server_api.dart';

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

  /// 上次探測成功：存活與校時端點都回傳了符合合同的回應。
  probeSucceeded,

  /// 上次探測失敗：原因見 [ConnectionTracker.error]。
  probeFailed,
}

/// 連線探測狀態（可訂閱）。
class ConnectionTracker extends ChangeNotifier {
  /// 以統一存取介面建立追蹤器；起點階段由組態決定，不預先假裝已探測過。
  ///
  /// [addresses] 給定時會訂閱其變更：位址一改，舊的探測結果與失敗原因立即
  /// 作廢。未給定（位址不可變的工具與測試）時行為與從前相同。
  ConnectionTracker(this.api, {ServerAddressSettings? addresses})
    : _phase = api.isConfigured
          ? ServerConnectionPhase.notProbed
          : ServerConnectionPhase.notConfigured,
      _stateUrl = api.addressDisplay {
    if (addresses != null) {
      _addresses = addresses..addListener(_onAddressChanged);
    }
  }

  /// 探測所用的端點存取介面。
  final ServerApi api;

  ServerAddressSettings? _addresses;
  ServerConnectionPhase _phase = ServerConnectionPhase.notConfigured;
  ServerProbeResult? _result;
  ApiError? _error;
  Future<void>? _inFlight;

  /// 目前這份狀態（階段與數值）是針對哪個位址算出來的。
  ///
  /// 這是作廢與否的唯一依據：位址一變，掛著的結果與階段就不再描述這台伺服器，
  /// 連「尚未探測」這種起點階段也要重算——起點本身就是從位址推出來的。
  String? _stateUrl;

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
      _resetToAddressState();
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

  /// 收用一趟已完成的探測結果（保存位址時那趟驗證打的就是同一個位址）。
  ///
  /// 由呼叫端在 [ServerAddressSettings.save] 成功後轉交，避免「剛驗證過又立刻
  /// 再探一次」的重複請求；失敗或不屬成功的結果不改變狀態。
  void adopt(ServerProbeOutcome outcome) {
    final ServerProbeResult? result = outcome.result;
    if (!outcome.isSuccessful || result == null) {
      return;
    }
    _result = result;
    _error = null;
    _stateUrl = api.addressDisplay;
    _phase = ServerConnectionPhase.probeSucceeded;
    notifyListeners();
  }

  /// 實際執行探測；任何失敗都收斂為狀態，不外洩例外。
  Future<void> _runProbe(String? acceptLanguage) async {
    // 記錄發起時的位址：探測期間使用者若改了地址，完成時寫回的就是過期結果。
    final String? probedUrl = api.addressDisplay;
    _stateUrl = probedUrl;
    _phase = ServerConnectionPhase.probing;
    _error = null;
    notifyListeners();

    final ServerProbeOutcome outcome = await probeServerConnectivity(
      api,
      acceptLanguage: acceptLanguage,
    );
    if (api.addressDisplay != probedUrl) {
      // 位址在請求進行間被換掉：丟棄這筆結果，讓介面停在「尚未探測」，
      // 由下一次顯式探測給出新地址的真實狀態。
      _resetToAddressState();
      return;
    }

    switch (outcome) {
      case ServerProbeOutcome(result: final ServerProbeResult result?):
        // 失敗時一併清掉上次的成功回應：狀態條與探測區不會出現「已失敗」
        // 卻還掛著舊數值的矛盾畫面。要保留舊數值的呈現屬後續能力。
        _result = result;
        _error = null;
        _phase = ServerConnectionPhase.probeSucceeded;
      case ServerProbeOutcome(error: final ApiError error?):
        _result = null;
        _error = error;
        _phase = ServerConnectionPhase.probeFailed;
      default:
        // 探測結果必為成功或失敗之一；走到這裡代表拿到不成對的值，
        // 當成沒有依據處理，絕不保留任何看起來像數值的東西。
        _result = null;
        _error = null;
        _resetToAddressState();
        return;
    }
    notifyListeners();
  }

  /// 位址變更：舊結果不再描述目前這台伺服器，一律作廢。
  void _onAddressChanged() {
    if (_phase == ServerConnectionPhase.probing) {
      // 探測進行中：完成時 [_runProbe] 自行比對並丟棄過期結果，此處不打斷。
      return;
    }
    if (_stateUrl == api.addressDisplay) {
      return;
    }
    _resetToAddressState();
  }

  /// 依目前位址回到起點階段，並清掉所有數值。
  void _resetToAddressState() {
    _stateUrl = api.addressDisplay;
    _result = null;
    _error = null;
    _phase = api.isConfigured
        ? ServerConnectionPhase.notProbed
        : ServerConnectionPhase.notConfigured;
    notifyListeners();
  }

  @override
  void dispose() {
    _addresses?.removeListener(_onAddressChanged);
    _addresses = null;
    super.dispose();
  }
}
