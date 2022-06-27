/// 向子樹暴露伺服器位址設定的提供者。
///
/// 用 `InheritedNotifier` 而非第三方狀態管理庫：位址變更需要同時刷新狀態條、
/// 位址卡片與探測區，但不引入新的依賴。設定物件的生命週期由組裝點（`main`）負責。
library;

import 'package:flutter/widgets.dart';

import '../core/api/server_address_settings.dart';

/// 伺服器位址設定的作用域元件。
class AddressScope extends InheritedNotifier<ServerAddressSettings> {
  /// 以設定與子樹建立作用域。
  // 父類 InheritedNotifier 的建構子非 const，此處無法宣告 const。
  // ignore: prefer_const_constructors_in_immutables
  AddressScope({
    super.key,
    required ServerAddressSettings settings,
    required super.child,
  }) : super(notifier: settings);

  /// 由最近的 [AddressScope] 取得設定；不存在時直接失敗，避免靜默降級。
  static ServerAddressSettings of(BuildContext context) {
    final AddressScope? scope = context
        .dependOnInheritedWidgetOfExactType<AddressScope>();
    assert(scope != null, '元件樹中找不到 AddressScope：請經由 EvernightApp 啟動應用');
    return scope!.notifier!;
  }
}
