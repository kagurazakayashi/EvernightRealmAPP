/// 本地 CJK 字體家族、資產路徑與載入入口。
///
/// 為什麼要自帶字體：Flutter Web 的 CanvasKit 無法取用作業系統字體，缺字時會向
/// `https://fonts.gstatic.com` 拉 Noto 系列，違反完全離線（規格 §29）且會被後端 CSP 攔阻。
/// 桌面與行動端由 Skia 直接使用系統字體，因此只在 Web 載入，且只載入目前語言需要的那一個檔案。
library;

import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

import 'app_locale.dart';

/// 字體相關常數與載入動作。
abstract final class AppFonts {
  /// 簡體中文用字族（含假名與全量漢字，可作其他語言的通用兼底）。
  static const String notoSansSc = 'Noto Sans SC';

  /// 繁體中文用字族。
  static const String notoSansTc = 'Noto Sans TC';

  /// 日文用字族。
  static const String notoSansJp = 'Noto Sans JP';

  /// 本進程已載入的字體家族（引擎未提供已載清單，自行記錄）。
  static final Set<String> _loadedFamilies = <String>{};

  /// 依介面語言選出應載入的字體家族。
  ///
  /// 英文介面仍需要一個 CJK 家族：語言選項以各語言本身書寫（簡體中文／繁體中文／日本語）。
  static String familyFor(AppLocale locale) {
    return switch (locale) {
      AppLocale.zhCN => notoSansSc,
      AppLocale.zhTW => notoSansTc,
      AppLocale.jaJP => notoSansJp,
      AppLocale.enUS => notoSansSc,
    };
  }

  /// 字體家族對應的資產路徑（pubspec 宣告的 `assets/fonts/`）。
  ///
  /// 檔名刻意不含方括號：AssetManifest 會把 `[` `]` 百分號編碼，而靜態伺服器
  /// 不解碼該名稱，實測會 404 導致字體載入失敗。
  static String assetFor(String family) {
    return switch (family) {
      notoSansTc => 'assets/fonts/NotoSansTC-wght.ttf',
      notoSansJp => 'assets/fonts/NotoSansJP-wght.ttf',
      _ => 'assets/fonts/NotoSansSC-wght.ttf',
    };
  }

  /// 該家族是否已載入。
  static bool isLoaded(String family) => _loadedFamilies.contains(family);

  /// 在 Web 載入指定字體家族；非 Web 平台或已載入時回傳 `false`。
  ///
  /// 回傳 `true` 代表這次呼叫完成了載入，呼叫端可據此重建以套用新字體。
  static Future<bool> loadFamily(String family) async {
    if (!kIsWeb || _loadedFamilies.contains(family)) {
      return false;
    }
    final Uint8List bytes = (await rootBundle.load(assetFor(family))).buffer
        .asUint8List();
    await ui.loadFontFromList(bytes, fontFamily: family);
    _loadedFamilies.add(family);
    return true;
  }
}
