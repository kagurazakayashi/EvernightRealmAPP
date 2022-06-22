/// 應用殼的狀態條：持續顯示版號、系統語系、伺服器位址與連線狀態。
///
/// 數值一律取自 [AppDependencies]，頁面不得自行宣稱連線結果；尚未具備的能力
/// 如實顯示未設定與未接上，不以範例值填補。標籤與「標籤：數值」的組合格式
/// 全部取自本地化資源。
library;

import 'package:flutter/material.dart';

import '../../core/app_information.dart';
import '../../core/runtime_status.dart';
import '../../l10n/app_localizations.dart';
import '../app_dependencies.dart';

/// 狀態條中的單一欄位。
///
/// 標籤與數值以當地語言的組合格式一起呈現，確保狀態不只靠顏色區分。
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

  /// 數值文字節點的測試與語意標識。
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Text(
      l10n.labelValuePair(label, value),
      key: valueKey,
      style: theme.textTheme.labelSmall,
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RuntimeStatus status = AppScope.of(context).runtimeStatus;
    final AppInformation information = status.information;
    // 系統語系取裝置設定，與介面目前使用的語言是兩件事。
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
                label: l10n.statusVersionLabel,
                value: information.hasBuildVersion
                    ? information.buildVersion
                    : l10n.valueNotProvided,
                valueKey: versionKey,
              ),
              StatusItem(
                label: l10n.statusLocaleLabel,
                value: systemLocale.toLanguageTag(),
                valueKey: localeKey,
              ),
              StatusItem(
                label: l10n.statusServerLabel,
                value: status.hasServerAddress
                    ? status.serverAddress!
                    : l10n.serverAddressNotSet,
                valueKey: serverKey,
              ),
              StatusItem(
                label: l10n.statusConnectionLabel,
                value: switch (status.connection) {
                  ServerConnectionState.notWired => l10n.connectionNotWired,
                },
                valueKey: connectionKey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
