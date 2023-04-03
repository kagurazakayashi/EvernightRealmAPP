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

/// 單筆普通帳戶端點的路徑前綴：GET 是詳情，PUT 是以白名單編輯非安全資料，
/// DELETE 是軟刪除（無本體、無依據值，帶任何欄位一律 1004）。
///
/// 三個方法掛在同一條路徑上是刻意的：刪除動的就是「這一個人」，不是一種新的資料——
/// 為它另開一個 `/delete` 子資源會讓協定層出現兩條都能宣稱刪除、卻只有一條真的落庫的路。
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
/// 只認管理員目錄，這條經伺服器級管理權判定、目標範圍把持有授予者排掉；刪除與退休
/// 兩種終態不在「查不到」那一側，各自回自己那句拒絕（2027／2028）。
/// 憑據與狀態同屬安全欄位，但兩條白名單、兩套確認語意各走各的子資源——
/// 「重置不是解除停用」在 URL 形狀上就分開。本方法無依據值欄位（見
/// [ServerApi.resetStandardAccountPassword] 的說明）。
String adminAccountPasswordPath(String accountId) =>
    '${adminAccountItemPath(accountId)}/password';

/// 訪戶「原地升級」子資源的路徑：PUT 唯一方法，動的是這個帳戶是哪一類主體。
///
/// 與 `/password` 分成兩條子資源正是為了讓「重置口令」永遠不可能順帶完成一次身分升級
/// （那條 PUT 的本體連登入名的格子都沒有）；這條動的是比憑據與狀態更高一層的事實，
/// 目標範圍也更窄——只認「此刻是訪戶且可登入」的人，其餘形態由後端以 2024 回答。
String adminAccountUpgradePath(String accountId) =>
    '${adminAccountItemPath(accountId)}/upgrade';

/// 訪戶「綁定預檢」子資源的路徑：POST 唯一方法，是一場純只讀的衝突預覽。
///
/// 它與 [adminAccountUpgradePath] 那條的分别是本步最要講清的一句話：升級動的是訪戶
/// 自己那一行（原地轉正，標識存續）；綁定是把訪戶併入**另一個既有正式帳戶**
/// （存續的是目標那一行）。本倉庫今日只有這條**預覽**通路——綁定的執行動詞屬後續
/// 步驟，而且按用戶批准的決定只能由目標帳戶持有人以自己的會話發起，管理端永遠
/// 拿不到「代人完成綁定」的那顆按鈕。「此刻不可綁定」不是錯誤而是 200 預覽本體裡
/// 的穩定原因記號，所以這條路徑不掛任何新機器碼。
String adminAccountBindPreflightPath(String accountId) =>
    '${adminAccountItemPath(accountId)}/bind-preflight';

/// 訪戶「綁定憑證簽發」子資源的路徑：POST 唯一方法，是本目錄裡唯一會寫的綁定通路。
///
/// 它落的不是綁定而是**一份授權**：一經伺服器級管理員簽發、限定這一對（來源, 目標）、
/// 15 分鐘內有效、只准核銷一次的操作憑證。這一動把「最後由誰按下執行」交給憑證上那個
/// 目標帳戶的持有人——管理端到此為止，永遠沒有代人綁定的按鈕（用戶批准的同意形態）。
/// 與 [adminAccountBindPreflightPath] 的分别是本步最要緊的一句話：那一條零寫入、
/// 「不可綁定」以 200 帶原因記號回來；這一條會寫，所以不可行的這一對以 2026 被拒，
/// 而不是回一份 200 加空影響清單（签发成功這件事本身就承諾了可行）。
String adminAccountBindTicketPath(String accountId) =>
    '${adminAccountItemPath(accountId)}/bind-ticket';

/// 本人綁定端點的集合路徑：POST 執行綁定、GET（／HEAD）讀自己接住過哪些人。
///
/// 這三條通路刻意落在 `/auth` 而不是 `/admin` 之下：那一側全部經 NeedServerAdmin，
/// 而這一側只承認「憑證上釘著的那個普通正式帳戶本人」。讀的那一頁是「結果待確認」的
/// 落點——提交成功但回應遺失時，界面对它只能說「待確認」，而這裡讀到的那一行留痕
/// 才是完成與否的證據（重試同一枚憑證只會拿到 2025，它已被用掉）。
const String kAuthGuestBindingsPath = '/auth/guest-bindings';

/// 本人的「核銷前預覽」子資源路徑：POST 唯一方法，只讀、不核銷任何東西。
///
/// 用 POST 是因為輸入是一段凭據：放進路徑或查詢串就會進訪問日誌、瀏覽器歷史與快取，
/// 而一枚还没被用掉的小票不該出現在那些地方。它與 [kAuthGuestBindingsPath] 那一條 POST
/// 的分别是界面上「先展示已驗證的影響、再單獨確認執行」那兩顆按鈕的分别是同一件事。
const String kAuthGuestBindingsPreviewPath = '/auth/guest-bindings/preview';

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

/// 活動管理端點的路徑前綴：GET／HEAD 是分頁目錄，POST 是建立一個活動。
///
/// 目錄與建立掛在同一條父路徑的兩個方法上（與 [kAdminAccountsPath]／
/// [kRootInviteCodesPath] 同一形態）：建立會產出一個新的穩定標識，因此它是 POST 一條新建，
/// 而目錄是讀。
const String kAdminActivitiesPath = '/admin/activities';

/// 單筆活動端點的路徑前綴：GET 是詳情，PUT 是以白名單編輯名稱與描述。
///
/// 狀態不在這條路徑上改（見 [adminActivityStatusPath]）：把「能不能繼續發生」與
/// 「這件事叫什麼」混進同一次提交，等於讓一次改名可以順手把歸檔的活動改回開放。
String adminActivityItemPath(String activityId) =>
    '$kAdminActivitiesPath/${Uri.encodeComponent(activityId)}';

/// 活動狀態轉換的子資源路徑：PUT 一條路徑做一件事（開放／停止／重新開放／歸檔）。
String adminActivityStatusPath(String activityId) =>
    '${adminActivityItemPath(activityId)}/status';

/// 活動管理人名冊的讀取路徑：GET／HEAD 只列這個活動此刻的管理人。
///
/// 讀掛在 /admin（管理員加上該活動的指派），寫掛在 /root（見 [rootActivityManagersPath]）：
/// 同一張表、兩套准入邊界，因此是兩條路徑而不是一條路徑上的兩個方法。
String adminActivityManagersPath(String activityId) =>
    '${adminActivityItemPath(activityId)}/managers';

/// Root 那側的管理人指派路徑：POST 指派、GET／HEAD 不在此掛（讀法在 /admin 那條上）。
const String kRootActivityManagersPathPrefix = '/root/activities';

/// Root 指派活動管理人的集合路徑（POST 一條指派）。
String rootActivityManagersPath(String activityId) =>
    '$kRootActivityManagersPathPrefix/${Uri.encodeComponent(activityId)}/managers';

/// Root 撤銷單筆指派的路徑：DELETE 什麼都不帶（無本體、無依據值）。
///
/// 被撤銷的是「這一对（活動, 帳戶）」，所以目標在位址裡而不是在本體裡；
/// 撤銷不存在的指派回 1001 而不是謊報成功。
String rootActivityManagerItemPath(String activityId, String accountId) =>
    '${rootActivityManagersPath(activityId)}/${Uri.encodeComponent(accountId)}';

/// 陣營集合路徑（活動詳情路徑的子資源）：GET／HEAD 讀列表、POST 建立。
///
/// 准入與活動資料編輯同一道閘（管理員加上該活動的指派），因此掛在 /admin 而不另發
/// /root 一組：打理一個活動裡的陣營是「管這個活動的資料」，不是權限授予。
String adminActivityFactionsPath(String activityId) =>
    '${adminActivityItemPath(activityId)}/factions';

/// 單筆陣營路徑：本步只有 PUT 一條編輯通路。
///
/// 沒有單筆 GET（列表就是這個活動的全量，另發一條會造出第二個答案來源），
/// 也沒有 DELETE（用戶批准：只有可用／停用，沒有刪除通路）。
String adminActivityFactionItemPath(String activityId, String factionId) =>
    '${adminActivityFactionsPath(activityId)}/${Uri.encodeComponent(factionId)}';

/// 標籤定義集合路徑（活動詳情路徑的子資源）：GET／HEAD 讀定義列表、POST 建立。
///
/// 准入與活動資料編輯、陣營管理同一道閘（管理員加上該活動的指派），因此掛在 /admin。
/// 這一族讀到的是完整定義，含未公開的那幾枚——管理面本來就是內部資訊的持有者。
String adminActivityTagsPath(String activityId) =>
    '${adminActivityItemPath(activityId)}/tags';

/// 單筆標籤定義路徑：本步只有 PUT 一條編輯通路。
///
/// 沒有單筆 GET（列表就是這個活動的全量，另發一條會造出第二個答案來源），
/// 也沒有 DELETE（用戶批准：只有可用／停用，沒有刪除通路，也不級聯清空歷史）。
String adminActivityTagItemPath(String activityId, String tagId) =>
    '${adminActivityTagsPath(activityId)}/${Uri.encodeComponent(tagId)}';

/// 玩家側的公開標籤定義清單路徑：GET／HEAD。
///
/// 它與 `/admin/.../tags` 是兩份不同的讀法：那道給管理人看全量並帶內部欄位，
/// 這一條只列被設成公開的定義，而且回應裡根本沒有可用性、公開旗標、時刻與計數那些格子。
/// 準入只問「這次請求的憑據換出的是哪一個帳戶、他在這場活動有沒有成員行」。
String playerActivityTagsPath(String activityId) =>
    '${playerActivitiesPath()}/${Uri.encodeComponent(activityId)}/tags';

/// 玩家側的單枚公開定義直查路徑：GET／HEAD。
///
/// 查一枚未公開的定義與查一枚從未存在的標識是同一句 1001：這條路徑不當內部定義的
/// 存在性探測器，也沒有任何一格能宣稱「我是管理人所以給我看內部標籤」。
String playerActivityTagItemPath(String activityId, String tagId) =>
    '${playerActivityTagsPath(activityId)}/${Uri.encodeComponent(tagId)}';

/// 成員集合路徑（活動詳情路徑的子資源）：GET／HEAD 讀名冊、POST 建立成員身份。
///
/// 准入與活動資料編輯、陣營管理同一道閘（管理員加上該活動的指派），因此掛在 /admin
/// 而不另發 /root 一組：打理一個活動裡的成員名冊是「管這個活動的事」，不是權限授予。
String adminActivityMembersPath(String activityId) =>
    '${adminActivityItemPath(activityId)}/members';

/// 單筆成員路徑：本版本只有 PUT 一條編輯暱稱的通路。
///
/// 沒有單筆 GET（名冊就是這個活動的全量，另發一條會造出第二個答案來源），
/// 也沒有 DELETE（用戶批准：沒有把成員移出活動的通路），也沒有能改陣營歸屬的方法——
/// 分配屬下一步，今日這一格在任何本體裡都沒有格子。
String adminActivityMemberItemPath(String activityId, String memberId) =>
    '${adminActivityMembersPath(activityId)}/${Uri.encodeComponent(memberId)}';

/// 活動的玩家業務狀態目錄路徑：GET／HEAD 讀狀態定義、POST 建立自訂狀態。
///
/// 准入與活動資料編輯、陣營與標籤管理同一道閘（管理員加上該活動的指派），因此掛在
/// /admin：打理一場活動能用哪些狀態、各自叫什麼名，屬「管這個活動的資料」。
/// 這一族讀到的是七個內建鍵的展示現值與全量自訂定義（含已停用的那些），停止與歸檔
/// 的活動照樣可讀——拒的是寫，不是把當時的定義藏起來。
String adminActivityPlayerStatusesPath(String activityId) =>
    '${adminActivityItemPath(activityId)}/player-statuses';

/// 單筆自訂狀態路徑：本族只有 PUT 一條編輯通路（改名與可用性並在同一條白名單裡）。
///
/// 沒有單筆 GET（目錄就是這個活動的全量，另發一條會造出第二個答案來源），
/// 也沒有 DELETE（用戶批准於本步：自訂狀態只停用、不刪除，不級聯清空任何人的歸屬）。
String adminActivityPlayerStatusItemPath(String activityId, String statusId) =>
    '${adminActivityPlayerStatusesPath(activityId)}/${Uri.encodeComponent(statusId)}';

/// 內建狀態顯示名稱路徑：PUT 編輯那一場活動對那個內建鍵的覆蓋。
///
/// 它與自訂定義分開一條路徑：改內建狀態的顯示名稱不碰任何人的內部值，
/// 也不能順手新建或停用一枚狀態（七個內建鍵不可增刪）。路徑上的 `{status_key}`
/// 只能是那七個穩定值之一，集合外的值回 1004 點名。
String adminActivityPlayerStatusLabelPath(
  String activityId,
  String statusKey,
) =>
    '${adminActivityItemPath(activityId)}/player-status-labels'
    '/${Uri.encodeComponent(statusKey)}';

/// 成員業務狀態路徑：PUT 變更那一位玩家此刻的業務狀態。
///
/// 它掛在名冊那一族的單筆路徑之下（准入同活動資料編輯），是一條只碰狀態兩欄的白名單
/// 子資源：改名、換組、目錄覆蓋與身分三欄都不在這條通路上（口徑同「改名不會順手換組」）。
/// 這一族沒有 GET（狀態現值由名冊與玩家投影帶回）、也沒有 DELETE。
String adminActivityMemberBusinessStatusPath(
  String activityId,
  String memberId,
) => '${adminActivityMemberItemPath(activityId, memberId)}/business-status';

/// 成員分項限制路徑：PUT 逐欄編輯那一位玩家在这一场的六枚限制旗標。
///
/// 它掛在名冊那一族的單筆路徑之下（准入同活動資料編輯），是一條只碰被選中
/// `restrict_*` 欄的白名單子資源：每一欄都要帶上它所依據的現值（compare-and-set，
/// 沿用 2013），沒選中的欄位不進本體、也不進 UPDATE——「取消聊天不順手取消私聊」
/// 成立在這個形狀上。這一族沒有 DELETE（取消就是寫 0，沒有「清回未設定」那種形態）。
String adminActivityMemberRestrictionsPath(
  String activityId,
  String memberId,
) => '${adminActivityMemberItemPath(activityId, memberId)}/restrictions';

/// 活動的「玩家自選陣營」那一欄配置路徑：PUT 編輯。
///
/// 它是活動管理面的一條白名單子資源（準入同活動資料編輯：管理員加上該活動的指派），
/// 與 `.../status` 分開的理由也同一套——一欄配置換的是「往後允不允許玩家自己選」，
/// 不該讓任何一次改名順手把它一起存進去。本族群沒有 GET（那一格的現值由活動詳情帶回）、
/// 也沒有 DELETE（關閉就是 disabled 這個取值，沒有「清回未設定」這種形態）。
String adminActivityFactionSelectPath(String activityId) =>
    '${adminActivityItemPath(activityId)}/faction-select';

/// 本人活動清單路徑：GET／HEAD 讀「我參加了哪些活動」。
///
/// 這一族掛在 /player 而不掛在 /admin：準入只問「這次請求的憑據此刻換出的是哪一個帳戶」，
/// 路徑裡沒有一格能填「哪個玩家」，本體裡也沒有。前綴無版本（只增不刪的相容演進）。
String playerActivitiesPath() => '/player/activities';

/// 本人在某一場活動裡的陣營現況路徑：GET／HEAD 讀現況、PUT 自選。
///
/// 沒有 DELETE——本步批準的自選只能設定歸屬，不能清空（把歸屬改回「尚未分組」
/// 屬管理側分配通路，今日不存在那條路）。
String playerActivityFactionPath(String activityId) =>
    '${playerActivitiesPath()}/${Uri.encodeComponent(activityId)}/faction';

/// 玩家目錄路徑：GET／HEAD 讀「這一態讓我看見的那些人」。
///
/// 它與 `/admin/.../members`（名冊）是兩份不同的讀法：那道給管理人看全量並帶帳戶側
/// 投影，這一條只給白名單投影，而且「能看見誰」由後端現讀模式、覆蓋與授予決定——
/// 查詢串與本體裡都沒有格子能宣稱「用管理視角給我全部人」。
String playerActivityMembersPath(String activityId) =>
    '${playerActivitiesPath()}/${Uri.encodeComponent(activityId)}/members';

/// 目錄裡的單筆詳情路徑：GET／HEAD 按成員標識直查。
///
/// 這條不是「列表那一行的展開」：介面進入詳情時重新問一次可見性判定，
/// 於是「列得出來卻點不進去」與「列表收了他而詳情還給得出來」在結構上都不成立。
String playerActivityMemberItemPath(String activityId, String memberId) =>
    '${playerActivityMembersPath(activityId)}/${Uri.encodeComponent(memberId)}';

/// 本人在某一場活動裡的資料投影路徑：GET／HEAD。
///
/// 它不經目錄可見性判定（本人看得見自己不是特權），所以目錄收成 `hidden` 時
/// 這一條照舊成功——介面因此能把「別人看不見我」與「我看見的自己」分兩句講。
String playerActivityProfilePath(String activityId) =>
    '${playerActivitiesPath()}/${Uri.encodeComponent(activityId)}/profile';

/// 本人分項限制查閱路徑：GET／HEAD。
///
/// 這是用戶批准的「本人獲准查看有效結果」那一側，也是被 `restrict_login` 擋下之後
/// 唯一還讀得動的活動通路——被限制的人必須能問出「我被限制的是哪些項」。
/// 回應只有六個布林與標識：沒有原因、沒有操作者、也沒有時間（那些屬審計）。
String playerActivityRestrictionsPath(String activityId) =>
    '${playerActivitiesPath()}/${Uri.encodeComponent(activityId)}/restrictions';

/// 活動的「玩家目錄可見性」那一欄配置路徑：PUT 編輯。
///
/// 與 faction-select 同一形態——它是活動管理面的一條白名單子資源（準入同活動資料編輯：
/// 管理員加上該活動的指派），本族群沒有 GET（現值由活動詳情帶回）也沒有 DELETE
/// （關閉就是 hidden 這個取值，沒有「清回未設定」這種形態）。
String adminActivityMemberDirectoryPath(String activityId) =>
    '${adminActivityItemPath(activityId)}/member-directory';

/// 一行成員的目錄覆蓋路徑：PUT 編輯那一格（只可收緊的兩態）。
///
/// 「動哪一行」由路徑決定，本體裡沒有一格能填 member_id／account_id，
/// 也沒有格子的寫法是「把這個人單獨開放給所有人」。
String adminMemberDirectoryVisibilityPath(String activityId, String memberId) =>
    '${adminActivityMemberItemPath(activityId, memberId)}/directory-visibility';

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
  /// 不在其中，而**已進入刪除終態的帳戶照樣列出**（用戶批准的展示策略：留行不是遺漏，
  /// 而是讓既有審計與歷史引用指得回同一個人）。列出與能讀不等於能改——那一行的詳情
  /// 讀得開，但每一條寫入通路都回自己那句終態拒絕（2027／2028），界面據此收起全部控件。
  /// 五個引數是本端點僅有的篩選（頁碼、每頁筆數、狀態、來源、名稱關鍵字），
  /// 「列誰的清單」仍由後端按解析出的受信主體決定：沒有任何引數可以指定別人的目錄，
  /// 也沒有任何引數可以把管理員拉進來。狀態取值是 all／active／disabled／deleted，
  /// 審批鏈那兩態（pending／rejected）屬另一本名冊、帶過來一樣 1004；其餘非法取值
  /// 一律 1004 並點出是哪個參數，超出總數的合法頁碼則回空清單與真實總數（那不是錯誤）。
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
  /// 還在審批鏈門外）一律同一個 1001，端點因此不是標識格式探測器，也不是
  /// 「某個人是不是管理員」的 oracle。
  ///
  /// 兩種終態（deleted 與 retired）刻意留在讀取範圍內：批准的展示策略是「列得出、
  /// 點得開、但一律只讀」，回應帶著 deleted_at／retired_at 而那兩個時刻就是這句話的
  /// 時間部分。呼叫端據狀態欄位收起全部寫入控件，而不是把終態當 1001 報成查無此人。
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
  /// 目標已是終態時回的是 2027（已被刪除）或 2028（被綁走的退休訪戶），不是 1001：
  /// 那一行讀得到、動不了，界面該收起表单而不是叫操作者換目標。
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
  /// 終態目標走這條通路回的是 2027（已被刪除）或 2028（退休訪戶），與 2014 那句
  /// 「現狀已變，重讀再確認」是兩句話——終態重讀之後還是終態，那顆按鈕不該再出現。
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
  /// 停用狀態保持原樣（重置不是解除停用）。口令只在請求本體
  /// 出現一次，回應不回顯、日誌與審計不留痕；線下的交付管道屬協議之外。
  /// 訪戶帳戶走這條通路會拿到 2018（他今日沒有可重置的一般密碼，設口令等於把身分
  /// 升級成普通帳戶，那要等後續那條明確的訪戶升級通路）；持有授予者與操作者自己
  /// 一律 1001，與詳情、編輯、停用同一句話；而兩種終態各有自己那句拒絕——
  /// 已被刪除的是 2027、被綁走的退休訪戶是 2028，都不是 1001：這本目錄列得出他，
  /// 叫操作者「換個目標」是誤導，而「重讀現值再來一次」對終態也不是答案。
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

  /// 管理員軟刪除一名普通帳戶或訪戶帳戶：DELETE `/admin/accounts/{account_id}`。
  ///
  /// 本體是空的，而且刻意沒有依據值欄位：刪除的正當性錨在「他還不在終態」這條狀態機
  /// 守衛上，發起人對「現行刪除時刻」拿不出任何可交的東西（未被刪時那一欄本來就是缺席）。
  /// 因此這裡也沒有 2013／2014 那樣的「陳舊依據被拒」——對已刪除目標再發一次回的是
  /// 2027，對被綁走的退休訪戶回的是 2028，兩者都是 409 上的獨立語意。
  /// 本體帶任何欄位（reason、purge、expected_status、account_id……）一律 1004：
  /// 「留個理由」與「選個強度」都不在這條通路的合同裡。
  ///
  /// 成功效果（同一次交易落地）：新登入被拒、名下全部會話即刻撤銷（[revokedSessions]
  /// 是權威數量）、顯示名換成服務端寫的 `DEL_<UTC日期>_<原名>` 佔位值。它【不】做的事
  /// 同樣要講清楚：帳戶行與登入名保留（因此登入名不可被複用，同名開設回 2012）、
  /// 既有審計與歷史引用一行不動（歷史操作者仍指回每一個人）、也不存在任何把刪除
  /// 改回來的通路——「恢復登入」那條子資源對已刪除目標回的是 2027。
  ///
  /// **結果不明時絕不自動重發**：那不會是重試，而是對一個可能已進入終態的對象再下
  /// 一次寫入令。操作者該做的是重讀目錄或詳情——回應遺失的事實由那份只讀現值來回答，
  /// 不是由第二次按下那顆按鈕來猜。
  Future<StandardAccountDeleteReport> deleteStandardAccount({
    required String accountId,
    String? acceptLanguage,
  }) {
    return apiClient.delete(
      adminAccountItemPath(accountId),
      decode: StandardAccountDeleteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 管理員把一名可登入的訪戶原地升級成普通帳戶：PUT `/admin/accounts/{account_id}/upgrade`。
  ///
  /// 這是在地升級，不是綁定：後端動的是同一行帳戶——穩定標識、建立時刻、顯示名與
  /// 既有歷史引用全部原樣保留，不新建一筆再刪舊一筆。「綁定到另一個既有正式帳戶」
  /// 是另一條通路（尚未實作），界面必須把兩者分開講。
  /// 白名單只有正式登入名與一次性初始口令兩欄：account_type、roles、status、
  /// must_change_password 之類的宣稱會被後端打成 1004——升級出來的形態恆為
  /// 「普通帳戶＋可登入＋首次登入必須改密」，由端點決定而不是由請求內容決定。
  /// 一次成功落地三件事：身分與憑據同一條 UPDATE 轉正、名下全部舊會話同交易撤銷
  /// （用戶批准的決定：撿到舊臨時憑據的人不自動獲得正式權限，本人要用新口令重新登入）、
  /// Root 域審計追加一筆（歷史事件照舊描述發生時的訪戶身份，不會被重寫）。
  /// 結論分流：2024 說「他此刻不是可升級的訪戶」（已轉正或已被停用，重讀現值再決定）、
  /// 2012 說「那個登入名是別人的」（訪戶一個字都沒被改）、1004 點名欄位、
  /// 1001 是目標不在這本目錄（不存在或持有授予）、2011 是主體不對——訪戶本人敲這條端點
  /// 拿到的就是 2011，他不能給自己提升權限；兩種終態各回自己那句（2027 已被刪除、
  /// 2028 已被綁走），不是 2024 那句「重讀現值之後還能再決定」。口令與重置同套交付語意：伺服端不生成、不回顯；結果不明時
  /// 不得自動補發（重複提交對已轉正者是 2024，但那要經過一次完整的現值判定）。
  Future<StandardAccountUpgradeReport> upgradeGuestAccount({
    required String accountId,
    required String loginName,
    required String password,
    String? acceptLanguage,
  }) {
    return apiClient.put<StandardAccountUpgradeReport>(
      adminAccountUpgradePath(accountId),
      jsonBody: <String, Object?>{
        'login_name': loginName,
        'password': password,
      },
      decode: StandardAccountUpgradeReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 訪戶綁定預檢：POST `/admin/accounts/{account_id}/bind-preflight`。
  ///
  /// 這是一條**純只讀**的評估通路（用戶批准的 R2-018 決定：零寫入、不落審計）：
  /// 本體恰好一欄 `target_account_id`，來源在路徑上、目標在本體裡，一次請求只評估
  /// 這一個（來源, 目標）配對——沒有「替這個訪戶列出可綁定目標」的讀法，請求形態
  /// 本身就是反枚舉邊界。用 POST 是因為目標標識是被評估的輸入而不是資源地址，
  /// 放進查詢串就成了可書籤、可快取的尋人請求。
  /// 回應的 [StandardAccountBindPreflightReport] 如實帶出可執行性、穩定原因記號、
  /// 將產生的影響、源會話計數與這份快照運行的資料庫版本；consent_mode 恆為
  /// `target_self_initiated`——綁定只能由目標持有人自己發起，這份預覽不是任何
  /// 一半的綁定。拒絕只走既有碼：1001（兩側任一方根本不在這本目錄，不可分辨）、2011
  /// （訪戶本人与其餘非管理主體）、1004（目標標識缺失或不成形）、1002（方法）。
  /// 兩側之一是**終態**（已被刪除或已被綁走）時不在拒絕之列：那是 200 的一場預覽，
  /// 由 blockers 裡的 `source_not_active`／`target_not_active` 說出「他不再登得進來」——
  /// 綁定要問的是「此刻還能不能登入」，兩種終態都答「不了」，而那是一句可展示的事實
  /// 而不是一個錯誤碼。
  Future<StandardAccountBindPreflightReport> guestBindPreflight({
    required String accountId,
    required String targetAccountId,
    String? acceptLanguage,
  }) {
    return apiClient.post<StandardAccountBindPreflightReport>(
      adminAccountBindPreflightPath(accountId),
      jsonBody: <String, Object?>{'target_account_id': targetAccountId},
      decode: StandardAccountBindPreflightReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 簽發訪戶綁定的操作憑證：POST `/admin/accounts/{account_id}/bind-ticket`。
  ///
  /// 這是本目錄裡唯一會寫的綁定通路，但它**不是綁定的一半**：落庫的只有憑證一行與
  /// Root 域審計一筆——訪戶未退休、會話未撤、留痕未追加（用戶批准的 R2-019 決定）。
  /// 後端在同一筆交易裡把預檢重做一遍，可行才簽發；不可行以 2026 帶著穩定原因記號回絕
  /// （不像 [guestBindPreflight] 那樣回 200——簽發成功本身就承諾了可行）。
  /// 有效期是後端碼內的 15 分鐘常量：請求裡沒有任何格子可以調它，也沒有撤销通路。
  /// 回應的 [GuestBindTicketReport.ticket] 是憑證明文，只在這一次出現：庫裡存的是它的
  /// SHA-256，此後任何讀法都拿不回來，因此它也不進本倉庫的任何本地儲存。
  Future<GuestBindTicketReport> issueGuestBindTicket({
    required String accountId,
    required String targetAccountId,
    String? acceptLanguage,
  }) {
    return apiClient.post<GuestBindTicketReport>(
      adminAccountBindTicketPath(accountId),
      jsonBody: <String, Object?>{'target_account_id': targetAccountId},
      decode: GuestBindTicketReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 本人的核銷前預覽：POST `/auth/guest-bindings/preview`。
  ///
  /// 只讀，且不核銷任何東西：同一枚憑證在被用掉之前可以讀任意多次（直到過期）。
  /// 它回的是**此刻**重做的判定（來源與目標現值、將產生的影響、源會話數、資料庫版本、
  /// 失效時刻），不是簽發那份快照的回音——界面要讓本人在按下確認之前看見的正是這個。
  /// 事實已漂或形態變了以 2026 回絕（要請管理員重新預檢並另發一枚），憑證本身用不了
  /// 以 2025 回絕（不存在、形狀不合、已過期、已核銷、或准的不是你，五者同形一句）。
  Future<GuestBindClaimPreviewReport> guestBindPreview({
    required String ticket,
    String? acceptLanguage,
  }) {
    return apiClient.post<GuestBindClaimPreviewReport>(
      kAuthGuestBindingsPreviewPath,
      jsonBody: <String, Object?>{'ticket': ticket},
      decode: GuestBindClaimPreviewReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 本人的綁定執行：POST `/auth/guest-bindings`。
  ///
  /// 今日唯一的綁定執行入口，而且只能由憑證上的目標本人通過：主體判定先於任何查詢，
  /// 訪戶、Root 與管理員拿到的是 2011。本體恰好一欄 `ticket`——沒有任何「我以誰的身分」
  /// 可填，來源與目標都由憑證行釘死，因此「換一個目標重放同一枚憑證」在協議層就沒有格子。
  /// 成功回應的 [GuestBindResultReport] 帶出留痕標識、退休後的來源現值、原樣的目標現值
  /// 與这次撤銷的會話數。這是一筆寫入且**刻意不做自動重發**：小票只有一張，
  /// 按兩次不會變成兩次綁定；回應遺失時的答案是 [guestBindingsList] 讀到的那一行。
  Future<GuestBindResultReport> guestBindConfirm({
    required String ticket,
    String? acceptLanguage,
  }) {
    return apiClient.post<GuestBindResultReport>(
      kAuthGuestBindingsPath,
      jsonBody: <String, Object?>{'ticket': ticket},
      decode: GuestBindResultReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀回「目標是我」的已完成綁定：GET `/auth/guest-bindings`。
  ///
  /// 沒有任何查詢參數、也沒有本體：範圍就是本次憑據換出的那個人，所以這條通路問不出
  /// 別人的綁定。它也不是管理員那本目錄的替代品——它回答的是「我以自己的會話接住過誰」。
  /// 界面用它的兩個時刻：一是提交後回應遺失時判定那次綁定到底有沒有落地
  /// （區分失敗／已完成／結果待確認的依據），二是讓本人看得见歷史解釋的存在。
  Future<GuestBindingListReport> guestBindingsList({String? acceptLanguage}) {
    return apiClient.get<GuestBindingListReport>(
      kAuthGuestBindingsPath,
      decode: GuestBindingListReport.decode,
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

  /// 建立一個活動：POST `/admin/activities`。
  ///
  /// 本體只有名稱與描述兩個欄位：狀態不在其中（新建一律是草稿）、建立者不在其中
  /// （他來自那枚會話憑據）、也沒有 id／created_at／archived_at 的格子——多帶会被後端
  /// 打成 1004 並點名是哪一欄。回應是保存後的資料庫現值（含自動指派給建立者的管理人數量）。
  Future<ActivityDetailReport> createActivity({
    required String name,
    required String description,
    String? acceptLanguage,
  }) {
    return apiClient.post<ActivityDetailReport>(
      kAdminActivitiesPath,
      jsonBody: <String, Object?>{'name': name, 'description': description},
      decode: ActivityDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀一頁活動目錄：GET `/admin/activities`。
  ///
  /// 可見範圍由服務端決定：持有伺服器級管理權但未獲指派的人拿到的是空的一頁，
  /// 而不是「全部活動」——漏帶授權資料在這裡不會被放寬成權限。
  /// Root 那一側不受指派限制，看到的才是全量。
  Future<ActivityDirectoryReport> activitiesDirectory({
    int page = 1,
    int pageSize = 20,
    String status = 'all',
    String query = '',
    String? acceptLanguage,
  }) {
    final buffer = StringBuffer(kAdminActivitiesPath)
      ..write('?page=')
      ..write(page)
      ..write('&page_size=')
      ..write(pageSize)
      ..write('&status=')
      ..write(Uri.encodeComponent(status));
    // 空關鍵字不發參數：後端把「沒帶」與「帶了但全是空白」收斂成同一句話（不篩選）。
    if (query.trim().isNotEmpty) {
      buffer
        ..write('&q=')
        ..write(Uri.encodeComponent(query));
    }
    return apiClient.get(
      buffer.toString(),
      decode: ActivityDirectoryReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀單筆活動詳情：GET `/admin/activities/{activity_id}`。
  ///
  /// 詳情是編輯表單底稿的唯一來源：「這個活動此刻叫什麼」只能取自服務端，
  /// 不能拿目錄行或本地印象湊一份。「這個標識不存在」與「它存在但不是你管的活動」
  /// 在這裡是同一個 1001，端點因此不是活動存在性的探測器。
  Future<ActivityDetailReport> activityDetail({
    required String activityId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      adminActivityItemPath(activityId),
      decode: ActivityDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯活動的名称与描述：PUT `/admin/activities/{activity_id}`。
  ///
  /// 白名單是兩欄資料，另帶它們各自依據的現值（compare-and-set）。本體裡沒有
  /// 狀態、建立者、活動標識與時刻的格子（多帶即 1004），後端的 UPDATE 語句也不碰那些欄位：
  /// 「保存資料順手把活動改成已開放」或「順手把它挪進另一個活動」在協定層就沒有發生點。
  /// 現值已變時回 2013 且整個編輯不發生；已歸檔的活動回 2029（終態，重讀之後也沒有那顆按鈕）。
  Future<ActivityDetailReport> updateActivityProfile({
    required String activityId,
    required String name,
    required String description,
    required String expectedName,
    required String expectedDescription,
    String? acceptLanguage,
  }) {
    return apiClient.put<ActivityDetailReport>(
      adminActivityItemPath(activityId),
      jsonBody: <String, Object?>{
        'name': name,
        'description': description,
        'expected_name': expectedName,
        'expected_description': expectedDescription,
      },
      decode: ActivityDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 轉換活動狀態：PUT `/admin/activities/{activity_id}/status`。
  ///
  /// 本體只帶目標狀態一欄，刻意不帶依據值：正當性錨在「庫裡此刻的狀態等於你以为的那個狀態」
  /// 這條可觀測事實上（帶 WHERE 的單向更新），現值已變與同態重複都回 2030。
  /// 四條合法路徑之外回 2031（重讀現值也沒有用，要改的是意圖）；
  /// 歸檔之後任何轉換回 2029。成功回應帶著伺服器的現值與歸檔時刻。
  Future<ActivityDetailReport> updateActivityStatus({
    required String activityId,
    required String status,
    String? acceptLanguage,
  }) {
    return apiClient.put<ActivityDetailReport>(
      adminActivityStatusPath(activityId),
      jsonBody: <String, Object?>{'status': status},
      decode: ActivityDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀活動管理人名冊：GET `/admin/activities/{activity_id}/managers`。
  ///
  /// 讀的權限與活動本身同一道閘（Root 或該活動的管理人）：管理人看得見還有誰在管，
  /// 但不能據此加人或刪人。已進入終態的帳戶那一行仍列，帶著他的現狀，
  /// 因為「历史指向原標識」是这份名冊的合同而不是可選修飾。
  Future<ActivityManagerRosterReport> activityManagers({
    required String activityId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      adminActivityManagersPath(activityId),
      decode: ActivityManagerRosterReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 指派一位活動管理人：POST `/root/activities/{activity_id}/managers`。
  ///
  /// 這是一次權限授予，因此只在 Root 那一側（NeedRoot）：活動自己的管理人不能自行加人。
  /// 本體只有目標帳戶標識一欄——「誰在指派」由那枚 Root 憑據決定，本體沒有格子能填操作者，
  /// 也沒有 role／granted_at 可以宣稱。目標必須已是持有 server_admin 的可用帳戶，
  /// 否則回 1001（不存在、訪戶、停用、待審批或沒有授予一律同一句話）；
  /// 已是該活動管理人回 2032，活動已歸檔回 2029。
  Future<ActivityDetailReport> assignActivityManager({
    required String activityId,
    required String accountId,
    String? acceptLanguage,
  }) {
    return apiClient.post<ActivityDetailReport>(
      rootActivityManagersPath(activityId),
      jsonBody: <String, Object?>{'account_id': accountId},
      decode: ActivityDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 撤銷一位活動管理人：DELETE `/root/activities/{activity_id}/managers/{account_id}`。
  ///
  /// 無本體、無依據值：撤的正當性錨在「這一行確實還在」上，查無此行回 1001 而不是謊報成功。
  /// 指向帳戶的欄位是無外鍵軟参照，因此帳戶被軟刪除後這一行的歷史仍解析得到——
  /// 撤銷與否由 Root 決定，不由綁定或刪除通路代為處置。
  Future<ActivityDetailReport> revokeActivityManager({
    required String activityId,
    required String accountId,
    String? acceptLanguage,
  }) {
    return apiClient.delete(
      rootActivityManagerItemPath(activityId, accountId),
      decode: ActivityDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀一個活動的陣營列表：GET `/admin/activities/{activity_id}/factions`。
  ///
  /// 仍列、可讀：停止與歸檔的活動照樣列出行（拒的是寫）。順序取後端回顯
  /// （排序值、建立時刻、標識），客戶端不重排。「還沒有陣營」是一份空列表而不是錯誤。
  Future<FactionListReport> activityFactions({
    required String activityId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      adminActivityFactionsPath(activityId),
      decode: FactionListReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 建立一個陣營：POST `/admin/activities/{activity_id}/factions`。
  ///
  /// 本體白名單是四欄資料加一格可選的排序值：可用性不在其中（新建一律可用，
  /// 停用走編輯那一跳）、也沒有 id／activity_id／時刻的格子——多帶會被後端打成 1004。
  /// [sortOrder] 為 null 時不發該欄，由後端在交易內排到最後一格。
  /// 同活動重名回 2034；活動停止回 2033、歸檔回 2029。
  Future<FactionWriteReport> createFaction({
    required String activityId,
    required String name,
    required String description,
    required String icon,
    required String color,
    int? sortOrder,
    String? acceptLanguage,
  }) {
    return apiClient.post<FactionWriteReport>(
      adminActivityFactionsPath(activityId),
      jsonBody: <String, Object?>{
        'name': name,
        'description': description,
        'icon': icon,
        'color': color,
        'sort_order': ?sortOrder,
      },
      decode: FactionWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯一個陣營：PUT `/admin/activities/{activity_id}/factions/{faction_id}`。
  ///
  /// 白名單六欄新值，另帶它們各自依據的現值（compare-and-set，沿用 2013 那一枚）。
  /// 可用性開關並在這條通路裡（用戶批准：旗標不是狀態機，不另設 /status 子資源），
  /// 因此「停用」與「重新啟用」也是這一次 PUT——只翻那一欄，其餘五欄帶著現值原樣送回。
  /// 回應裡的 `accepts_new_members` 是服務端派生值，本體沒有這一格：帶了會被 1004 點名。
  /// 標識、歸屬與時刻在本體裡沒有一格可填：跨活動的標識收斂成 1001，
  /// 撞同活動內他人的名字回 2034。
  Future<FactionWriteReport> updateFaction({
    required String activityId,
    required String factionId,
    required String name,
    required String description,
    required String icon,
    required String color,
    required int sortOrder,
    required bool available,
    required String expectedName,
    required String expectedDescription,
    required String expectedIcon,
    required String expectedColor,
    required int expectedSortOrder,
    required bool expectedAvailable,
    String? acceptLanguage,
  }) {
    return apiClient.put<FactionWriteReport>(
      adminActivityFactionItemPath(activityId, factionId),
      jsonBody: <String, Object?>{
        'name': name,
        'description': description,
        'icon': icon,
        'color': color,
        'sort_order': sortOrder,
        'available': available,
        'expected_name': expectedName,
        'expected_description': expectedDescription,
        'expected_icon': expectedIcon,
        'expected_color': expectedColor,
        'expected_sort_order': expectedSortOrder,
        'expected_available': expectedAvailable,
      },
      decode: FactionWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀一個活動的標籤定義列表：GET `/admin/activities/{activity_id}/tags`。
  ///
  /// 仍列、可讀：停止與歸檔的活動照樣列出行（拒的是寫），內部定義也照樣列——這一族的閘
  /// 是活動管理面那道。順序取後端回顯（排序值、建立時刻、標識），客戶端不重排。
  /// 「還沒有標籤」是一份空列表而不是錯誤。
  Future<TagListReport> activityTags({
    required String activityId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      adminActivityTagsPath(activityId),
      decode: TagListReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 建立一枚標籤定義：POST `/admin/activities/{activity_id}/tags`。
  ///
  /// 本體白名單是四欄資料加一格可選的排序值：`public` 不在其中——新建一律是管理員的
  /// 內部資訊，要對外必須是建好之後那一跳明確的編輯（因此界面不可能「保存時預設勾公開」）；
  /// `available` 也沒有格子（新建即可用），id／activity_id／時刻同理由服務端決定。
  /// [sortOrder] 為 null 時不發該欄，由後端在交易內排到最後一格。
  /// 同活動重名回 2040；活動停止回 2033、歸檔回 2029。
  Future<TagWriteReport> createTag({
    required String activityId,
    required String name,
    required String description,
    required String icon,
    required String color,
    int? sortOrder,
    String? acceptLanguage,
  }) {
    return apiClient.post<TagWriteReport>(
      adminActivityTagsPath(activityId),
      jsonBody: <String, Object?>{
        'name': name,
        'description': description,
        'icon': icon,
        'color': color,
        'sort_order': ?sortOrder,
      },
      decode: TagWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯一枚標籤定義：PUT `/admin/activities/{activity_id}/tags/{tag_id}`。
  ///
  /// 白名單七欄新值，另帶它們各自依據的現值（compare-and-set，沿用 2013 那一枚）。
  /// 可用性與公開兩個開關並在這條通路裡（用戶批准：旗標不是狀態機，不另設子資源），
  /// 因此「停用」「翻公開」「收回公開」都是這一次 PUT——只翻要動的那一欄，其餘帶著現值原樣送回。
  /// 回應裡的 `accepts_new_assignments` 是服務端派生值，本體沒有這一格：帶了會被 1004 點名。
  /// 標識、歸屬與時刻在本體裡沒有一格可填：跨活動的標識收斂成 1001，撞同活動內他人的名字回 2040。
  Future<TagWriteReport> updateTag({
    required String activityId,
    required String tagId,
    required String name,
    required String description,
    required String icon,
    required String color,
    required int sortOrder,
    required bool available,
    required bool public,
    required String expectedName,
    required String expectedDescription,
    required String expectedIcon,
    required String expectedColor,
    required int expectedSortOrder,
    required bool expectedAvailable,
    required bool expectedPublic,
    String? acceptLanguage,
  }) {
    return apiClient.put<TagWriteReport>(
      adminActivityTagItemPath(activityId, tagId),
      jsonBody: <String, Object?>{
        'name': name,
        'description': description,
        'icon': icon,
        'color': color,
        'sort_order': sortOrder,
        'available': available,
        'public': public,
        'expected_name': expectedName,
        'expected_description': expectedDescription,
        'expected_icon': expectedIcon,
        'expected_color': expectedColor,
        'expected_sort_order': expectedSortOrder,
        'expected_available': expectedAvailable,
        'expected_public': expectedPublic,
      },
      decode: TagWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀一場活動裡對外公開的標籤定義清單：GET `/player/activities/{activity_id}/tags`。
  ///
  /// 這一條只列被設成公開的定義，且讀到的是玩家側投影（沒有可用性、公開旗標、時刻與計數）。
  /// 準入是「這次請求的憑據換出的那個帳戶在這場活動有沒有成員行」：非成員與 Root 拿到 1001，
  /// 匿名 2002。空清單語意是「這場活動還沒把任何標籤設成對外」，不是錯誤。
  /// 它不改變目錄的可見範圍：一枚標籤公開與否，不讓任何人多被看見、也不多得到一項能力。
  Future<PublicTagListReport> publicActivityTags({
    required String activityId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      playerActivityTagsPath(activityId),
      decode: PublicTagListReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 按標識直查一枚公開標籤定義：GET `/player/activities/{activity_id}/tags/{tag_id}`。
  ///
  /// 「有這枚標籤、只是沒被設成公開」與「從未有過這個標識」「它屬於另一場活動」是同一句
  /// 1001：這一條路徑不當內部定義的存在性探測器，因此界面不能據回應分辨三者。
  Future<PublicTagDetailReport> publicActivityTag({
    required String activityId,
    required String tagId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      playerActivityTagItemPath(activityId, tagId),
      decode: PublicTagDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀一個活動的成員名冊：GET `/admin/activities/{activity_id}/members`。
  ///
  /// 仍列、可讀：停止與歸檔的活動照樣列出行（拒的是寫）。順序取後端回顯
  /// （加入時刻、標識），客戶端不重排。「還沒有人加入」是一份空列表而不是錯誤。
  Future<MemberListReport> activityMembers({
    required String activityId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      adminActivityMembersPath(activityId),
      decode: MemberListReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 在一個活動裡為一個既有帳戶建立成員身份：POST `/admin/activities/{activity_id}/members`。
  ///
  /// 本體白名單只有兩格（目標帳戶標識與活動內暱稱）：身分三欄、時刻與陣營歸屬
  /// 都沒有格子——多帶會被後端打成 1004，而「他此刻屬於哪個陣營」在本版本根本無處可填
  /// （分配通路尚未存在，出生即為「尚未分組」）。
  /// 目標帳戶的型別與狀態由後端現讀：終態者（待審批／被拒／已刪除／已退休）與幽靈
  /// 一律回同一句 1001；重複建立回 2035；活動停止回 2033、歸檔回 2029。
  Future<MemberWriteReport> createMember({
    required String activityId,
    required String accountId,
    required String nickname,
    String? acceptLanguage,
  }) {
    return apiClient.post<MemberWriteReport>(
      adminActivityMembersPath(activityId),
      jsonBody: <String, Object?>{
        'account_id': accountId,
        'nickname': nickname,
      },
      decode: MemberWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯一個成員的活動內暱稱：PUT `/admin/activities/{activity_id}/members/{member_id}`。
  ///
  /// 這是本版本唯一一條寫入成員資料的通路：白名單只有暱稱一欄，另帶它所依據的現值
  /// （compare-and-set，沿用 2013 那一枚）。身分三欄與 `faction_id` 在本體裡沒有一格可填——
  /// 「儲存名字順手把他挪進另一個陣營」不是被拒，而是無處可填。
  /// 跨活動的標識與幽靈同形收斂成 1001；活動停止回 2033、歸檔回 2029。
  Future<MemberWriteReport> updateMemberNickname({
    required String activityId,
    required String memberId,
    required String nickname,
    required String expectedNickname,
    String? acceptLanguage,
  }) {
    return apiClient.put<MemberWriteReport>(
      adminActivityMemberItemPath(activityId, memberId),
      jsonBody: <String, Object?>{
        'nickname': nickname,
        'expected_nickname': expectedNickname,
      },
      decode: MemberWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀一個活動的玩家業務狀態目錄：GET `/admin/activities/{activity_id}/player-statuses`。
  ///
  /// 回應是兩份清單：七個內建鍵各自的顯示名稱覆蓋現值，與這場活動的全部自訂狀態定義
  /// （含已停用的那些）。仍列、可讀：停止與歸檔的活動照樣回現值（拒的是寫入）。
  /// 「還沒定義過任何自訂狀態」是一份空清單而不是錯誤，界面也不拿空清單冒充「沒有狀態」。
  Future<PlayerStatusCatalogReport> playerStatusCatalog({
    required String activityId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      adminActivityPlayerStatusesPath(activityId),
      decode: PlayerStatusCatalogReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 建立一個自訂狀態定義：POST `/admin/activities/{activity_id}/player-statuses`。
  ///
  /// 本體白名單只有 `name` 一格：可用性、標識、歸屬活動與時刻都沒有格子可填
  /// （新建即可用，其餘由服務端決定）。
  /// 同活動重名回 2042；已歸檔回 2029（停止態仍可準備定義，因為它只是「能不能被選用」的
  /// 一份清單，玩家那一側的寫入本來就被業務門禁擋在外面）。
  Future<PlayerCustomStatusWriteReport> createPlayerStatus({
    required String activityId,
    required String name,
    String? acceptLanguage,
  }) {
    return apiClient.post<PlayerCustomStatusWriteReport>(
      adminActivityPlayerStatusesPath(activityId),
      jsonBody: <String, Object?>{'name': name},
      decode: PlayerCustomStatusWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯一個自訂狀態定義：PUT `/admin/activities/{activity_id}/player-statuses/{status_id}`。
  ///
  /// 白名單兩欄新值（名稱與可用性）加上它們各自依據的現值（compare-and-set，沿用 2013）。
  /// 停用＝翻 `available` 那一欄：既有成員保留原狀態與標識，只擋下新的選用（回 2041），
  /// 界面上沒有刪除这颗按鈕，也沒有任何一格能把別人的歸屬搬走。
  /// 標識、歸屬與時刻在本體裡沒有格子可填：跨活動的標識收斂成 1001。
  Future<PlayerCustomStatusWriteReport> updatePlayerStatus({
    required String activityId,
    required String statusId,
    required String name,
    required bool available,
    required String expectedName,
    required bool expectedAvailable,
    String? acceptLanguage,
  }) {
    return apiClient.put<PlayerCustomStatusWriteReport>(
      adminActivityPlayerStatusItemPath(activityId, statusId),
      jsonBody: <String, Object?>{
        'name': name,
        'available': available,
        'expected_name': expectedName,
        'expected_available': expectedAvailable,
      },
      decode: PlayerCustomStatusWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯內建狀態在某一場活動的顯示名稱：
  /// PUT `/admin/activities/{activity_id}/player-status-labels/{status_key}`。
  ///
  /// 白名單兩格：新的 `display_name` 與它所依據的現值 `expected_display_name`。
  /// 空字串是「恢復四語言預設文案」，不是刪除那一個狀態——七個內建鍵不可增刪。
  /// 這一格只改展示值：任何人的 `business_status` 內部值與歷史引用都不動。
  /// 現值已變時回 2013；已歸檔回 2029（停止態仍可準備顯示名稱）。
  Future<PlayerStatusLabelWriteReport> updatePlayerStatusLabel({
    required String activityId,
    required String statusKey,
    required String displayName,
    required String expectedDisplayName,
    String? acceptLanguage,
  }) {
    return apiClient.put<PlayerStatusLabelWriteReport>(
      adminActivityPlayerStatusLabelPath(activityId, statusKey),
      jsonBody: <String, Object?>{
        'display_name': displayName,
        'expected_display_name': expectedDisplayName,
      },
      decode: PlayerStatusLabelWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 變更一位玩家此刻的業務狀態：
  /// PUT `/admin/activities/{activity_id}/members/{member_id}/business-status`。
  ///
  /// 白名單四格：`business_status`（七個內建穩定值之一）與 `custom_status_id`
  /// （非 custom 時空字串），加上它們各自依據的現值 `expected_business_status`／
  /// `expected_custom_status_id`（compare-and-set，沿用 2013）。
  /// 成對關係不成立（custom 沒帶定義、或內建值卻帶了定義）回 1004 點名 `business_status`；
  /// 選中已停用的自訂定義回 2041；定義屬於別的活動或從未存在收斂成 1001。
  /// 目標與現值相同時服務端視為冪等成功（不產生第二次留痕）。
  /// 這條通路不碰暱稱、陣營、目錄覆蓋與任何帳戶欄位；變更狀態也不清空資產、不退出活動。
  /// 停止態回 2033、歸檔回 2029（業務寫入門禁在这一侧照样成立）。
  Future<MemberWriteReport> updateMemberBusinessStatus({
    required String activityId,
    required String memberId,
    required String businessStatus,
    required String customStatusId,
    required String expectedBusinessStatus,
    required String expectedCustomStatusId,
    String? acceptLanguage,
  }) {
    return apiClient.put<MemberWriteReport>(
      adminActivityMemberBusinessStatusPath(activityId, memberId),
      jsonBody: <String, Object?>{
        'business_status': businessStatus,
        'custom_status_id': customStatusId,
        'expected_business_status': expectedBusinessStatus,
        'expected_custom_status_id': expectedCustomStatusId,
      },
      decode: MemberWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 逐欄編輯一位成員的分項限制：
  /// PUT `/admin/activities/{activity_id}/members/{member_id}/restrictions`。
  ///
  /// `restrictions` 的鍵就是協定欄位名（`restrict_login`／`restrict_chat`／
  /// `restrict_private_chat`／`restrict_trade`／`restrict_transfer`／
  /// `restrict_item_use`），每一鍵帶一對「新值＋依據值」：本體裡只出現被選中的欄，
  /// 沒選中的欄位不進請求、也不進資料庫的 UPDATE——取消聊天不會順手取消私聊或登入。
  /// 空映射在客戶端就拒發（那顆按鈕不該按下去撞 1004）；任一欄依據值過期回 2013
  /// 且整個編輯不落；全部新值等於現值時服務端視為冪等成功（不產生第二次留痕）。
  /// 停止態回 2033、歸檔回 2029（業務寫入門禁在這一側照樣成立）。
  Future<MemberWriteReport> updateMemberRestrictions({
    required String activityId,
    required String memberId,
    required Map<String, MemberRestrictionPatch> restrictions,
    String? acceptLanguage,
  }) {
    if (restrictions.isEmpty) {
      throw ArgumentError.value(restrictions, 'restrictions', '至少需要一欄被選中的限制');
    }
    final Map<String, Object?> body = <String, Object?>{};
    for (final MapEntry<String, MemberRestrictionPatch> entry
        in restrictions.entries) {
      body[entry.key] = entry.value.value;
      body['expected_${entry.key}'] = entry.value.expected;
    }
    return apiClient.put<MemberWriteReport>(
      adminActivityMemberRestrictionsPath(activityId, memberId),
      jsonBody: body,
      decode: MemberWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀本人在某一場活動裡的六枚限制現值：GET `/player/activities/{activity_id}/restrictions`。
  ///
  /// 被 `restrict_login` 擋下的人這一條照舊讀得動（它是「有效結果」的本人查閱，
  /// 不是使用訪問資格）；除此之外玩家族其餘通路在服務層逐請求現讀擋下，回 2043。
  Future<OwnMemberRestrictionsReport> ownMemberRestrictions({
    required String activityId,
    String? acceptLanguage,
  }) {
    return apiClient.get<OwnMemberRestrictionsReport>(
      playerActivityRestrictionsPath(activityId),
      decode: OwnMemberRestrictionsReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯某一場活動的「玩家自選陣營」那一欄配置：PUT `/admin/activities/{activity_id}/faction-select`。
  ///
  /// 白名單只有 `mode`（disabled／first_only／free）與它所依據的現值 `expected_mode`。
  /// 本體裡沒有狀態、名稱、描述或任何人的歸屬格子（多帶即 1004）：
  /// 「改開關順手把活動改名」與「改開關順手把某個人搬出陣營」都不是被拒，而是無處可填。
  /// 現值已變時回 2013 且整個編輯不發生；已歸檔回 2029（停止態照樣可以準備這欄配置）。
  Future<ActivityDetailReport> updateFactionSelectMode({
    required String activityId,
    required String mode,
    required String expectedMode,
    String? acceptLanguage,
  }) {
    return apiClient.put<ActivityDetailReport>(
      adminActivityFactionSelectPath(activityId),
      jsonBody: <String, Object?>{'mode': mode, 'expected_mode': expectedMode},
      decode: ActivityDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀「我參加了哪些活動」：GET `/player/activities`。
  ///
  /// 主體只由會話決定，沒有任何引數能宣稱「動的是誰」；這一份清單就是玩家端唯一的
  /// 活動入口讀法（不是活動目錄，也不回答「還有哪些活動存在」）。
  /// 空清單是一句事實：我還沒有參加任何活動。本人不是成員時不會得到任何別人的行。
  Future<MyActivityListReport> myActivities({String? acceptLanguage}) {
    return apiClient.get(
      playerActivitiesPath(),
      decode: MyActivityListReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀我在某一場活動裡的陣營現況：GET `/player/activities/{activity_id}/faction`。
  ///
  /// 三份同源事實：那場活動（狀態與自選模式）、我自己（此刻歸屬）、這場活動的全部候選項。
  /// 「他不是這個活動的成員」與「沒有這場活動」「那場活動不歸你看」收斂成同一個 1001。
  Future<FactionSelectionReport> myFactionSelection({
    required String activityId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      playerActivityFactionPath(activityId),
      decode: FactionSelectionReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 自己把歸屬選成一個此刻可用的陣營：PUT `/player/activities/{activity_id}/faction`。
  ///
  /// 本體恰好兩格：目標陣營與它所依據的我的歸屬現值（空字串＝我以為自己尚未分組）。
  /// 後端在寫入交易內重新問全部規則，因此界面讀到的 [FactionSelectionReport.canSelectNow]
  /// 只是顯示面，不是通行證：
  /// 2037 那場活動沒開放、2038 還在草稿、2033 已停止、2029 已歸檔、
  /// 2036 那個陣營已停用、2039 僅首次模式下我已選過、2013 我依據的現值已過期、
  /// 1004 本體寫法不對、1001 目標標識寫壞或我根本不是這個活動的成員。
  /// 本步沒有清空歸屬的通路：`faction_id` 填空字串是 1001 那一句，不是「把我移出陣營」。
  Future<SelfFactionWriteReport> selectOwnFaction({
    required String activityId,
    required String factionId,
    required String expectedFactionId,
    String? acceptLanguage,
  }) {
    return apiClient.put<SelfFactionWriteReport>(
      playerActivityFactionPath(activityId),
      jsonBody: <String, Object?>{
        'faction_id': factionId,
        'expected_faction_id': expectedFactionId,
      },
      decode: SelfFactionWriteReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀某一場活動的玩家目錄：GET `/player/activities/{activity_id}/members`。
  ///
  /// 四個查詢引數是這個端點僅有的篩選（頁碼、每頁筆數、暱稱關鍵字、陣營篩選）：
  /// 「誰能進這份清單」不在引數裡——後端現讀活動模式、我自己那一行、每一行的覆蓋
  /// 與授予之後才切頁與計數，所以列表、計數與篩選候選吃同一份已授權結果集。
  /// 取值不合法回 1004 並點名是哪一個參數；他不是這個活動的成員、查無這場活動、
  /// 那一行此刻不給他看，全都收斂成同一個 1001（不可分辨，不是存在性探測器）。
  /// `hidden` 態的答案是空的一頁加上回顯的那一欄模式，不是錯誤。
  Future<MemberDirectoryReport> playerMemberDirectory({
    required String activityId,
    int page = 1,
    int pageSize = 20,
    String query = '',
    String factionId = '',
    String? acceptLanguage,
  }) {
    final buffer = StringBuffer(playerActivityMembersPath(activityId))
      ..write('?page=')
      ..write(page)
      ..write('&page_size=')
      ..write(pageSize);
    // 空關鍵字與空篩選都不發參數：後端把「沒帶」與「帶了但全是空白」收斂成同一句話
    // （不篩選），但介面不必因此多送兩個無意義的空值。
    if (query.trim().isNotEmpty) {
      buffer
        ..write('&q=')
        ..write(Uri.encodeComponent(query));
    }
    if (factionId.isNotEmpty) {
      buffer
        ..write('&faction=')
        ..write(Uri.encodeComponent(factionId));
    }
    return apiClient.get(
      buffer.toString(),
      decode: MemberDirectoryReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀目錄裡的單筆玩家資料：GET `/player/activities/{activity_id}/members/{member_id}`。
  ///
  /// 「詳情直達」走這一條而不是從列表那一行本地展開：同一句可見性判定在這次請求裡
  /// 重新問一遍，所以失權之後重新進入這一路徑拿到的是 1001，而不是上一批留下的那一份。
  /// 那一行此刻不可見、從未存在、屬於另一場活動——三種形態同一個 1001。
  Future<DirectoryMemberDetailReport> playerDirectoryMember({
    required String activityId,
    required String memberId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      playerActivityMemberItemPath(activityId, memberId),
      decode: DirectoryMemberDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 讀我自己在某一場活動裡的資料投影：GET `/player/activities/{activity_id}/profile`。
  ///
  /// 這一讀不經目錄可見性判定：活動把目錄收成 `hidden`、或管理人把我那一行收起來，
  /// 都不該讓我讀不到自己叫什麼。回應只有我自己的活動內事實加那兩格規則現值，
  /// 別人一個都不在其中。非成員與 Root／系統主體一樣收斂成 1001。
  Future<OwnMemberProfileReport> playerOwnMemberProfile({
    required String activityId,
    String? acceptLanguage,
  }) {
    return apiClient.get(
      playerActivityProfilePath(activityId),
      decode: OwnMemberProfileReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯某一場活動的「玩家目錄可見性」那一欄配置：PUT `/admin/activities/{activity_id}/member-directory`。
  ///
  /// 白名單只有 `mode`（hidden｜same_faction_only｜all_players_except_admin｜all_members）
  /// 與它所依據的現值 `expected_mode`。本體裡沒有任何一格能宣稱「用管理視角給我全部人」
  /// （多帶即 1004）：可見範圍由後端現讀指派與授予決定，客戶端連「我是誰」都填不了。
  /// 現值已變回 2013 且整個編輯不發生；已歸檔回 2029；停止態照樣可以準備這欄配置
  /// （它屬活動自己的資料，與名稱描述同側）。
  Future<ActivityDetailReport> updateMemberDirectoryMode({
    required String activityId,
    required String mode,
    required String expectedMode,
    String? acceptLanguage,
  }) {
    return apiClient.put<ActivityDetailReport>(
      adminActivityMemberDirectoryPath(activityId),
      jsonBody: <String, Object?>{'mode': mode, 'expected_mode': expectedMode},
      decode: ActivityDetailReport.decode,
      acceptLanguage: acceptLanguage,
    );
  }

  /// 編輯單一行成員的目錄覆蓋：PUT `/admin/activities/{activity_id}/members/{member_id}/directory-visibility`。
  ///
  /// 本體恰好兩格：新覆蓋與它所依據的現值。取值只有 inherit｜hidden——
  /// 覆蓋只能收緊，庫裡沒有一格能表達「把這個人單獨公開」。
  /// 2013 現值已過期、2033 活動已停止（這是对一行成員資料的改動，走業務寫入門禁）、
  /// 2029 已歸檔、1004 寫法不對、1001 那一行不存在或不屬於這個活動或這場活動不歸你管。
  Future<MemberWriteReport> updateMemberDirectoryVisibility({
    required String activityId,
    required String memberId,
    required String visibility,
    required String expectedVisibility,
    String? acceptLanguage,
  }) {
    return apiClient.put<MemberWriteReport>(
      adminMemberDirectoryVisibilityPath(activityId, memberId),
      jsonBody: <String, Object?>{
        'visibility': visibility,
        'expected_visibility': expectedVisibility,
      },
      decode: MemberWriteReport.decode,
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
