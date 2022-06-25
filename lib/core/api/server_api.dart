/// 基礎端點的統一存取入口：頁面只經由此處讀伺服器，不自行拼 URL 或判狀態。
///
/// 三個端點的職責分工取自後端發布的合同（DEC-016）：`/health` 回答進程存活、
/// `/ready` 回答依賴可用與否、`/time` 回答伺服器時間與顯示時區。
/// 其中 `/time` 不受就緒門控，資料庫不可用時仍需校時與顯示斷線狀態。
///
/// 本檔可宣告為常值：未注入客戶端時共用存取層的全域連線，因此組裝依賴時
/// 不需要額外的生命週期管理。
library;

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'server_models.dart';

/// 存活檢查端點路徑。
const String kHealthPath = '/health';

/// 就緒檢查端點路徑。
const String kReadyPath = '/ready';

/// 伺服器時間端點路徑。
const String kTimePath = '/time';

/// 基礎端點的存取介面。
class ServerApi {
  /// 以組態與（可選的）傳輸實作建立存取介面。
  const ServerApi({this.config = const ServerApiConfig(), this.client});

  /// 底層統一存取客戶端。
  ApiClient get apiClient => ApiClient(config: config, httpClient: client);

  /// 存取組態。
  final ServerApiConfig config;

  /// 注入的傳輸實作；`null` 時使用共用連線。
  final http.Client? client;

  /// 是否已設定可用的基準位址。
  bool get isConfigured => config.hasAddress;

  /// 實際發出的基準位址文字；未設定時回傳 `null`。
  String? get addressDisplay => config.address?.displayText;

  /// 讀取進程存活狀態。失敗一律拋出 `ApiError`。
  Future<HealthReport> health({String? acceptLanguage}) {
    return apiClient.get(
      kHealthPath,
      decode: HealthReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀取依賴就緒狀態。不就緒時伺服器回 503，同樣拋出 `ApiError`。
  Future<ReadinessReport> ready({String? acceptLanguage}) {
    return apiClient.get(
      kReadyPath,
      decode: ReadinessReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀取伺服器時間與顯示時區。失敗一律拋出 `ApiError`。
  Future<ServerTimeReport> time({String? acceptLanguage}) {
    return apiClient.get(
      kTimePath,
      decode: ServerTimeReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }
}
