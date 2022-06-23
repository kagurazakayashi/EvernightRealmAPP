/// 產品支援的介面語言，以及「候選語言 → 實際介面語言」的解析規則。
///
/// 本檔是純邏輯：不讀設定、不碰平台，因此可直接被單元測試穷舉。
/// 語言選項的顯示名採「以該語言本身書寫」的慣例（简体中文／繁體中文（台灣）／
/// English／日本語），刻意不進本地化資源——換語言時選項名不應跟著變，
/// 否則使用者無法認出自己原本點的是哪一項。
library;

import 'dart:ui' show Locale;

/// 介面語言。
enum AppLocale {
  /// 簡體中文（大陸習慣），對應資源檔 `app_zh.arb`。
  zhCN(tag: 'zh-CN', locale: Locale('zh', 'CN'), endonym: '简体中文'),

  /// 繁體中文（台灣習慣），對應資源檔 `app_zh_TW.arb`。
  zhTW(tag: 'zh-TW', locale: Locale('zh', 'TW'), endonym: '繁體中文（台灣）'),

  /// 英文（美國），同時是缺鍵與未知語言的回退語言。
  enUS(tag: 'en-US', locale: Locale('en', 'US'), endonym: 'English'),

  /// 日文（日本），對應資源檔 `app_ja.arb`。
  jaJP(tag: 'ja-JP', locale: Locale('ja', 'JP'), endonym: '日本語');

  /// 以穩定標識、資源 Locale 與自稱名建立語言。
  const AppLocale({
    required this.tag,
    required this.locale,
    required this.endonym,
  });

  /// 持久化與顯示用的 BCP-47 標識（如 `zh-TW`）。
  final String tag;

  /// 交給 `MaterialApp.locale` 的 Locale。
  final Locale locale;

  /// 以該語言本身書寫的語言名（不做本地化）。
  final String endonym;

  /// 繁體中文適用的地區碼：台灣、香港、澳門。
  static const Set<String> traditionalRegions = {'TW', 'HK', 'MO'};

  /// 由持久化標識取回語言；無法辨識時回傳 `null`（視為未設定）。
  static AppLocale? fromTag(String? tag) {
    if (tag == null) {
      return null;
    }
    final String normalized = tag.trim().replaceAll('_', '-').toUpperCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final AppLocale candidate in AppLocale.values) {
      if (candidate.tag.toUpperCase() == normalized) {
        return candidate;
      }
    }
    return null;
  }
}

/// 由候選語言（已儲存的選擇或裝置語言）解析出實際使用的介面語言。
///
/// 規則：
/// 1. 中文先看書寫系統標記（`Hant` 繁體、`Hans` 簡體），無標記時依地區分流——
///    `TW`/`HK`/`MO` 用繁體，其餘中文（含 `CN`、`SG` 與無地區碼）用簡體；
/// 2. `en*` 用英文、`ja*` 用日文；
/// 3. 其他任何語言一律回退 `en-US`，不猜測未支援語言的文字。
AppLocale resolveAppLocale(Locale candidate) {
  final String language = candidate.languageCode.toLowerCase();
  final String script = (candidate.scriptCode ?? '').toUpperCase();
  final String region = (candidate.countryCode ?? '').toUpperCase();

  return switch (language) {
    'zh' => switch (true) {
      _ when script.startsWith('HANT') => AppLocale.zhTW,
      _ when script.startsWith('HANS') => AppLocale.zhCN,
      _ when AppLocale.traditionalRegions.contains(region) => AppLocale.zhTW,
      _ => AppLocale.zhCN,
    },
    'en' => AppLocale.enUS,
    'ja' => AppLocale.jaJP,
    _ => AppLocale.enUS,
  };
}
