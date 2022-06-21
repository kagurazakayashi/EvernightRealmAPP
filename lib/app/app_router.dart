/// Navigator 路由表：只登記五個頂層導航上下文。
///
/// 各身份內部頁面等對應後端能力開發時再逐條加入；未登記的路由由
/// [AppRouter.onUnknownRoute] 統一回退，不猜測目標頁面。
library;

import 'package:flutter/material.dart';

import '../core/app_copy.dart';
import 'app_shell.dart';
import '../features/admin/admin_console_page.dart';
import '../features/npc/npc_console_page.dart';
import '../features/player/player_surface_page.dart';
import '../features/root_console/root_console_page.dart';
import '../features/server_entry/server_entry_page.dart';
import 'nav_context.dart';
import 'widgets/not_wired_view.dart';

/// 應用壳的路由表。
abstract final class AppRouter {
  /// 啟動後的第一個畫面：未登入與已登入通用的伺服器入口層。
  static String get initialRoute => NavContext.serverEntry.routeName;

  /// 已登記的路由與對應頁面。
  static Map<String, WidgetBuilder> get routes {
    return <String, WidgetBuilder>{
      NavContext.serverEntry.routeName: (BuildContext context) => AppShell(
        title: NavContext.serverEntry.title,
        child: const ServerEntryPage(),
      ),
      NavContext.rootConsole.routeName: (BuildContext context) => AppShell(
        title: NavContext.rootConsole.title,
        child: const RootConsolePage(),
      ),
      NavContext.adminConsole.routeName: (BuildContext context) => AppShell(
        title: NavContext.adminConsole.title,
        child: const AdminConsolePage(),
      ),
      NavContext.npcConsole.routeName: (BuildContext context) => AppShell(
        title: NavContext.npcConsole.title,
        child: const NpcConsolePage(),
      ),
      NavContext.playerSurface.routeName: (BuildContext context) => AppShell(
        title: NavContext.playerSurface.title,
        child: const PlayerSurfacePage(),
      ),
    };
  }

  /// 為未登記的路由產生回退頁面。
  ///
  /// 只由 `onUnknownRoute` 使用：不掛在 `onGenerateRoute` 上，否則 MaterialApp
  /// 會以它產生佔位根路由，把真正的起始頁壓在一個「無法開啟」頁面之上。
  static Route<dynamic> onUnknownRoute(RouteSettings settings) {
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (BuildContext context) => AppShell(
        title: AppCopy.unknownRouteTitle,
        child: NotWiredView.forUnknownRoute(settings.name ?? ''),
      ),
    );
  }
}
