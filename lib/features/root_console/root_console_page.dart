/// Root 控制台頁面。
///
/// Root 屬伺服器級上下文，與活動端導航嚴格隔離。本頁目前只有一項真的接了線的能力：
/// 開設伺服器級管理員帳戶，以及核實開出來的那個人（[AdminProvisionCard] 與
/// [AdminListCard]，全部經統一端點介面讀寫伺服器）。
///
/// 其餘 Root 域能力（總覽、運行日誌、備份與恢復的網頁化入口）仍然沒有實作，
/// 而且其中兩項按既定邊界永遠不會有 HTTP 入口——備份與恢復只有 `evernight-server`
/// 子命令，審計只由服務層寫入、沒有查詢端點。因此本頁以一行如實說明收尾，
/// 而不是擺一組按了不會有任何事的按鈕。
library;

import 'package:flutter/material.dart';

import '../../app/app_dependencies.dart';
import '../../app/nav_context.dart';
import '../../app/nav_context_labels.dart';
import '../../core/api/server_api.dart';
import '../../l10n/app_localizations.dart';
import 'admin_provision_view.dart';

/// Root 控制台頁面。
class RootConsolePage extends StatefulWidget {
  /// 建立頁面。
  const RootConsolePage({super.key});

  @override
  State<RootConsolePage> createState() => _RootConsolePageState();
}

class _RootConsolePageState extends State<RootConsolePage> {
  /// 開設成功後加一，作為確認清單的重新載入觸發器。
  ///
  /// 用計數而不是直接抓清單卡的 State 呼叫：清單卡自己決定「token 變了就重讀」，
  /// 頁面不需要認得它的內部結構，兩張卡也就不會因重構而互相依賴。
  int _reloadToken = 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    // 存取伺服器一律經裝配依賴的統一介面（DEC-020）：頁面不自建連線、不自判結果。
    final ServerApi api = AppScope.of(context).api;

    // 垂直滾動由應用殼統一承擔（DEC-020），因此內容是不滾動的 Column，
    // 也不出現 ListView／SingleChildScrollView。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            NavContext.rootConsole.summaryOf(l10n),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Text(
            l10n.rootConsoleAdminSectionTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          AdminProvisionCard(
            api: api,
            onCreated: () => setState(() => _reloadToken++),
          ),
          const SizedBox(height: 28),
          Text(l10n.adminListTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AdminListCard(api: api, reloadToken: _reloadToken),
          const SizedBox(height: 28),
          Text(
            l10n.rootConsoleRemainingNotice,
            key: const ValueKey<String>('root-console-remaining-notice'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
