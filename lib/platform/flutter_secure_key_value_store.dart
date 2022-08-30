/// 以 `flutter_secure_storage` 為底的秘密鍵值實作：把系統級安全儲存（Android Keystore、
/// Apple Keychain、Linux libsecret、Windows DPAPI）包成 [SecureKeyValueStore]。
///
/// 這一层刻意薄到只轉接協定，不写任何會話語意：鍵名如何按伺服器身份構成、
/// 失敗如何呈現在會話層，都不在這裡决定。它只保证一件事——值一律進系統安全儲存，
/// 讀寫失敗一律上拋，绝不有「寫不進去就先存明文」这种降级路径（套件本身也无此选项）。
///
/// Web 不经过这里：瀏覽器端會話由 HttpOnly Cookie 代管，装配点（`main.dart`）根本
/// 不会在 Web 建立本實作，因此這套件的 Web 實作（localStorage）不会在本應用被初始化，
/// 秘密也就绝不会落进 LocalStorage。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_key_value_store.dart';

/// 用 [FlutterSecureStorage] 存取秘密鍵值。
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  /// 以一個 [FlutterSecureStorage] 實例建立；未給時用預設安全選項建立。
  ///
  /// 各平台的默认选项均为系统级加密（Android v11 走 Keystore 包裹金钥的 AES-GCM，
  /// 无明文回退开关；其余走各平台原生钥匙库），因此这里不额外放宽任何安全参数。
  const FlutterSecureKeyValueStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) {
    // 不吞异常：平台钥匙库不可用时必须让上层知道「读不到」，而不是当成「没有值」。
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) {
    // value 恒为非空秘密；空字串也不该发生，但交给套件处理，绝不在这里改写成明文占位。
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) {
    return _storage.delete(key: key);
  }
}
