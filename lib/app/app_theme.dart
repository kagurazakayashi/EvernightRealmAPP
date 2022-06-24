/// 應用主題：同時提供淺色與深色（規格 §37.2），並統一文字比例與字體。
///
/// 品牌色與專屬字型屬後續品牌步驟，這裡只用 Material 3 預設色板；
/// Web 端必須指定本地 CJK 字體家族，否則 CanvasKit 會向線上服務取字。
library;

import 'package:flutter/material.dart';

/// 主題建構入口。
abstract final class AppTheme {
  /// 淺色主題；[fontFamily] 非空時整套文字都使用該家族（Web 本地字體）。
  static ThemeData light({String? fontFamily}) =>
      _build(Brightness.light, fontFamily);

  /// 深色主題。
  static ThemeData dark({String? fontFamily}) =>
      _build(Brightness.dark, fontFamily);

  /// 依亮度與可選字體家族組主題。
  static ThemeData _build(Brightness brightness, String? fontFamily) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
    );
  }
}
