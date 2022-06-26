/// Navigator 路由表：只登記五個頂層導航上下文。
///
/// 各身份內部頁面等對應後端能力開發時再逐條加入；未登記的路由由
/// [AppRouter.onUnknownRoute] 統一回退，不猜測目標頁面。
/// 頁面標題依目前語言取自本地化資源，路由表本身不保存文字。
library;

import 'package:flutter/material.dart';

import '../features/admin/admin_console_page.dart';
import '../features/npc/npc_console_page.dart';
import '../features/player/player_surface_page.dart';
import '../features/root_console/root_console_page.dart';
import '../features/server_entry/server_entry_page.dart';
import '../l10n/app_localizations.dart';
import 'app_shell.dart';
import 'nav_context.dart';
import 'nav_context_labels.dart';
import 'widgets/not_wired_view.dart';

/// 應用殼的路由表。
abstract final class AppRouter {
  /// 導航器的金鑰：讓錯誤畫面能在「返回可用頁面」時把堆疊清回起始路由。
  ///
  /// 安全畫面由 `MaterialApp.builder` 覆蓋在導航器之上，它自己的 context 取不到
  /// 下方的 Navigator，因此需要這個由 `MaterialApp.navigatorKey` 接住的金鑰。
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// 啟動後的第一個畫面：未登入與已登入通用的伺服器入口層。
  static String get initialRoute => NavContext.serverEntry.routeName;

  /// 已登記的路由與對應頁面。
  static Map<String, WidgetBuilder> get routes {
    return <String, WidgetBuilder>{
      NavContext.serverEntry.routeName: (BuildContext context) =>
          _shell(context, NavContext.serverEntry, const ServerEntryPage()),
      NavContext.rootConsole.routeName: (BuildContext context) =>
          _shell(context, NavContext.rootConsole, const RootConsolePage()),
      NavContext.adminConsole.routeName: (BuildContext context) =>
          _shell(context, NavContext.adminConsole, const AdminConsolePage()),
      NavContext.npcConsole.routeName: (BuildContext context) =>
          _shell(context, NavContext.npcConsole, const NpcConsolePage()),
      NavContext.playerSurface.routeName: (BuildContext context) =>
          _shell(context, NavContext.playerSurface, const PlayerSurfacePage()),
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
        title: AppLocalizations.of(context).unknownRouteTitle,
        child: NotWiredView.forUnknownRoute(settings.name ?? ''),
      ),
    );
  }

  /// 以上下文名稱套上應用殼。
  static Widget _shell(
    BuildContext context,
    NavContext navContext,
    Widget page,
  ) {
    return AppShell(
      title: navContext.titleOf(AppLocalizations.of(context)),
      child: page,
    );
  }
}
