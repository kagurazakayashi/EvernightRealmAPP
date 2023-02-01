/// 管理員端頁面。
///
/// 管理員以玩家身份進入活動時會切到玩家端上下文，管理操作與玩家操作上下文分離。
/// 本頁目前接線的伺服器級能力只有一項，且後端只認「持有 server_admin 的受信主體」：
///
/// * 建立普通帳戶（[StandardAccountProvisionCard]）——受伺服器「管理員建立普通帳戶」
///   開關約束，開關關閉時由服務端在提交那一刻回話，界面不預讀、不猜。
///
/// 其餘管理端能力仍然沒有實作：活動管理、名冊、資產與聊天都不在今天後端的端點裡，
/// 因此本頁以一行如實說明收尾，而不是擺一組按了不會有任何事的按鈕。
/// 新建的普通帳戶此刻只是一個 Account：他登入後看到的空狀態是伺服器的真實答案，
/// 本應用不冒充已配置的活動大廳。
library;

import 'package:flutter/material.dart';

import '../../app/app_dependencies.dart';
import '../../app/nav_context.dart';
import '../../app/nav_context_labels.dart';
import '../../core/api/server_api.dart';
import '../../l10n/app_localizations.dart';
import 'standard_account_provision_view.dart';

/// 管理員端頁面。
class AdminConsolePage extends StatelessWidget {
  /// 建立頁面。
  const AdminConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    // 存取伺服器一律經裝配依賴的統一介面（DEC-020）：頁面不自建連線、不自判結果。
    final ServerApi api = AppScope.of(context).api;

    // 垂直滾動由應用殼統一承擔（DEC-020），因此內容是不滾動的 Column。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            NavContext.adminConsole.summaryOf(l10n),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          StandardAccountProvisionCard(api: api),
          const SizedBox(height: 28),
          Text(
            l10n.adminConsoleRemainingNotice,
            key: const ValueKey<String>('admin-console-remaining-notice'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
