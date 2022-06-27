/// 位址格式問題的介面文字映射：把 [ServerAddressIssue] 對應到當地語言的說明。
///
/// 與錯誤碼映射同一條規則——資料層只保存機器分類（DEC-017），顯示文字一律取自
/// 本地化資源。這裡是「格式錯誤有可理解提示」的唯一出口：卡片不自己拼句子，
/// 因此四語言不會出現兩種說法。
library;

import '../core/api/server_address.dart';
import '../l10n/app_localizations.dart';

/// 回傳該格式問題要對使用者說的那句話；[issue] 為 `null` 或合格時回傳 `null`。
String? addressIssueLabel(AppLocalizations l10n, ServerAddressIssue? issue) {
  return switch (issue) {
    null || ServerAddressIssue.ok => null,
    ServerAddressIssue.empty => l10n.addressIssueEmpty,
    ServerAddressIssue.missingScheme => l10n.addressIssueMissingScheme,
    ServerAddressIssue.unsupportedScheme => l10n.addressIssueUnsupportedScheme,
    ServerAddressIssue.embeddedWhitespace => l10n.addressIssueWhitespace,
    ServerAddressIssue.unresolved => l10n.addressIssueUnresolved,
    ServerAddressIssue.hostMissing => l10n.addressIssueHostMissing,
    ServerAddressIssue.credentials => l10n.addressIssueCredentials,
    ServerAddressIssue.queryOrFragment => l10n.addressIssueQueryOrFragment,
  };
}
