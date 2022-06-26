/// 一筆「未處理錯誤」的結構化記錄：只保留可安全顯示與可對應日誌的欄位。
///
/// 刻意**不保存**原始例外物件、堆疊文字、請求本體或基準位址——這些都可能在
/// 某處帶出憑證。畫面只取 [diagnosticCode]、[requestId] 與類別，stderr 另記
/// 一筆經過脫敏的描述。
library;

/// 失敗發生的位置（決定介面用哪一句話解釋，以及日誌怎麼歸檔）。
enum AppFailureKind {
  /// 元件在建構、佈局或繪製階段拋出例外。
  widgetBuild,

  /// 框架在非構建階段回報的問題（例如本地化載入失敗、平台通道錯誤）。
  frameworkReport,

  /// 非同步工作拋出而沒有人接住的例外。
  uncaughtAsync,

  /// 與伺服器往來時產生的失敗（來自存取層的 `ApiError`）。
  apiCall,

  /// 判不出來路的一次失敗。
  unknown,
}

/// 一筆已脫敏的失敗記錄。
class AppFailure {
  /// 以已脫敏的欄位建立記錄。
  const AppFailure({
    required this.kind,
    required this.diagnosticCode,
    required this.summary,
    this.requestId,
    this.library,
    this.repeated = false,
  });

  /// 失敗發生的位置。
  final AppFailureKind kind;

  /// 本機診斷碼：對應 stderr 裡的一行記錄，供使用者回報時對照。
  ///
  /// 它不是伺服器產生的識別碼，也不含任何時間或個人資訊。
  final String diagnosticCode;

  /// 經過脫敏的錯誤描述（型別名加首行訊息，長度封頂）。
  final String summary;

  /// 請求關聯 ID：有它就能與伺服器日誌對上同一筆請求。
  final String? requestId;

  /// 框架回報的所屬庫名稱（例如 `rendering`、`services`）。
  final String? library;

  /// 是否為使用者剛按過「返回可用頁面」後又立刻重現的同一個失敗。
  ///
  /// 重現代表返回並不能繞開問題，介面據此改口請使用者重新載入。
  final bool repeated;
}
