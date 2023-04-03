/// 玩家端頁面。
///
/// 玩家端持有一個活動身份上下文，Guest 與 Player 共用同一組頁面並按權限呈現受限內容。
/// 本版本接通的是四條：「我的陣營」——先列我有身份的活動，再在某一場活動裡讀自己的歸屬、
/// 讀可選陣營、在活動允許時自己把歸屬選下去；「玩家目錄」——讀這一態准我看見的人、
/// 按暱稱搜尋、按陣營篩選、翻頁、點開單筆受權詳情，並永遠讀得到我自己的活動內資料；
/// 以及「公開標籤定義」——讀某一場活動被管理人對外公開的那幾枚定義本身（唯讀、無快取）；
/// 「我的限制狀態」——讀某一場活動掛在我身上的六枚分項限制現值。它是被「禁止進入這一場
/// 活動」擋下之後唯一還讀得動的活動通路：被限制的人必須能問出「我被限制的是哪些項」，
/// 而六欄各存各的、只作用這一場活動，不是帳戶停用（界面上把分界寫在按鈕之外）。
/// 四條都是「先有後端通路，才有這一張卡」：活動首頁、錢包、聊天與文件庫等頁面
/// 待後端能力就緒後在此擴充，而那件事由清單那一側自己如實說明，不在這裡宣稱。
/// 「誰帶著哪個標籤」尚未落地，因此這三張卡都沒有一格能列出貼了標籤的人。
library;

import 'package:flutter/material.dart';

import '../../app/nav_context.dart';
import '../../app/nav_context_labels.dart';
import '../../l10n/app_localizations.dart';
import 'faction_self_select_view.dart';
import 'player_member_directory_view.dart';
import 'player_restrictions_view.dart';
import 'player_tags_view.dart';

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
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        // 目錄與自選是兩條獨立的讀法：兩張卡各讀各的，誰失敗都不抹掉另一份結果。
        const PlayerDirectorySurface(),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        // 標籤定義是第三條讀法，也是唯讀的一條：它問的是「這場活動把哪幾枚定義對外說了」，
        // 與目錄能看見誰、與自己能選哪個陣營都是兩件事，因此各一張卡、各讀各的，
        // 誰失敗都不抹掉對方的結果。「誰帶著哪個標籤」尚未落地，這一卡只列定義本身。
        const PlayerTagsCard(),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        // 限制狀態是第四條讀法：它問的是「這一場活動把哪些限制掛在我身上」，
        // 與目錄看見誰、能選哪個陣營、標籤公開了哪幾枚都是兩件事，因此各一張卡、
        // 各讀各的。它是被禁止進入後唯一讀得動的活動通路，其餘卡片在那個人身上
        // 各回各的 2043，互不掩蓋。
        const PlayerRestrictionsCard(),
      ],
    );
  }
}
