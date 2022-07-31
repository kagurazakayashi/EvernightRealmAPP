/// 以 `shared_preferences` 實作的介面語言持久化。
///
/// 同一份協定在 Web 落到 localStorage、在桌面落到平台設定檔，
/// 由套件的平台實作負責；本檔只关心鍵名與值型別。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/language_settings.dart';

/// 用共用偏好儲存介面語言選擇。
class SharedPreferencesLanguageStore implements LanguagePersistence {
  /// 建立持久化實作。
  const SharedPreferencesLanguageStore();

  /// 介面語言選擇使用的儲存鍵（含套件前綴，避免與他機設定相撞）。
  static const String storageKey = 'evernightrealm.interface_locale';

  @override
  Future<String?> readTag() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? value = prefs.getString(storageKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  @override
  Future<void> writeTag(String? tag) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (tag == null) {
      await prefs.remove(storageKey);
      return;
    }
    await prefs.setString(storageKey, tag);
  }
}
