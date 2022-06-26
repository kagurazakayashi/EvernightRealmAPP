/// 啟動護欄：把沒有人接住的錯誤收進同一個失敗收集器，而不是讓它變成紅框或無聲消失。
///
/// 三條來源各自對應 Flutter 的一種失敗方式：
/// * `FlutterError.onError`——框架在構建、佈局、繪製與平台通道上回報的錯誤；
/// * `ErrorWidget.builder`——上述錯誤發生後框架放進原位置的取代元件；
/// * `runZonedGuarded` 的第二個參數——非同步工作裡拋出而沒人接住的例外。
///
/// 全部只寫本機控制台與記憶體，**不發遙測、不發崩潰報告**（規格 SEC-014／ADR-015），
/// 也不開任何網路連線。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/diagnostics/app_failure.dart';
import '../core/diagnostics/diagnostics_hub.dart';

/// 框架錯誤取代元件：不含任何文字。
///
/// 它拿不到 `BuildContext`（`ErrorWidget.builder` 只給 `FlutterErrorDetails`），
/// 因此無法取本地化資源、也無法取字型；在這裡放文字會有兩個後果——可能觸發
/// CanvasKit 線上取字（違反完全離線），也可能把未脫敏的異常內容顯示出來。
/// 真正要給使用者看的說明由 [ErrorBoundary] 的安全畫面負責，這裡只留一塊透明區域。
class SilentErrorPlaceholder extends StatelessWidget {
  /// 建立透明佔位。
  const SilentErrorPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(color: Color(0x00000000)),
    );
  }
}

/// 把框架的兩個錯誤接點接到 [diagnostics] 上。
///
/// 獨立成一個函式是為了可測：元件測試可以直接呼叫它，再故意拋出例外來驗證
/// 安全畫面真的會出現，不必把整個 `runApp` 跑一遍。
void installFrameworkErrorCapture(DiagnosticsHub diagnostics) {
  FlutterError.onError = (FlutterErrorDetails details) {
    diagnostics.reportFlutterError(details);
  };
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      const SilentErrorPlaceholder();
}

/// 以護欄包住應用啟動。
///
/// [body] 內必須先 `WidgetsFlutterBinding.ensureInitialized()` 再 `runApp`，
/// 兩者都留在同一個 zone 裡，否則綁定階段的例外不會被這裡接住。
void bootstrapApp({
  required DiagnosticsHub diagnostics,
  required FutureOr<void> Function() body,
}) {
  runZonedGuarded<void>(
    () {
      installFrameworkErrorCapture(diagnostics);
      Future<void>.sync(body).catchError((Object error, StackTrace stack) {
        // 啟動流程自己失敗（例如讀本地設定時拋錯）也算未處理錯誤。
        diagnostics.report(
          error,
          kind: AppFailureKind.uncaughtAsync,
          stack: stack,
          library: 'bootstrap',
        );
      });
    },
    (Object error, StackTrace stack) {
      diagnostics.report(
        error,
        kind: AppFailureKind.uncaughtAsync,
        stack: stack,
        library: 'zone',
      );
    },
  );
}
