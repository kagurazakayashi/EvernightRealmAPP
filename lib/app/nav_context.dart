/// 應用殼的頂層導航上下文與對應路由名稱。
///
/// 頁面名稱與分層依據《Evernight-Realm-頁面與身份切換關係》（ER-IA-001）：
/// 各身份內部頁面由對應後端能力開發時再註冊，此處只登記五個頂層上下文，
/// 不預先發明頁面。
library;

/// 頂層導航上下文。
enum NavContext {
  /// 伺服器入口層：未登入與已登入通用，為啟動後的第一個畫面。
  ///
  /// 登记為應用根路由，使入口層就是 Navigator 的第一條路由、沒有可返回的上層。
  serverEntry(
    routeName: '/',
    title: '伺服器入口',
    summary: '選擇伺服器並完成登入、註冊或以 Guest 進入；身份判定由伺服器回報。',
  ),

  /// Root 控制台：伺服器級上下文，與活動端導航嚴格隔離。
  rootConsole(
    routeName: '/root-console',
    title: 'Root 控制台',
    summary: '伺服器級管理上下文，不與活動端混在同一導航內。',
  ),

  /// 管理員端：活動管理上下文。
  adminConsole(
    routeName: '/admin-console',
    title: '管理員端',
    summary: '活動、玩家、資產與時間線等管理操作的進入點。',
  ),

  /// NPC 操作台：需在已選定的 NPC 身份上下文中操作。
  npcConsole(
    routeName: '/npc-console',
    title: 'NPC 操作台',
    summary: '以顯式選定的 NPC 身分進行操作，與玩家操作上下文分離。',
  ),

  /// 玩家端：單一活動身份上下文，Guest 與 Player 共用頁面。
  playerSurface(
    routeName: '/player-surface',
    title: '玩家端',
    summary: '活動內的玩家頁面集合，同一時刻只持有一個活動身份上下文。',
  );

  /// 由路由名稱與顯示文字建立上下文描述。
  const NavContext({
    required this.routeName,
    required this.title,
    required this.summary,
  });

  /// Navigator 路由名稱。
  final String routeName;

  /// 頁面標題（面向使用者的身份層級名稱）。
  final String title;

  /// 該上下文的用途說明，僅描述範圍、不含任何業務資料。
  final String summary;

  /// 全部路由名稱，供測試與導航表核對。
  static List<String> get allRouteNames => NavContext.values
      .map((context) => context.routeName)
      .toList(growable: false);
}
