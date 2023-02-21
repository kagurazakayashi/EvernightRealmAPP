/// 伺服器入口層頁面。
///
/// 本層未登入與已登入通用，是啟動後的第一個畫面，也是介面語言選擇的所在位置
/// （全域設定放全局頁面，其他上下文尚未開發時不重複放選單）。
/// 這裡同時放置伺服器位址輸入卡、連通性探測區、Root 初始化引導卡、會話摘要卡、
/// 自註冊入口卡與訪客進入卡：前者決定本機要連哪臺伺服器，其餘幾張以同一個位址如實回報
/// 連得上與否、那臺伺服器進行到哪一步（還沒有 Root，或已經有了），此刻「這臺伺服器上的我」
/// 是什麼身分——未登入時給登入入口，已登入時只呈現伺服器確認過的身分與
/// 該身分真的能開啟的入口。自註冊入口卡只讀登入前能力（sign_up_open）決定要不要
/// 露出這扇門，真正准不准建仍由後端在提交那一刻現讀策略判定；訪客進入卡同理讀
/// guest_open，而且它唯一的那次寫入只由人主動按下那顆按鈕觸發（載入、刷新、重連都不寫）。
///
/// 內容一律為固定高度的Column：垂直滾動由應用殼承擔，頁面不與殼搶滾動區。
library;

import 'package:flutter/material.dart';

import '../../app/nav_context.dart';
import '../../app/widgets/guest_entry_view.dart';
import '../../app/widgets/language_selector.dart';
import '../../app/widgets/not_wired_view.dart';
import '../../app/widgets/register_entry_view.dart';
import '../../app/widgets/root_init_guide_view.dart';
import '../../app/widgets/server_address_editor.dart';
import '../../app/widgets/server_probe_view.dart';
import '../../app/widgets/session_summary_view.dart';
import '../../l10n/app_localizations.dart';

/// 伺服器入口層頁面。
class ServerEntryPage extends StatelessWidget {
  /// 建立頁面。
  const ServerEntryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LanguageSelector(),
              const SizedBox(height: 6),
              Text(
                l10n.interfaceLanguageHint,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: ServerAddressEditor(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: ServerProbeView(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: RootInitGuideView(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: SessionSummaryView(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: RegisterEntryView(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: GuestEntryView(),
        ),
        const NotWiredView.forContext(NavContext.serverEntry),
      ],
    );
  }
}
