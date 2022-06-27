/// 伺服器位址的使用者設定：本地保存、來源優先序，以及「驗證得通才準保存」。
///
/// 本檔是位址的唯一權威：組態層（`ServerApiConfig`）每次發出請求前向這裡取值，
/// 因此改完位址不需要重建客戶端，也不可能出現「畫面已改、請求仍打舊位址」。
///
/// 兩條刻意遵守的規則：
/// 1. **必達才保存**——候選位址先以同一份探測邏輯走過 `/health` 與 `/time`，
///    不通就不落盤、也不生效，介面如實顯示不通的原因（完成判斷要求「不可達有
///    可理解提示」）。讓錯位址留在設定裡，之後每個畫面都會一直顯示失敗。
/// 2. **寫入成功後才更新狀態**——與介面語言設定同一規則；落盤失敗時不留
///    「看著存好了、重啟又跳回」的中間態。
///
/// 來源優先序（使用者 2026-09-26 定案）：debug 建置以編譯期注入值為準，方便
/// 用 `--dart-define` 指定除錯目標而不被本地殘留值蓋掉；其餘建置一律以本地
/// 保存值為準，未保存過時才退回注入值。「已保存但本建置未生效」會如實呈現，
/// 不讓使用者以為自己改的值正在被使用。
library;

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_error.dart';
import 'server_address.dart';
import 'server_api.dart';

/// 伺服器位址的本地持久化協定。
///
/// 實作放 `lib/platform/`：本檔不依賴任何儲存套件，測試可直接以假實作取代。
abstract interface class ServerAddressPersistence {
  /// 讀取已保存的位址文字；未設定時回傳 `null`。
  Future<String?> readUrl();

  /// 寫入位址文字。
  Future<void> writeUrl(String url);

  /// 移除已保存的位址。
  Future<void> clearUrl();
}

/// 候選位址的驗證協定：回傳一趟探測的成敗（不拋例外）。
typedef VerifyServerAddress = Future<ServerProbeOutcome> Function(
  ServerAddress address, {
  String? acceptLanguage,
});

/// 目前生效位址的來源，僅用於向使用者說明「這個位址是從哪來的」。
enum ServerAddressOrigin {
  /// 編譯期注入的 `ER_SERVER_BASE_URL`（debug 建置下優先採用）。
  injected,

  /// 本機已保存的使用者輸入。
  saved,

  /// 沒有任何來源，探測與請求都無法發出。
  unset,
}

/// 一次保存動作的結果類別。
enum ServerAddressSaveStatus {
  /// 已驗證可達、已落盤，而且目前就是生效位址。
  saved,

  /// 已驗證可達並落盤，但本建置以編譯期注入值為準，因此尚未生效。
  savedInactive,

  /// 格式不合格：未發出任何請求，[ServerAddressSaveResult.issue] 說明原因。
  rejectedByFormat,

  /// 格式合格但連不通：未保存，[ServerAddressSaveResult.error] 說明原因。
  rejectedByConnectivity,

  /// 連通了但本機寫入失敗：狀態保持原樣，不留下未落盤的地址。
  persistenceFailed,
}

/// 一次保存動作的完整結果。
class ServerAddressSaveResult {
  /// 以類別與對應的依據建立結果。
  const ServerAddressSaveResult({
    required this.status,
    this.issue,
    this.error,
    this.probe,
  });

  /// 本次結果類別。
  final ServerAddressSaveStatus status;

  /// 格式不合格時的具體原因；其餘情況為 `null`。
  final ServerAddressIssue? issue;

  /// 連不通時的結構化錯誤；其餘情況為 `null`。
  final ApiError? error;

  /// 驗證成功時的那趟探測回應，可直接沿用以免重複請求。
  final ServerProbeOutcome? probe;

  /// 是否已寫入本地（不代表已生效）。
  bool get isSaved =>
      status == ServerAddressSaveStatus.saved ||
      status == ServerAddressSaveStatus.savedInactive;

  /// 是否為目前生效的位址。
  bool get isActive => status == ServerAddressSaveStatus.saved;
}

/// 以編譯期注入值與本地已保存值解析出生效位址的設定物件（可訂閱）。
class ServerAddressSettings extends ChangeNotifier
    implements ServerAddressSource {
  /// 以持久化協定建立設定。
  ///
  /// [injectedUrl] 與 [preferInjected] 刻意開放注入：兩者都來自建置期，
  /// 測試需要用它們重現「debug 以注入為準」與「release 以本地為準」兩種解析。
  ServerAddressSettings(
    this._persistence, {
    String? injectedUrl = injectedServerBaseUrl,
    bool? preferInjected,
    VerifyServerAddress? verifier,
  }) : _injectedUrl = _normalizeOrNull(injectedUrl),
       _preferInjected = preferInjected ?? kDebugMode,
       _verifier = verifier ?? verifyServerAddressConnectivity;

  /// 以已保存與注入值建立設定並完成載入（組裝點與測試的捷徑）。
  static Future<ServerAddressSettings> restored(
    ServerAddressPersistence persistence, {
    String? injectedUrl,
    bool? preferInjected,
    VerifyServerAddress? verifier,
  }) async {
    final ServerAddressSettings settings = ServerAddressSettings(
      persistence,
      injectedUrl: injectedUrl,
      preferInjected: preferInjected,
      verifier: verifier,
    );
    await settings.restore();
    return settings;
  }

  final ServerAddressPersistence _persistence;
  final String? _injectedUrl;
  final bool _preferInjected;
  final VerifyServerAddress _verifier;

  String? _savedUrl;

  /// 把原始位址文字正規為已驗證的顯示文字；不合格一律回傳 `null`。
  static String? _normalizeOrNull(String? raw) {
    if (raw == null) {
      return null;
    }
    return ServerAddress.tryParse(raw)?.displayText;
  }

  /// 從本地載入先前保存的位址；無法辨識的值視為未設定（不保留壞值）。
  Future<void> restore() async {
    _savedUrl = _normalizeOrNull(await _persistence.readUrl());
    notifyListeners();
  }

  /// 本地已保存的位址文字；未保存時為 `null`。
  String? get savedUrl => _savedUrl;

  /// 編譯期注入的位址文字；未注入時為 `null`。
  String? get injectedUrl => _injectedUrl;

  /// 本建置是否讓編譯期注入值壓過本地保存值。
  bool get prefersInjected => _preferInjected;

  @override
  String? currentUrl() {
    if (_preferInjected && _injectedUrl != null) {
      return _injectedUrl;
    }
    return _savedUrl ?? _injectedUrl;
  }

  /// 生效位址的來源：說明此刻是「哪一條規則」決定了這個地址，而非只比對文字。
  ServerAddressOrigin get origin {
    if (_preferInjected && _injectedUrl != null) {
      return ServerAddressOrigin.injected;
    }
    if (_savedUrl != null) {
      return ServerAddressOrigin.saved;
    }
    return _injectedUrl != null
        ? ServerAddressOrigin.injected
        : ServerAddressOrigin.unset;
  }

  /// 已驗證的生效位址；未設定或格式不合格時為 `null`。
  ServerAddress? get address => ServerAddress.tryParse(currentUrl() ?? '');

  /// 是否具備可用的生效位址。
  bool get hasAddress => address != null;

  /// 供畫面顯示的生效位址文字；未設定時為 `null`。
  String? get addressDisplay => address?.displayText;

  /// 驗證並保存候選位址；只有成功才會改變狀態。
  ///
  /// 順序固定：先判格式（不合格連請求都不發，避免把亂輸入送到網路）、再探測
  /// 可達性（不通就不落盤）、最後寫入本地。[acceptLanguage] 只影響驗證那趟
  /// 請求的診斷語言，不影響保存的內容。
  Future<ServerAddressSaveResult> save(
    String input, {
    String? acceptLanguage,
  }) async {
    final ServerAddressIssue issue = ServerAddress.validate(input);
    if (!issue.isOk) {
      return ServerAddressSaveResult(
        status: ServerAddressSaveStatus.rejectedByFormat,
        issue: issue,
      );
    }
    final ServerAddress candidate = ServerAddress.tryParse(input)!;

    final ServerProbeOutcome outcome = await _verifier(
      candidate,
      acceptLanguage: acceptLanguage,
    );
    if (!outcome.isSuccessful) {
      return ServerAddressSaveResult(
        status: ServerAddressSaveStatus.rejectedByConnectivity,
        error: outcome.error,
        probe: outcome,
      );
    }

    try {
      await _persistence.writeUrl(candidate.displayText);
    } catch (_) {
      // 寫不進去就不改本機狀態：寧可繼續用舊位址，也不能顯示一個重啟就消失的
      // 新位址。呼叫端據此提示使用者重試或檢查本機儲存。
      return ServerAddressSaveResult(
        status: ServerAddressSaveStatus.persistenceFailed,
        error: outcome.error,
        probe: outcome,
      );
    }

    _savedUrl = candidate.displayText;
    notifyListeners();

    return ServerAddressSaveResult(
      status: currentUrl() == candidate.displayText
          ? ServerAddressSaveStatus.saved
          : ServerAddressSaveStatus.savedInactive,
      probe: outcome,
    );
  }

  /// 清除本地保存的位址；寫入失敗時擲例外且保持原狀態。
  Future<void> clear() async {
    await _persistence.clearUrl();
    _savedUrl = null;
    notifyListeners();
  }
}

/// 對單一候選位址走一次連通性探測（不改變任何本機狀態）。
///
/// 與探測區走的是同一個 [probeServerConnectivity]，因此「能不能保存」與
/// 「探測區顯示什麼」用的是同一個判準，不會各說各話。
Future<ServerProbeOutcome> verifyServerAddressConnectivity(
  ServerAddress address, {
  String? acceptLanguage,
}) {
  final ServerApi api = ServerApi(
    config: ServerApiConfig.fixed(address.displayText),
  );
  return probeServerConnectivity(api, acceptLanguage: acceptLanguage);
}
