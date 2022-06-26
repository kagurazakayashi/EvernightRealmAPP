/// 未處理錯誤的安全畫面：蓋住已損壞的內容，給出一條回得了的路。
///
/// 三個要求直接對應完成判斷：
/// 1. **使用者可返回可用頁面**——唯一的動作就是回到起始路由並清掉失敗狀態；
/// 2. **畫面不洩露憑證**——只顯示類別、本機診斷碼與請求關聯 ID，不顯示原始
///    異常文字、堆疊、基準位址或任何請求內容；
/// 3. 同一個失敗在返回後立刻重現時，改口請使用者重新載入，而不是假裝返回有用。
library;

import 'package:flutter/material.dart';

import '../../core/diagnostics/app_failure.dart';
import '../../core/layout_breakpoints.dart';
import '../../l10n/app_localizations.dart';
import '../app_failure_labels.dart';

/// 全畫面的失敗呈現。
class SafeErrorView extends StatelessWidget {
  /// 以失敗記錄與返回動作建立畫面。
  const SafeErrorView({
    super.key,
    required this.failure,
    required this.onReturn,
  });

  /// 要呈現的失敗記錄。
  final AppFailure failure;

  /// 使用者選擇返回可用頁面。
  final VoidCallback onReturn;

  /// 返回按鈕的測試識別鍵。
  static const Key returnKey = ValueKey<String>('safe-error-return');

  /// 診斷列的測試識別鍵。
  static const Key diagnosticsKey = ValueKey<String>('safe-error-diagnostics');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Material(
      // 覆蓋在套裝內容之上：用 surface 而不是透明色，避免露出已損壞的畫面。
      type: MaterialType.canvas,
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Align(
          alignment: Alignment.center,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Breakpoints.contentMaxWidth,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(height: 12),
                  Text(
                    l10n.safeErrorTitle,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    failureKindLabel(l10n, failure.kind),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(l10n.safeErrorBody, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Wrap(
                    // 鍵放在這一層而不是每一行：診斷至少兩條（診斷碼＋可能的關聯 ID），
                    // 逐行掛同一個 Key 會觸發「Duplicate keys found」，讓安全畫面自己崩掉。
                    key: diagnosticsKey,
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      for (final String line in failureDiagnostics(
                        l10n,
                        failure,
                      ))
                        Text(line, style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 40,
                    child: FilledButton(
                      key: returnKey,
                      onPressed: onReturn,
                      child: Text(l10n.safeErrorReturnAction),
                    ),
                  ),
                  if (failure.repeated) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      l10n.safeErrorRepeatedHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
