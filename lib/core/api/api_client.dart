/// 統一 API 存取層：整個應用只有這裡會碰網路，所有端點都經由此處發出請求。
///
/// 存在的理由有兩條：
/// 1. **單一出口**——基準位址驗證、標頭、期限、狀態判定與錯誤轉換集中一處，
///    頁面不可能繞過判定而自行宣稱請求成功。
/// 2. **失敗不可能被誤讀為成功**——本檔的每一條失敗路徑都以拋出 [ApiError]
///    結束，不回傳任何值；連「HTTP 200 但內容不合合同」這種最容易蒙混過關的
///    情況也算失敗（完成判斷要求網路錯誤不得顯示為成功）。
///
/// 刻意不 import Flutter 介面層，使這一層可被 `dart run` 的驗證腳本直接重用，
/// 對實際啟動的服務走同一份程式碼。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_error.dart';
import 'server_address.dart';

/// 存取組態。
///
/// 位址以 [ServerAddressSource] 即時取用而非保存一段文字：位址可在執行期間被
/// 使用者改動並本地保存，若組態複制了一份，就會出現「畫面已改、請求仍打舊位址」。
class ServerApiConfig {
  /// 以位址來源與期限建立組態。
  const ServerApiConfig({
    this.source = const InjectedServerAddressSource(),
    this.requestTimeout = defaultRequestTimeout,
  });

  /// 以固定位址文字建立組態：測試、工具腳本，以及驗證尚未保存的候選位址。
  ServerApiConfig.fixed(
    String? url, {
    this.requestTimeout = defaultRequestTimeout,
  }) : source = StaticServerAddressSource(url);

  /// 內建請求期限：區域網路的正常回應在毫秒級，5 秒已涵蓋資料庫尚未就緒時
  /// `/ready` 的 3 秒上限，又短到不會讓探測按鈕卡住介面。
  static const Duration defaultRequestTimeout = Duration(seconds: 5);

  /// 基準位址的即時來源。
  final ServerAddressSource source;

  /// 單一請求的期限。
  final Duration requestTimeout;

  /// 目前生效的基準位址文字；未設定時為 `null`。
  String? get baseUrl => source.currentUrl();

  /// 已驗證的基準位址；未設定或格式不合格時為 `null`。
  ServerAddress? get address => ServerAddress.tryParse(baseUrl ?? '');

  /// 是否具備可用的基準位址。
  bool get hasAddress => address != null;
}

/// 回應解碼器：把已確認為 JSON 物件的回應轉成模型，不合合同時拋出
/// [ApiResponseShapeException]。
typedef ResponseDecoder<T> = T Function(Map<String, Object?> json);

/// 統一 API 存取客戶端。
class ApiClient {
  /// 以組態建立客戶端；未注入 [httpClient] 時共用一個全域連線。
  const ApiClient({this.config = const ServerApiConfig(), this.httpClient});

  /// 共用客戶端：延遲到第一次實際請求才建立，測試與未連線的畫面不會觸發它。
  static final http.Client _sharedClient = http.Client();

  /// 存取組態。
  final ServerApiConfig config;

  /// 注入的傳輸實作（測試用假客戶端）；`null` 時使用 [_sharedClient]。
  final http.Client? httpClient;

  /// 實際使用的傳輸實作。
  http.Client get _transport => httpClient ?? _sharedClient;

  /// 對指定路徑發起 GET，並把成功回應解碼為 [T]。
  ///
  /// 任何一步不合格都拋出 [ApiError]：本方法沒有任何「回傳值但其實失敗」的
  /// 路徑。[acceptLanguage] 決定送出的 `Accept-Language`，讓伺服器的診斷
  /// 訊息與介面使用同一種語言（介面顯示文字仍一律取自本地化資源）。
  Future<T> get<T>(
    String path, {
    required ResponseDecoder<T> decode,
    String? acceptLanguage,
  }) async {
    final ServerAddress? address = config.address;
    if (address == null) {
      throw ApiError(kind: ApiErrorKind.notConfigured, path: path);
    }

    final Uri uri = address.resolve(path);
    final Map<String, String> headers = <String, String>{
      'accept': 'application/json',
      if (acceptLanguage != null && acceptLanguage.isNotEmpty)
        'accept-language': acceptLanguage,
    };

    final http.Response response;
    try {
      response = await _transport
          .get(uri, headers: headers)
          .timeout(config.requestTimeout);
    } on TimeoutException {
      throw ApiError(
        kind: ApiErrorKind.timeout,
        path: path,
        cause: '超過 ${config.requestTimeout.inMilliseconds} 毫秒',
      );
    } on http.ClientException catch (error) {
      // 連不上：包含服務未啟動、位址錯誤、離線與瀏覽器阻擋。
      // ClientException 的 message 不含基準位址與憑證，可直接留作診斷。
      throw ApiError(
        kind: ApiErrorKind.unreachable,
        path: path,
        cause: error.message,
      );
    } catch (error) {
      // 未預期的底層異常一律當作「沒有拿到可信回應」處理，絕不可向上回傳值。
      throw ApiError(
        kind: ApiErrorKind.unreachable,
        path: path,
        cause: '$error'.isEmpty
            ? error.runtimeType.toString()
            : _reasonOf(error),
      );
    }

    final String? requestId = _headerOf(response, 'x-request-id');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _failureFromStatus(
        path: path,
        response: response,
        requestId: requestId,
      );
    }

    final Object? payload = _decodeBody(
      body: response.bodyBytes,
      contentType: _headerOf(response, 'content-type'),
      path: path,
      requestId: requestId,
    );

    try {
      return decode(payload as Map<String, Object?>);
    } on ApiResponseShapeException catch (error) {
      throw ApiError(
        kind: ApiErrorKind.invalidResponse,
        path: path,
        httpStatus: response.statusCode,
        requestId: requestId,
        cause: error.reason,
      );
    }
  }

  /// 非 2xx 回應：優先採用統一錯誤信封的機器碼與關聯 ID，信封不合時退回狀態碼判定。
  ApiError _failureFromStatus({
    required String path,
    required http.Response response,
    required String? requestId,
  }) {
    final Object? payload = _tryDecodeJson(response.bodyBytes);
    ApiErrorEnvelope? envelope;
    if (payload is Map<String, Object?>) {
      envelope = ApiErrorEnvelope.tryParse(payload);
    }

    return ApiError(
      kind: ApiErrorKind.httpStatus,
      path: path,
      httpStatus: response.statusCode,
      machineCode: envelope?.machineCode,
      serverMessage: envelope?.message,
      details: envelope?.details,
      // 信封內的 ID 優先，標頭為備援（431 這類由 net/http 直接回應的錯誤沒有信封）。
      requestId: envelope?.requestId ?? requestId,
    );
  }

  /// 2xx 回應的本體解析：內容型別、JSON 可解析性與「必須是物件」逐一把關。
  Object? _decodeBody({
    required List<int> body,
    required String? contentType,
    required String path,
    required String? requestId,
  }) {
    if (contentType == null ||
        !contentType.toLowerCase().contains('application/json')) {
      throw ApiError(
        kind: ApiErrorKind.invalidResponse,
        path: path,
        httpStatus: 200,
        requestId: requestId,
        cause: 'content-type: $contentType',
      );
    }

    final Object? payload = _tryDecodeJson(body);
    if (payload is! Map<String, Object?>) {
      throw ApiError(
        kind: ApiErrorKind.invalidResponse,
        path: path,
        httpStatus: 200,
        requestId: requestId,
        cause: payload == null ? '本體不是可解析的 JSON 物件' : '頂層不是 JSON 物件',
      );
    }
    return payload;
  }

  /// 嘗試把本體解為 JSON；失敗回傳 `null`（呼叫端依情境決定是錯誤還是忽略）。
  ///
  /// `utf8.decode` 對非 UTF-8 位元組回傳 `FormatException`，與 JSON 畸形同類處理。
  Object? _tryDecodeJson(List<int> body) {
    if (body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(utf8.decode(body));
    } on FormatException {
      return null;
    }
  }

  /// 大小寫不敏感地讀取標頭（Go 會把 `X-Request-ID` 正規化為 `X-Request-Id`）。
  String? _headerOf(http.Response response, String name) {
    final String? direct = response.headers[name.toLowerCase()];
    if (direct != null) {
      return direct;
    }
    for (final MapEntry<String, String> entry in response.headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  /// 從未預期異常取出一段不帶位址的原因描述。
  String _reasonOf(Object error) {
    final String text = '$error';
    final int breakIndex = text.indexOf('\n');
    return breakIndex < 0 ? text : text.substring(0, breakIndex);
  }
}
