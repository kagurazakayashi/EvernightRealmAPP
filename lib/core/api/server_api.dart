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

/// 本人改密端點路徑（有副作用：更換自己的口令並讓名下全部會話退出；
/// 請求本體只有現行口令與新口令，沒有任何欄位可以指定「改誰」）。
const String kAuthPasswordChangePath = '/auth/password/change';

/// Root 管理員集合端點路徑：GET（／HEAD）是分頁目錄，POST 是開設。
///
/// 方法由後端分流，集合路徑只有一條：這裡沒有任何引數可以指定「建成哪一種主體」——
/// 「建的是管理員」由「打到哪個端點」決定，請求本體裡沒有 role 這個格子。
const String kRootAdminsPath = '/root/admins';

/// 單筆管理員端點的路徑前綴：GET（／HEAD）是詳情，PUT 是以白名單編輯非安全資料。
///
/// 目標在路徑上而不是本體欄位裡：編輯請求的本體只有「新值」與「提交所依據的現值」，
/// 沒有任何 account_id 之類的格子可以填。標識經 [Uri.encodeComponent] 轉義後拼接
/// （UUIDv7 本來是 URL 安全字串，轉義是對「呼叫端傳了別的東西」的防呆，不是修飾）。
String rootAdminItemPath(String accountId) =>
    '$kRootAdminsPath/${Uri.encodeComponent(accountId)}';

/// 管理員「登入狀態」子資源的路徑：PUT 唯一方法，動的是 status 一欄。
///
/// 狀態與普通資料各有自己的白名單與確認語意，因此分成子資源而不是塞進
/// 詳情那條 PUT——那裡連狀態的格子都沒有。
String rootAdminStatusPath(String accountId) =>
    '${rootAdminItemPath(accountId)}/status';

/// 管理員「登入憑據」子資源的路徑：PUT 唯一方法，動的是 password 一欄。
///
/// 憑據與狀態同屬安全欄位，但兩條白名單、兩套確認語意各走各的子資源：
/// 「重置不是解除停用」在 URL 形狀上就分開。本方法無依据值欄位（見
/// [ServerApi.resetAdminPassword] 的說明）。
String rootAdminPasswordPath(String accountId) =>
    '${rootAdminItemPath(accountId)}/password';

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

  /// 本人改密：POST `/auth/password/change`，只準帶現行口令與新口令。
  ///
  /// 憑據的攜帶與 [logout] 同一條路（Web 由 HttpOnly Cookie 自動附帶、原生由傳輸層
  /// 按請求身份注入 Bearer），因此本方法沒有 `bearerToken` 引數；再認證靠的是
  /// `currentPassword` 本身——「會話還活著」從來不是改密的授權，客戶端也沒辦法
  /// 自報「已經驗證過」。現行口令不對回 2001（不撤任何東西、會話仍有效）；
  /// 新口令等於現行或不合形狀回 1004；成功回 200＋被撤銷的會話數。
  /// 兩個口令都只在這一次調用裡存在：呼叫端不得把它們存進任何狀態或緩存。
  Future<PasswordChangeReport> changePassword({
    required String currentPassword,
    required String newPassword,
    String? acceptLanguage,
  }) {
    return apiClient.post<PasswordChangeReport>(
      kAuthPasswordChangePath,
      jsonBody: <String, Object?>{
        'current_password': currentPassword,
        'new_password': newPassword,
      },
      decode: PasswordChangeReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 開設一個伺服器級管理員帳戶：POST `/root/admins`。
  ///
  /// 只有 Root 的會話能成功：普通帳戶與普通管理員都拿到 2011（不是 2002／2003，
  /// 也不是任何「再登入一次試試」能繞過的東西）。請求本體只有登入名、顯示名與
  /// 一次性初始口令三個欄位，沒有任何角色／類型欄位可填，多帶會被後端打成 1004。
  /// 重複的登入名回 2012，且後端不會因此多出一個帳戶，也不會回顯任何口令。
  /// 回應本體只有可展示的身分事實——初始口令不進回應，因此呼叫端要把口令
  /// 交給對方的那條路在應用之外，這裡也沒有保存它的格子。
  Future<CreatedAdminReport> createAdmin({
    required String loginName,
    required String displayName,
    required String password,
    String? acceptLanguage,
  }) {
    return apiClient.post<CreatedAdminReport>(
      kRootAdminsPath,
      jsonBody: <String, Object?>{
        'login_name': loginName,
        'display_name': displayName,
        'password': password,
      },
      decode: CreatedAdminReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀取管理員目錄的一頁：GET `/root/admins`（唯讀，只列後端認定持有角色的帳戶）。
  ///
  /// 憑據攜帶與 [currentSession] 同一條路；分頁與狀態篩選是本端點僅有的引數，
  /// 「列誰的清單」仍由後端按解析出的受信主體決定，沒有任何引數可以指定別人的目錄。
  /// 失敗一律以 [ApiError] 丟擲。
  Future<AdminDirectoryReport> adminsDirectory({
    int page = 1,
    int pageSize = 20,
    String status = 'all',
    String? acceptLanguage,
  }) {
    return apiClient.get(
      '$kRootAdminsPath?page=$page&page_size=$pageSize&status=${Uri.encodeComponent(status)}',
      decode: AdminDirectoryReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀取單筆管理員詳情：GET `/root/admins/{account_id}`。
  ///
  /// 回應是經後端實體校驗的當前資料：編輯表單的預填值與「提交所依據的現值」
  /// 都只能取自這裡，不得拿目錄行或本地印象湊一份。
  Future<AdminDetailReport> adminDetail({
    required String accountId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      rootAdminItemPath(accountId),
      decode: AdminDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯管理員的顯示名：PUT `/root/admins/{account_id}`。
  ///
  /// 白名單只有 display_name 一欄，外加它所依據的 expectedDisplayName（比較-and-set）：
  /// 本體裡沒有狀態／旗標／類型／口令／登入名的格子，多帶會被後端打成 1004。
  /// 現值已變時後端回 2013 且整個編輯不發生——呼叫端要重讀詳情再決定，
  /// 而不是重發同一個意圖。成功回應是保存後的資料庫現值，不是請求的迴音。
  Future<AdminDetailReport> updateAdminProfile({
    required String accountId,
    required String displayName,
    required String expectedDisplayName,
    String? acceptLanguage,
  }) {
    return apiClient.put(
      rootAdminItemPath(accountId),
      jsonBody: <String, Object?>{
        'display_name': displayName,
        'expected_display_name': expectedDisplayName,
      },
      decode: AdminDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 停用或恢復一名管理員的登入：PUT `/root/admins/{account_id}/status`。
  ///
  /// 白名單只有狀態一欄，外加它所依據的 expectedStatus（比較-and-set）：
  /// 本體裡沒有顯示名／旗標／類型／口令／原因的格子，多帶會被後端打成 1004。
  /// 現狀已變時後端回 2014 且整個操作不發生——狀態、撤銷、審計一件都不留，
  /// 呼叫端要重讀目標現狀並重新確認，而不是重發同一個意圖。
  /// 成功回應是變更後的資料庫現值與這次撤銷的會話數量，不是請求的迴音。
  Future<AdminStatusReport> updateAdminStatus({
    required String accountId,
    required String status,
    required String expectedStatus,
    String? acceptLanguage,
  }) {
    return apiClient.put(
      rootAdminStatusPath(accountId),
      jsonBody: <String, Object?>{
        'status': status,
        'expected_status': expectedStatus,
      },
      decode: AdminStatusReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// Root 重置一名管理員的登入憑據：PUT `/root/admins/{account_id}/password`。
  ///
  /// 白名單只有新口令一欄，且刻意沒有 expected_* 依據值：重置的發起人（Root）
  /// 拿不出「現行口令」那類誠實的錨點，重複提交是又做一次完整重置而不是被拒的
  /// 陳舊嘗試——呼叫端因此不得在結果不明時自動重發。多帶任何其他欄位會被後端打成 1004。
  /// 成功效果：舊口令與名下全部會話即刻失效、該帳戶首次登入必須改密、
  /// 停用狀態保持原樣（重置不是解除停用）。口令只在請求本體出現一次，
  /// 回應不回顯、日誌與審計不留痕；線下的交付管道屬協議之外。
  Future<AdminPasswordResetReport> resetAdminPassword({
    required String accountId,
    required String password,
    String? acceptLanguage,
  }) {
    return apiClient.put(
      rootAdminPasswordPath(accountId),
      jsonBody: <String, Object?>{'password': password},
      decode: AdminPasswordResetReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// Root 軟刪除一名管理員帳戶：DELETE `/root/admins/{account_id}`。
  ///
  /// 本體是空的，而且刻意沒有依據值欄位：刪除的正當性錨在「他還沒被刪」這條狀態機
  /// 守衛上，Root 對「現行刪除時刻」拿不出任何可交的東西（未被刪時那一欄本來就是 NULL）。
  /// 因此這裡也沒有 2013/2014 那樣的「陳舊依據被拒」——第二次刪除回的是 2015
  /// 「目標已被刪除」，結果不明時界面不得自動重發（那不會是重試，而是對一個已刪除
  /// 的人再下一次寫入令）。
  ///
  /// 成功效果（同一次交易落地）：新登入被拒、名下全部會話即刻撤銷（[revokedSessions]
  /// 是權威數量）、顯示名換成匿名化佔位值。它【不】做的事同樣要講清楚：帳戶行與
  /// 登入名保留（因此登入名不可被復用，同名開設回 2012）、授予與既有審計一行不動
  /// （歷史操作者仍指回每一個人）、也不存在任何把刪除改回來的通路——
  /// 「恢復登入」那條子資源對已刪除目標一律回 2015。
  Future<AdminDeleteReport> deleteAdmin({
    required String accountId,
    String? acceptLanguage,
  }) {
    return apiClient.delete(
      rootAdminItemPath(accountId),
      decode: AdminDeleteReport.decode,
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
