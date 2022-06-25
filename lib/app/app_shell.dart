/// 應用殼外框：標題列、可滾動的內容區與持續顯示的連線狀態條。
///
/// 外框不攜帶任何業務資料；狀態條的數值一律取自裝配的依賴與探測狀態，
/// 頁面無法自行宣稱連線結果。
/// 內容區做兩件事：依視窗寬度限制內文寬度並置中（讓同一套頁面從 360 px 到
/// 桌面大窗都不出現超長行），以及**由殼統一負責垂直滾動**——否則窄屏上
/// 固定高度的區塊會把可滾動的清單壓到零高度而溢出。
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

  /// 內容區的測試識別鍵（佈局測試據此量測內寬）。
  static const Key contentKey = ValueKey<String>('app-shell-content');

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
            child: SingleChildScrollView(key: contentKey, child: child),
          ),
        ),
      ),
      bottomNavigationBar: const ConnectionStatusBar(),
    );
  }
}
