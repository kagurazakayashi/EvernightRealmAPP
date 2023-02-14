/// 基礎端點的回應模型：欄位型別服從後端發布的合同，缺欄或型別不符即判為失敗。
///
/// 相容策略刻意與請求端相反：後端的版本規則是「只增不刪」，因此回應中出現
/// 本合同未列出的新欄位必須被容忍（見測試），但合同列出的必要欄位缺任何一個
/// 或型別不符，都不能猜測預設值——那會讓介面把一份不完整的回應當成正常資料。
///
/// 本檔不保存任何語言的顯示字串；時間一律以伺服器回應的 UTC 為準（DEC-015）。
library;

import 'api_error.dart';

/// 嚴格讀取必要欄位：缺少、型別不符或空字串即拋出形狀例外。
String _requireText(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is! String) {
    throw ApiResponseShapeException('欄位 $field 不是字串');
  }
  if (value.isEmpty) {
    throw ApiResponseShapeException('欄位 $field 為空');
  }
  return value;
}

/// 嚴格讀取整數欄位：不接受字串或帶小數的數值。
///
/// 金額一律以字串承載（DEC-001），因此這裡只服務確實發布為整數的小範圍欄位
/// （時區偏移秒數、錯誤碼），不用它讀金額。
int _requireInt(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is! int) {
    throw ApiResponseShapeException('欄位 $field 不是整數');
  }
  return value;
}

/// 嚴格讀取布林欄位：不接受字串、0/1 或「看起來像真」的寫法。
///
/// 型別寬容在這裡的代價比別處都大：`root_initialized` 一旦被誤讀成真，
/// 介面就會對一個還沒初始化的部署說「已經好了」；誤讀成假，則會對一個已經有 Root
/// 的服務建議一次注定被拒的初始化。兩個錯法都比直接判為合同違例嚴重。
bool _requireBool(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is! bool) {
    throw ApiResponseShapeException('欄位 $field 不是布林');
  }
  return value;
}

/// 讀取「只增不刪」合同後來補上的布林欄位：缺席視為 false，出現但型別不合仍判失敗。
///
/// 缺席與 false 對呼叫端意味著同一句話（「沒有這項義務／狀態」），所以缺欄不該把
/// 一份 otherwise 合格的回應打成失敗——那是對舊服務器的不兼容；但帶了壞型別的值
/// 就是合同違例，不能猜：猜錯的方向可能是把「必須改密」讀成「不用改」。
bool _optionalBool(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value == null) {
    return false;
  }
  if (value is! bool) {
    throw ApiResponseShapeException('欄位 $field 不是布林');
  }
  return value;
}

/// 嚴格讀取 UTC 時間戳欄位。
///
/// 只接受帶 `Z` 或明確偏移的 RFC3339 寫法，並正規化為 UTC。沒有時區標記的
/// 寫法一律拒絕、不推測為本機時區：本機時鐘與時區設定不得參與業務時間判定。
DateTime _requireUtcTime(Map<String, Object?> json, String field) {
  final String text = _requireText(json, field);
  if (!_hasExplicitZone(text)) {
    throw ApiResponseShapeException('欄位 $field 缺少時區標記');
  }
  final DateTime? parsed = DateTime.tryParse(text);
  if (parsed == null) {
    throw ApiResponseShapeException('欄位 $field 無法解析為時間');
  }
  return parsed.toUtc();
}

/// 嚴格讀取可選的 UTC 時間戳欄位：欄位缺席或為 null 時回 `null`。
///
/// 「沒有這回事」與「有某個時刻」必須分得開（見 `last_login_at` 的合同：從未登入為缺席，
/// 不是拿建立時刻冒充）；出現時仍以 [_requireUtcTime] 的同一個時區標記閘校驗。
DateTime? _optionalUtcTime(Map<String, Object?> json, String field) {
  if (!json.containsKey(field) || json[field] == null) {
    return null;
  }
  return _requireUtcTime(json, field);
}

/// 讀取可選的字串清單（合同以「只增不刪」補上的欄位）。
///
/// 缺席回空清單；出現但形態不合（不是清單、元素不是非空字串）仍判合同違例。
/// 元素值一律原樣保留成字串、不收緊成列舉：後端日後多發布一個取值時，前端該有的結果是
/// 「這一行我不認得」，而不是「整份回應解碼失敗、連登入都進不去」。
List<String> _optionalTextList(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value == null) {
    return const <String>[];
  }
  if (value is! List) {
    throw ApiResponseShapeException('欄位 $field 不是清單');
  }
  return value
      .map((Object? item) {
        if (item is! String || item.isEmpty) {
          throw ApiResponseShapeException('欄位 $field 的項不是非空字串');
        }
        return item;
      })
      .toList(growable: false);
}

/// 已發布的伺服器級角色值（與後端 `roles` 欄逐字一致）：Root 之下可執行跨活動維運的主體。
///
/// 它是「可展示事實」的判據，不是權限的依據：每一次判定都在服務端重做，
/// 前端拿它決定要呈現哪些入口。
const String kServerAdminRole = 'server_admin';

/// 判斷時間字串是否自帶 `Z` 或 `±HH:MM` 尾綴。
///
/// `DateTime.parse` 對沒有標記的寫法會回傳本機時間，無法由結果區分，因此先看文字。
bool _hasExplicitZone(String value) {
  if (value.length < 20) {
    return false;
  }
  final String tail = value[value.length - 1];
  if (tail == 'Z' || tail == 'z') {
    return true;
  }
  // 偏移寫法為 6 字元（±HH:MM），且一定出現在日期與分鐘之後。
  return RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(value);
}

/// 把 UTC 時刻加上偏移後取出的牆鐘時、分、秒組成 HH:mm:ss。
///
/// [utc] 必須是帶 `isUtc` 標記的時刻；加上偏移秒數後 `add` 保留該標記，
/// 因此讀出的就是該時區當地的牆鐘時間，與本機時區無關。
String formatShiftedClock(DateTime utc, int offsetSeconds) {
  final DateTime shifted = utc.add(Duration(seconds: offsetSeconds));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(shifted.hour)}:${two(shifted.minute)}:${two(shifted.second)}';
}

/// `/health` 的回應：回答「這個進程還活著」，不代表業務可用。
class HealthReport {
  /// 以已驗證的欄位建立存活報告。
  const HealthReport({
    required this.status,
    required this.service,
    required this.version,
    required this.requestId,
  });

  /// 從 `/health` 的 JSON 回應建立報告。
  static HealthReport decode(Map<String, Object?> json) {
    return HealthReport(
      status: _requireText(json, 'status'),
      service: _requireText(json, 'service'),
      version: _requireText(json, 'version'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 伺服器自報的狀態文字；合同目前為 `ok`。
  final String status;

  /// 服務識別名。
  final String service;

  /// 服務版本。
  final String version;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 是否回報為合同定義的正常狀態。
  bool get reportsOk => status == 'ok';
}

/// `/ready` 的回應：回答依賴（目前為資料庫）能否回應。
///
/// 不就緒時伺服器回的是 HTTP 503 與統一錯誤信封，不會走到這個模型。
class ReadinessReport {
  /// 以已驗證的欄位建立就緒報告。
  const ReadinessReport({
    required this.status,
    required this.service,
    required this.requestId,
  });

  /// 從 `/ready` 的 JSON 回應建立報告。
  static ReadinessReport decode(Map<String, Object?> json) {
    return ReadinessReport(
      status: _requireText(json, 'status'),
      service: _requireText(json, 'service'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 伺服器自報的就緒狀態文字；合同目前為 `ready`。
  final String status;

  /// 服務識別名。
  final String service;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 是否回報為已就緒。
  bool get reportsReady => status == 'ready';
}

/// `/time` 的回應：伺服器時間與顯示時區，供用戶端校時與顯示。
class ServerTimeReport {
  /// 以已驗證的欄位建立校時報告。
  const ServerTimeReport({
    required this.timeText,
    required this.time,
    required this.timezone,
    required this.utcOffsetSeconds,
    required this.requestId,
  });

  /// 從 `/time` 的 JSON 回應建立報告。
  static ServerTimeReport decode(Map<String, Object?> json) {
    final String timeText = _requireText(json, 'time');
    return ServerTimeReport(
      timeText: timeText,
      time: _requireUtcTime(json, 'time'),
      timezone: _requireText(json, 'timezone'),
      utcOffsetSeconds: _requireInt(json, 'utc_offset_seconds'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 伺服器下發的時間原文：原樣保留，不改寫成另一種精度或寫法。
  final String timeText;

  /// 伺服器時間，已正規化為 UTC。
  final DateTime time;

  /// 伺服器設定的顯示時區（IANA 名稱）。
  final String timezone;

  /// 該時刻在顯示時區的偏移秒數（有日光節約的時區會隨之變化）。
  final int utcOffsetSeconds;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 偏移秒數的 `+HH:MM`／`-HH:MM` 寫法（符號與數字皆語言無關）。
  String get utcOffsetText {
    final int total = utcOffsetSeconds.abs();
    final String sign = utcOffsetSeconds < 0 ? '-' : '+';
    String two(int value) => value.toString().padLeft(2, '0');
    return '$sign${two(total ~/ 3600)}:${two((total % 3600) ~/ 60)}';
  }

  /// 伺服器時間在其顯示時區的牆鐘時間 HH:mm:ss（本機時區不參與計算）。
  String get displayClock => formatShiftedClock(time, utcOffsetSeconds);
}

/// `/root/init-status` 的回應：這台伺服器的 Root 初始化進行到哪一步。
///
/// 三個布林就是後端發布全部内容——沒有路徑、沒有長度、沒有任何憑據片段，
/// 因此這個模型也沒有任何欄位需要「記得不要顯示」。
///
/// 它是**只讀**的：查這一次不會讓 Root 出現，也不會讓 Root 消失。
/// 初始化的通路只有伺服器本機的 `evernight-server init-root`，
/// 本應用因此沒有任何表單可以向這條路送出口令。
class InitStatusReport {
  /// 以已驗證的欄位建立狀態報告。
  const InitStatusReport({
    required this.configExists,
    required this.rootInitialized,
    required this.envOverride,
    required this.requestId,
  });

  /// 從 `/root/init-status` 的 JSON 回應建立報告。
  static InitStatusReport decode(Map<String, Object?> json) {
    return InitStatusReport(
      configExists: _requireBool(json, 'config_exists'),
      rootInitialized: _requireBool(json, 'root_initialized'),
      envOverride: _requireBool(json, 'env_override'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 伺服器的組態檔是否已建立（全新資料目錄可能還沒跑過任何命令）。
  final bool configExists;

  /// 組態檔是否已帶有非空的 Root 憑據。
  final bool rootInitialized;

  /// Root 憑據的環境變數覆蓋是否處於設定狀態。
  ///
  /// 這一位決定「檔案裡沒有」能不能講成「這個服務沒有 Root」：兩者不等時介面必須
  /// 如實分開說，否則會勸操作者去跑一個在這種狀態下必然拒絕寫入的初始化命令。
  final bool envOverride;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// 認証合同發布的主體類別（值與後端 `subject_kind` 欄位逐字一致）。
enum AuthSubjectKind {
  /// 普通帳戶主體（accounts 表中的帳戶）。
  account,

  /// 伺服器級 Root 主體（不在 accounts 表，無帳戶標識）。
  root,
}

/// 嚴格讀取 `subject_kind`：只收已發布的兩個值，其餘一律判為合同違例。
///
/// 未知值不降級成「帳戶」也不原樣保留列舉：那讓前端把「後端多發了一類主體」
/// 誤讀成「這類主體我早就認識」，是權限展示最容易出事的錯法。
AuthSubjectKind _requireSubjectKind(Map<String, Object?> json) {
  final String text = _requireText(json, 'subject_kind');
  return switch (text) {
    'account' => AuthSubjectKind.account,
    'root' => AuthSubjectKind.root,
    _ => throw ApiResponseShapeException('subject_kind 值 $text 不在合同內'),
  };
}

/// 嚴格讀取可選的帳戶標識：Root 主體該欄缺席；出現但型別不合即失敗。
String? _optionalAccountId(Map<String, Object?> json, AuthSubjectKind kind) {
  final Object? value = json['account_id'];
  if (kind == AuthSubjectKind.root) {
    if (value != null) {
      throw ApiResponseShapeException('root 主體不該攜帶 account_id');
    }
    return null;
  }
  if (value is! String || value.isEmpty) {
    throw ApiResponseShapeException('account 主體必須攜帶 account_id');
  }
  return value;
}

/// `/auth/login` 與 `/auth/root/login` 的成功回應。
///
/// 合同裡沒有會話秘密：它只出現在 `Set-Cookie` 標頭（原生客戶端由此讀取，
/// 瀏覽器由 HttpOnly Cookie 代管）。本模型因此也沒有任何欄位可以「忘記不顯示」它。
class LoginReport {
  /// 以已驗證的欄位建立登入結果。
  const LoginReport({
    required this.subjectKind,
    required this.accountId,
    required this.deviceId,
    required this.expiresAt,
    required this.requestId,
    this.mustChangePassword = false,
    this.roles = const <String>[],
  });

  /// 從登入回應的 JSON 建立結果。
  static LoginReport decode(Map<String, Object?> json) {
    final AuthSubjectKind kind = _requireSubjectKind(json);
    return LoginReport(
      subjectKind: kind,
      accountId: _optionalAccountId(json, kind),
      deviceId: _requireText(json, 'device_id'),
      expiresAt: _requireUtcTime(json, 'expires_at'),
      requestId: _requireText(json, 'request_id'),
      mustChangePassword: _optionalBool(json, 'must_change_password'),
      roles: _optionalTextList(json, 'roles'),
    );
  }

  /// 主體類別。
  final AuthSubjectKind subjectKind;

  /// 帳戶標識（UUIDv7 字串）；Root 主體為 `null`。
  final String? accountId;

  /// 用戶可見的設備標識（洩露也換不來操作能力，可安全展示與保存）。
  final String deviceId;

  /// 會話到期時刻（UTC，取自伺服器）。
  final DateTime expiresAt;

  /// 「首次登入必須改密」旗標：登入已被放行，但受保護功能在服務端被 2010 擋著，
  /// 界面據此主動把人帶進改密流程。合同以只增不刪補上此欄，缺席即 false。
  final bool mustChangePassword;

  /// 服務端現讀到的伺服器級角色清單（合同以只增不刪補上；缺席即空清單）。
  ///
  /// Root 主體不在這裡出現（它的權限來自主體類別而不是授予），因此它恆為空。
  final List<String> roles;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 是否為 Root 主體的登入。
  bool get isRoot => subjectKind == AuthSubjectKind.root;

  /// 是否被後端認定為伺服器級管理員（据真實授予，不是據自報欄位）。
  bool get isServerAdmin => roles.contains(kServerAdminRole);
}

/// `/auth/session` 的成功回應：當前會話的事實，比登入回應多帶建立與最近活動時刻。
class CurrentSessionReport {
  /// 以已驗證的欄位建立當前會話報告。
  const CurrentSessionReport({
    required this.subjectKind,
    required this.accountId,
    required this.deviceId,
    required this.rotationSeq,
    required this.createdAt,
    required this.lastActiveAt,
    required this.expiresAt,
    required this.requestId,
    this.mustChangePassword = false,
    this.roles = const <String>[],
  });

  /// 從 `/auth/session` 的 JSON 回應建立報告。
  static CurrentSessionReport decode(Map<String, Object?> json) {
    final AuthSubjectKind kind = _requireSubjectKind(json);
    return CurrentSessionReport(
      subjectKind: kind,
      accountId: _optionalAccountId(json, kind),
      deviceId: _requireText(json, 'device_id'),
      rotationSeq: _requireInt(json, 'rotation_seq'),
      createdAt: _requireUtcTime(json, 'created_at'),
      lastActiveAt: _requireUtcTime(json, 'last_active_at'),
      expiresAt: _requireUtcTime(json, 'expires_at'),
      requestId: _requireText(json, 'request_id'),
      mustChangePassword: _optionalBool(json, 'must_change_password'),
      roles: _optionalTextList(json, 'roles'),
    );
  }

  /// 主體類別。
  final AuthSubjectKind subjectKind;

  /// 帳戶標識；Root 主體為 `null`。
  final String? accountId;

  /// 用戶可見的設備標識。
  final String deviceId;

  /// 會話秘密的世代號：每次輪換加一，登入簽發的新會話從 0 起算。
  ///
  /// 它是計數器不是秘密，可以展示與儲存。用途只有一個：讓客戶端能把「手上這一枚
  /// 是第幾代」與伺服器的權威事實對上，於是一次倒序送達的輪換回應不會蓋掉更新的
  /// 憑據，一次丟失的輪換回應也能被查出來。
  final int rotationSeq;

  /// 會話建立時刻（UTC）。
  final DateTime createdAt;

  /// 最近一次通過驗證的時刻（UTC）。
  final DateTime lastActiveAt;

  /// 會話到期時刻（UTC）。
  final DateTime expiresAt;

  /// 「首次登入必須改密」旗標的現讀值：本端點永遠可讀（它就是得知欠改的入口），
  /// 改密成功後的下一次刷新即轉為 false，界面據此解除強制態。
  final bool mustChangePassword;

  /// 服務端現讀到的伺服器級角色清單（缺席即空清單；Root 主體恆為空）。
  ///
  /// 這條通路是「重新整理即知道最新權限」的來源：授予在後端被改动之後，
  /// 客戶端不必重新登入也能從這裡讀到現值，界面據此載入或收起入口。
  final List<String> roles;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 是否為 Root 主體的會話。
  bool get isRoot => subjectKind == AuthSubjectKind.root;

  /// 是否被後端認定為伺服器級管理員（據真實授予；自報欄位在合同裡根本不存在）。
  bool get isServerAdmin => roles.contains(kServerAdminRole);
}

/// `POST /auth/password/change` 的成功回應：一次本人改密的結果。
///
/// 與登入／輪換回應同一套缺席規則——不含任何口令或憑據欄位。[revokedSessions]
/// 是本人名下被撤銷的會話數（含發起這一次的裝置）：改密成功即全部退出，
/// 呼叫端據此進入退出態並講出「已讓 N 臺裝置重新登入」。
class PasswordChangeReport {
  /// 以已驗證的欄位建立改密結果。
  const PasswordChangeReport({
    required this.revokedSessions,
    required this.requestId,
  });

  /// 從改密回應的 JSON 建立結果。
  static PasswordChangeReport decode(Map<String, Object?> json) {
    return PasswordChangeReport(
      revokedSessions: _requireInt(json, 'revoked_sessions'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 本次改密撤銷掉的會話數量（含發起這一次的裝置）。
  final int revokedSessions;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// `POST /auth/session/rotate` 的成功回應：換發後那一代的事實。
///
/// 合同與登入回應同一套缺席規則——新秘密不在本體裡（只在 `Set-Cookie`），
/// 會話內部標識也不在；這裡能拿到的只有可展示事實與世代號。
class RotationReport {
  /// 以已驗證的欄位建立輪換結果。
  const RotationReport({
    required this.subjectKind,
    required this.accountId,
    required this.deviceId,
    required this.rotationSeq,
    required this.expiresAt,
    required this.requestId,
  });

  /// 從輪換回應的 JSON 建立結果。
  static RotationReport decode(Map<String, Object?> json) {
    final AuthSubjectKind kind = _requireSubjectKind(json);
    return RotationReport(
      subjectKind: kind,
      accountId: _optionalAccountId(json, kind),
      deviceId: _requireText(json, 'device_id'),
      rotationSeq: _requireInt(json, 'rotation_seq'),
      expiresAt: _requireUtcTime(json, 'expires_at'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 主體類別。
  final AuthSubjectKind subjectKind;

  /// 帳戶標識；Root 主體為 `null`。
  final String? accountId;

  /// 使用者可見的裝置標識：輪換前後必須是同一個（同一臺裝置換密不是新增裝置）。
  final String deviceId;

  /// 換發後的世代號。
  final int rotationSeq;

  /// 會話到期時刻（UTC）：輪換不延長它，這裡回的是原本那一個。
  final DateTime expiresAt;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 是否為 Root 主體的會話。
  bool get isRoot => subjectKind == AuthSubjectKind.root;
}

/// `/auth/devices` 清單裡的一枚裝置。
///
/// 只帶可展示事實（裝置標識、三個時刻、推導狀態、是否本請求所用這一臺）——合同裡
/// 沒有任何憑據材料，因此這個模型也沒有任何欄位需要「記得不要顯示」。
/// `device_id` 就是使用者可見的裝置展示名：它是隨機 UUIDv7、看到也換不來任何操作能力。
///
/// [status] 刻意保存伺服器給的原字串而不是硬列舉：合同對回應採「只增不刪」，
/// 日後若多出一種狀態值，舊的硬列舉會讓整份清單解碼失敗，原字串加派生 getter
/// 則只讓「這一行不認得」而不牽連其餘。
class DeviceReport {
  /// 以已驗證的欄位建立一筆裝置記錄。
  const DeviceReport({
    required this.deviceId,
    required this.createdAt,
    required this.lastActiveAt,
    required this.expiresAt,
    required this.status,
    required this.current,
  });

  /// 從清單單項的 JSON 建立。
  static DeviceReport decode(Map<String, Object?> json) {
    return DeviceReport(
      deviceId: _requireText(json, 'device_id'),
      createdAt: _requireUtcTime(json, 'created_at'),
      lastActiveAt: _requireUtcTime(json, 'last_active_at'),
      expiresAt: _requireUtcTime(json, 'expires_at'),
      status: _requireText(json, 'status'),
      current: _requireBool(json, 'current'),
    );
  }

  /// 使用者可見的裝置標識（展示名）。
  final String deviceId;

  /// 建立時刻（UTC）。
  final DateTime createdAt;

  /// 最近一次通過驗證的時刻（UTC）。
  final DateTime lastActiveAt;

  /// 到期時刻（UTC）。
  final DateTime expiresAt;

  /// 伺服器推導的狀態原字串：`active`／`expired`／`revoked`，或未來新增值。
  final String status;

  /// 是否為本請求所用這一臺（伺服器按當前會話判定，客戶端不自行比對）。
  final bool current;

  /// 是否仍處於有效狀態。
  bool get isActive => status == 'active';
}

/// `GET /auth/devices` 的成功回應：當前主體名下的裝置清單。
class DeviceListReport {
  /// 以已驗證的欄位建立清單。
  const DeviceListReport({required this.devices, required this.requestId});

  /// 從 `/auth/devices` 的 JSON 回應建立清單。
  static DeviceListReport decode(Map<String, Object?> json) {
    final Object? raw = json['devices'];
    if (raw is! List) {
      throw const ApiResponseShapeException('devices 不是清單');
    }
    final List<DeviceReport> devices = <DeviceReport>[];
    for (final Object? item in raw) {
      if (item is! Map<String, Object?>) {
        throw const ApiResponseShapeException('devices 項不是物件');
      }
      devices.add(DeviceReport.decode(item));
    }
    return DeviceListReport(
      devices: devices,
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 裝置清單（順序由伺服器決定，新建立的在前）。
  final List<DeviceReport> devices;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// `POST /auth/devices/revoke` 的成功回應：一次定向撤銷的結果。
///
/// 與登入／輪換回應同一套缺席規則——沒有任何憑據欄位。[current] 為真表示剛撤的是
/// 本請求這一臺，呼叫端據此進入退出態；[revoked] 為假表示目標本就已是失效態（冪等 no-op）。
class DeviceRevokeReport {
  /// 以已驗證的欄位建立撤銷結果。
  const DeviceRevokeReport({
    required this.deviceId,
    required this.revoked,
    required this.current,
    required this.requestId,
  });

  /// 從撤銷回應的 JSON 建立結果。
  static DeviceRevokeReport decode(Map<String, Object?> json) {
    return DeviceRevokeReport(
      deviceId: _requireText(json, 'device_id'),
      revoked: _requireBool(json, 'revoked'),
      current: _requireBool(json, 'current'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 被指向的裝置標識。
  final String deviceId;

  /// 本次是否真的停掉了一枚原本有效的會話（false＝目標本就已是失效態）。
  final bool revoked;

  /// 撤銷的是否為本請求這一臺。
  final bool current;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// Root 開設管理員帳戶的成功回應（`POST /root/admins`）。
///
/// 全部是可展示的身分事實；合同沒有一個欄位可以容納口令，本模型因此也沒有
/// 「記得但不出現」的欄位——初始口令只在後端的一次調用裡存在過。
/// [mustChangePassword] 恆為 true（一次性初始口令的產品語意），界面據此
/// 把「這個口令要用第一次登入去換掉」講明白，而不是讓 Root 以為那是長期口令。
class CreatedAdminReport {
  /// 以已驗證的欄位建立開設結果。
  const CreatedAdminReport({
    required this.accountId,
    required this.loginName,
    required this.displayName,
    required this.status,
    required this.mustChangePassword,
    required this.roles,
    required this.createdAt,
    required this.requestId,
  });

  /// 從開設回應的 JSON 建立結果。
  static CreatedAdminReport decode(Map<String, Object?> json) {
    return CreatedAdminReport(
      accountId: _requireText(json, 'account_id'),
      loginName: _requireText(json, 'login_name'),
      displayName: _requireText(json, 'display_name'),
      status: _requireText(json, 'status'),
      mustChangePassword: _requireBool(json, 'must_change_password'),
      roles: _optionalTextList(json, 'roles'),
      createdAt: _requireUtcTime(json, 'created_at'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 新帳戶的穩定標識（UUIDv7 字串）。
  final String accountId;

  /// 登入名原始寫法（保留大小寫，僅供展示）。
  final String loginName;

  /// 顯示名稱。
  final String displayName;

  /// 帳戶狀態原字串（日後多一種狀態時本行不牽連整份回應）。
  final String status;

  /// 是否仍欠「首次登入必須改密」。
  final bool mustChangePassword;

  /// 服務端授予的角色清單。
  final List<String> roles;

  /// 建立時刻（UTC，取自伺服器時鐘）。
  final DateTime createdAt;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// 管理員建立普通帳戶的成功結果：後端回傳的可展示事實。
///
/// 與 [CreatedAdminReport] 分兩個型別而不是共用，是因為後端合同就真的不同：
/// 這裡沒有一個 roles 欄位（建的帳戶恆無任何伺服器級授予，回應不描述一件不存在的事），
/// 也沒有任何活動欄位——「已建立」不等於「已加入活動」。未知的新欄位照既有合同
/// 容忍（只增不刪），缺必填欄位則判合同違例，不降級成預設值。
class CreatedStandardAccountReport {
  /// 以已驗證的欄位建立結果。
  const CreatedStandardAccountReport({
    required this.accountId,
    required this.loginName,
    required this.displayName,
    required this.status,
    required this.mustChangePassword,
    required this.createdAt,
    required this.requestId,
  });

  /// 從建立回應的 JSON 建立結果。
  static CreatedStandardAccountReport decode(Map<String, Object?> json) {
    return CreatedStandardAccountReport(
      accountId: _requireText(json, 'account_id'),
      loginName: _requireText(json, 'login_name'),
      displayName: _requireText(json, 'display_name'),
      status: _requireText(json, 'status'),
      mustChangePassword: _requireBool(json, 'must_change_password'),
      createdAt: _requireUtcTime(json, 'created_at'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 新帳戶的穩定標識（UUIDv7 字串）——此刻得到的只是一枚 Account 標識，
  /// 不意味著任何 Activity Profile 或活動資產存在。
  final String accountId;

  /// 登入名原始寫法（保留大小寫，僅供展示）。
  final String loginName;

  /// 顯示名稱。
  final String displayName;

  /// 帳戶狀態原字串（日後多一種狀態時本行不牽連整份回應）。
  final String status;

  /// 是否仍欠「首次登入必須改密」（本端點的合同恆為真，值仍取自伺服器回應）。
  final bool mustChangePassword;

  /// 建立時刻（UTC，取自伺服器時鐘）。
  final DateTime createdAt;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// 匿名自註冊普通帳戶的成功結果（`POST /auth/register`）。
///
/// 全部是可展示的身分事實，與管理員建號的 [CreatedStandardAccountReport] 分兩個型別
/// 而不共用，是因為後端合同就真的不同：這裡 [mustChangePassword] 恆為 false——口令由
/// 本人自選、選完即可直接登入，「註冊後立即可用」正是既定語意；那一側則恆為 true
/// （管理員代選的一次性初始口令）。界面一律轉述伺服器回傳的值，不把自己當成事實來源。
/// 兩側都沒有 roles 欄位（普通帳戶不帶任何伺服器級授予，回應不描述一件不存在的事），
/// 也沒有任何活動欄位：「已建立」不等於「已加入活動」。未知新欄位照「只增不刪」容忍，
/// 缺必填欄位則判合同違例，不降級成預設值。
class SelfRegisterReport {
  /// 以已驗證的欄位建立結果。
  const SelfRegisterReport({
    required this.accountId,
    required this.loginName,
    required this.displayName,
    required this.status,
    required this.mustChangePassword,
    required this.createdAt,
    required this.requestId,
  });

  /// 從自註冊回應的 JSON 建立結果。
  static SelfRegisterReport decode(Map<String, Object?> json) {
    return SelfRegisterReport(
      accountId: _requireText(json, 'account_id'),
      loginName: _requireText(json, 'login_name'),
      displayName: _requireText(json, 'display_name'),
      status: _requireText(json, 'status'),
      mustChangePassword: _requireBool(json, 'must_change_password'),
      createdAt: _requireUtcTime(json, 'created_at'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 新帳戶的穩定標識（UUIDv7 字串）——此刻得到的只是一枚 Account 標識，
  /// 不意味著任何 Activity Profile 或活動資產存在。
  final String accountId;

  /// 登入名原始寫法（保留大小寫，僅供展示）。
  final String loginName;

  /// 顯示名稱。
  final String displayName;

  /// 帳戶狀態原字串（日後多一種狀態時本行不牽連整份回應）。
  final String status;

  /// 是否仍欠「首次登入必須改密」（自註冊由本人自選口令，合同恆為 false；值仍取自伺服器回應）。
  final bool mustChangePassword;

  /// 建立時刻（UTC，取自伺服器時鐘）。
  final DateTime createdAt;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// 申請人查本人待審批申請狀態的結果（POST `/auth/registration-status`）。
///
/// 這是整份合同裡最窄的一種回應，而「窄」是要害不是省事：
///
/// * 沒有 `account_id`、也沒有 `display_name`：申請人查的是「我那份申請怎麼樣了」，
///   一個可被轉述的標識對這句話沒有幫助，少一欄就少一處能被拿到別處用的東西。
/// * 沒有審核人是誰、沒有拒絕理由、沒有「排到第幾位」：那些屬伺服器的內部狀態，
///   而其中「為什麼被拒」連審批那一步都還沒落地。
/// * `reviewed_at` 可缺席：還沒有任何人做過決定時，缺席是事實的缺席，
///   界面不得拿提交時刻或當前時刻冒充一個決定時刻。
///
/// [outcome] 保留原字串（`pending`／`approved`／`rejected`）：後端只增不刪，
/// 日後多一種結局時本模型不牽連整份回應；界面據值分流，認不得的值如實說
/// 「查到的結果無法辨認」，不猜成「還在等」也不猜成「已批准」。
class ApplicationStatusReport {
  /// 以已驗證的欄位建立結果。
  const ApplicationStatusReport({
    required this.outcome,
    required this.submittedAt,
    required this.reviewedAt,
    required this.requestId,
  });

  /// 從狀態查詢回應的 JSON 建立結果。
  static ApplicationStatusReport decode(Map<String, Object?> json) {
    return ApplicationStatusReport(
      outcome: _requireText(json, 'outcome'),
      submittedAt: _requireUtcTime(json, 'submitted_at'),
      reviewedAt: _optionalUtcTime(json, 'reviewed_at'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 申請結局的原字串。
  final String outcome;

  /// 申請提交時刻（UTC，即帳戶建立時刻）。
  final DateTime submittedAt;

  /// 審核做出決定的時刻（UTC）；`null` 代表還沒有決定。
  final DateTime? reviewedAt;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// 管理員單筆資料：目錄的一行、詳情與編輯結果共用的形状（同一筆資料在不同回應裡必須同源）。
///
/// 可缺席的三個欄位各有其人：
///
/// * `last_login_at`：從未登入的帳戶在合同裡是欄位缺席，本模型不拿建立時刻冒充。
/// * `disabled_at`：只在目標停過時出現；被刪前若本是停用者，這個時刻在刪除之後仍留在回應裡。
/// * `deleted_at`：只在目標已被刪除時出現，界面不得拿停用時刻或建立時刻代填。
/// * `roles`：只有單筆回應（詳情與編輯結果）帶出；目錄的每一行本來就是按授予查出來的，
///   逐行重複同一個字串不回答任何新問題。未知角色值原樣保留為字串，不收緊成枚舉。
///
/// [grantedAt] 在合同的目錄行、詳情與編輯結果裡恆在（成員資格本身就是授予），
/// 所以它是必填欄位：少了它就該判合同違例，而不是顯示成「未知時刻」。
/// 普通帳戶目錄／詳情裡的一行（`GET /admin/accounts` 的行與單筆回應共用的形狀）。
///
/// 這是管理員端「普通帳戶目錄」的形狀，與 [AdminAccountReport] 分開是合同差而不是抄一份：
///
/// * 沒有 `granted_at` 也沒有 `roles`——本目錄的定義就是「不帶任何伺服器級授予」，
///   回應不描述一件不存在的事；拿管理員那一個模型套上來，界面就會多出一列永遠為空的授予時刻。
/// * 多一個必填的 `account_type`：他是普通帳戶還是訪客帳戶，是這本目錄必須講清楚的來源事實，
///   值原樣保留為字串（未知取值不收緊成枚舉，與狀態欄同一取向）。
/// * 沒有 `deleted_at`：刪除終態不在本目錄的範圍之內（後端把那些行整個排除了），
///   因此這裡也沒有一個格子可以去猜「這個缺席是『沒被刪』還是『查不到』」。
///
/// `last_login_at` 與 `disabled_at` 可缺席：前者是從未登入，後者只在停過時出現，
/// 兩個都不拿建立時刻或零值冒充。
class StandardAccountReport {
  /// 以已驗證的欄位建立單筆普通帳戶資料。
  const StandardAccountReport({
    required this.accountId,
    required this.loginName,
    required this.displayName,
    required this.accountType,
    required this.status,
    required this.mustChangePassword,
    required this.createdAt,
    this.lastLoginAt,
    this.disabledAt,
  });

  /// 從 JSON 單項建立。
  static StandardAccountReport decode(Map<String, Object?> json) {
    return StandardAccountReport(
      accountId: _requireText(json, 'account_id'),
      loginName: _requireText(json, 'login_name'),
      displayName: _requireText(json, 'display_name'),
      accountType: _requireText(json, 'account_type'),
      status: _requireText(json, 'status'),
      mustChangePassword: _requireBool(json, 'must_change_password'),
      createdAt: _requireUtcTime(json, 'created_at'),
      lastLoginAt: _optionalUtcTime(json, 'last_login_at'),
      disabledAt: _optionalUtcTime(json, 'disabled_at'),
    );
  }

  /// 帳戶穩定標識。
  final String accountId;

  /// 登入名原始寫法（保留大小寫，僅供展示；它不是授權依據，也不是本步的可改欄位）。
  final String loginName;

  /// 顯示名稱。
  final String displayName;

  /// 來源類型原字串（standard|guest，未知值原樣保留）。
  final String accountType;

  /// 帳戶狀態原字串（本目錄可能出现的值是 active 與 disabled；deleted 不在範圍內）。
  final String status;

  /// 是否仍欠首次改密（只讀展示；解除它的唯一通路是本人改密，本目錄不提供）。
  final bool mustChangePassword;

  /// 建立時刻（UTC）。
  final DateTime createdAt;

  /// 最近一次登入時刻（UTC）；從未登入為 `null`（合同欄位缺席）。
  final DateTime? lastLoginAt;

  /// 進入禁用狀態的時刻（UTC）；可用狀態時欄位缺席，讀成 `null`（不拿零值冒充「停過」）。
  final DateTime? disabledAt;

  /// 是否為有效狀態（未知值不冒充有效）。
  bool get isActive => status == 'active';

  /// 是否為停用狀態（同樣只認服務端回傳的原字串；未知值既不算有效也不算停用）。
  ///
  /// 界面那顆「恢復登入」按鈕只在這裡為真時出現：拿「不是 active」推斷會把
  /// 未來任何新狀態都當成「可恢復」，而那正是 2014 要擋的那種註定落敗的請求。
  bool get isDisabled => status == 'disabled';

  /// 是否為訪客帳戶（只認服務端回傳的來源欄位，不看口令、也不看有無授予）。
  bool get isGuest => accountType == 'guest';
}

/// `GET /admin/accounts` 的成功回應：普通帳戶目錄的一頁，含分頁回顯與篩選後總數。
///
/// 與 [AdminDirectoryReport] 同一形態但各是各型別：兩本目錄的範圍規則不同
/// （一本按授予列、另一本按「沒有授予」列），混成一個型別遲早會有人拿錯那份回顯去算頁。
class StandardAccountDirectoryReport {
  /// 以已驗證的欄位建立一頁目錄。
  const StandardAccountDirectoryReport({
    required this.accounts,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.requestId,
  });

  /// 從 `/admin/accounts` 的 JSON 回應建立一頁目錄。
  static StandardAccountDirectoryReport decode(Map<String, Object?> json) {
    final Object? raw = json['accounts'];
    if (raw is! List) {
      throw const ApiResponseShapeException('accounts 不是清單');
    }
    final List<StandardAccountReport> accounts = <StandardAccountReport>[];
    for (final Object? item in raw) {
      if (item is! Map<String, Object?>) {
        throw const ApiResponseShapeException('accounts 項不是物件');
      }
      accounts.add(StandardAccountReport.decode(item));
    }
    return StandardAccountDirectoryReport(
      accounts: accounts,
      page: _requireInt(json, 'page'),
      pageSize: _requireInt(json, 'page_size'),
      total: _requireInt(json, 'total'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 本頁的行（依後端給出的順序，新建立的在前）。
  final List<StandardAccountReport> accounts;

  /// 本頁頁碼（1 起算，後端回顯）。
  final int page;

  /// 本頁尺寸（後端回顯）。
  final int pageSize;

  /// 符合篩選條件的總筆數（不是全表數，也不是本頁數）。
  final int total;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 總頁數至少為 1：零筆資料時第 1 頁就是那個「空但存在」的頁。
  int get totalPages => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;

  /// 是否還有後頁；由伺服器回顯的頁碼與總數判定，客戶端不自算第二份真相。
  bool get hasMore => page < totalPages;
}

/// `GET／PUT /admin/accounts/{account_id}` 的成功回應：單筆詳情或編輯後的資料庫現值。
///
/// PUT 回的也是它：界面顯示的「當前資料」必須來自服務端保存結果，不是請求本體的迴音——
/// 本模型只從回應構造，結構上沒有「本地意圖」的格子。
class StandardAccountDetailReport {
  /// 以已驗證的欄位建立單筆回應。
  const StandardAccountDetailReport({
    required this.account,
    required this.requestId,
  });

  /// 從 JSON 回應建立單筆資料。
  static StandardAccountDetailReport decode(Map<String, Object?> json) {
    final Object? raw = json['account'];
    if (raw is! Map<String, Object?>) {
      throw const ApiResponseShapeException('account 不是物件');
    }
    return StandardAccountDetailReport(
      account: StandardAccountReport.decode(raw),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 單筆普通帳戶資料。
  final StandardAccountReport account;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// `PUT /admin/accounts/{account_id}/status` 的成功回應：變更後的資料庫現值與撤銷數量。
///
/// 形態與 [AdminStatusReport] 同構但各是各型別（與目錄那兩對同一取向）：兩條通路的
/// 目標範圍與權限檔位不同（一本按授予列、另一本按「沒有授予」列），合併型別就會有人
/// 拿錯那一側的資料去講「我剛動了誰」。
/// [revokedSessions] 是這次落庫的會話撤銷數——缺席判合同違例，不降級成 0：
/// 「撤銷了幾個」是這次操作對外的影響範圍陳述，把它讀成 0 等於對使用者謊報「沒有別人
/// 因此被登出」，而那正是停用最要緊的那一半效果。恢復時服務端恆回 0（不復活也不新撤），
/// 那個 0 是事實而不是失敗。
/// [account] 是變更後的單筆真相：`status` 與 `disabled_at` 成對（disabled 帶時刻、
/// active 欄位缺席），而 `must_change_password` 保持原樣——恢復只恢復新登入資格。
class StandardAccountStatusReport {
  /// 以已驗證的欄位建立單次狀態變更回應。
  const StandardAccountStatusReport({
    required this.account,
    required this.revokedSessions,
    required this.requestId,
  });

  /// 從 JSON 回應建立狀態變更結果。
  static StandardAccountStatusReport decode(Map<String, Object?> json) {
    final Object? raw = json['account'];
    if (raw is! Map<String, Object?>) {
      throw const ApiResponseShapeException('account 不是物件');
    }
    return StandardAccountStatusReport(
      account: StandardAccountReport.decode(raw),
      revokedSessions: _requireInt(json, 'revoked_sessions'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 變更後的單筆普通帳戶資料。
  final StandardAccountReport account;

  /// 這次撤銷的會話數量（恢復恆為 0）。
  final int revokedSessions;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// `PUT /admin/accounts/{account_id}/password` 的成功回應：重置後的資料庫現值與撤銷數量。
///
/// 欄位形態與 [StandardAccountStatusReport] 同構但刻意各自獨名（與管理員那側
/// [AdminStatusReport]／[AdminPasswordResetReport] 同一取向）：兩條子資源白名單的語意不同
/// （一個動狀態、一個動憑據），合併成一個型別會讓「這次成功的是哪件事」在界面層失去出處。
/// [account] 是重置後的單筆真相：`must_change_password` 必為 true（重置交付的永遠是
/// 一次性口令），`status` 與 `disabled_at` 保持目標原樣（重置不是解除停用）。
/// [revokedSessions] 為這次落庫的會話撤銷數，缺席判合同違例、不降級成 0；對停用中的目標
/// 這個數通常是 0（其會話早在停用時已撤），0 是事實而不是失敗。
/// 回應裡不存在、也不允許出現任何口令或憑據材料——口令只在請求那一側出現一次。
class StandardAccountPasswordResetReport {
  /// 以已驗證的欄位建立單次憑據重置回應。
  const StandardAccountPasswordResetReport({
    required this.account,
    required this.revokedSessions,
    required this.requestId,
  });

  /// 從 JSON 回應建立憑據重置結果。
  static StandardAccountPasswordResetReport decode(Map<String, Object?> json) {
    final Object? raw = json['account'];
    if (raw is! Map<String, Object?>) {
      throw const ApiResponseShapeException('account 不是物件');
    }
    return StandardAccountPasswordResetReport(
      account: StandardAccountReport.decode(raw),
      revokedSessions: _requireInt(json, 'revoked_sessions'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 重置後的單筆普通帳戶資料。
  final StandardAccountReport account;

  /// 這次撤銷的會話數量（停用中的目標通常是 0——其會話早在停用時已撤）。
  final int revokedSessions;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// 註冊申請名冊的一行：`GET /admin/registrations` 的行，也是決定之後回顯的形狀。
///
/// 六格就是「審核一個人需要的全部依據」：他是誰（標識與兩個名字）、他在審批鏈的哪一站
/// （status）、他等了多久（submitted_at）與有沒有已經落地的決定（reviewed_at）。
/// 回應裡不會有的東西：口令與任何憑據材料、登入名的內部正規化鍵、角色與授予、活動與資產
/// ——那些對「要不要放行這個人」不構成依據，多一格就多一個可外流的格子。
/// 也沒有「審核人是誰」與「為什麼拒」：後端今日根本沒有那兩格（決定者的身分只存在伺服器端
/// 審計裡，而理由文本不落庫），介面因此無處可顯示，也不該本地捏造一句。
///
/// [status] 與 [reviewedAt] 的配對是後端的事實：`pending` 恆無決定時刻、`rejected` 必帶；
/// 決定成功後回顯的那一筆可能是 `active`（批准）或 `rejected`（拒絕）——
/// 前者的意思是「他已經離開這本書、進普通帳戶目錄那一側」，界面據此把行收掉而不是本地改寫。
class RegistrationApplicationReport {
  /// 以已驗證的欄位建立一筆申請資料。
  const RegistrationApplicationReport({
    required this.accountId,
    required this.loginName,
    required this.displayName,
    required this.status,
    required this.submittedAt,
    required this.reviewedAt,
  });

  /// 從 JSON 單項建立一筆申請資料。
  static RegistrationApplicationReport decode(Map<String, Object?> json) {
    return RegistrationApplicationReport(
      accountId: _requireText(json, 'account_id'),
      loginName: _requireText(json, 'login_name'),
      displayName: _requireText(json, 'display_name'),
      status: _requireText(json, 'status'),
      submittedAt: _requireUtcTime(json, 'submitted_at'),
      // 缺席就是「還沒有任何人做過決定」：不得拿提交時刻或當前時刻冒充一個決定時刻。
      reviewedAt: _optionalUtcTime(json, 'reviewed_at'),
    );
  }

  /// 申請人的穩定帳戶標識（決定就是按它下的）。
  final String accountId;

  /// 登入名原始寫法（僅供展示與確認對話框點名，不是授權依據）。
  final String loginName;

  /// 顯示名稱。
  final String displayName;

  /// 狀態原字串（這本名冊可能出現的是 pending 與 rejected；未知值原樣保留）。
  final String status;

  /// 申請提交時刻（UTC，即帳戶建立時刻）。
  final DateTime submittedAt;

  /// 審核做出決定的時刻（UTC）；`null` 代表還沒有人做過決定。
  final DateTime? reviewedAt;

  /// 是否還在等著被決定（只有這一格為真時才有一顆可以按的按鈕）。
  ///
  /// 認的是服務端回傳的原字串而不是「沒有決定時刻」：一個曾被批准此後被停用的人
  /// 也帶著決定時刻，但他早就不在這本名冊上了。
  bool get isPending => status == 'pending';

  /// 是否已被拒絕（只認原字串；未知值既不算等待也不算被拒）。
  bool get isRejected => status == 'rejected';
}

/// `GET /admin/registrations` 的成功回應：註冊申請名冊的一頁，含分頁回顯與篩選後總數。
///
/// 與 [StandardAccountDirectoryReport] 同一形態但各是各型別：兩本名冊的範圍規則不同
/// （一本按「可以打理的普通帳戶」列、另一本按「走審批通路的申請」列），
/// 混成一個型別遲早有人拿錯那份回顯去算頁，也把「列得到＝可編輯」這層誤解帶進來。
/// 分頁三元組一律取伺服器回顯：客戶端不拿本頁筆數冒充總數、也不自行排序。
class RegistrationRosterReport {
  /// 以已驗證的欄位建立一頁名冊。
  const RegistrationRosterReport({
    required this.applications,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.requestId,
  });

  /// 從 `/admin/registrations` 的 JSON 回應建立一頁名冊。
  static RegistrationRosterReport decode(Map<String, Object?> json) {
    final Object? raw = json['applications'];
    if (raw is! List) {
      throw const ApiResponseShapeException('applications 不是清單');
    }
    final List<RegistrationApplicationReport> items =
        <RegistrationApplicationReport>[];
    for (final Object? item in raw) {
      if (item is! Map<String, Object?>) {
        throw const ApiResponseShapeException('applications 項不是物件');
      }
      items.add(RegistrationApplicationReport.decode(item));
    }
    return RegistrationRosterReport(
      applications: items,
      page: _requireInt(json, 'page'),
      pageSize: _requireInt(json, 'page_size'),
      total: _requireInt(json, 'total'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 本頁的行（依後端給出的順序，最新提交的在前）。
  final List<RegistrationApplicationReport> applications;

  /// 本頁頁碼（1 起算，後端回顯）。
  final int page;

  /// 本頁尺寸（後端回顯）。
  final int pageSize;

  /// 符合篩選條件的總筆數（不是全表數，也不是本頁數）。
  final int total;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 總頁數至少為 1：零筆申請時第 1 頁就是那個「空但存在」的頁。
  int get totalPages => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;

  /// 是否還有後頁；由伺服器回顯的頁碼與總數判定，客戶端不自算第二份真相。
  bool get hasMore => page < totalPages;
}

/// `PUT /admin/registrations/{account_id}/decision` 的成功回應：決定之後的現值與本次落地的那顆。
///
/// [application] 是「寫入之後的資料庫現值」（後端在交易內重讀），不是請求本體的迴音：
/// 界面顯示的當前資料必須來自服務端保存的結果。批准時它的 status 是 `active`——
/// 那一筆自此不在名冊上（普通帳戶目錄那一側接手），界面要收掉這一行而不是自己留一份。
/// [decision] 回顯的是本次落地的那個決定（`approve`／`reject`），讓成功句能講出
/// 「你批准了這一份」而不是「操作完成」這種無所指的話；它不是憑據、也不是個人資料。
/// 這一格刻意不叫 `revoked_sessions` 之類的數字：審批不動任何會話——
/// 被批准的人能不能進去由他自己交口令那條既有的登入通路決定，那一步不在本回應裡。
class RegistrationDecisionReport {
  /// 以已驗證的欄位建立單次審批決定回應。
  const RegistrationDecisionReport({
    required this.application,
    required this.decision,
    required this.requestId,
  });

  /// 從 JSON 回應建立審批決定結果。
  static RegistrationDecisionReport decode(Map<String, Object?> json) {
    final Object? raw = json['application'];
    if (raw is! Map<String, Object?>) {
      throw const ApiResponseShapeException('application 不是物件');
    }
    return RegistrationDecisionReport(
      application: RegistrationApplicationReport.decode(raw),
      decision: _requireText(json, 'decision'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 決定之後的單筆申請現值。
  final RegistrationApplicationReport application;

  /// 本次落地的決定原字串（approve|reject，未知值原樣保留）。
  final String decision;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 是否落地的是批准（只認服務端回顯的原字串，不認本地按下的是哪顆按鈕）。
  bool get isApproved => decision == 'approve';

  /// 是否落地的是拒絕。
  bool get isRejected => decision == 'reject';
}

class AdminAccountReport {
  /// 以已驗證的欄位建立單筆管理員資料。
  const AdminAccountReport({
    required this.accountId,
    required this.loginName,
    required this.displayName,
    required this.status,
    required this.mustChangePassword,
    required this.createdAt,
    required this.grantedAt,
    this.lastLoginAt,
    this.disabledAt,
    this.deletedAt,
    this.roles = const <String>[],
  });

  /// 從 JSON 單項建立。
  static AdminAccountReport decode(Map<String, Object?> json) {
    return AdminAccountReport(
      accountId: _requireText(json, 'account_id'),
      loginName: _requireText(json, 'login_name'),
      displayName: _requireText(json, 'display_name'),
      status: _requireText(json, 'status'),
      mustChangePassword: _requireBool(json, 'must_change_password'),
      createdAt: _requireUtcTime(json, 'created_at'),
      lastLoginAt: _optionalUtcTime(json, 'last_login_at'),
      disabledAt: _optionalUtcTime(json, 'disabled_at'),
      deletedAt: _optionalUtcTime(json, 'deleted_at'),
      grantedAt: _requireUtcTime(json, 'granted_at'),
      roles: _optionalTextList(json, 'roles'),
    );
  }

  /// 帳戶標識。
  final String accountId;

  /// 登入名原始寫法。
  final String loginName;

  /// 顯示名稱。
  final String displayName;

  /// 帳戶狀態原字串。
  final String status;

  /// 是否仍欠首次改密。
  final bool mustChangePassword;

  /// 建立時刻（UTC）。
  final DateTime createdAt;

  /// 最近一次登入時刻（UTC）；從未登入為 `null`。
  final DateTime? lastLoginAt;

  /// 進入禁用狀態的時刻（UTC）；active 時合同欄位缺席，讀成 `null`（不拿零值冒充「停過」）。
  final DateTime? disabledAt;

  /// 進入刪除終態的時刻（UTC）；未被刪除時合同欄位缺席，讀成 `null`。
  ///
  /// 它與 [disabledAt] 是兩件事：後者記「何時停的」（被刪前若本是停用者，那個時刻仍留著），
  /// 前者記「何時被刪」。界面不得把兩者混成一個標籤，也不得用其中一個去推另一個。
  final DateTime? deletedAt;

  /// server_admin 授予寫下的時刻（UTC）。
  final DateTime grantedAt;

  /// 服務端核實的角色清單；目錄行為空（欄位按合同缺席），單筆回應帶真實值。
  final List<String> roles;

  /// 是否為有效狀態（未知值不冒充有效）。
  bool get isActive => status == 'active';

  /// 是否已是刪除終態（只認服務端回傳的狀態字串）。
  ///
  /// 判的是 `status` 而不是 `deletedAt != null`：兩個值在後端由同一條 CHECK 成對鎖定，
  /// 但介面要問的原話是「他現在是哪個狀態」，答案就取那個欄位。
  bool get isDeleted => status == 'deleted';
}

/// `GET /root/admins` 的成功回應：管理員目錄的一頁，含分頁回顯與篩選後總數。
///
/// 分頁三元組由後端回顯而不是客戶端複述：「你問的是哪一頁」的唯一答案在回應裡。
/// [admins] 恆為清單，空頁是空清單（後端合同：空頁回 `[]`，不是 null、也不是錯誤）。
class AdminDirectoryReport {
  /// 以已驗證的欄位建立一頁目錄。
  const AdminDirectoryReport({
    required this.admins,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.requestId,
  });

  /// 從 `/root/admins` 的 JSON 回應建立一頁目錄。
  static AdminDirectoryReport decode(Map<String, Object?> json) {
    final Object? raw = json['admins'];
    if (raw is! List) {
      throw const ApiResponseShapeException('admins 不是清單');
    }
    final List<AdminAccountReport> admins = <AdminAccountReport>[];
    for (final Object? item in raw) {
      if (item is! Map<String, Object?>) {
        throw const ApiResponseShapeException('admins 項不是物件');
      }
      admins.add(AdminAccountReport.decode(item));
    }
    return AdminDirectoryReport(
      admins: admins,
      page: _requireInt(json, 'page'),
      pageSize: _requireInt(json, 'page_size'),
      total: _requireInt(json, 'total'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 本頁的行（依後端給出的順序，新授予的在前）。
  final List<AdminAccountReport> admins;

  /// 本頁頁碼（1 起算，後端回顯）。
  final int page;

  /// 本頁尺寸（後端回顯，含對非法請求的收斂結果）。
  final int pageSize;

  /// 符合篩選條件的總筆數（不是全表數，也不是本頁數）。
  final int total;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 總頁數至少為 1：零筆資料時第 1 頁就是那個「空但存在」的頁。
  int get totalPages => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;

  /// 是否還有後頁；由伺服器回顯的頁碼與總數判定，客戶端不自算第二份真相。
  bool get hasMore => page < totalPages;
}

/// `GET／PUT /root/admins/{account_id}` 的成功回應：單筆詳情或編輯後的資料庫現值。
///
/// PUT 的回應同样是它：界面顯示的「當前資料」必須來自服務端保存結果，
/// 不是請求本體的迴音——本模型只從回應構造，結構上沒有「本地意圖」的格子。
class AdminDetailReport {
  /// 以已驗證的欄位建立單筆回應。
  const AdminDetailReport({required this.admin, required this.requestId});

  /// 從 JSON 回應建立單筆資料。
  static AdminDetailReport decode(Map<String, Object?> json) {
    final Object? raw = json['admin'];
    if (raw is! Map<String, Object?>) {
      throw const ApiResponseShapeException('admin 不是物件');
    }
    return AdminDetailReport(
      admin: AdminAccountReport.decode(raw),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 單筆管理員資料。
  final AdminAccountReport admin;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// `PUT /root/admins/{account_id}/status` 的成功回應：變更後的資料庫現值與撤銷數量。
///
/// [revokedSessions] 是這次落庫的會話撤銷數：界面據此如實說出「這次讓 N 臺裝置
/// 重新登入」，而不是讓 Root 對著一句「已停用」猜影響範圍。恢復時它恆為 0——
/// 「不復活停用前會話」由後端保證，界面只轉計數。admin 欄位與詳情同形：
/// 狀態變更後的展示仍以服務端結果為唯一來源，不是請求本體的迴音。
class AdminStatusReport {
  /// 以已驗證的欄位建立單次狀態變更回應。
  const AdminStatusReport({
    required this.admin,
    required this.revokedSessions,
    required this.requestId,
  });

  /// 從 JSON 回應建立狀態變更結果。
  static AdminStatusReport decode(Map<String, Object?> json) {
    final Object? raw = json['admin'];
    if (raw is! Map<String, Object?>) {
      throw const ApiResponseShapeException('admin 不是物件');
    }
    return AdminStatusReport(
      admin: AdminAccountReport.decode(raw),
      revokedSessions: _requireInt(json, 'revoked_sessions'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 變更後的單筆管理員資料。
  final AdminAccountReport admin;

  /// 這次撤銷的會話數量（恢復恆為 0）。
  final int revokedSessions;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// `PUT /root/admins/{account_id}/password` 的成功回應：重置後的資料庫現值與撤銷數量。
///
/// 欄位形態與 [AdminStatusReport] 同構但刻意各自獨名：兩條子資源白名單的語意不同
/// （一個動狀態、一個動憑據），合併成一個型別會讓「這次成功的是哪件事」在界面層失去出處。
/// [admin] 是重置後的單筆真相：`must_change_password` 必為 true（重置交付的永遠是
/// 一次性口令），`status` 與 `disabled_at` 保持目標原樣（重置不是解除停用）。
/// [revokedSessions] 為這次落庫的會話撤銷數，缺席判合同違例、不降級成 0；
/// 回應裡不存在、也不允許出現任何口令或憑據材料——口令只在請求那一側出現一次。
class AdminPasswordResetReport {
  /// 以已驗證的欄位建立單次憑據重置回應。
  const AdminPasswordResetReport({
    required this.admin,
    required this.revokedSessions,
    required this.requestId,
  });

  /// 從 JSON 回應建立憑據重置結果。
  static AdminPasswordResetReport decode(Map<String, Object?> json) {
    final Object? raw = json['admin'];
    if (raw is! Map<String, Object?>) {
      throw const ApiResponseShapeException('admin 不是物件');
    }
    return AdminPasswordResetReport(
      admin: AdminAccountReport.decode(raw),
      revokedSessions: _requireInt(json, 'revoked_sessions'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 重置後的單筆管理員資料。
  final AdminAccountReport admin;

  /// 這次撤銷的會話數量（停用中的目標通常是 0——其會話早在停用時已撤）。
  final int revokedSessions;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// `DELETE /root/admins/{account_id}` 的成功回應：刪除後的資料庫現值與撤銷數量。
///
/// 欄位形態與 [AdminStatusReport]、[AdminPasswordResetReport] 同構但刻意各自獨名：
/// 三條通路成功的是三件不同的事，合併成一個型別會讓「這次辦掉的是哪一件」在界面層
/// 失去出處。[admin] 是刪除後的單筆真相：`status` 必為 `deleted`、`deleted_at` 必在、
/// `display_name` 已是匿名化佔位值，而 `login_name` 原樣保留（它就是歷史身份的承載者）。
/// [revokedSessions] 為這次落庫的會話撤銷數，缺席判合同違例、不降級成 0。
/// 回應裡不會有任何「如何恢復」的暗示：刪除是終態，協定層沒有一條把它改回來的路。
class AdminDeleteReport {
  /// 以已驗證的欄位建立單次刪除回應。
  const AdminDeleteReport({
    required this.admin,
    required this.revokedSessions,
    required this.requestId,
  });

  /// 從 JSON 回應建立刪除結果。
  static AdminDeleteReport decode(Map<String, Object?> json) {
    final Object? raw = json['admin'];
    if (raw is! Map<String, Object?>) {
      throw const ApiResponseShapeException('admin 不是物件');
    }
    return AdminDeleteReport(
      admin: AdminAccountReport.decode(raw),
      revokedSessions: _requireInt(json, 'revoked_sessions'),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 刪除後的單筆管理員資料。
  final AdminAccountReport admin;

  /// 這次撤銷的會話數量（本就停用且會話早已撤盡的目標是 0）。
  final int revokedSessions;

  /// 本次請求的關聯 ID。
  final String requestId;
}

/// 登入前界面可見的兩個入口答案（`/auth/capabilities` 的本體，也嵌在策略回應裡）。
///
/// 只有兩個布林，是刻意的：模式名字、最後修改時刻、管理員建號開關都不在這個合同裡，
/// 因此界面無法把「這台伺服器打算怎麼做准入」講給還站在門外的人聽。
/// 兩個值是「策略說要開」與「那條通路真的存在」的合成結果，所以策略被存成放開而通路
/// 還沒上線時，這裡照樣是 `false`——界面據此不得顯示任何按下必然失敗的入口。
class AccountEntryCapabilities {
  /// 以已驗證的欄位建立對外入口答案。
  const AccountEntryCapabilities({
    required this.signUpOpen,
    required this.guestOpen,
  });

  /// 從 JSON 建立（頂層與嵌在 `entry` 裡都是同一組欄位名，因此共用這個解碼點）。
  static AccountEntryCapabilities decode(Map<String, Object?> json) {
    return AccountEntryCapabilities(
      signUpOpen: _requireBool(json, 'sign_up_open'),
      guestOpen: _requireBool(json, 'guest_open'),
    );
  }

  /// 用戶自註冊入口對外是否開放。
  final bool signUpOpen;

  /// 訪客（臨時帳戶）入口對外是否開放。
  final bool guestOpen;
}

/// `GET／PUT /root/account-policy` 的成功回應：帳戶建立策略現值與其對外結果。
///
/// 三個值就是策略全文（後端那張表也只有這三個值加一個時刻）：[adminCreateStandard]、
/// [selfRegisterMode]、[guestEnabled] 彼此獨立，界面不得把其中一個的變動推給另一個。
/// [updatedAt] 為 null 是一個有意義的事實——「這一列出廠以來沒人改過」，
/// 不是「時刻查不到」，因此界面要說「尚未修改過」而不能顯示一個假日期。
/// [entry] 是「這份策略此刻讓登入前界面看到什麼」：它與策略值刻意並列在同一份回應裡，
/// 讓操作者能同時核對意圖與結果，而不是自己推算（推算就會推錯）。
/// [selfRegisterMode] 原字串保留：日後後端多出新模式名字時，界面要能如實顯示那個名字
/// 並把「本版本還不能選它」說出來，而不是判成合同違例或默默當成 `closed`。
class AccountPolicyReport {
  /// 以已驗證的欄位建立一份策略現值。
  const AccountPolicyReport({
    required this.adminCreateStandard,
    required this.selfRegisterMode,
    required this.guestEnabled,
    required this.entry,
    required this.requestId,
    this.updatedAt,
  });

  /// 從 JSON 建立。`entry` 缺席或不是物件判合同違例：少了它，界面就只剩策略值、
  /// 沒有「對外此刻是什麼」，而那正是這張卡要避免猜測的一件事。
  static AccountPolicyReport decode(Map<String, Object?> json) {
    final Object? raw = json['entry'];
    if (raw is! Map<String, Object?>) {
      throw const ApiResponseShapeException('entry 不是物件');
    }
    return AccountPolicyReport(
      adminCreateStandard: _requireBool(json, 'admin_create_standard'),
      selfRegisterMode: _requireText(json, 'self_register_mode'),
      guestEnabled: _requireBool(json, 'guest_enabled'),
      updatedAt: _optionalUtcTime(json, 'updated_at'),
      entry: AccountEntryCapabilities.decode(raw),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 「管理員可建立普通帳戶」開關。
  final bool adminCreateStandard;

  /// 自註冊模式原字串。
  final String selfRegisterMode;

  /// 「可建立訪客（臨時）帳戶」開關。
  final bool guestEnabled;

  /// 最後一次修改的時刻（UTC）；從未被改寫為 `null`。
  final DateTime? updatedAt;

  /// 由這份策略合成的對外入口答案。
  final AccountEntryCapabilities entry;

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 模式是否為已批准的四個名字之一（未知名字不是錯誤，但界面不能假裝認得它）。
  bool get isKnownMode =>
      selfRegisterMode == 'closed' ||
      selfRegisterMode == 'open' ||
      selfRegisterMode == 'approval' ||
      selfRegisterMode == 'invite';

  /// 模式是否為本版本可寫入的兩個名字之一。
  ///
  /// 判定只依這條清單，界面不得另猜一份：後端放行哪個模式是它那一側的登記，
  /// 這裡只是「不要讓 Root 選一個必然被打成 2016 的值」。
  bool get isWritableMode =>
      selfRegisterMode == 'closed' || selfRegisterMode == 'open';
}

/// `GET /auth/capabilities` 的成功回應：兩個對外布林加關聯 ID。
///
/// 這是登入前界面唯一的准入資訊來源，而且只進不出：本請求沒有任何欄位可以攜帶
/// 身分或意圖，查得到的結果也不含帳戶清單、名額、閾值或策略全文。
class EntryCapabilitiesReport {
  /// 以已驗證的欄位建立對外入口答案的回應。
  const EntryCapabilitiesReport({required this.entry, required this.requestId});

  /// 從 JSON 建立。
  static EntryCapabilitiesReport decode(Map<String, Object?> json) {
    return EntryCapabilitiesReport(
      entry: AccountEntryCapabilities.decode(json),
      requestId: _requireText(json, 'request_id'),
    );
  }

  /// 兩個入口的對外答案。
  final AccountEntryCapabilities entry;

  /// 本次請求的關聯 ID。
  final String requestId;
}
