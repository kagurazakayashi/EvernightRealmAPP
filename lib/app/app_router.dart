/// Navigator 路由表：登記五個頂層導航上下文，以及登入、自註冊、查本人申請狀態三條
/// 取得身份的通路，
/// 並為受保護上下文掛上會話閘。
///
/// 各身份內部頁面等對應後端能力開發時再逐條加入；未登記的路由由
/// [AppRouter.onUnknownRoute] 統一回退，不猜測目標頁面。
/// 頁面標題依目前語言取自本地化資源，路由表本身不保存文字。
///
/// 受保護路由一律包在 [SessionGate] 裡：未登入者只會看到登入頁，驗證中不會
/// 閃現受保護內容，身份不合（例如非 Root 開 Root 控制台）也會被擋回入口。
/// 判定依據只有會話控制器裡那份「伺服器確認過的身分」，路由表不讀任何
/// 本地自報的角色值。
library;

import 'dart:collection';

import 'package:flutter/material.dart';

import '../core/session/session_controller.dart';
import '../features/admin/admin_console_page.dart';
import '../features/auth/application_status_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/npc/npc_console_page.dart';
import '../features/player/player_surface_page.dart';
import '../features/root_console/root_console_page.dart';
import '../features/server_entry/server_entry_page.dart';
import '../l10n/app_localizations.dart';
import 'app_shell.dart';
import 'nav_context.dart';
import 'nav_context_labels.dart';
import 'session_gate.dart';
import 'widgets/not_wired_view.dart';

/// 登入頁的路由名稱。
///
/// 刻意不進 [NavContext]：那五個值是「身分上下文」，登入不是一種身份，
/// 而是取得身份的通路。
const String kLoginRoute = '/login';

/// 匿名自註冊頁的路由名稱。
///
/// 與 [kLoginRoute] 同類：都是「取得身份的通路」，不是一種身份，因此不進 [NavContext]，
/// 也不進受保護清單——會話閘的語意是「未登入者只看登入頁」，而自註冊恰恰是
/// 未登入者要做的事。入口層是否呈現這扇門由伺服器的登入前能力（sign_up_open）決定，
/// 路由本身只保證「這條路存在且不需會話」，能否真的建成仍由後端在提交時現讀策略判定。
const String kRegisterRoute = '/register';

/// 申請人查本人待審批狀態頁的路由名稱。
///
/// 與 [kLoginRoute]、[kRegisterRoute] 同類：都是「取得身份的通路」上的一段，
/// 不是一種身份，因此不進 [NavContext]，也不進受保護清單。
///
/// 它之所以必須是一條獨立的路徑而不是登入後的一頁：待審批的人沒有一枚能碰普通業務的
/// 會話（後端那條通路刻意不簽發 Cookie），而他依然有權利知道自己那份申請怎麼樣了。
/// 每一次查詢都要重新交憑據，因此這一頁不假裝「記得您是誰」——沒有本地狀態、
/// 沒有自動重查，刷新與離開都不留下任何可被複用的東西。
const String kApplicationStatusRoute = '/application-status';

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

  /// 需要登入才能開啟的受保護路由名稱。
  ///
  /// 這是「返回目標」的唯一合法清單：登入成功後要跳去的地方只准從這裡取，
  /// 任何外部網址、未登記路徑或入口層本身都不在其中，結構上排除了
  /// 「把使用者送到應用外面」的開放式跳轉。
  static Set<String> get guardedRouteNames => _guardedRouteNames;
  static final Set<String> _guardedRouteNames = UnmodifiableSetView(<String>{
    NavContext.rootConsole.routeName,
    NavContext.adminConsole.routeName,
    NavContext.npcConsole.routeName,
    NavContext.playerSurface.routeName,
  });

  /// 受保護路由中要求 Root 身分的那幾個。
  static Set<String> get rootOnlyRouteNames => _rootOnlyRouteNames;
  static final Set<String> _rootOnlyRouteNames = UnmodifiableSetView(<String>{
    NavContext.rootConsole.routeName,
  });

  /// 判斷「伺服器確認過的身分」能否開啟指定路由。
  ///
  /// 只准拿會話控制器裡由 `/auth/login`、`/auth/session` 回應建立的
  /// [ActiveSession] 判定；未登入（`null`）對任何受保護路由都是假。
  /// Root 專屬上下文另比 `isRoot`——這一位同樣只來自伺服器回應，
  /// 與登入表單上選了哪種方式無關。
  static bool identityAllows(String routeName, ActiveSession? session) {
    if (session == null || !guardedRouteNames.contains(routeName)) {
      return false;
    }
    if (rootOnlyRouteNames.contains(routeName)) {
      return session.isRoot;
    }
    return true;
  }

  /// 從路由參數解析登入後的返回目標；不在合法清單內的一律當作沒有。
  ///
  /// 參數屬外部可構造輸入（路由可以被帶參推入），所以要過兩道閘：
  /// 必須是字串、必須逐字命中受保護清單。比對是集合成員檢查，
  /// 不解析、不拼接、不放行任何「看起來像內部路徑」的變化型。
  static String? parseReturnRoute(Object? arguments) {
    if (arguments is! String) {
      return null;
    }
    return guardedRouteNames.contains(arguments) ? arguments : null;
  }

  /// 已登記的路由與對應頁面。
  static Map<String, WidgetBuilder> get routes {
    return <String, WidgetBuilder>{
      NavContext.serverEntry.routeName: (BuildContext context) =>
          _shell(context, NavContext.serverEntry, const ServerEntryPage()),
      NavContext.rootConsole.routeName: (BuildContext context) => _guardedShell(
        context,
        NavContext.rootConsole,
        const RootConsolePage(),
      ),
      NavContext.adminConsole.routeName: (BuildContext context) =>
          _guardedShell(
            context,
            NavContext.adminConsole,
            const AdminConsolePage(),
          ),
      NavContext.npcConsole.routeName: (BuildContext context) =>
          _guardedShell(context, NavContext.npcConsole, const NpcConsolePage()),
      NavContext.playerSurface.routeName: (BuildContext context) =>
          _guardedShell(
            context,
            NavContext.playerSurface,
            const PlayerSurfacePage(),
          ),
      kLoginRoute: (BuildContext context) => AppShell(
        title: AppLocalizations.of(context).loginTitle,
        child: const LoginPage(),
      ),
      kRegisterRoute: (BuildContext context) => AppShell(
        title: AppLocalizations.of(context).registerTitle,
        child: const RegisterPage(),
      ),
      kApplicationStatusRoute: (BuildContext context) => AppShell(
        title: AppLocalizations.of(context).applicationStatusTitle,
        child: const ApplicationStatusPage(),
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

  /// 受保護上下文：先過會話閘，再套應用殼。
  ///
  /// 閘放在殼的 child 之内、導航路由之外：如此不論從路由表、深連結回退還是
  /// 程式化 pushNamed 進來，都必然經過同一道判定，不存在「繞過閘的第二條路」。
  static Widget _guardedShell(
    BuildContext context,
    NavContext navContext,
    Widget page,
  ) {
    return _shell(
      context,
      navContext,
      SessionGate(
        targetRoute: navContext.routeName,
        requireRoot: rootOnlyRouteNames.contains(navContext.routeName),
        child: page,
      ),
    );
  }
}
