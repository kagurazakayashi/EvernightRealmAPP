/// 向子树暴露會話状态的提供者。
///
/// 与連線追蹤器同一手法：用 `InheritedNotifier` 而非第三方状态库，控制器的生命週期
/// 由组装点（`main`）负责，本元件只是订阅者，离开作用域不 disposing。页面经
/// [SessionScope.of] 读状态、呼叫登入／登出流程，从而不存在「各畫面各写一套會話逻辑」。
library;

import 'package:flutter/widgets.dart';

import '../core/session/session_controller.dart';

/// 會話状态的作用域元件。
class SessionScope extends InheritedNotifier<SessionController> {
  /// 以控制器与子树建立作用域。
  // 父类 InheritedNotifier 的建构子非 const，此处无法宣告 const。
  // ignore: prefer_const_constructors_in_immutables
  SessionScope({
    super.key,
    required SessionController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 由最近的 [SessionScope] 取得控制器；不存在时直接失败，避免静默降级。
  static SessionController of(BuildContext context) {
    final SessionScope? scope = context
        .dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, '元件树中找不到 SessionScope：请经由 EvernightApp 启动应用');
    return scope!.notifier!;
  }
}
