/// 會話憑據的持久化協定：把「原生端把憑據放哪」這件事抽象成協定，實作在 `lib/platform/`。
///
/// 這層抽象存在的理由有三：
/// 1. 核心不依賴任何儲存套件（與介面語言、位址設定同一取向），控制器可直接以
///    記憶體替身做測試，包括「寫入失敗」「讀取失敗」這類真機上難以穩定重現的路徑。
/// 2. 憑據的儲存範圍以「正規化後的伺服器身份」為鍵：一臺伺服器一枚憑據，彼此隔離，
///    從協定層就排除「所有伺服器共用一枚」或「按登入名存」這類會串台的鍵法。
/// 3. 失敗必須如實上拋：實作不得在安全儲存不可用时降級成明文落盤，也不得吞掉錯誤
///    回一個假的成功——那會把「沒存住」偽裝成「已登出」。
///
/// 儲存的單位是 [SessionCredential]（秘密＋世代號）而不是裸秘密：秘密輪換之後，
/// 「這枚秘密是第幾代」與秘密本身同等重要——少了世代號，重啟後就無法判出
/// 手上這枚是不是已經被更新的憑據取代，也無法拒絕一個倒序送達的舊輪換結果。
library;

/// 一枚可回傳給伺服器的會話憑據：秘密本身，加上它所屬的世代號。
///
/// [rotationSeq] 是伺服器給的計數器（每次輪換加一，登入簽發的新會話為 0），
/// 不是秘密、不含任何可推導秘密的資訊，因此可以與秘密一同儲存與比較。
class SessionCredential {
  /// 以秘密與世代號建立憑據。
  const SessionCredential({required this.secret, required this.rotationSeq});

  /// 會話秘密明文（一次性露出，只經安全儲存與 `Authorization` 標頭）。
  final String secret;

  /// 這枚秘密的世代號；越小越舊。
  final int rotationSeq;

  /// 是否比 [other] 更新（世代號嚴格較大）。
  ///
  /// 相等不算更新：同一代的兩個回應描述的是同一枚憑據，沒有誰該蓋掉誰，
  /// 而「倒序送達的舊回應不得覆蓋新憑據」這條規則需要的是嚴格比較。
  bool isNewerThan(SessionCredential other) => rotationSeq > other.rotationSeq;

  @override
  String toString() => 'SessionCredential(seq=$rotationSeq)';
}

/// 以伺服器身份為鍵存取會話憑據的協定。
abstract interface class SessionPersistence {
  /// 讀取指定伺服器身份對應的會話憑據；未儲存過時回傳 `null`。
  ///
  /// 讀取失敗（例如 Linux 沒有可用的鑰匙圈服務）一律上拋例外，不回 `null`——
  /// `null` 的語意是「這台沒有已登入的會話」，把「查不到」說成「沒有」會讓控制器
  /// 無緣無故把一個本來有效的會話當成正未登入。
  ///
  /// 儲存內容不是本協定認得的形狀時（例如更早版本留下的裸秘密）也回 `null`：
  /// 寧可請人重新登入一次，也不猜一枚憑據屬於第幾代。
  Future<SessionCredential?> readCredential(String serverIdentity);

  /// 寫入指定伺服器身份的會話憑據。
  ///
  /// 實作只能把它交給系統級安全儲存；寫入失敗時上拋例外，絕不回退成明文儲存。
  Future<void> writeCredential(
    String serverIdentity,
    SessionCredential credential,
  );

  /// 移除指定伺服器身份的會話憑據；該身份本就沒有憑據時視為成功（不拋錯）。
  Future<void> clearCredential(String serverIdentity);
}
