/// 響應式佈局的斷點與內文寬度上限。
///
/// 移動優先：最小支援 360 px 寬（規格 UI-001），寬螢幕則限制內文寬度，
/// 避免一行文字拉得太長而難以閱讀。
library;

import 'dart:ui' show Size;

/// 版面斷點。
abstract final class Breakpoints {
  /// 窄於此寬度視為單欄緊湊版面。
  static const double compact = 600;

  /// 窄於此寬度視為中等版面，超過即寬版。
  static const double medium = 840;

  /// 內文最大寬度（不含頁面留白）。
  static const double contentMaxWidth = 720;

  /// 緊湊版面下語言列單行放不下的臨界寬度。
  static const double inlineControls = 420;

  /// 是否為單欄緊湊版面。
  static bool isCompact(Size size) => size.width < compact;

  /// 是否為中等版面（含緊湊）。
  static bool isMediumOrCompact(Size size) => size.width < medium;
}
