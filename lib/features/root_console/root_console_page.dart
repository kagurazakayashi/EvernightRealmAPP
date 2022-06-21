/// Root 控制台頁面。
///
/// Root 屬伺服器級上下文，與活動端導航嚴格隔離；實際的總覽、日誌與備份頁面
/// 待後端能力就緒後在此擴充。
library;

import 'package:flutter/widgets.dart';

import '../../app/nav_context.dart';
import '../../app/widgets/not_wired_view.dart';

/// Root 控制台頁面。
class RootConsolePage extends StatelessWidget {
  /// 建立頁面。
  const RootConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return NotWiredView.forContext(NavContext.rootConsole);
  }
}
