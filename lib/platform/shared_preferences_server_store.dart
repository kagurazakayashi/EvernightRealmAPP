/// 以 `shared_preferences` 實作的伺服器位址持久化。
///
/// 與介面語言的保存走同一套件與同一條抽象協定：Web 落到 localStorage、
/// 桌面與行動端落到平台設定檔，由套件的平台實作負責；本檔只關心鍵名與值型別。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/server_address_settings.dart';

/// 用共用偏好儲存伺服器位址。
class SharedPreferencesServerAddressStore implements ServerAddressPersistence {
  /// 建立持久化實作。
  const SharedPreferencesServerAddressStore();

  /// 伺服器位址使用的儲存鍵（含套件前綴，避免與他機設定相撞）。
  static const String storageKey = 'evernight_realm.server_base_url';

  @override
  Future<String?> readUrl() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? value = prefs.getString(storageKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  @override
  Future<void> writeUrl(String url) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, url);
  }

  @override
  Future<void> clearUrl() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
