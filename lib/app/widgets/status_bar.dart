/// 應用壳的狀態條：持續顯示版號、系統語系、伺服器位址與連線狀態。
///
/// 數值一律取自 [AppDependencies]，頁面不得自行宣稱連線結果；尚未具備的能力
/// 如實顯示「未設定」「未接上」，不以範例值填補。
library;

import 'package:flutter/material.dart';

import '../../core/app_copy.dart';
import '../../core/runtime_status.dart';
import '../app_dependencies.dart';

/// 狀態條中的單一欄位。
///
/// 標籤與數值一起以文字呈現，確保狀態不只靠顏色區分。
class StatusItem extends StatelessWidget {
  /// 以標籤與數值建立欄位。
  const StatusItem({
    super.key,
    required this.label,
    required this.value,
    required this.valueKey,
  });

  /// 欄位標籤。
  final String label;

  /// 欄位數值。
  final String value;

  /// 數值文字節點的測試與語意标识。
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label：', style: theme.textTheme.labelSmall),
        Text(
          value,
          key: valueKey,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 所有頁面共用的連線狀態條。
class ConnectionStatusBar extends StatelessWidget {
  /// 建立狀態條。
  const ConnectionStatusBar({super.key});

  /// 版號欄位的識別鍵。
  static const Key versionKey = ValueKey<String>('status-value-version');

  /// 系統語系欄位的識別鍵。
  static const Key localeKey = ValueKey<String>('status-value-locale');

  /// 伺服器位址欄位的識別鍵。
  static const Key serverKey = ValueKey<String>('status-value-server');

  /// 連線狀態欄位的識別鍵。
  static const Key connectionKey = ValueKey<String>('status-value-connection');

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final RuntimeStatus status = AppScope.of(context).runtimeStatus;
    final Locale systemLocale =
        WidgetsBinding.instance.platformDispatcher.locale;
    return Material(
      type: MaterialType.canvas,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Wrap(
            alignment: WrapAlignment.start,
            runSpacing: 4,
            spacing: 12,
            children: [
              StatusItem(
                label: AppCopy.statusVersionLabel,
                value: status.information.displayVersion,
                valueKey: versionKey,
              ),
              StatusItem(
                label: AppCopy.statusLocaleLabel,
                value: systemLocale.toLanguageTag(),
                valueKey: localeKey,
              ),
              StatusItem(
                label: AppCopy.statusServerLabel,
                value: status.serverAddressLabel,
                valueKey: serverKey,
              ),
              StatusItem(
                label: AppCopy.statusConnectionLabel,
                value: status.connectionLabel,
                valueKey: connectionKey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
