/// 伺服器入口層頁面。
///
/// 本層未登入與已登入通用，是啟動後的第一個畫面，也是介面語言選擇的所在位置
/// （全域設定放全局頁面，其他上下文尚未開發時不重複放選單）。
/// 這裡同時放置連通性探測區：它是目前唯一能如實讀取伺服器的入口。
/// 伺服器位址輸入、登入、註冊與 Guest 入口待對應能力就緒後在此擴充。
///
/// 內容一律為固定高度的Column：垂直滾動由應用殼承擔，頁面不與殼搶滾動區。
library;

import 'package:flutter/material.dart';

import '../../app/nav_context.dart';
import '../../app/widgets/language_selector.dart';
import '../../app/widgets/not_wired_view.dart';
import '../../app/widgets/server_probe_view.dart';
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
          child: ServerProbeView(),
        ),
        const NotWiredView.forContext(NavContext.serverEntry),
      ],
    );
  }
}
