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

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 是否為 Root 主體的登入。
  bool get isRoot => subjectKind == AuthSubjectKind.root;
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

  /// 本次請求的關聯 ID。
  final String requestId;

  /// 是否為 Root 主體的會話。
  bool get isRoot => subjectKind == AuthSubjectKind.root;
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
