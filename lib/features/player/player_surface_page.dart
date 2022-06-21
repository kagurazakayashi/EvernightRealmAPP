/// 玩家端頁面。
///
/// 玩家端持有一個活動身份上下文，Guest 與 Player 共用同一組頁面並按權限呈現受限內容；
/// 活動首頁、錢包、聊天與文件庫等頁面待後端能力就緒後在此擴充。
library;

import 'package:flutter/widgets.dart';

import '../../app/nav_context.dart';
import '../../app/widgets/not_wired_view.dart';

/// 玩家端頁面。
class PlayerSurfacePage extends StatelessWidget {
  /// 建立頁面。
  const PlayerSurfacePage({super.key});

  @override
  Widget build(BuildContext context) {
    return NotWiredView.forContext(NavContext.playerSurface);
  }
}
