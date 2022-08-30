/// 秘密鍵值儲存的抽象：會話儲存只依赖這個協定，真正的系統級實作可被注入取代。
///
/// 拆這一层的唯一目的是「可测」：控制器與會話儲存的邏輯（按伺服器身份分鍵、
/// 失败上拋、绝不降级明文）必须能在没有真实鑰匙圈的测试环境里被验证；
/// 而真正调用系统 API（Keystore／Keychain／libsecret／DPAPI）的那层留待各平台实机验证。
library;

/// 以字串鍵存取字串秘密的最小協定。
abstract interface class SecureKeyValueStore {
  /// 讀取鍵對應的秘密；不存在時回傳 `null`。
  ///
  /// 底層安全儲存不可用（例如 Linux 沒有運行的鑰匙圈服務）時上拋例外，
  /// 不回 `null`——`null` 只表示「這個鍵確實沒有值」。
  Future<String?> read(String key);

  /// 寫入鍵對應的秘密；失敗時上拋例外，絕不回退成明文。
  Future<void> write(String key, String value);

  /// 刪除鍵對應的秘密；鍵不存在時視為成功。失敗時上拋例外。
  Future<void> delete(String key);
}
