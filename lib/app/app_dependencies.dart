/// 啟動時裝配的依賴集合，以及向下暴露給子樹的容器。
///
/// 這裡是應用唯一的依賴組裝點：頁面不自行 new 基礎元件，也不直接取用平台能力。
/// 存取伺服器一律經由 [AppDependencies.api]，頁面不得自行建立網路連線或判定請求結果。
/// 刻意不含本機時鐘來源——業務時間一律以伺服器回應中的 UTC 時間為準，
/// 本機時鐘不得影響業務判斷。
library;

import 'package:flutter/widgets.dart';

import '../core/api/api_client.dart';
import '../core/api/server_address.dart';
import '../core/api/server_api.dart';
import '../core/runtime_status.dart';

/// 應用的裝配依賴。
@immutable
class AppDependencies {
  /// 以既定狀態與端點存取介面建立依賴集合。
  const AppDependencies({
    this.runtimeStatus = const RuntimeStatus.informationOnly(),
    this.api = const ServerApi(),
  });

  /// 由位址來源裝配的預設依賴（不含任何業務資料）。
  ///
  /// 端點介面只拿到「去哪取位址」這件事而不複制位址文字：使用者改過地址後
  /// 不需要重建依賴集合，也不會出現新舊兩份基準位址。未給來源時退回編譯期
  /// 注入值，供尚未接入使用者設定的場合（工具腳本、只看文字的測試）使用。
  factory AppDependencies.assembled({ServerAddressSource? addresses}) {
    return AppDependencies(
      runtimeStatus: const RuntimeStatus.informationOnly(),
      api: ServerApi(
        config: ServerApiConfig(
          source: addresses ?? const InjectedServerAddressSource(),
        ),
      ),
    );
  }

  /// 狀態條與頁面顯示用的執行期事實。
  final RuntimeStatus runtimeStatus;

  /// 基礎端點的統一存取介面。
  final ServerApi api;
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
