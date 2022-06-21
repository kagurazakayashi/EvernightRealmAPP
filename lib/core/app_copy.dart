/// 集中放置介面顯示用的文案與狀態標籤。
///
/// 本檔是介面文字的唯一來源。四語言資源機制建立後，本表內容整批遷入資源檔，
/// 呼叫端不改寫字串原則：頁面一律透過這裡的常數取字，不散落硬編碼文字。
library;

/// 介面文案常數。
abstract final class AppCopy {
  /// 品牌顯示名稱（各平台可見名，依根倉庫 §1.1 映射）。
  static const String appDisplayName = 'Evernight Realm';

  /// 狀態列：版號欄位標籤。
  static const String statusVersionLabel = '版號';

  /// 狀態列：建置通道欄位標籤。
  static const String statusChannelLabel = '通道';

  /// 狀態列：系統語系欄位標籤。
  static const String statusLocaleLabel = '系統語系';

  /// 狀態列：伺服器位址欄位標籤。
  static const String statusServerLabel = '伺服器';

  /// 狀態列：連線狀態欄位標籤。
  static const String statusConnectionLabel = '連線狀態';

  /// 未取得值時的顯示文字。
  static const String valueNotProvided = '未指定';

  /// 伺服器位址尚未設定時的顯示文字。
  static const String serverAddressNotSet = '尚未設定';

  /// 網路層尚未接上時的連線狀態文字。
  static const String connectionNotWired = '未接上（尚無網路層）';

  /// 尚未實作頁面的說明文字。
  static const String notWiredBody = '此頁面的後端能力尚未開發，因此不顯示任何內容，也不使用範例或模擬資料。';

  /// 尚未實作頁面的提示文字。
  static const String notWiredHint = '待後端提供資料後才會出現實際內容。';

  /// 未知路由頁面的標題。
  static const String unknownRouteTitle = '無法開啟此頁面';

  /// 未知路由頁面的說明文字。
  static const String unknownRouteBody = '要求的路由並不存在於導航表，或其所屬功能尚未開放。';
}
