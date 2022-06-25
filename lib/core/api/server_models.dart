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
