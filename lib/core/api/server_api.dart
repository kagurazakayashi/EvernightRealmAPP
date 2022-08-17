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
import 'api_error.dart';
import 'server_models.dart';

/// 存活檢查端點路徑。
const String kHealthPath = '/health';

/// 就緒檢查端點路徑。
const String kReadyPath = '/ready';

/// 伺服器時間端點路徑。
const String kTimePath = '/time';

/// 普通帳戶登入端點路徑。
const String kAuthLoginPath = '/auth/login';

/// Root 登入端點路徑（校驗對象是伺服器組態的 Root 憑據，與帳戶端點完全分開）。
const String kAuthRootLoginPath = '/auth/root/login';

/// 當前會話端點路徑。
const String kAuthSessionPath = '/auth/session';

/// 會話 Cookie 名（後端合同的固定值）。
///
/// 原生客戶端從 `Set-Cookie` 標頭按此名稱提取會話秘密；提取後的保存與回傳
/// 屬會話狀態管理步驟，必須走批准的安全保存方案，不得進 shared_preferences。
const String kSessionCookieName = 'evernight_session';

/// 從 `Set-Cookie` 標頭文字提取會話秘密；讀不到時回傳 `null`。
///
/// 只認合同內那一枚 Cookie（名稱見 [kSessionCookieName]）。注意標頭文字可能
/// 含属性段（`; Path=/` 等），比對到分號、逗號與空白為止；瀏覽器環境
/// 本來就拿不到 `Set-Cookie`，回傳 `null` 是預期行為而不是失敗。
String? extractSessionCookie(String? setCookieHeader) {
  if (setCookieHeader == null || setCookieHeader.isEmpty) {
    return null;
  }
  final RegExpMatch? match = RegExp(
    '(?:^|,)\\s*$kSessionCookieName=([^;,\\s]+)',
  ).firstMatch(setCookieHeader);
  final String? value = match?.group(1);
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

/// 一次登入的完整成果：已驗證的回應，與（僅原生可得）的會話秘密。
class LoginExchange {
  /// 以已驗證的回應建立成果。
  const LoginExchange({required this.report, this.sessionSecret});

  /// 登入回應的事實欄位（主體類別、設備標識、到期時刻）。
  final LoginReport report;

  /// 會話秘密的一次性明文；瀏覽器環境恆為 `null`（HttpOnly 語意）。
  ///
  /// 不得寫入日誌、診斷輸出或任何介面文字；保存與回傳方式屬後續的
  /// 會話狀態管理步驟（批准的安全儲存）。
  final String? sessionSecret;
}

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

  /// 普通帳戶登入：POST `/auth/login`。
  ///
  /// 失敗（查無此人、口令錯誤、帳戶不可登入）由後端收斂為同一個機器碼 2001，
  /// 呼叫端只拿得到「被拒」這件事，拿不到可據以枚舉帳戶的第二句。
  /// 成功時若在执行环境能讀到 `Set-Cookie`（原生平台），會話秘密一併回傳。
  Future<LoginExchange> login({
    required String loginName,
    required String password,
    String? acceptLanguage,
  }) async {
    final ({LoginReport value, String? setCookie}) result = await apiClient
        .postCapturingCookie(
          kAuthLoginPath,
          jsonBody: <String, Object?>{
            'login_name': loginName,
            'password': password,
          },
          decode: LoginReport.decode,
          acceptLanguage: acceptLanguage,
        );
    return LoginExchange(
      report: result.value,
      sessionSecret: extractSessionCookie(result.setCookie),
    );
  }

  /// Root 登入：POST `/auth/root/login`，只交出口令，沒有也不需要登入名。
  Future<LoginExchange> rootLogin({
    required String password,
    String? acceptLanguage,
  }) async {
    final ({LoginReport value, String? setCookie}) result = await apiClient
        .postCapturingCookie(
          kAuthRootLoginPath,
          jsonBody: <String, Object?>{'password': password},
          decode: LoginReport.decode,
          acceptLanguage: acceptLanguage,
        );
    return LoginExchange(
      report: result.value,
      sessionSecret: extractSessionCookie(result.setCookie),
    );
  }

  /// 讀取當前會話：GET `/auth/session`。
  ///
  /// 瀏覽器路徑不帶任何參數（Cookie 自動附帶）；原生路徑傳 [bearerToken]。
  /// 未認證回機器碼 2002、憑據失效回 2003——兩者都以 `ApiError` 拋出，
  /// 不存在「回傳了報告但其實沒登入」的形態。
  Future<CurrentSessionReport> currentSession({
    String? bearerToken,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      kAuthSessionPath,
      decode: CurrentSessionReport.decode,
      acceptLanguage: acceptLanguage,
      bearerToken: bearerToken,
    );
  }
}

/// 一趟成功探測收集到的回應。
class ServerProbeResult {
  /// 以已驗證的回應建立探測結果。
  const ServerProbeResult({required this.health, required this.time});

  /// `/health` 的存活回應。
  final HealthReport health;

  /// `/time` 的校時回應。
  final ServerTimeReport time;
}

/// 一趟連通性探測的結果：成功時帶 [result]，失敗時帶 [error]，兩者必居其一。
///
/// 之所以把失敗做成值而非例外，是因為探測的呼叫端（狀態條、位址卡片）需要的
/// 都是「把原因顯示出來」，而不是中斷執行流；做成例外會讓每條路徑都得自己接。
class ServerProbeOutcome {
  /// 以成功回應建立結果。
  const ServerProbeOutcome.success(this.result) : error = null;

  /// 以失敗原因建立結果。
  const ServerProbeOutcome.failure(this.error) : result = null;

  /// 成功的探測回應；失敗時為 `null`。
  final ServerProbeResult? result;

  /// 失敗原因；成功時為 `null`。
  final ApiError? error;

  /// 本次探測是否成功。
  bool get isSuccessful => error == null;
}

/// 依序讀取存活與校時端點，把成敗收斂為 [ServerProbeOutcome]（本函式不拋例外）。
///
/// 這是「這個位址到底通不通」的唯一依據：探測區的探測與保存前的候選位址驗證
/// 都走它，因此不會出現「探測區說通、保存時用另一套標準說不通」。
Future<ServerProbeOutcome> probeServerConnectivity(
  ServerApi api, {
  String? acceptLanguage,
}) async {
  try {
    final HealthReport health = await api.health(
      acceptLanguage: acceptLanguage,
    );
    final ServerTimeReport time = await api.time(
      acceptLanguage: acceptLanguage,
    );
    return ServerProbeOutcome.success(
      ServerProbeResult(health: health, time: time),
    );
  } on ApiError catch (error) {
    return ServerProbeOutcome.failure(error);
  }
}
