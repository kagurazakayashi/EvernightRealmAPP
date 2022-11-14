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

/// 登出端點路徑（後端在此撤銷「本請求憑據所指向的那一枚」會話並回刪除指令）。
const String kAuthLogoutPath = '/auth/logout';

/// 會話秘密輪換端點路徑：用當代憑據換發一枚新秘密（同一會話、同一裝置、同一期限）。
const String kAuthSessionRotatePath = '/auth/session/rotate';

/// Root 初始化狀態端點路徑（唯讀：查一次不會改變伺服器任何狀態）。
const String kRootInitStatusPath = '/root/init-status';

/// 「我的裝置」清單端點路徑（唯讀：只列當前主體名下的會話）。
const String kAuthDevicesPath = '/auth/devices';

/// 定向撤銷某一臺裝置的端點路徑（有副作用：撤的是當前主體名下、由 device_id 指向的會話）。
const String kAuthDeviceRevokePath = '/auth/devices/revoke';

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

/// 一次輪換的完整成果：已驗證的回應，與（僅原生可得）換發出的新秘密。
class RotationExchange {
  /// 以已驗證的回應建立成果。
  const RotationExchange({required this.report, this.sessionSecret});

  /// 輪換回應的事實欄位（主體類別、裝置標識、世代號、到期時刻）。
  final RotationReport report;

  /// 新秘密的一次性明文；瀏覽器環境恆為 `null`（HttpOnly 語意，由瀏覽器代管）。
  ///
  /// 與 [LoginExchange.sessionSecret] 同一套界線：不得寫入日誌、診斷輸出或任何
  /// 介面文字，儲存只經批准的安全儲存抽象。
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

  /// 登出：POST `/auth/logout`，讓伺服器撤銷「本請求憑據所指向的那一枚」會話。
  ///
  /// 憑據的攜帶與 [currentSession] 同一條路：瀏覽器形态由 HttpOnly Cookie 自動附帶、
  /// 指令碼不讀也不注入令牌；原生形态由傳輸層按「本筆請求的伺服器身份」注入 Bearer。
  /// 因此本方法沒有任何 `bearerToken` 參數——它只需要「打到那台伺服器」，憑據由装配決定。
  ///
  /// 回傳：本方法成功即代表「伺服器確認撤銷」；任何非 2xx 或連不上、逾時都以
  /// [ApiError] 拋出，由呼叫端據 [SessionController.signOut] 區分「本机已清理」
  /// 與「服务端撤销未确认」。後端對登出刻意做成冪等——重複登出同一枚已失效的
  /// 憑據也回 2xx，因此這裡不會把「其實早就登出了」誤報成失敗。
  /// 回應本體只有 request_id，合同上沒有可展示的身分欄位，故解碼直接忽略內容。
  Future<void> logout({String? acceptLanguage}) async {
    await apiClient.post<bool>(
      kAuthLogoutPath,
      jsonBody: const <String, Object?>{},
      decode: (Map<String, Object?> json) => true,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 輪換會話秘密：POST `/auth/session/rotate`，用當代憑據換發一枚新秘密。
  ///
  /// 憑據的攜帶與 [logout] 同一條路：瀏覽器形態由 HttpOnly Cookie 自動附帶，
  /// 原生形態由傳輸層按「本筆請求的伺服器身份」注入 Bearer，因此本方法沒有
  /// `bearerToken` 引數，也沒有任何可自報「要換哪一枚」的欄位。
  ///
  /// 回傳：成功即代表「伺服器已換發」，新秘密在原生環境從 `Set-Cookie` 取得
  /// （瀏覽器環境恆為 `null`，那枚 Cookie 由瀏覽器自己收下）。失敗一律以
  /// [ApiError] 丟擲，其中機器碼 2007 表示「本請求帶的是上一代憑據」——
  /// 處置是重試而不是重新登入；2003 表示那枚會話已失效。
  /// 回應本體不含任何秘密，只有可展示事實與世代號。
  Future<RotationExchange> rotateSession({String? acceptLanguage}) async {
    final ({RotationReport value, String? setCookie}) result = await apiClient
        .postCapturingCookie(
          kAuthSessionRotatePath,
          jsonBody: const <String, Object?>{},
          decode: RotationReport.decode,
          acceptLanguage: acceptLanguage,
        );
    return RotationExchange(
      report: result.value,
      sessionSecret: extractSessionCookie(result.setCookie),
    );
  }

  /// 讀取「我的裝置」清單：GET `/auth/devices`，只列當前主體名下的會話。
  ///
  /// 憑據的攜帶與 [currentSession] 同一條路：瀏覽器形態由 HttpOnly Cookie 自動附帶，
  /// 原生形態由傳輸層按「本筆請求的伺服器身份」注入 Bearer。本方法沒有任何 device_id／
  /// account_id 引數——查詢範圍由後端按解析出的受信主體決定，客戶端無從指定「列誰的裝置」。
  /// 失敗一律以 [ApiError] 丟擲（未帶憑據 2002、失效 2003、上一代 2007、混用 2004），
  /// 不存在「回了一份清單但其實沒登入」的形態。
  Future<DeviceListReport> devices({String? acceptLanguage}) {
    return apiClient.get(
      kAuthDevicesPath,
      decode: DeviceListReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 定向撤銷一臺裝置：POST `/auth/devices/revoke`，只准帶目標 device_id。
  ///
  /// 這裡傳的是「要撤哪一臺」的展示標識，不是憑據：撤銷的授權仍是本次請求帶來的會話憑據
  /// （由傳輸層自動注入），後端會先重檢當前會話有效、再在當前主體範圍內撤銷目標。
  /// 越權／不存在的 device_id 一律回 2009；被撤的是當前這臺時 [DeviceRevokeReport.current]
  /// 為真，呼叫端據此進入退出態。任何非 2xx 都以 [ApiError] 丟擲。
  Future<DeviceRevokeReport> revokeDevice({
    required String deviceId,
    String? acceptLanguage,
  }) {
    return apiClient.post<DeviceRevokeReport>(
      kAuthDeviceRevokePath,
      jsonBody: <String, Object?>{'device_id': deviceId},
      decode: DeviceRevokeReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀取 Root 初始化狀態：GET `/root/init-status`。
  ///
  /// 這是本應用對「這台伺服器有沒有 Root」唯一的得知管道，而且只進不出：
  /// 請求本體是空的，沒有任何欄位可以攜帶口令——初始化的通路只有伺服器本機的
  /// `evernight-server init-root`，把那個命令搬到 HTTP 上並不是本端點在做的事。
  ///
  /// 查不出來（後端讀組態檔失敗等）時一樣拋出 `ApiError`：呼叫端據此顯示
  /// 「狀態不明」，不存在「把查詢失敗當成尚未初始化」的可能。
  Future<InitStatusReport> initStatus({String? acceptLanguage}) {
    return apiClient.get(
      kRootInitStatusPath,
      decode: InitStatusReport.decode,
      acceptLanguage: acceptLanguage,
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
