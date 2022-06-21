/// NPC 操作台頁面。
///
/// 進入 NPC 身份必須顯式選定被分配的 NPC，一個上下文內只允許該 NPC 的授權操作；
/// NPC 選擇與資產操作頁面待後端能力就緒後在此擴充。
library;

import 'package:flutter/widgets.dart';

import '../../app/nav_context.dart';
import '../../app/widgets/not_wired_view.dart';

/// NPC 操作台頁面。
class NpcConsolePage extends StatelessWidget {
  /// 建立頁面。
  const NpcConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return NotWiredView.forContext(NavContext.npcConsole);
  }
}
