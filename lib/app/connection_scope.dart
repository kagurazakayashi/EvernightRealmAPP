/// 向子樹暴露連線探測狀態的提供者。
///
/// 用 `InheritedNotifier` 而非第三方狀態管理庫：探測結果需要同時驅動狀態條與
/// 探測區，但不引入新的依賴。追蹤器的生命週期由組裝點（`main`）負責，
/// 本元件只是訂閱者，離開作用域時不 disposing。
library;

import 'package:flutter/widgets.dart';

import '../core/api/connection_tracker.dart';

/// 連線探測狀態的作用域元件。
class ConnectionScope extends InheritedNotifier<ConnectionTracker> {
  /// 以追蹤器與子樹建立作用域。
  // 父類 InheritedNotifier 的建構子非 const，此處無法宣告 const。
  // ignore: prefer_const_constructors_in_immutables
  ConnectionScope({
    super.key,
    required ConnectionTracker tracker,
    required super.child,
  }) : super(notifier: tracker);

  /// 由最近的 [ConnectionScope] 取得追蹤器；不存在時直接失敗，避免靜默降級。
  static ConnectionTracker of(BuildContext context) {
    final ConnectionScope? scope = context
        .dependOnInheritedWidgetOfExactType<ConnectionScope>();
    assert(scope != null, '元件樹中找不到 ConnectionScope：請經由 EvernightApp 啟動應用');
    return scope!.notifier!;
  }
}
