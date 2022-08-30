/// 會話秘密的持久化實作：把 [SessionPersistence] 的「按伺服器身份存取」翻译成
/// 底層鍵值儲存的一個鍵，並守住兩條界線——鍵綁定正規化身份、失敗一律上拋。
///
/// 之所以单独一层做鍵名，是因为「保存範圍綁定规范化后的服务器身份」是安全要求而非
/// 实作细节：一台伺服器一枚秘密，http↔https、不同埠、不同主机、不同路径前缀都算
/// 不同身份（[ServerAddress.displayText] 已把这些规范化进字串），换服务器即换键，
/// 旧键由控制器在切换时清除。键名沿用既有 `evernightrealm.` 前缀约定，不迁移、不复用
/// 伺服器位址設定那個鍵。
library;

import '../core/session/session_persistence.dart';
import 'secure_key_value_store.dart';

/// 以鍵值儲存實作的會話秘密持久化。
class KeyedSessionPersistence implements SessionPersistence {
  /// 以底層鍵值儲存建立。
  const KeyedSessionPersistence(this._store);

  /// 會話秘密键的统一前缀（含末尾连字符，与既有偏好键的命名风格一致）。
  static const String keyPrefix = 'evernightrealm.session.';

  final SecureKeyValueStore _store;

  /// 由正規化伺服器身份拼出儲存鍵。身份字串已是 `scheme://host[:port][/prefix]`，
  /// 不同协议、端口、主机或路径前缀天然是不同键，互不覆盖。
  static String keyFor(String serverIdentity) => '$keyPrefix$serverIdentity';

  @override
  Future<String?> readSecret(String serverIdentity) {
    return _store.read(keyFor(serverIdentity));
  }

  @override
  Future<void> writeSecret(String serverIdentity, String secret) {
    return _store.write(keyFor(serverIdentity), secret);
  }

  @override
  Future<void> clearSecret(String serverIdentity) {
    return _store.delete(keyFor(serverIdentity));
  }
}
