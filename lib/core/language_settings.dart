/// 介面語言設定的狀態與持久化協定。
///
/// 這裡不直接依賴任何儲存套件：持久化以 [LanguagePersistence] 抽象表示，
/// 實作放在 `lib/platform/`，因此本檔可在測試中以假實作取代。
library;

import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import 'app_locale.dart';

/// 介面語言選擇的持久化協定。
abstract interface class LanguagePersistence {
  /// 讀取已儲存的語言標識；未設定時回傳 `null`。
  Future<String?> readTag();

  /// 寫入語言標識；傳入 `null` 代表取消手工選擇、改回跟隨系統。
  Future<void> writeTag(String? tag);
}

/// 介面語言設定：未設定時跟隨系統語言，設定後固定使用該語言。
///
/// 語言只改變介面文字，不改變任何業務狀態；業務時間與資料一律以伺服器回應為準。
class LanguageSettings extends ChangeNotifier {
  /// 以持久化協定（位置引數）與裝置語言（可選）建立設定。
  LanguageSettings(this._persistence, {Locale? systemLocale})
    : _systemLocale = systemLocale ?? const Locale('en');

  final LanguagePersistence _persistence;

  Locale _systemLocale;

  AppLocale? _selected;

  /// 裝置目前使用的語言（由装配層讀取平台後給定）。
  Locale get systemLocale => _systemLocale;

  /// 是否尚未手工選擇語言（true 表示跟隨系統語言）。
  bool get followsSystem => _selected == null;

  /// 實際生效的介面語言。
  AppLocale get effective => _selected ?? resolveAppLocale(_systemLocale);

  /// 交給 `MaterialApp.locale` 的 Locale。
  Locale get effectiveLocale => effective.locale;

  /// 從持久化載入先前的選擇；無法辨識的標識視為未設定。
  Future<void> restore() async {
    _selected = AppLocale.fromTag(await _persistence.readTag());
    notifyListeners();
  }

  /// 切換介面語言並寫入持久化；寫入成功後才更新狀態。
  ///
  /// [locale] 為 `null` 時取消手工選擇、改回跟隨系統語言。
  Future<void> select(AppLocale? locale) async {
    await _persistence.writeTag(locale?.tag);
    _selected = locale;
    notifyListeners();
  }

  /// 更新裝置語言（供平台語言變更或測試使用）；已手工選擇時不影響生效語言。
  void updateSystemLocale(Locale locale) {
    if (_systemLocale.toLanguageTag() == locale.toLanguageTag()) {
      return;
    }
    _systemLocale = locale;
    if (followsSystem) {
      notifyListeners();
    }
  }
}
