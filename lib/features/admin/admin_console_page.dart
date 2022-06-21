/// 管理員端頁面。
///
/// 管理員以玩家身份進入活动时會切到玩家端上下文，管理操作與玩家操作上下文分離；
/// Live Dashboard、活動與資產管理等頁面待後端能力就緒後在此擴充。
library;

import 'package:flutter/widgets.dart';

import '../../app/nav_context.dart';
import '../../app/widgets/not_wired_view.dart';

/// 管理員端頁面。
class AdminConsolePage extends StatelessWidget {
  /// 建立頁面。
  const AdminConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return NotWiredView.forContext(NavContext.adminConsole);
  }
}
