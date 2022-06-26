/// 未處理錯誤記錄到介面文字的對照。
///
/// 畫面只說「發生在哪一類位置」與語言無關的診斷碼，**不顯示原始異常文字、
/// 不顯示堆疊、不顯示位址**——那些東西可能含憑證，且對使用者沒有意義。
library;

import '../core/diagnostics/app_failure.dart';
import '../l10n/app_localizations.dart';

/// 取得失敗類別的介面文字（把五種來源收成三句使用者聽得懂的話）。
String failureKindLabel(AppLocalizations l10n, AppFailureKind kind) {
  return switch (kind) {
    AppFailureKind.widgetBuild => l10n.safeErrorKindUi,
    AppFailureKind.frameworkReport ||
    AppFailureKind.unknown => l10n.safeErrorKindBackground,
    AppFailureKind.uncaughtAsync => l10n.safeErrorKindBackground,
    AppFailureKind.apiCall => l10n.safeErrorKindServer,
  };
}

/// 取得診斷行：本機診斷碼一律顯示，請求關聯 ID 有就顯示。
List<String> failureDiagnostics(AppLocalizations l10n, AppFailure failure) {
  return <String>[
    l10n.labelValuePair(
      l10n.safeErrorDiagnosticCodeLabel,
      failure.diagnosticCode,
    ),
    if (failure.requestId != null && failure.requestId!.isNotEmpty)
      l10n.labelValuePair(l10n.diagnosticRequestId, failure.requestId!),
  ];
}
