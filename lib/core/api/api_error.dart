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

/// 已發布的穩定機器錯誤碼（1xxx 通用與協定段、2xxx 帳號與身分段）。
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
  notReady(1007),

  /// 2001：登入被拒。查無此人、口令錯誤、帳戶不可登入在後端收斂為同一個碼，
  /// 介面據此顯示唯一的失敗文案（不透露是哪一半錯的）。
  invalidCredentials(2001),

  /// 2002：請求沒有攜帶任何會話憑據（需要身分的端點收到匿名請求）。
  notAuthenticated(2002),

  /// 2003：攜帶的會話憑據無效（過期、撤銷或主體狀態變化），處置是重新登入。
  sessionInvalid(2003),

  /// 2004：請求混用認證方式（Cookie 與 Bearer 並存，或瀏覽器企圖用 Bearer）。
  authMethodConflict(2004),

  /// 2005：有副作用的請求未通過來源（CSRF）策略。
  originForbidden(2005),

  /// 2006：登入嘗試過於頻繁，已被伺服器冷卻。處置是依 Retry-After 稍後再試；
  /// 後端對「哪個帳戶被打滿」完全同形，介面據此也只能顯示通用的稍後再試。
  loginThrottled(2006),

  /// 2007：帶來的會話憑據是「上一代」的——那枚會話還在，但已換發過新秘密。
  ///
  /// 與 [sessionInvalid] 分開只為一件事：這一句失敗的處置是「重試」，不是
  /// 「重新登入」。把一次正常的秘密輪換說成會話失效，會把與輪換交錯的那條請求
  /// 變成使用者的意外掉線。它不代表舊憑據還有訪問能力：後端對它一律拒絕，
  /// 也不會回傳任何新秘密。
  sessionStale(2007),

  /// 2008：憑據正確，但這個主體的有效會話名額已達伺服器的裝置登入上限，
  /// 於是這次登入整個沒有發生（既沒有新會話，也沒有任何既有裝置被踢掉）。
  ///
  /// 與 [invalidCredentials] 分開是因為處置完全不同：一個是「口令再來一次也是錯」，
  /// 另一個是「口令沒錯，只是別臺裝置還掛著線」。它也**不**是 [loginThrottled]：
  /// 冷卻時間一到就有全新預算，名額卻要等到某個會話被登出或自然到期才釋放，
  /// 因此本值不標為可重試——對著它重點登入只會撞同一堵牆。
  /// 後端刻意不把上限值與現存裝置數放進回應，介面因此也只能給一句不帶數字的說明。
  deviceLimitReached(2008),

  /// 2009：定向撤銷指向的裝置不在本人的會話範圍內——它可能從未存在、已被清理，或本就
  /// 是別的裝置／別人的裝置，後端對這三種情況給同一個答案。
  ///
  /// 它不屬於 [retryable]：對同一枚已不在的裝置再點一次撤銷不會讓它回來，正確的處置是
  /// 重新整理清單。它也刻意不洩露「這個 device_id 是否存在於別人名下」，因此介面只能
  /// 給一句「這臺已不在你的清單中，請重新整理」，不帶任何存在性暗示。
  deviceNotFound(2009),

  /// 2010：該帳戶帶有「首次登入必須改密」旗標，此端點不在改密必要入口之內。
  ///
  /// 處置是「先完成改密或登出」，與 [sessionInvalid]（該重新登入）、
  /// [invalidBody]（該改表單）都不同：憑據有效、輸入也無辜，缺的是完成那項義務。
  /// 它不屬於 [retryable]——對著同一個旗標重試不會讓它自己變好。
  passwordChangeRequired(2010),

  /// 2011：身分可信，但這個身分沒有這件事所需要的權限。
  ///
  /// 它不屬於 [retryable]，也不該被當成 [sessionInvalid] 處理：憑據有效、重新登入也有效，
  /// 但那個主體本來就不該做這件事——把 2011 顯示成「你被登出了」是謊報，
  /// 而後端也刻意不在回應裡說「需要哪個角色」，那屬伺服器的內部授權資料。
  permissionDenied(2011),

  /// 2012：要開設的登入名（正規化後）已被佔用。
  ///
  /// 它是可預期的業務衝突：重複提交、與併發的另一次開設撞鍵、丟失回應後的整筆重試，
  /// 後端都只回這一句，而且不會因此多出一個帳戶。處置是換一個名字，不是改寫法
  /// （比對本來就會吸收大小寫與全形／半形差異），也不是重登。
  /// 後端不回顯既有帳戶的任何資料，也不回顯任何口令。
  loginNameTaken(2012),

  /// 2013：編輯管理員資料所依據的現值已不是資料庫現值——整個編輯沒有發生。
  ///
  /// 它是可預期的併發結論，處置與 [deviceNotFound] 同形：重讀服務端現值再決定，
  /// 不是重登、也不是照原樣重發（重發一百次也比不中同一個過期現值）。
  /// 後端不回顯雙方的值：最新現值本來就是「重讀詳情」該拿到的資料。
  profileConflict(2013),

  /// 2014：停用／恢復管理員所依據的狀態現值已不是資料庫現值——整個操作沒有發生。
  ///
  /// 它與 [profileConflict] 分開只為處置不同：改名落敗是「重讀那個欄位再改」，
  /// 這裡落敗是「目標的可用性已經不是你確認時的那樣」——要重讀整個狀態並
  /// 重新走一次確認，把人手上那顆按鈕再點一次對這不是答案。
  /// 重複操作（對已停用者再停用）也收斂到這裡：後端不會把「什麼都沒發生」
  /// 說成第二次成功，界面也不會拿到第二筆撤銷。
  adminStatusConflict(2014),

  /// 2015：目標是已被軟刪除的管理員帳戶——本次操作沒有可發生的對象。
  ///
  /// 它與 [notFound]（1001，這個人不在這本目錄裡）分開只為處置不同：一個要換目標，
  /// 另一個是「你正看著的那個人已經被刪掉了，別再對他下任何寫入令」。
  /// 把它報成 1001，Root 會對著一份明明列著他的目錄反覆懷疑標識抄錯；
  /// 把它報成成功，則是在審計與真相之間造出一件沒發生過的事。
  /// 它也與 [profileConflict]／[adminStatusConflict] 不同：那兩者說「重讀現值再來一次」，
  /// 而刪除是終態——重讀之後的答案是「他不再生效」，再點一次那顆按鈕不是答案。
  adminDeleted(2015),

  /// 2016：送來的自註冊模式是已批准的名字，但它所需的准入通路在本伺服器版本尚未落地。
  ///
  /// 介面必須把它與 [invalidBody]（1004）分開：1004 的處置是「改寫法再來」，
  /// 而這裡改寫法換不來任何結果——要等的是後端把那條通路做出來。
  /// 把兩者唸成同一句，Root 就會對著一個規格裡見過的名字反覆懷疑自己打錯字。
  accountPolicyModeUnavailable(2016),

  /// 2017：帳戶建立通路此刻被伺服器策略關閉——請求合法、權限也真的足夠。
  ///
  /// 介面必須把它與 [permissionDenied]（2011）分開：2011 說「你的身分做不了這件事，
  /// 再試一次也不會變」，而這裡說的是「你有這個能力，但伺服器目前不許」——
  /// 處置是請 Root 在帳戶建立策略裡打開開關，換名字、換身分、重新登入都不是答案。
  /// 也與 [invalidBody]（1004）分開：本體沒有任何可改的欄位。
  /// Root 走同一條端點時同被拒（開關不豁免任何主體），這句話因此不暗示
  /// 「換個管理員帳號就有用」。
  accountCreationDisabled(2017),

  /// 2018：目標是訪戶帳戶，他今日沒有一般密碼可重置——請求合法、權限也真的足夠。
  ///
  /// 介面必須把它與已發布的幾句分開：[invalidBody]（1004）說「那個口令寫法不合規，
  /// 改寫法再來」，對訪戶改寫法換不來任何結果；[permissionDenied]（2011）說
  /// 「換個身分也沒用」，而操作者的管理權確實足夠；[notFound]（1001）說
  /// 「他不在這本目錄裡，換個目標」，但普通帳戶目錄按定義把訪戶列得進去，
  /// 叫操作者換目標是誤導。要等的是後續那條明確的訪戶升級通路——
  /// 「給訪戶設一個口令」等於替他做一次身分升級，那不是一欄口令該決定的事。
  /// 重複提交只會再拒一次，界面因此不擺「再試一次」的出口。
  guestUpgradeRequired(2018),

  /// 2019：匿名自註冊時正規化後的登入名已被佔用——這是可預期的業務衝突，帳戶一個也沒多出來。
  ///
  /// 它與 [loginNameTaken]（2012）分開只為出處與可見範圍不同：2012 的合同寫明只在
  /// Root／管理員的建號入口出現，那條路需要先有已認證主體；2019 出現在匿名自註冊入口，
  /// 面向任何站在這扇門外的人。處置與 2012 同形——換一個名字，不是改寫法（正規化本就吸收
  /// 大小寫與全形／半形差異）、不是重新登入。後端不回顯既有帳戶的任何資料，也不回顯任何口令。
  selfRegisterNameTaken(2019),

  /// 2020：查本人申請狀態時憑據有效，但這一筆帳戶根本不是待審批的申請。
  ///
  /// 它只在「已經證明你是他本人」之後才可能出現，因此對外人是一部探測不到的回答——
  /// 查無此名、訪客帳戶與口令不符一律收斂成 [invalidCredentials]（2001），兩者不同形。
  /// 處置與其他碼都不同：不是換名字（2019）、不是等 Root 打開開關（2017）、
  /// 也不是等一條還沒上線的功能（2016），而是「這組憑據直接走登入就好」。
  /// 一個剛被批准的人不會拿到這一句——他帶著審核時刻，回報的是 approved。
  notAnApplication(2020),

  /// 2021：這一筆註冊申請已經有過決定——本次審批整個沒有發生（狀態沒改、
  /// 決定時刻沒寫、審計沒記）。
  ///
  /// 它是可預期的併發與重複結論，與 [adminStatusConflict]（2014）同族但不是同一句話：
  /// 2014 說「你依據的現值已過期，重讀之後同一顆按鈕還可以再按一次」，而這裡重讀之後的
  /// 答案是「他已經被決定過了」——那顆按鈕對這個目標不再存在，再按一次既不會撤銷
  /// 別人那次決定，也不會把拒絕改成批准（後端的決定是單向的）。
  /// 兩個審核者同時按下時只有先提交的那一次生效，後到的拿到這一句，
  /// 因此界面必須把它導向「重新讀取名冊」，而不是「再試一次」。
  /// 後端不回顯是誰做的決定、不帶任何理由文本，也不回顯決定時刻。
  /// 它不屬於 [retryable]：原樣重發不會讓它變好。
  applicationDecided(2021),

  /// 2022：這一枚伺服器級註冊邀請碼已經被撤銷——本次撤銷整個沒有發生（撤銷時刻沒改、
  /// 已用次數沒動、審計沒記）。
  ///
  /// 它是可預期的併發與重複結論，與 [applicationDecided]（2021）同族但不是同一句話：
  /// 撤銷是一枚碼的單向終態——重讀之後的答案是「它已經不在有效那一側了」，對著同一枚已撤銷的碼
  /// 再按一次那顆按鈕既不會讓先前那次撤銷被撤銷，也不會把它改成別的時刻。兩個撤銷者同時按下時
  /// 只有先提交的那一次生效，後到的拿到這一句，因此界面必須把它導向「重新讀取名冊」，
  /// 而不是「再試一次」。後端不回顯是誰撤銷的、不帶任何理由文本，也不回顯明文碼。
  /// 它不屬於 [retryable]：原樣重發不會讓它變好。
  inviteAlreadyRevoked(2022),

  /// 2023：策略開的是邀請碼自註冊，而這一次的邀請碼換不出一筆帳戶（HTTP 403）。
  ///
  /// 後端把「完全沒帶碼」「碼形状不合」「這臺伺服器沒簽過這枚碼」「已撤銷」「已過期」「額度用滿」
  /// 「併發下被另一筆註冊搶先耗盡」七種原因一律收斂成同一句不泄露細節的結論：界面據回應分辨不出
  /// 差的是哪一半，這條註冊通路因此不會變成一部逐枚探測碼有效性的探測器。它與 [inviteAlreadyRevoked]
  /// （2022，Root 撤銷一枚已撤銷碼）分開：一個是門外的人拿壞碼來註冊（准入被拒，處置是去要一枚新碼），
  /// 另一個是 Root 對名冊上同一枚碼按了第二次（處置是重讀名冊）。也不與 1004（改寫法）、
  /// 2017（策略沒開這條路）、2019（名字被佔用）混：換名字、改這一欄、重新登入都換不來放行，
  /// 要等的是發碼的人再給一枚有效碼。回應不回顯明文碼、驗證材料、是哪一枚或剩餘額度。
  /// 它不屬於 [retryable]：原樣重發同一枚無效碼不會讓它變好。
  inviteCodeRejected(2023),

  /// 2024：目標此刻不是一個可升級的訪戶（HTTP 409）——他已是普通帳戶（重複升級），
  /// 或他的登入能力此刻被停用。本次升級整個沒有發生：身分沒改、憑據沒落地、
  /// 會話沒撤、審計沒記。
  ///
  /// 介面必須把它與相鄰幾句分開，因為處置各不同：[guestUpgradeRequired]（2018）的
  /// 方向剛好相反——那句說「他是訪戶，重置口令要等升級通路」，而升級通路現在就是
  /// `/upgrade` 這條；[notFound]（1001）說「換個目標」，但這本目錄按定義把他列得進去；
  /// [permissionDenied]（2011）說「你的身分不夠」，而操作者的管理權確實足夠；
  /// [adminStatusConflict]（2014）說「重讀之後同一顆按鈕還可以再按」，而對已轉正的人
  /// 重讀之後的答案是那顆按鈕已不存在。處置是重讀這一筆的服務端現值再決定；
  /// 原樣重發不會讓它變好，所以也不屬於 [retryable]。後端不回顯目標現值，也不帶口令材料。
  guestNotUpgradable(2024);

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
      ApiMachineCode.notReady ||
      ApiMachineCode.requestTimeout ||
      ApiMachineCode.loginThrottled => true,
      // 落後一代：等更新的憑據就位後重試同一次操作即可，不需要重新登入。
      ApiMachineCode.sessionStale => true,
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
