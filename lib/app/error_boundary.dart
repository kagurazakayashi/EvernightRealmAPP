/// 錯誤邊界：訂閱失敗收集器，把全畫面換成可返回的安全畫面。
///
/// 放在 `MaterialApp.builder` 的位置（導航器之上），理由是：出錯的可能是某個
/// 頁面、也可能是頁面裡的元件，只有蓋在整棵導航樹之上才一定遮得住。該位置的
/// `BuildContext` 已取得到本地化資源（實測確認），所以安全畫面能用使用者的語言。
///
/// 它自己不做任何判斷，只讀 [DiagnosticsHub.current]；失敗的產生與脫敏都在
/// 收集器與框架接點（`FlutterError.onError`、zone）那裡。
library;

import 'package:flutter/widgets.dart';

import '../core/diagnostics/app_failure.dart';
import '../core/diagnostics/diagnostics_hub.dart';
import 'widgets/safe_error_view.dart';

/// 失敗時接管整頁的邊界元件。
class ErrorBoundary extends StatelessWidget {
  /// 以收集器、導航器金鑰與受保護的子樹建立邊界。
  const ErrorBoundary({
    super.key,
    required this.diagnostics,
    required this.navigatorKey,
    required this.child,
  });

  /// 失敗收集器。
  final DiagnosticsHub diagnostics;

  /// 返回可用頁面時要操作的那個導航器。
  final GlobalKey<NavigatorState> navigatorKey;

  /// 受保護的子樹（正常情況下就是整個應用的導航內容）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: diagnostics,
      builder: (BuildContext context, Widget? child) {
        final AppFailure? failure = diagnostics.current;
        return Stack(
          children: <Widget>[
            if (child != null) Positioned.fill(child: child),
            if (failure != null)
              Positioned.fill(
                child: SafeErrorView(
                  failure: failure,
                  onReturn: _returnToSafety,
                ),
              ),
          ],
        );
      },
      child: child,
    );
  }

  /// 返回可用頁面：先清掉失敗狀態，再把導航堆疊清回起始路由。
  ///
  /// 順序有意如此——`recover()` 會記下「剛返回過哪一個失敗」，隨後的重建若
  /// 再次拋出同一個錯誤，安全畫面就能標成「返回沒用」，改口請使用者重新載入。
  void _returnToSafety() {
    diagnostics.recover();
    navigatorKey.currentState?.popUntil(
      (Route<dynamic> route) => route.isFirst,
    );
  }
}
