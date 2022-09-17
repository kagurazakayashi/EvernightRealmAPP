/// 伺服器入口層頁面。
///
/// 本層未登入與已登入通用，是啟動後的第一個畫面，也是介面語言選擇的所在位置
/// （全域設定放全局頁面，其他上下文尚未開發時不重複放選單）。
/// 這裡同時放置伺服器位址輸入卡、連通性探測區、Root 初始化引導卡與會話摘要卡：
/// 前者決定本機要連哪台伺服器，後三者以同一個位址如實回報連得上與否、
/// 那台伺服器進行到哪一步（還沒有 Root，或已經有了），以及此刻「這台伺服器上的我」
/// 是什麼身分——未登入時給登入入口，已登入時只呈現伺服器確認過的身分與
/// 該身分真的能開啟的入口。註冊與 Guest 入口待對應能力就緒後再擴充，本步不新增。
///
/// 內容一律為固定高度的Column：垂直滾動由應用殼承擔，頁面不與殼搶滾動區。
library;

import 'package:flutter/material.dart';

import '../../app/nav_context.dart';
import '../../app/widgets/language_selector.dart';
import '../../app/widgets/not_wired_view.dart';
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
        const NotWiredView.forContext(NavContext.serverEntry),
      ],
    );
  }
}
