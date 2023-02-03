/// 管理員端頁面。
///
/// 管理員以玩家身份進入活動時會切到玩家端上下文，管理操作與玩家操作上下文分離。
/// 本頁接線的伺服器級能力目前有三項，且後端只認「持有 server_admin 的受信主體」：
///
/// * 建立普通帳戶（[StandardAccountProvisionCard]）——受伺服器「管理員建立普通帳戶」
///   開關約束，開關關閉時由服務端在提交那一刻回話，界面不預讀、不猜。
/// * 普通帳戶目錄（[StandardAccountDirectoryCard]）——分頁與狀態／來源／名稱篩選的
///   答案全部取自服務端回應；這本目錄列不到管理員，也列不到 Root。
/// * 單筆詳情與顯示名編輯（[StandardAccountProfileCard]）——底稿按標識重讀，
///   保存走白名單＋compare-and-set；憑據、狀態與安全狀態不在這一頁可改。
///
/// 其餘管理端能力仍然沒有實作：普通帳戶的停用／重置／刪除、改角色、活動管理、名冊、
/// 資產與聊天都不在今天後端的端點裡，因此本頁以一行如實說明收尾，
/// 而不是擺一組按了不會有任何事的按鈕。
/// 目錄與詳情都是「資料變化後重新取服務端結果」：本頁只持有被選中的標識與一個重載計數，
/// 不持有任何一份當前資料——當前資料的唯一來源是那張卡的伺服器讀取。
library;

import 'package:flutter/material.dart';

import '../../app/app_dependencies.dart';
import '../../app/nav_context.dart';
import '../../app/nav_context_labels.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../l10n/app_localizations.dart';
import 'standard_account_directory_view.dart';
import 'standard_account_profile_view.dart';
import 'standard_account_provision_view.dart';

/// 管理員端頁面。
class AdminConsolePage extends StatefulWidget {
  /// 建立頁面。
  const AdminConsolePage({super.key});

  @override
  State<AdminConsolePage> createState() => _AdminConsolePageState();
}

class _AdminConsolePageState extends State<AdminConsolePage> {
  /// 目錄重載計數：建立與編輯成功都加一，讓清單以服務端的結果為準。
  int _reloadToken = 0;

  /// 當前展開詳情卡的帳戶標識。
  ///
  /// 這裡刻意只放標識而不放那份資料：詳情卡一律按標識重讀，
  /// 目錄行與本地印象都不夠格當編輯底稿。
  String? _selectedAccountId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    // 存取伺服器一律經裝配依賴的統一介面（DEC-020）：頁面不自建連線、不自判結果。
    final ServerApi api = AppScope.of(context).api;
    final String? selected = _selectedAccountId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            NavContext.adminConsole.summaryOf(l10n),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          StandardAccountProvisionCard(
            api: api,
            onCreated: () => setState(() => _reloadToken++),
          ),
          const SizedBox(height: 24),
          StandardAccountDirectoryCard(
            api: api,
            reloadToken: _reloadToken,
            onSelected: (StandardAccountReport account) =>
                setState(() => _selectedAccountId = account.accountId),
          ),
          if (selected != null) ...<Widget>[
            const SizedBox(height: 16),
            // 標識變動即重建整張卡：詳情卡不沿用上一個人的那份資料。
            StandardAccountProfileCard(
              key: ValueKey<String>(selected),
              api: api,
              accountId: selected,
              onClosed: () => setState(() => _selectedAccountId = null),
              onSaved: () => setState(() => _reloadToken++),
            ),
          ],
          const SizedBox(height: 24),
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
