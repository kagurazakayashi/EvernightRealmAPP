/// 頂層導航上下文的本地化標題與範圍說明。
///
/// 介面文字一律來自 ARB 產生的 [AppLocalizations]，切換語言後頁面名稱隨之改變；
/// 這裡用 switch 運算式對列舉值窮舉對應，新增上下文時會由編譯器提示補齊分支。
library;

import '../l10n/app_localizations.dart';
import 'nav_context.dart';

/// 依目前語言取得上下文的顯示文字。
extension NavContextLabels on NavContext {
  /// 目前語言下的頁面標題。
  String titleOf(AppLocalizations l10n) {
    return switch (this) {
      NavContext.serverEntry => l10n.serverEntryTitle,
      NavContext.rootConsole => l10n.rootConsoleTitle,
      NavContext.adminConsole => l10n.adminConsoleTitle,
      NavContext.npcConsole => l10n.npcConsoleTitle,
      NavContext.playerSurface => l10n.playerSurfaceTitle,
    };
  }

  /// 目前語言下的範圍說明。
  String summaryOf(AppLocalizations l10n) {
    return switch (this) {
      NavContext.serverEntry => l10n.serverEntrySummary,
      NavContext.rootConsole => l10n.rootConsoleSummary,
      NavContext.adminConsole => l10n.adminConsoleSummary,
      NavContext.npcConsole => l10n.npcConsoleSummary,
      NavContext.playerSurface => l10n.playerSurfaceSummary,
    };
  }
}
