/// 會話憑據的持久化實作：把 [SessionPersistence] 的「按伺服器身份存取」翻譯成
/// 底層鍵值儲存的一個鍵，並守住三條界線——鍵綁定正規化身份、失敗一律上拋、
/// 形狀不合格一律當成「沒有」。
///
/// 之所以单独一层做鍵名，是因为「保存範圍綁定规范化后的服务器身份」是安全要求而非
/// 实作细节：一台伺服器一枚秘密，http↔https、不同埠、不同主机、不同路径前缀都算
/// 不同身份（[ServerAddress.displayText] 已把这些规范化进字串），换服务器即换键，
/// 旧键由控制器在切换时清除。键名沿用既有 `evernightrealm.` 前缀约定，不迁移、不复用
/// 伺服器位址設定那個鍵。
///
/// 值的形狀是 `<世代號>:<秘密>`：世代號是十進位整數，秘密是 base64url 字串
/// （字元集不含冒號），因此第一個冒號就是唯一的分隔點，不需要 escaping 也不需要 JSON。
library;

import '../core/session/session_persistence.dart';
import 'secure_key_value_store.dart';

/// 以鍵值儲存實作的會話憑據持久化。
class KeyedSessionPersistence implements SessionPersistence {
  /// 以底層鍵值儲存建立。
  const KeyedSessionPersistence(this._store);

  /// 會話憑據鍵的統一字首（含末尾連字元，與既有偏好鍵的命名風格一致）。
  static const String keyPrefix = 'evernightrealm.session.';

  /// 世代號與秘密之間的分隔字元：秘密的字元集（base64url）不含它，故無歧義。
  static const String separator = ':';

  final SecureKeyValueStore _store;

  /// 由正規化伺服器身份拼出儲存鍵。身份字串已是 `scheme://host[:port][/prefix]`，
  /// 不同协议、端口、主机或路径前缀天然是不同键，互不覆盖。
  static String keyFor(String serverIdentity) => '$keyPrefix$serverIdentity';

  /// 把憑據編成儲存字串。
  static String encode(SessionCredential credential) =>
      '${credential.rotationSeq}$separator${credential.secret}';

  /// 把儲存字串解回憑據；形狀不合格一律回 `null`。
  ///
  /// 「不合格就當成沒有」是刻意的：更早版本存的是裸秘密（沒有世代號），
  /// 猜它屬於第幾代等於讓一個倒序送達的舊輪換結果有機會蓋掉新憑據。
  /// 代價是升級後原生端要重新登入一次，這比猜錯安全。
  static SessionCredential? decode(String? stored) {
    if (stored == null || stored.isEmpty) {
      return null;
    }
    final int split = stored.indexOf(separator);
    if (split <= 0 || split == stored.length - 1) {
      return null;
    }
    final int? seq = int.tryParse(stored.substring(0, split));
    if (seq == null || seq < 0) {
      return null;
    }
    return SessionCredential(
      secret: stored.substring(split + 1),
      rotationSeq: seq,
    );
  }

  @override
  Future<SessionCredential?> readCredential(String serverIdentity) async {
    return decode(await _store.read(keyFor(serverIdentity)));
  }

  @override
  Future<void> writeCredential(
    String serverIdentity,
    SessionCredential credential,
  ) {
    return _store.write(keyFor(serverIdentity), encode(credential));
  }

  @override
  Future<void> clearCredential(String serverIdentity) {
    return _store.delete(keyFor(serverIdentity));
  }
}
