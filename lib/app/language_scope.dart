/// 向子樹暴露介面語言設定的提供者。
///
/// 用 `InheritedNotifier` 而非第三方狀態管理庫：語言變更需要重建整棵樹的
/// 顯示文字，但不引入新的依賴。
library;

import 'package:flutter/widgets.dart';

import '../core/language_settings.dart';

/// 介面語言設定的作用域元件。
class LanguageScope extends InheritedNotifier<LanguageSettings> {
  /// 以設定與子樹建立作用域。
  // 父類 InheritedNotifier 的建構子非 const，此處無法宣告 const。
  // ignore: prefer_const_constructors_in_immutables
  LanguageScope({
    super.key,
    required LanguageSettings settings,
    required super.child,
  }) : super(notifier: settings);

  /// 由最近的 [LanguageScope] 取得設定；不存在時直接失敗。
  static LanguageSettings of(BuildContext context) {
    final LanguageScope? scope = context
        .dependOnInheritedWidgetOfExactType<LanguageScope>();
    assert(scope != null, '元件樹中找不到 LanguageScope：請經由 EvernightApp 啟動應用');
    return scope!.notifier!;
  }
}
