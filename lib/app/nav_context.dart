/// 應用殼的頂層導航上下文與對應路由名稱。
///
/// 頁面名稱與分層依據《Evernight-Realm-頁面與身份切換關係》（ER-IA-001）：
/// 各身份內部頁面由對應後端能力開發時再註冊，此處只登記五個頂層上下文，
/// 不預先發明頁面。
///
/// 列舉值不保存任何介面文字，顯示用的標題與說明見 `NavContextLabels` 擴充。
library;

/// 頂層導航上下文。
enum NavContext {
  /// 伺服器入口層：未登入與已登入通用，為啟動後的第一個畫面。
  ///
  /// 登記為應用根路由，使入口層就是 Navigator 的第一條路由、沒有可返回的上層。
  serverEntry(routeName: '/'),

  /// Root 控制台：伺服器級上下文，與活動端導航嚴格隔離。
  rootConsole(routeName: '/root-console'),

  /// 管理員端：活動管理上下文。
  adminConsole(routeName: '/admin-console'),

  /// NPC 操作台：需在已選定的 NPC 身份上下文中操作。
  npcConsole(routeName: '/npc-console'),

  /// 玩家端：單一活動身份上下文，Guest 與 Player 共用頁面。
  playerSurface(routeName: '/player-surface');

  /// 由路由名稱建立上下文描述。
  const NavContext({required this.routeName});

  /// Navigator 路由名稱。
  final String routeName;

  /// 全部路由名稱，供測試與導航表核對。
  static List<String> get allRouteNames => NavContext.values
      .map((context) => context.routeName)
      .toList(growable: false);
}
