/// 玩家端頁面。
///
/// 玩家端持有一個活動身份上下文，Guest 與 Player 共用同一組頁面並按權限呈現受限內容。
/// 本版本接通的是「我的陣營」這一條：先列我有身份的活動，再在某一場活動裡讀自己的歸屬、
/// 讀可選陣營、在活動允許時自己把歸屬選下去。活動首頁、錢包、聊天與文件庫等頁面
/// 待後端能力就緒後在此擴充，而那件事由清單那一側自己如實說明，不在這裡宣稱。
library;

import 'package:flutter/material.dart';

import '../../app/nav_context.dart';
import '../../app/nav_context_labels.dart';
import '../../l10n/app_localizations.dart';
import 'faction_self_select_view.dart';

/// 玩家端頁面。
class PlayerSurfacePage extends StatelessWidget {
  /// 建立頁面。
  const PlayerSurfacePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 上下文說明取自導航表那份唯一來源（口徑同管理端頁面）：這一頁屬於哪個身份
        // 不由本地另寫一句，Guest 與 Player 共用這件事因此只有一套說法。
        Text(
          NavContext.playerSurface.summaryOf(l10n),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        // 身份由會話決定：這一頁沒有一格能填「哪個玩家」，也不本地保存任何歸屬。
        const PlayerFactionSurface(),
      ],
    );
  }
}
