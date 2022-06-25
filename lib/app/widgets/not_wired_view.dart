/// 頂層上下文的共用內容視圖：說明該上下文的範圍，並如實標明後端尚未實作。
///
/// 這裡刻意不放任何範例、模擬或佔位的業務資料（清單、餘額、玩家名稱等一律不出現），
/// 讓「尚未開發」在介面上是可讀的事實，而不是看起來像已運作的空殼。
/// 顯示文字全部取自本地化資源，本檔不出現任何語言的硬編碼字串。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../nav_context.dart';
import '../nav_context_labels.dart';

/// 「後端尚未實作」的內容視圖。
class NotWiredView extends StatelessWidget {
  /// 顯示某個頂層上下文的範圍與未實作狀態。
  const NotWiredView.forContext(this.navContext, {super.key})
    : routeName = null;

  /// 顯示未登記路由的回退說明。
  const NotWiredView.forUnknownRoute(this.routeName, {super.key})
    : navContext = null;

  /// 要顯示的頂層上下文；為 `null` 時顯示 [routeName] 的回退說明。
  final NavContext? navContext;

  /// 未登記的路由名稱；為 `null` 時顯示 [navContext] 的說明。
  final String? routeName;

  /// 狀態說明的測試識別鍵。
  static const Key bodyKey = ValueKey<String>('not-wired-body');

  /// 內容欄的識別鍵（佈局測試據此量測內文寬度）。
  static const Key contentKey = ValueKey<String>('not-wired-content');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NavContext? navContext = this.navContext;
    final String detail = navContext != null
        ? navContext.summaryOf(l10n)
        : l10n.unknownRouteDetail(routeName ?? '');
    final String body = navContext != null
        ? l10n.notWiredBody
        : l10n.unknownRouteBody;

    final ThemeData theme = Theme.of(context);
    // 垂直滾動由應用殼統一負責，這裡因此是純 Column 而不是清單元件；
    // stretch 讓寬度等於殼給定的內文寬度，窄屏換行、寬屏不拉成長行。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        key: contentKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(detail, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 20),
          Text(body, key: bodyKey, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(l10n.notWiredHint, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
