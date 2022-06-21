/// 應用壳外框：標題列、內容區與持續顯示的連線狀態條。
///
/// 外框不携带任何業務資料；狀態條的數值一律取自裝配的依賴，頁面無法自行宣稱連線結果。
library;

import 'package:flutter/material.dart';

import 'widgets/status_bar.dart';

/// 所有頂層上下文共用的壳。
class AppShell extends StatelessWidget {
  /// 以頁面標題與內容建立壳。
  const AppShell({super.key, required this.title, required this.child});

  /// 標題列文字（頂層上下文名稱）。
  final String title;

  /// 內容區元件。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(top: false, child: child),
      bottomNavigationBar: const ConnectionStatusBar(),
    );
  }
}
