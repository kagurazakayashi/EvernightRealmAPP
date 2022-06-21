/// 伺服器入口層頁面。
///
/// 本層未登入與已登入通用，是啟動後的第一個畫面；伺服器位址輸入、登入、註冊與
/// Guest 入口待對應能力就緒後在此擴充。
library;

import 'package:flutter/widgets.dart';

import '../../app/nav_context.dart';
import '../../app/widgets/not_wired_view.dart';

/// 伺服器入口層頁面。
class ServerEntryPage extends StatelessWidget {
  /// 建立頁面。
  const ServerEntryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return NotWiredView.forContext(NavContext.serverEntry);
  }
}
