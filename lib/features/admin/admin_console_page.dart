/// 管理員端頁面。
///
/// 管理員以玩家身份進入活動時會切到玩家端上下文，管理操作與玩家操作上下文分離。
/// 本頁接線的伺服器級能力目前有四項，且後端只認「持有 server_admin 的受信主體」：
///
/// * 建立普通帳戶（[StandardAccountProvisionCard]）——受伺服器「管理員建立普通帳戶」
///   開關約束，開關關閉時由服務端在提交那一刻回話，界面不預讀、不猜。
/// * 普通帳戶目錄（[StandardAccountDirectoryCard]）——分頁與狀態／來源／名稱篩選的
///   答案全部取自服務端回應；這本目錄列不到管理員，也列不到 Root。
/// * 單筆詳情與顯示名編輯（[StandardAccountProfileCard]）——底稿按標識重讀，
///   保存走白名單＋compare-and-set；憑據、狀態與安全狀態不在這一頁可改。
/// * 註冊申請的審批（[RegistrationReviewCard]）——另一本名冊：列的是還在等決定的申請
///   與已被拒絕的申請，而上面那本目錄按定義把這兩態排在門外。批准只能批出一個
///   不帶任何伺服器級授予的普通帳戶，界面沒有一格可以填角色，也沒有一格可以填理由。
///
/// 本頁另外接了一組活動管理（[ActivityConsoleCard]／[ActivityProfileCard]）：
/// 建立活動、讀自己獲指派的活动目錄、編輯名稱與描述、開放／停止／重新開放／歸檔，
/// 並讀取該活動的管理人名冊。這裡的「讀得到哪些活動」與後端那道活動作用域判定同源：
/// 持有伺服器級管理權但沒被指派任何活動的主體，看見的是空目錄而不是全部活動。
/// 加人或刪人不在本頁（那是 Root 的決定，見 Root 控制台），名冊因此只讀。
///
/// 其餘能力仍然沒有實作：改伺服器級角色、活動裡面的成員名冊、陣營、資產與聊天
/// 都不在今天後端的端點裡，因此本頁以一行如實說明收尾，
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
import 'activity_directory_view.dart';
import 'activity_profile_view.dart';
import 'registration_review_view.dart';
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

  /// 活動目錄與名冊的重載計數：建立、編輯、狀態轉換與指派成功都加一。
  ///
  /// 與上面的 `_reloadToken` 分開是刻意的：帳戶那边的成功不該讓活動目錄多發一次請求，
  /// 反之亦然——共用一個計數會讓兩本書互相拖著重讀，也更難看出是哪一本書變了。
  int _activityReload = 0;

  /// 當前展開詳情卡的活動標識。
  ///
  /// 與帳戶詳情那個欄位各自獨立：兩張詳情卡可以同時開著，但它們讀的是兩本書，
  /// 誰也不該因為另一本的選擇而被重建。
  String? _selectedActivityId;

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
          // 另一本名冊：等審批的申請與已被拒絕的申請。它與上面那本目錄互斥
          // （同一個人不可能同時列在兩本書的範圍裡），因此各自重讀各自的伺服器真相，
          // 不共用本地那一份「我以為他現在是什麼」。
          RegistrationReviewCard(api: api),
          const SizedBox(height: 28),
          // 活動管理：建立與目錄（可見範圍由服務端的指派表決定），選中一行才展開詳情卡。
          ActivityConsoleCard(
            api: api,
            reloadToken: _activityReload,
            onCreated: () => setState(() => _activityReload++),
            onSelected: (ActivityReport activity) =>
                setState(() => _selectedActivityId = activity.activityId),
          ),
          if (_selectedActivityId != null) ...<Widget>[
            const SizedBox(height: 16),
            // 標識變動即重建整張卡：詳情卡不沿用上一個活動那份資料。
            // canManageManagers 保持預設 false——加人與刪人只在 Root 那一側，
            // 這裡的名冊只讀。
            ActivityProfileCard(
              key: ValueKey<String>(_selectedActivityId!),
              api: api,
              activityId: _selectedActivityId!,
              onClosed: () => setState(() => _selectedActivityId = null),
              onSaved: () => setState(() => _activityReload++),
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
