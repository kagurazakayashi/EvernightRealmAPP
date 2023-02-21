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

/// 登入前界面用的對外入口能力端點路徑（匿名唯讀：回應只有兩個布林）。
///
/// 掛在 `/auth` 首段下而不是 `/root` 下：它是「還站在門外的人」要問的事，
/// 而 `/root` 那一整段屬 Root 面。路徑本身不透露任何策略細節。
const String kAuthCapabilitiesPath = '/auth/capabilities';

/// 匿名自註冊端點路徑：POST 一條路徑做一件事（建立一個可立即登入的普通帳戶）。
///
/// 與 [kAuthLoginPath] 分屬兩件事：登入是「拿已有憑據換一枚會話」，自註冊是
/// 「在策略放開時新建一筆普通帳戶」。同樣掛在 `/auth` 首段下——它是門外的人要走的通路。
/// 本方法成功不簽發會話、不下發 Cookie（見 [ServerApi.register]），因此呼叫端用
/// [ApiClient.post] 而非 captureCookie 那一條：註冊只把人送進目錄，登入另走 [ServerApi.login]。
const String kAuthRegisterPath = '/auth/register';

/// 訪客進入端點路徑：POST 一條路徑做一件事（換得一個臨時受限身分與一枚會話）。
///
/// 與 [kAuthRegisterPath] 分屬兩條准入通路：自註冊建的是「帶口令、之後用口令登入」的
/// 普通帳戶，而訪客按定義沒有任何憑據，因此這一步必須同時簽發會話——他手上除了這枚憑據
/// 沒有第二樣東西可以證明自己是誰。會話的壽命、到期、撤銷與裝置名額全部由後端按
/// 普通帳戶同一條規則給出，這裡沒有一枚特殊 Cookie。
/// 請求本體只有一格可選的暱稱（展示用，不是憑據、也不是登入名）：
/// 登入名一律由伺服器產生，協定層沒有一格能自報身分或佔住某個真人将来想用的名字。
const String kAuthGuestPath = '/auth/guest';

/// 申請人查本人待審批狀態的端點路徑：POST 一條路徑做一件事（驗證憑據、回報結局）。
///
/// 它刻意是 POST 而不是 GET：這條通路每次都要交登入名與口令，而秘密不進 URL
/// （GET 能被預取、能被快取、位址欄一貼就是一份憑據副本）。它與 [kAuthRegisterPath]
/// 同屬「還站在門外的人」要走的通路，因此也掛在 `/auth` 首段下。
/// 成功同樣不簽發會話、不下發 Cookie（見 [ServerApi.applicationStatus]）。
const String kAuthRegistrationStatusPath = '/auth/registration-status';

/// 帳戶建立策略端點路徑：GET（／HEAD）是現讀三份值與對外答案，PUT 是整份寫入。
///
/// 一條路徑、一份單例文件：這裡沒有目標標識、也沒有「只改某一欄」的子路徑——
/// 三個值一次寫入正是後端合同的形狀（少一個欄位就是 1004，不是默默按關）。
const String kRootAccountPolicyPath = '/root/account-policy';

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

/// 管理員端普通帳戶的集合端點路徑：GET（／HEAD）是分頁目錄，POST 是建立。
///
/// 與 `/root/admins` 的分工是一條邊界而不是一個目錄慣例：這組端點打理的是普通帳戶
/// （不帶任何伺服器級授予的 standard 與 guest），經伺服器級管理權判定，而建號那一條
/// 另受「管理員建立普通帳戶」開關約束；`/root/admins` 那組打理的是管理員，只有 Root 走得通、
/// 不受三個開關約束。兩組目錄彼此互斥：這裡列不到持有授予的人，那裡列不到沒有授予的人。
/// 「動的是哪一類資料」由端點與方法決定，請求本體裡沒有 role／type／status 的格子。
const String kAdminAccountsPath = '/admin/accounts';

/// 單筆普通帳戶端點的路徑前綴：GET（／HEAD）是詳情，PUT 是以白名單編輯非安全資料。
///
/// 目標在路徑上而不是本體欄位裡：編輯的本體只有「新值」與「提交所依據的現值」兩欄，
/// 沒有任何 account_id 之類的格子可以填。標識經 [Uri.encodeComponent] 轉義後拼接
/// （與 [rootAdminItemPath] 同一防呆理由：轉義不是修飾，是不讓呼叫端把路徑寫壞）。
String adminAccountItemPath(String accountId) =>
    '$kAdminAccountsPath/${Uri.encodeComponent(accountId)}';

/// 普通帳戶「登入狀態」子資源的路徑：PUT 唯一方法，動的是 status 一欄。
///
/// 與管理員那一條（[rootAdminStatusPath]）同形但分屬兩組端點：狀態與普通資料各有
/// 自己的白名單與確認語意，因此分成子資源而不是塞進詳情那條 PUT——那裡連狀態的
/// 格子都沒有。目標範圍也不同：這條碰不到管理員，也碰不到 Root。
String adminAccountStatusPath(String accountId) =>
    '${adminAccountItemPath(accountId)}/status';

/// 普通帳戶「登入憑據」子資源的路徑：PUT 唯一方法，動的是 password 一欄。
///
/// 與管理員那一條（[rootAdminPasswordPath]）同形但分屬兩組端點：那條經 Root 判定且
/// 只認管理員目錄，這條經伺服器級管理權判定、目標範圍把持有授予者與刪除終態排掉。
/// 憑據與狀態同屬安全欄位，但兩條白名單、兩套確認語意各走各的子資源——
/// 「重置不是解除停用」在 URL 形狀上就分開。本方法無依據值欄位（見
/// [ServerApi.resetStandardAccountPassword] 的說明）。
String adminAccountPasswordPath(String accountId) =>
    '${adminAccountItemPath(accountId)}/password';

/// 註冊申請名冊的集合端點路徑：GET（／HEAD）分頁列出走審批通路的申請。
///
/// 這本名冊與 [kAdminAccountsPath] 那本目錄是兩句話，各有各的範圍條件：
/// 這一頁列的是「還在等決定的申請」與「已被拒絕的申請」，而普通帳戶目錄按定義把
/// 那兩態排在門外。批准過的人不在這本書上——他進的是普通帳戶目錄那一側。
/// 讀它需要伺服器級管理權：站在門外的人只有一條「交憑據查自己結局」的路
/// （[kAuthRegistrationStatusPath]），沒有任何一格可以翻別人的申請。
const String kAdminRegistrationsPath = '/admin/registrations';

/// 註冊申請「審批決定」子資源的路徑：PUT 唯一方法，動的是那一個決定。
///
/// 與普通帳戶那兩條子資源（[adminAccountStatusPath]／[adminAccountPasswordPath]）同形：
/// 「做決定」在協定層只有一個入口，讀名冊本來就在父路徑上，不在這裡開第二份讀法。
/// 目標在路徑上、不在本體欄位裡：本體只有 decision 一格，沒有任何 account_id、role、
/// status、password 或 reason 的格子可填（多帶即 1004）。標識經 [Uri.encodeComponent]
/// 轉義後拼接，與其餘子資源同一防呆理由。
String adminRegistrationDecisionPath(String accountId) =>
    '$kAdminRegistrationsPath/${Uri.encodeComponent(accountId)}/decision';

/// Root 管理「伺服器級註冊邀請碼」的集合端點路徑：GET（／HEAD）是分頁名冊，POST 是簽發。
///
/// 這組端點全部經 NeedRoot 判定（與 [kRootAccountPolicyPath] 同側）：邀請碼是建立普通帳戶的
/// 准入憑證，「誰能拿這張路條」本身就是伺服器級的准入決定，不是管理員的日常打理範圍。
/// 本版本 invite 模式仍未落地、也沒有核銷端點，所以名冊裡一枚「有效」的碼此刻還換不出帳戶。
const String kRootInviteCodesPath = '/root/invite-codes';

/// 單枚邀請碼「撤銷」端點的路徑：DELETE 唯一方法，動的是把這枚碼叫停。
///
/// 與 [rootAdminItemPath] 的刪除同一形態：撤銷是單向終態、正當性錨在「它此刻還沒被撤銷」這條
/// 狀態機守衛上，本體不帶任何依據值。目標在路徑上、經 [Uri.encodeComponent] 轉義；這裡刻意
/// 沒有單筆讀法——名冊一行就是管理一枚碼需要的全部資料，而明文碼在簽發之後根本讀不回來。
String rootInviteCodeItemPath(String codeId) =>
    '$kRootInviteCodesPath/${Uri.encodeComponent(codeId)}';

/// 單筆管理員端點的路徑前綴：GET（／HEAD）是詳情，PUT 是以白名單編輯非安全資料。///
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

  /// 訪客以臨時受限身分進入：POST `/auth/guest`。
  ///
  /// 「此刻准不准放訪客」由後端在寫入那一刻現讀帳戶建立策略決定（判定發生在交易裡）：
  /// [entryCapabilities] 的 `guest_open` 只決定界面要不要顯示這扇門，從不代替提交時的
  /// 二次判定。開關關著回 2017（與自註冊共用同一句「這條帳戶建立通路此刻被策略關閉」）、
  /// 來源的嘗試預算用盡回 2006 並附 Retry-After、暱稱不合規回 1004 並點名 nickname 欄位。
  ///
  /// [nickname] 是本人自報的展示用暱稱，可留空——留空時由伺服器產生一個臨時編號。
  /// 它不是憑據、不承擔唯一性（两个人可以同名），呼叫端不得拿它做任何身份判定：
  /// 「凭暱稱找回這一趟」在這裡根本沒有對應的通路。
  ///
  /// 與 [register] 相反，這一條**會**簽發會話：訪客沒有任何口令可之後用它登入，
  /// 所以建號與簽發在同一筆交易裡完成。秘密的來路與去向與 [login] 逐字相同
  /// （Web 由 HttpOnly Cookie 代管、原生端由 [LoginExchange.sessionSecret] 交給會話層
  /// 的安全儲存），回應本體不含任何憑據材料。
  Future<LoginExchange> guestEnter({
    String? nickname,
    String? acceptLanguage,
  }) async {
    final String trimmed = (nickname ?? '').trim();
    final ({LoginReport value, String? setCookie}) result = await apiClient
        .postCapturingCookie(
          kAuthGuestPath,
          jsonBody: <String, Object?>{
            // 缺席＝不帶這一欄（由伺服器產生臨時編號）；不發空字串，免得界面把
            // 「我沒想好名字」說成「我要一個空名字」。
            if (trimmed.isNotEmpty) 'nickname': trimmed,
          },
          decode: LoginReport.decode,
          acceptLanguage: acceptLanguage,
        );
    return LoginExchange(
      report: result.value,
      sessionSecret: extractSessionCookie(result.setCookie),
    );
  }

  /// 匿名自註冊為普通帳戶：POST `/auth/register`。
  ///
  /// 「此刻准不准自註冊」由後端在寫入那一刻現讀策略並校驗生效模式決定（判定發生在
  /// 交易裡）：呼叫端不預讀、也預讀不到——[entryCapabilities] 那個入口答案只決定界面
  /// 「要不要顯示這扇門」，從不代替提交時的二次判定。開關關閉回 2017、模式對應的准入
  /// 流程尚未上線回 2016、登入名已被佔用回 2019（與需要已認證主體的 2012 分開）、
  /// 口令或登入名不合規回 1004 並點名是哪個欄位、來源被限流回 2006 並附 Retry-After、
  /// 邀請碼模式下一枚換不出帳戶的碼（缺／壞／過期／撤銷／用盡）回 2023（不區分原因）。
  ///
  /// 入參是登入名、顯示名、本人自選口令，外加一個「依模式才用到」的 [inviteCode]：
  /// 沒有任何角色／類型／狀態欄位——「建的是普通帳戶」由「打到哪個端點」決定。
  /// [inviteCode] 只在 `/auth/capabilities` 回報需要碼（invite 模式）時由表單遞進來；
  /// 其餘模式不發這個欄位（缺席＝後端不讀它、也不核銷任何一枚碼）。它是短暫停留的秘密：
  /// 只在這次呼叫的請求本體裡存在，呼叫端不得把它寫進 URL、瀏覽器歷史、狀態或緩存。
  /// 成功不帶回任何會話材料（本路徑不簽發 Cookie），因此走 [ApiClient.post] 而非
  /// captureCookie 那一條；口令只在這一次調用裡存在，呼叫端不得把它存進任何狀態或緩存。
  Future<SelfRegisterReport> register({
    required String loginName,
    required String displayName,
    required String password,
    String? inviteCode,
    String? acceptLanguage,
  }) {
    return apiClient.post<SelfRegisterReport>(
      kAuthRegisterPath,
      jsonBody: <String, Object?>{
        'login_name': loginName,
        'display_name': displayName,
        'password': password,
        // 缺席＝不帶這個欄位（開放／核准模式不看碼）；帶值才進本體，供 invite 模式核銷。
        if (inviteCode != null && inviteCode.isNotEmpty)
          'invite_code': inviteCode,
      },
      decode: SelfRegisterReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 申請人查本人申請狀態：POST `/auth/registration-status`。
  ///
  /// 這是一條「驗證憑據但不換發會話」的通路：待審批的人不能登入，也不該拿到一枚
  /// 能碰普通業務的憑據，所以他每次想知道「我的申請怎麼樣了」都要重新交一次登入名與口令。
  /// 成功不寫 Set-Cookie、回應裡沒有任何會話材料（因此走 [ApiClient.post] 而非
  /// captureCookie 那一條），也沒有需要壽命與撤銷邊界的臨時狀態證明——關掉頁面就什麼都不剩。
  ///
  /// 失敗形態與登入端點同形：查無此名、訪客帳戶、口令不符都是 2001（這條通路
  /// 對「誰的名字存在」不新增信號）；來源被限流 2006 並附 Retry-After；
  /// 憑據有效但這一筆根本不走審批通路 2020（處置是去登入，不是再查一次）。
  /// 回應只有申請人自己的三個事實：結局、提交時刻、決定時刻（後者只在已決定時出現）。
  Future<ApplicationStatusReport> applicationStatus({
    required String loginName,
    required String password,
    String? acceptLanguage,
  }) {
    return apiClient.post<ApplicationStatusReport>(
      kAuthRegistrationStatusPath,
      jsonBody: <String, Object?>{
        'login_name': loginName,
        'password': password,
      },
      decode: ApplicationStatusReport.decode,
      acceptLanguage: acceptLanguage,
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

  /// 建立一個普通帳戶：POST `/admin/accounts`。
  ///
  /// 只有持有伺服器級管理權的會話能成功：普通帳戶與匿名拿到 2011，
  /// 系統主體根本沒有對話路徑。「此刻准不准建」由後端在寫入那一刻現讀策略決定：
  /// 開關關閉回 2017（不是 2011，也不是 1004——換名字、換身分、重登都不是處置），
  /// 這裡也沒有、也不該有「預讀開關」的另一個端點：判定只發生在提交裡。
  /// 請求本體只有登入名、顯示名與一次性初始口令三個欄位，沒有任何
  /// role／account_type／status／activity_id 欄位可填，多帶會被後端打成 1004。
  /// 重複的登入名回 2012，後端不會因此多出一個帳戶，也不回顯任何口令。
  /// 回應本體只有可展示的身分事實——初始口令不進回應，交付管道在應用之外；
  /// 也沒有 roles 欄位（建的帳戶恆無授予），更沒有任何活動欄位：
  /// 「已建立」不等於「已加入活動」。結果不明時不得自動補發。
  Future<CreatedStandardAccountReport> createStandardAccount({
    required String loginName,
    required String displayName,
    required String password,
    String? acceptLanguage,
  }) {
    return apiClient.post<CreatedStandardAccountReport>(
      kAdminAccountsPath,
      jsonBody: <String, Object?>{
        'login_name': loginName,
        'display_name': displayName,
        'password': password,
      },
      decode: CreatedStandardAccountReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀取普通帳戶目錄的一頁：GET `/admin/accounts`。
  ///
  /// 這本目錄列的是「不帶任何伺服器級授予」的普通與訪客帳戶：管理員（含操作者自己）
  /// 與已進入刪除終態的帳戶都不在其中，讀到的每一筆都可以被這條通路編輯。
  /// 五個引數是本端點僅有的篩選（頁碼、每頁筆數、狀態、來源、名稱關鍵字），
  /// 「列誰的清單」仍由後端按解析出的受信主體決定：沒有任何引數可以指定別人的目錄，
  /// 也沒有任何引數可以把管理員拉進來。非法取值一律 1004 並點出是哪個參數，
  /// 超出總數的合法頁碼則回空清單與真實總數（那不是錯誤）。
  Future<StandardAccountDirectoryReport> standardAccountsDirectory({
    int page = 1,
    int pageSize = 20,
    String status = 'all',
    String type = 'all',
    String query = '',
    String? acceptLanguage,
  }) {
    final buffer = StringBuffer(kAdminAccountsPath)
      ..write('?page=')
      ..write(page)
      ..write('&page_size=')
      ..write(pageSize)
      ..write('&status=')
      ..write(Uri.encodeComponent(status))
      ..write('&type=')
      ..write(Uri.encodeComponent(type));
    // 空關鍵字不發參數：後端把「沒帶」與「帶了但全是空白」收斂成同一句話（不篩選），
    // 但界面不必因此多送一個無意義的 `q=`。
    if (query.trim().isNotEmpty) {
      buffer
        ..write('&q=')
        ..write(Uri.encodeComponent(query));
    }
    return apiClient.get(
      buffer.toString(),
      decode: StandardAccountDirectoryReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀取單筆普通帳戶詳情：GET `/admin/accounts/{account_id}`。
  ///
  /// 回應是經後端實體校驗的當前資料：編輯表單的預填值與「提交所依據的現值」都只能
  /// 取自這裡，不得拿目錄行或本地印象湊一份。目標不在這本目錄（不存在、是管理員、
  /// 或已是刪除終態）一律同一個 1001，端點因此不是標識格式探測器，也不是
  /// 「某個人是不是管理員」的 oracle。
  Future<StandardAccountDetailReport> standardAccountDetail({
    required String accountId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      adminAccountItemPath(accountId),
      decode: StandardAccountDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯普通帳戶的顯示名：PUT `/admin/accounts/{account_id}`。
  ///
  /// 白名單只有 display_name 一欄，另帶它所依據的 expected_display_name（compare-and-set）。
  /// 這裡動不到憑據、狀態、首次改密旗標與來源類型：本體連格子都沒有（多帶即 1004），
  /// 後端的 UPDATE 語句也不碰那些欄位。登入名不在此處修改（它是自建立起不變的身分錨點）。
  /// 現值已變時回 2013（409）且整個編輯不發生——處置是重讀詳情，不是再點一次保存。
  /// 成功回應是保存後的資料庫現值（含後端的空白整理），不是請求的迴音；
  /// 結果不明（逾時、連線中斷）時不得自動補發。
  Future<StandardAccountDetailReport> updateStandardAccountProfile({
    required String accountId,
    required String displayName,
    required String expectedDisplayName,
    String? acceptLanguage,
  }) {
    return apiClient.put<StandardAccountDetailReport>(
      adminAccountItemPath(accountId),
      jsonBody: <String, Object?>{
        'display_name': displayName,
        'expected_display_name': expectedDisplayName,
      },
      decode: StandardAccountDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 停用或恢復一名普通帳戶的伺服器級登入：PUT `/admin/accounts/{account_id}/status`。
  ///
  /// 動的是這個帳戶在整臺伺服器的登入能力，不是某一場活動裡的玩家限制：
  /// 停用同時拒絕他的新登入並撤銷他現有的全部會話（跨所有裝置、跨所有活動）。
  /// 白名單只有狀態一欄，外加它所依據的 expectedStatus（compare-and-set）；本體裡
  /// 沒有顯示名／憑據／旗標／類型／原因的格子，多帶會被後端打成 1004。
  /// 現狀已變時後端回 2014（409）且整個操作不發生——狀態、撤銷、審計一件都不留，
  /// 處置是重讀目標現狀並重新走一次確認，而不是把那顆按鈕再點一遍。
  /// 成功回應是變更後的資料庫現值與這次撤銷的會話數量，不是請求的迴音；
  /// 恢復只恢復新登入資格：舊會話不復活、首次改密義務不解除、刪除終態不可恢復。
  Future<StandardAccountStatusReport> updateStandardAccountStatus({
    required String accountId,
    required String status,
    required String expectedStatus,
    String? acceptLanguage,
  }) {
    return apiClient.put<StandardAccountStatusReport>(
      adminAccountStatusPath(accountId),
      jsonBody: <String, Object?>{
        'status': status,
        'expected_status': expectedStatus,
      },
      decode: StandardAccountStatusReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 管理員重置一名普通帳戶的登入憑據：PUT `/admin/accounts/{account_id}/password`。
  ///
  /// 白名單只有新口令一欄，且刻意沒有 expected_* 依據值：重置的發起人拿不出「現行口令」
  /// 那類誠實的錨點，重複提交是又做一次完整重置而不是被拒的陳舊嘗試——呼叫端因此
  /// 不得在結果不明時自動重發。多帶任何其他欄位（顯示名、狀態、旗標、類型、原因）
  /// 會被後端打成 1004。
  /// 成功效果：舊口令與名下全部會話即刻失效、該帳戶首次登入必須改密、
  /// 停用狀態與刪除終態保持原樣（重置不是解除停用，也不是復活）。口令只在請求本體
  /// 出現一次，回應不回顯、日誌與審計不留痕；線下的交付管道屬協議之外。
  /// 訪戶帳戶走這條通路會拿到 2018（他今日沒有可重置的一般密碼，設口令等於把身分
  /// 升級成普通帳戶，那要等後續那條明確的訪戶升級通路）；持有授予者、操作者自己
  /// 與刪除終態一律 1001，與詳情、編輯、停用同一句話。
  Future<StandardAccountPasswordResetReport> resetStandardAccountPassword({
    required String accountId,
    required String password,
    String? acceptLanguage,
  }) {
    return apiClient.put<StandardAccountPasswordResetReport>(
      adminAccountPasswordPath(accountId),
      jsonBody: <String, Object?>{'password': password},
      decode: StandardAccountPasswordResetReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀取註冊申請名冊的一頁：GET `/admin/registrations`。
  ///
  /// 這本名冊列的是「走審批通路的申請」：還在等決定的（pending）與已經被拒絕的（rejected）。
  /// 被批准的人不在這裡——他帶著決定時刻離開了審批鏈，此後的停用、重置與改名都在
  /// 普通帳戶目錄那一側（[standardAccountsDirectory]）。
  /// 三個引數是本端點僅有的篩選（頁碼、每頁筆數、狀態）加一段名稱關鍵字：
  /// 「列誰的申請」由後端按解析出的受信主體決定（只有伺服器級管理權讀得到），
  /// 非法取值一律 1004 並點出是哪個參數，超出總數的合法頁碼則回空清單與真實總數。
  /// 行裡只有審核需要的六格：沒有口令、沒有憑據雜湊、沒有角色，也沒有「審核人是誰」
  /// 與「為什麼拒」——後端今日沒有那兩格，介面無處可顯示。
  Future<RegistrationRosterReport> registrationRoster({
    int page = 1,
    int pageSize = 20,
    String status = 'all',
    String query = '',
    String? acceptLanguage,
  }) {
    final buffer = StringBuffer(kAdminRegistrationsPath)
      ..write('?page=')
      ..write(page)
      ..write('&page_size=')
      ..write(pageSize)
      ..write('&status=')
      ..write(Uri.encodeComponent(status));
    // 空關鍵字不發參數：後端把「沒帶」與「帶了但全是空白」收斂成同一句話（不篩選），
    // 但界面不必因此多送一個無意義的 `q=`。
    if (query.trim().isNotEmpty) {
      buffer
        ..write('&q=')
        ..write(Uri.encodeComponent(query));
    }
    return apiClient.get(
      buffer.toString(),
      decode: RegistrationRosterReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 對一筆待審批申請做出批准或拒絕：PUT `/admin/registrations/{account_id}/decision`。
  ///
  /// 白名單只有 `decision` 一欄（`approve`／`reject`），而且刻意沒有 expected_* 依據值：
  /// 一筆還沒被決定的申請，其現值就是「pending」這個詞本身，放進本體只會多出一格
  /// 「填錯就注定落敗」的欄位；真正的併發控制在後端那道 `status='pending'` 的條件上。
  /// 因此這裡沒有 2013／2014 那種「你依據的現值已過期」的結論——兩人同時按下時只有
  /// 先提交的那一次生效，後到的拿到 2021（409）「這份申請已經有過決定」，
  /// 整個操作不發生，先前那個決定也不會被蓋掉；處置是重讀名冊，不是把那顆按鈕再點一次。
  ///
  /// 批准的效果是「這個人從此刻起可以經既有登入通路用他自選的口令進去」，而且只此一件：
  /// 不帶任何伺服器級授予、不簽發也不會撤銷任何會話（回應裡沒有一枚憑據，也不下 Cookie），
  /// 也不解除任何獨立的停用或首次改密義務。拒絕則保留那一筆申請與它的登入名佔用，
  /// 且今日沒有任何通路能把已做過的決定改判。多帶任何其他欄位（角色、狀態、口令、理由）
  /// 都會被後端打成 1004；結果不明（逾時、連線中斷）時不得自動補發。
  Future<RegistrationDecisionReport> reviewRegistration({
    required String accountId,
    required String decision,
    String? acceptLanguage,
  }) {
    return apiClient.put<RegistrationDecisionReport>(
      adminRegistrationDecisionPath(accountId),
      jsonBody: <String, Object?>{'decision': decision},
      decode: RegistrationDecisionReport.decode,
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

  /// 讀取伺服器帳戶建立策略：GET `/root/account-policy`（只有 Root 讀得到）。
  ///
  /// 回的是資料庫裡此刻的三個值，以及由它們合成的對外入口答案；
  /// 查不出來一律拋 `ApiError`，沒有一條路把「讀失敗」降級成「全關」或一份預設策略。
  Future<AccountPolicyReport> accountPolicy({String? acceptLanguage}) {
    return apiClient.get(
      kRootAccountPolicyPath,
      decode: AccountPolicyReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 一次寫入帳戶建立策略：PUT `/root/account-policy`。
  ///
  /// 這是一份單例文件的整份 PUT：三個欄位一個都不能少（漏欄位會被後端打成 1004 並點名，
  /// 不會被當成「按關」——沉默是介面壞了，不是一個決定），也刻意沒有比較-and-set 依據值：
  /// 能改它的只有 Root 一個主體，重複提交不是「依據陳舊」而是「又確認一次」，
  /// 因此結果不明時呼叫端絕不自動補發。
  /// 模式字串要原樣交出去：`approval`／`invite` 是已批准但尚未上線的名字，
  /// 後端以 2016 拒之，界面據此另成一句，而不是自己攔下來假裝那個名字不存在。
  /// 成功回應是落庫後的現值加新的對外答案，不是請求的回音。
  Future<AccountPolicyReport> updateAccountPolicy({
    required bool adminCreateStandard,
    required String selfRegisterMode,
    required bool guestEnabled,
    String? acceptLanguage,
  }) {
    return apiClient.put(
      kRootAccountPolicyPath,
      jsonBody: <String, Object?>{
        'admin_create_standard': adminCreateStandard,
        'self_register_mode': selfRegisterMode,
        'guest_enabled': guestEnabled,
      },
      decode: AccountPolicyReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀取登入前界面的三個入口答案：GET `/auth/capabilities`（匿名可讀）。
  ///
  /// 這是尚未登入的界面唯一被允許詢問的准入資訊：回應只有三個布林加關聯 ID，
  /// 不含模式名字、修改時刻、建號開關、帳戶清單或任何閾值。第三個布林 [AccountEntryCapabilities.inviteCodeRequired]
  /// 只講「這一趟自行註冊要不要帶一枚碼」，讓共享註冊表單決定要不要顯示邀請碼欄位。
  /// 呼叫端必須把查不出來當成「不知道」處理（不顯示任何入口），而不是猜一個答案——猜「開」會露出一個
  /// 按下去必然失敗的入口，猜「關」也會讓一次故障看起來像 Root 做了決定。
  Future<EntryCapabilitiesReport> entryCapabilities({String? acceptLanguage}) {
    return apiClient.get(
      kAuthCapabilitiesPath,
      decode: EntryCapabilitiesReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀取邀請碼名冊的一頁：GET `/root/invite-codes`（只有 Root 讀得到）。
  ///
  /// 分頁與狀態／標籤篩選是本端點僅有的引數；「列哪幾行、每行算哪種狀態」都由後端按受信主體
  /// 與注入時鐘決定，客戶端不自行排序、也不自己派生狀態（那會造出第二套真相，與名冊那一格打架）。
  /// 空關鍵字不發 `q=`。回應裡永不含明文碼；讀不到時一律丟 [ApiError]，不降級成「一本空名冊」。
  Future<InviteCodeRosterReport> inviteCodeRoster({
    int page = 1,
    int pageSize = 20,
    String status = 'all',
    String query = '',
    String? acceptLanguage,
  }) {
    final buffer = StringBuffer(kRootInviteCodesPath)
      ..write('?page=')
      ..write(page)
      ..write('&page_size=')
      ..write(pageSize)
      ..write('&status=')
      ..write(Uri.encodeComponent(status));
    if (query.trim().isNotEmpty) {
      buffer
        ..write('&q=')
        ..write(Uri.encodeComponent(query));
    }
    return apiClient.get(
      buffer.toString(),
      decode: InviteCodeRosterReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 簽發一枚邀請碼：POST `/root/invite-codes`（只有 Root 能簽）。
  ///
  /// 白名單只有 label／max_uses／expires_at：本體裡沒有角色、帳戶類型、活動標識或口令的格子
  /// （多帶即 1004）——一枚註冊邀請碼按定義只能換來一個普通帳戶。max_uses 缺席即後端預設單次、
  /// expires_at 缺席即永不過期；兩樣要交時交正規值，否則後端以 1004 點名對應欄位。
  ///
  /// 成功回應的 `code` 是這枚碼的明文，而且是全鏈路唯一一次露出：庫裡只存它的驗證材料，
  /// 之後任何讀法（含名冊、含撤銷回顯）都拿不回來。丟了就重新簽發一枚。結果不明時絕不
  /// 自動補發（重發簽發是又簽一枚新碼）。
  Future<IssuedInviteCodeReport> issueInviteCode({
    required String label,
    int? maxUses,
    String? expiresAt,
    String? acceptLanguage,
  }) {
    final body = <String, Object?>{'label': label};
    // 缺席不發該欄：讓後端的預設值生效（額度單次、有效期永不過期），而不是界面先填一個
    // 再假裝那是操作者的決定。
    if (maxUses != null) {
      body['max_uses'] = maxUses;
    }
    if (expiresAt != null && expiresAt.isNotEmpty) {
      body['expires_at'] = expiresAt;
    }
    return apiClient.post<IssuedInviteCodeReport>(
      kRootInviteCodesPath,
      jsonBody: body,
      decode: IssuedInviteCodeReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 撤銷一枚邀請碼：DELETE `/root/invite-codes/{code_id}`（只有 Root 能撤）。
  ///
  /// 本體是空的、刻意沒有依據值欄位：撤銷的正當性錨在「它此刻還沒被撤銷」這條狀態機守衛上，
  /// Root 對一枚未撤銷碼的「現行撤銷時刻」拿不出任何可交的東西。因此第二次撤銷回的是 2022
  /// 「這枚碼已經被撤銷」，整個操作不發生，先前那次撤銷也不會被改；處置是重讀名冊，不是把
  /// 那顆按鈕再點一次，結果不明時也不自動補發。
  ///
  /// 撤銷擋住的是「這枚碼此後還能不能被核銷」，不是一個已合法建出來的帳戶——它不撤會話、
  /// 不改帳戶、也不動已核銷的次數（那是留住的歷史）。成功回應是撤銷後的資料庫現值（派生成
  /// revoked、帶撤銷時刻），仍不含明文碼。
  Future<InviteCodeMutationReport> revokeInviteCode({
    required String codeId,
    String? acceptLanguage,
  }) {
    return apiClient.delete(
      rootInviteCodeItemPath(codeId),
      decode: InviteCodeMutationReport.decode,
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
