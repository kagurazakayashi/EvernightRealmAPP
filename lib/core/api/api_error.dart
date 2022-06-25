/// 伺服器錯誤的結構化表示：把傳輸結果、HTTP 狀態、機器錯誤碼與請求關聯 ID
/// 分成可判定的欄位，供介面選擇文案、決定是否重試，讓日誌能對應到一次請求。
///
/// 核心不變量：**只要請求沒有成功，就一律以 [ApiError] 拋出**。呼叫端拿不到
/// 任何「看起來像成功值」的東西，因此不可能把失敗呈現為成功（包括伺服器回了
/// 200 但內容抵觸合同的情況）。
///
/// 本檔不保存任何語言的顯示字串（DEC-017）：錯誤分類到介面文字的映射
/// 一律在元件層向本地化資源取得。
library;

/// 請求失敗的類別：依「在哪一步失敗」區分，而不是依 HTTP 狀態碼區分。
enum ApiErrorKind {
  /// 本地前提不成立：伺服器位址尚未設定或無效，請求根本沒有發出。
  notConfigured,

  /// 無法取得回應：離線、服務未啟動、位址不可達、TLS 交握失敗等。
  ///
  /// 任何未預期的底層異常也歸此類並保留原因——總之不能當成成功。
  unreachable,

  /// 已發出請求，但在期限內沒有拿到完整回應。
  timeout,

  /// 伺服器明確回了非 2xx 回應：服務是可達的，只是這次請求不被接受。
  httpStatus,

  /// 伺服器回了 2xx 但內容不可信：不是 JSON、不是物件、缺少必要欄位
  /// 或欄位型別與合同不符。**這種情況一律視為失敗**。
  invalidResponse,
}

/// 已發布的穩定機器錯誤碼（1xxx 通用與協定段）。
///
/// 數值由後端權威定義且不得重用；這裡只做「已知碼→語意」的對應，
/// 未收錄的數值仍以 [ApiError.machineCode] 原樣保留，不丟棄也不猜測。
enum ApiMachineCode {
  /// 1000：未分類的內部錯誤；對外只有固定文案。
  internalError(1000),

  /// 1001：請求的路徑不存在。
  notFound(1001),

  /// 1002：路徑存在，但不支援該 HTTP 方法。
  methodNotAllowed(1002),

  /// 1003：請求體超過大小上限。
  payloadTooLarge(1003),

  /// 1004：請求體無法解析（畸形 JSON、未知欄位、空本體或尾隨資料）。
  invalidBody(1004),

  /// 1005：請求體不是 JSON 內容型別。
  unsupportedMediaType(1005),

  /// 1006：伺服器處理超過期限。
  requestTimeout(1006),

  /// 1007：服務尚未就緒，業務操作暫不可執行。
  notReady(1007);

  /// 以對外發布的數值建立錯誤碼。
  const ApiMachineCode(this.value);

  /// 對外協定中的數字錯誤碼。
  final int value;

  /// 依數值取得已知錯誤碼；未收錄者回傳 `null`（後續分段由端點實作細分）。
  static ApiMachineCode? fromValue(int value) {
    for (final ApiMachineCode code in ApiMachineCode.values) {
      if (code.value == value) {
        return code;
      }
    }
    return null;
  }
}

/// 一次失敗請求的結構化結果。
class ApiError implements Exception {
  /// 以分類與可選的細節建立失敗結果。
  ApiError({
    required this.kind,
    required this.path,
    this.httpStatus,
    this.machineCode,
    this.serverMessage,
    this.details,
    this.requestId,
    this.cause,
  });

  /// 失敗類別。
  final ApiErrorKind kind;

  /// 請求的端點路徑（不含主機與憑證），只用於診斷。
  final String path;

  /// HTTP 狀態碼；只有拿到回應時才有的值。
  final int? httpStatus;

  /// 伺服器回傳的機器錯誤碼原值；回應未帶或無法解析時為 `null`。
  final int? machineCode;

  /// 伺服器回傳的在地化訊息：僅供診斷與日誌，介面顯示一律另經 ARB 映射。
  final String? serverMessage;

  /// 伺服器附帶的可公開判定依據（如未知欄位名）。
  final Map<String, Object?>? details;

  /// 請求關聯 ID：與伺服器日誌對應同一筆請求。
  final String? requestId;

  /// 底層原因（例如 `http.ClientException`）；只保留訊息，不放位址。
  final Object? cause;

  /// 已解析的已知機器錯誤碼；未收錄的數值回傳 `null`。
  ApiMachineCode? get knownCode => switch (machineCode) {
    final int value? => ApiMachineCode.fromValue(value),
    _ => null,
  };

  /// 伺服器是否有回應過：區分「服務不可達」與「服務可達但拒絕此次請求」。
  bool get serverResponded => httpStatus != null;

  /// 是否值得重試：連不上、逾時、尚未就緒與內部錯誤屬暫時性問題。
  ///
  /// 請求體本身的問題（1003–1005）與路徑／方法錯誤（1001、1002）不會因為
  /// 重試而改變，因此不標為可重試。
  bool get retryable => switch (kind) {
    ApiErrorKind.notConfigured => false,
    ApiErrorKind.unreachable || ApiErrorKind.timeout => true,
    ApiErrorKind.invalidResponse => false,
    ApiErrorKind.httpStatus => switch (knownCode) {
      ApiMachineCode.notReady || ApiMachineCode.requestTimeout => true,
      ApiMachineCode.internalError => true,
      _ => (httpStatus ?? 0) >= 500,
    },
  };

  /// 供日誌使用的安全描述：不含基準位址、不含任何憑證，只留分類與關聯資訊。
  @override
  String toString() {
    final StringBuffer buffer = StringBuffer('ApiError(');
    buffer.write(kind.name);
    final int? status = httpStatus;
    if (status != null) {
      buffer.write(', http=$status');
    }
    final int? code = machineCode;
    if (code != null) {
      buffer.write(', code=$code');
    }
    buffer.write(', path=$path');
    final String? id = requestId;
    if (id != null) {
      buffer.write(', request_id=$id');
    }
    buffer.write(')');
    return buffer.toString();
  }
}

/// 統一錯誤信封的解析結果（欄位取自後端 errors.go 的權威定義）。
class ApiErrorEnvelope {
  /// 以已驗證的欄位建立信封解析結果。
  const ApiErrorEnvelope({
    required this.machineCode,
    this.message,
    this.details,
    this.requestId,
  });

  /// 從已解碼的 JSON 物件嘗試解析錯誤信封。
  ///
  /// 只有 `code` 為整數、`message`／`request_id` 為字串（若存在）且 `details`
  /// 為物件（若存在）才算成立；不符時回傳 `null`，由呼叫端改用狀態碼判定，
  /// 絕不因為信封不符而當成成功。
  static ApiErrorEnvelope? tryParse(Map<String, Object?> json) {
    final Object? code = json['code'];
    if (code is! int) {
      return null;
    }
    final Object? message = json['message'];
    if (message != null && message is! String) {
      return null;
    }
    final Object? requestId = json['request_id'];
    if (requestId != null && requestId is! String) {
      return null;
    }
    final Object? details = json['details'];
    if (details != null && details is! Map<String, Object?>) {
      return null;
    }
    return ApiErrorEnvelope(
      machineCode: code,
      message: message as String?,
      details: details as Map<String, Object?>?,
      requestId: requestId as String?,
    );
  }

  /// 數字錯誤碼原值。
  final int machineCode;

  /// 伺服器在地化訊息。
  final String? message;

  /// 可公開的判定依據。
  final Map<String, Object?>? details;

  /// 信封內的請求關聯 ID。
  final String? requestId;
}

/// 解碼失敗時擲出的例外，由 [ApiClient] 統一轉為 [ApiErrorKind.invalidResponse]。
///
/// 模型層只需要指出「哪個欄位不合」，不必自己組成完整的錯誤物件。
class ApiResponseShapeException implements Exception {
  /// 以一句話說明何處不符合合同。
  const ApiResponseShapeException(this.reason);

  /// 不合格的原因描述（供日誌與診斷，不直接作為介面文字）。
  final String reason;

  @override
  String toString() => 'ApiResponseShapeException($reason)';
}
