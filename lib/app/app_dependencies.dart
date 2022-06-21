/// 啟動時裝配的依賴集合，以及向下暴露給子樹的容器。
///
/// 這裡是應用唯一的依賴組裝點：頁面不自行 new 基礎元件，也不直接取用平台能力。
/// 刻意不含本機時鐘來源——業務時間一律以伺服器回應中的 UTC 時間為準，
/// 本機時鐘不得影響業務判斷。
library;

import 'package:flutter/widgets.dart';

import '../core/runtime_status.dart';

/// 應用的裝配依賴。
@immutable
class AppDependencies {
  /// 以既定狀態建立依賴集合；未給狀態時使用「僅有建置資訊」的預設。
  const AppDependencies({
    this.runtimeStatus = const RuntimeStatus.informationOnly(),
  });

  /// 由編譯期資訊組裝的預設依賴（不含任何業務資料）。
  factory AppDependencies.assembled() {
    return const AppDependencies(
      runtimeStatus: RuntimeStatus.informationOnly(),
    );
  }

  /// 狀態條與頁面顯示用的執行期事實。
  final RuntimeStatus runtimeStatus;
}

/// 向子樹暴露 [AppDependencies] 的提供者。
class AppScope extends InheritedWidget {
  /// 建立依賴提供者。
  const AppScope({super.key, required this.dependencies, required super.child});

  /// 本子樹可用的依賴集合。
  final AppDependencies dependencies;

  /// 由最近的 [AppScope] 取得依賴；不存在時直接失敗，避免靜默降級。
  static AppDependencies of(BuildContext context) {
    final AppScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, '組件樹中找不到 AppScope：請經由 EvernightApp 啟動應用');
    return scope!.dependencies;
  }

  /// 由最近的 [AppScope] 取得依賴，不存在時回傳 `null`。
  static AppDependencies? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppScope>()?.dependencies;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return dependencies != oldWidget.dependencies;
  }
}
