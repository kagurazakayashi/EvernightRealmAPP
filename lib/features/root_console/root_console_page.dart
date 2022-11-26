/// Root 控制台頁面。
///
/// Root 屬伺服器級上下文，與活動端導航嚴格隔離。本頁目前接線的 Root 域能力有三項，
/// 全部經統一端點介面讀寫伺服器，且後端對每一項都只認 Root 的受信主體：
///
/// * 開設伺服器級管理員帳戶（[AdminProvisionCard]）；
/// * 分頁瀏覽管理員目錄與狀態篩選（[AdminDirectoryCard]）；
/// * 單筆詳情與顯示名的白名單編輯（[AdminProfileCard]）。
///
/// 目錄由「確認清單」升級而來：它是只含管理員 Account 的目錄——配置 Root 不是
/// accounts 表裡的一行，也就不會被偽裝成一條可被普通帳戶接口編輯的記錄。
/// 詳情卡的底稿一律按標識重讀服務端單筆真相，目錄行只當入口。
///
/// 其餘 Root 域能力仍然沒有實作，而且其中兩項按既定邊界永遠不會有 HTTP 入口——
/// 備份與恢復只有 `evernight-server` 子命令，審計只由服務層寫入、沒有查詢端點。
/// 改角色、停用、刪除與重置憑據也不在本步開放。因此本頁以一行如實說明收尾，
/// 而不是擺一組按了不會有任何事的按鈕。
library;

import 'package:flutter/material.dart';

import '../../app/app_dependencies.dart';
import '../../app/nav_context.dart';
import '../../app/nav_context_labels.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../l10n/app_localizations.dart';
import 'admin_directory_view.dart';
import 'admin_profile_view.dart';
import 'admin_provision_view.dart';

/// Root 控制台頁面。
class RootConsolePage extends StatefulWidget {
  /// 建立頁面。
  const RootConsolePage({super.key});

  @override
  State<RootConsolePage> createState() => _RootConsolePageState();
}

class _RootConsolePageState extends State<RootConsolePage> {
  /// 開設或編輯成功後加一，作為目錄的重新載入觸發器。
  ///
  /// 用計數而不是直接抓目錄卡的 State 呼叫：卡自己決定「token 變了就重讀」，
  /// 頁面不需要認得卡的內部結構，幾張卡也就不會因重構而互相依賴。
  int _reloadToken = 0;

  /// 目前開啟詳情的帳戶標識；null 表示沒有詳情卡。
  ///
  /// 只保存標識而不保存整行資料：詳情的一切展示值都歸詳情卡自己按標識重讀，
  /// 頁面拿不到、也不該拿目錄行去「代填」當前資料。
  String? _selectedAccountId;

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
          Text(
            l10n.rootConsoleDirectorySectionTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          AdminDirectoryCard(
            api: api,
            reloadToken: _reloadToken,
            onSelected: (AdminAccountReport admin) =>
                setState(() => _selectedAccountId = admin.accountId),
          ),
          if (_selectedAccountId != null) ...<Widget>[
            const SizedBox(height: 12),
            AdminProfileCard(
              key: ValueKey<String>(_selectedAccountId!),
              api: api,
              accountId: _selectedAccountId!,
              onClosed: () => setState(() => _selectedAccountId = null),
              onSaved: () => setState(() => _reloadToken++),
            ),
          ],
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
