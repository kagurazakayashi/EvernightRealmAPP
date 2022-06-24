/// 應用殼外框：標題列、內容區與持續顯示的連線狀態條。
///
/// 外框不攜帶任何業務資料；狀態條的數值一律取自裝配的依賴，頁面無法自行宣稱連線結果。
/// 內容區依視窗寬度調整：窄屏單欄鋪滿，寬屏限制內文寬度並置中，
/// 讓同一套頁面從 360 px 到桌面大窗都不出現超長行或溢出。
library;

import 'package:flutter/material.dart';

import '../core/layout_breakpoints.dart';
import 'widgets/status_bar.dart';

/// 所有頂層上下文共用的殼。
class AppShell extends StatelessWidget {
  /// 以頁面標題與內容建立殼。
  const AppShell({super.key, required this.title, required this.child});

  /// 標題列文字（頂層上下文名稱）。
  final String title;

  /// 內容區元件。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // AppBar 的標題槽自帶寬度約束（_AppBarTitleBox），這裡只指定單行刪節；
        // 再包一層 Flexible 會被該 ParentData 拒收。
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Breakpoints.contentMaxWidth,
            ),
            child: child,
          ),
        ),
      ),
      bottomNavigationBar: const ConnectionStatusBar(),
    );
  }
}
