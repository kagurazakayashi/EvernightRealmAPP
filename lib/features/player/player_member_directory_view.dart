/// 玩家端的「活動玩家目錄」通路：列這一態讓我看見的人、按暱稱搜、按陣營篩、翻頁、
/// 點開單筆受權詳情，以及永遠讀得到的「我自己的活動內資料」。
///
/// 這一頁的每句顯示都來自服務端回讀，寫在這裡是因為界面藏不住它們：
///
/// * 能看見誰不由界面決定：目錄、單筆詳情、本人投影三條讀法背後都是同一句判定
///   （活動模式＋我自己那一行＋每一行的覆蓋＋授予現讀），查詢串與本體裡都沒有
///   格子能宣稱「用管理視角給我全部人」。界面先拿已授權的那一份結果集，
///   再在裡面搜、篩、切頁與計數——不存在「先下載全部成員再自己過濾」這種形態。
/// * 四種「沒有東西可看」是四句話：真的沒人加入、這一態本來就不列任何人、
///   這場活動我進不去（1001 那一句不可分辨）、以及這一次沒讀成功。
///   前三句各自說出來，但它們都不多出「那一個人其實存在」這種訊號。
/// * 目錄收起時我仍然讀得到自己：本人那一讀不經可見性判定，所以「別人看不見我」
///   與「我看見自己叫什麼」分開講，不會把全局的我的資料錯清成空。
/// * 詳情走受權的那條單筆路徑，不拿列表那一行本地展開：失權之後重新進入
///   拿到的是 1001，畫面随之清空，不繼續把上一批留下的那份當成在地的授權依據。
/// * 請求綁在發起它的那一場活動與那一次操作：每一次載入都帶著自己的序號，
///   遲到的那一份（換了活動、換了伺服器、按了重新讀取）一律丟掉，
///   不准它覆蓋新頁面的結果。
/// * 倉庫裡沒有快取層，也沒有實時層：失效形態只有「下一筆請求按新規則判定」。
///   在線狀態與在線人數尚未接入，這一頁因此一個字都不猜。
/// * 目錄裡那一格「業務狀態」是活動管理員維護的值，不是這個玩家連不連得上線：
///   頁面把它與「沒有在線指示」兩句一起寫出來，不把 offline 那個內部值唸成在線狀態。
/// * 簡介與頭像上傳都不在合同裡：那一格只有佔位與一句「後端還沒有這個欄位」，
///   不拿空白冒充已經有了，也不拿本地圖檔冒充服務端的頭像。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../app/app_dependencies.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';
import '../admin/activity_factions_view.dart' show factionIconData;
// 業務狀態的顯示名換算只有一份（管理名冊、目錄、單筆詳情與本人投影共用），
// 在這裡另寫一次就會出現「列表唸預設、點進去唸覆蓋」兩個答案來源。
import '../business_status_labels.dart';

/// 目錄每頁的筆數（取後端發布的預設值，界面不自造第二個上限）。
const int kPlayerDirectoryPageSize = 20;

/// 玩家端目錄入口（含本人的活動清單）。
class PlayerDirectorySurface extends StatefulWidget {
  /// 建立玩家端目錄通路。
  const PlayerDirectorySurface({super.key});

  /// 清單容器識別鍵。
  static const Key listKey = ValueKey<String>('player-directory-activities');

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('player-directory-loading');

  /// 載入失敗識別鍵。
  static const Key failedKey = ValueKey<String>('player-directory-failed');

  /// 重新讀取識別鍵。
  static const Key reloadKey = ValueKey<String>('player-directory-reload');

  /// 空清單識別鍵。
  static const Key emptyKey = ValueKey<String>('player-directory-empty');

  /// 某一行的進入按鈕識別鍵。
  static Key openKey(String activityId) =>
      ValueKey<String>('player-directory-open-$activityId');

  @override
  State<PlayerDirectorySurface> createState() => _PlayerDirectorySurfaceState();
}

class _PlayerDirectorySurfaceState extends State<PlayerDirectorySurface> {
  late final ServerApi _api = AppScope.of(context).api;

  List<MyActivityReport> _activities = const <MyActivityReport>[];
  bool _loading = true;
  String? _notice;

  /// 非 null 時顯示某一場活動的目錄（只由清單那一行按標識進入，不做本地推測）。
  String? _openActivityId;

  /// 本次卡片的請求序號：換目標、按重讀、離開這一頁都讓上一批回應變成過期件。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀本人的活動清單。失敗時整卡轉述那一句失敗，不顯示任何舊清單。
  Future<void> _load() async {
    final int generation = ++_generation;
    setState(() => _loading = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final MyActivityListReport report = await _api.myActivities(
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _activities = report.activities;
        _notice = null;
      });
    } on ApiError catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _loading = false;
        _activities = const <MyActivityReport>[];
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    if (_openActivityId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OutlinedButton(
            key: ValueKey<String>('player-directory-back'),
            onPressed: () => setState(() => _openActivityId = null),
            child: Text(l10n.playerBackToActivitiesAction),
          ),
          const SizedBox(height: 12),
          // 按「活動標識」做 key：換一場活動就整張重建，上一場的目錄與篩選不可能留場。
          ActivityMemberDirectoryCard(
            key: ValueKey<String>('player-directory-$_openActivityId'),
            activityId: _openActivityId!,
          ),
        ],
      );
    }
    if (_loading) {
      return Text(
        l10n.activityLoadingNotice,
        key: PlayerDirectorySurface.loadingKey,
        style: theme.textTheme.bodyMedium,
      );
    }
    if (_notice != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _notice!,
            key: PlayerDirectorySurface.failedKey,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: PlayerDirectorySurface.reloadKey,
            onPressed: _load,
            child: Text(l10n.activityReloadAction),
          ),
        ],
      );
    }
    if (_activities.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.playerActivitiesEmptyNotice,
            key: PlayerDirectorySurface.emptyKey,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.playerFactionRemainingNotice,
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.playerDirectorySectionTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.playerDirectorySectionIntro,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Column(
          key: PlayerDirectorySurface.listKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final MyActivityReport entry in _activities)
              Card(
                key: ValueKey<String>(
                  'player-directory-row-${entry.activityId}',
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 名稱與狀態都取服務端回顯：這一頁不重排、不翻譯取值。
                      Text(entry.name, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 4),
                      Text(
                        l10n.labelValuePair(
                          l10n.activityStatusLabel,
                          _statusLabel(l10n, entry.status),
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton(
                          key: PlayerDirectorySurface.openKey(entry.activityId),
                          onPressed: () => setState(
                            () => _openActivityId = entry.activityId,
                          ),
                          child: Text(l10n.playerDirectoryOpenAction),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l10n.playerFactionRemainingNotice,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// 某一場活動的目錄：篩選、搜尋、分頁、行、單筆詳情，以及永遠在下的本人資料。
class ActivityMemberDirectoryCard extends StatefulWidget {
  /// 以活動標識建立目錄卡。
  const ActivityMemberDirectoryCard({super.key, required this.activityId});

  /// 目標活動標識（路徑引數）。
  final String activityId;

  /// 目錄載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('member-directory-loading');

  /// 目錄載入失敗識別鍵。
  static const Key failedKey = ValueKey<String>('member-directory-failed');

  /// 1001 那一態（進不去這場活動的目錄）識別鍵。
  static const Key unavailableKey = ValueKey<String>(
    'member-directory-unavailable',
  );

  /// 「這一態不列任何人」識別鍵。
  static const Key hiddenKey = ValueKey<String>('member-directory-hidden');

  /// 真正空目錄識別鍵。
  static const Key emptyKey = ValueKey<String>('member-directory-empty-list');

  /// 篩後無識別鍵。
  static const Key noMatchKey = ValueKey<String>('member-directory-no-match');

  /// 列表容器識別鍵。
  static const Key listKey = ValueKey<String>('member-directory-list');

  /// 某一行的識別鍵。
  static Key rowKey(String memberId) =>
      ValueKey<String>('member-directory-row-$memberId');

  /// 某一行「打開資料」的識別鍵。
  static Key detailKey(String memberId) =>
      ValueKey<String>('member-directory-open-$memberId');

  /// 搜尋欄與送出識別鍵。
  static const Key searchKey = ValueKey<String>('member-directory-search');
  static const Key searchActionKey = ValueKey<String>(
    'member-directory-search-action',
  );
  static const Key filterAllKey = ValueKey<String>(
    'member-directory-filter-all',
  );
  static Key facetKey(String factionId) =>
      ValueKey<String>('member-directory-facet-$factionId');
  static const Key prevKey = ValueKey<String>('member-directory-prev');
  static const Key nextKey = ValueKey<String>('member-directory-next');
  static const Key modeKey = ValueKey<String>('member-directory-mode');

  /// 活動狀態列識別鍵（與「目錄空不空」分開講）。
  static const Key statusKey = ValueKey<String>('member-directory-status');

  /// 停止或歸檔那句說明列識別鍵。
  static const Key frozenKey = ValueKey<String>('member-directory-frozen');
  static const Key reloadKey = ValueKey<String>('member-directory-reload');
  static const Key presenceKey = ValueKey<String>('member-directory-presence');
  static const Key selfBadgeKey = ValueKey<String>(
    'member-directory-self-badge',
  );

  /// 本人資料那一段的容器識別鍵（它與目錄各成一段，不收錄別人）。
  static const Key profileKey = ValueKey<String>('member-directory-profile');

  /// 本人資料讀取失敗那一句的識別鍵。
  static const Key profileFailedKey = ValueKey<String>(
    'member-directory-profile-failed',
  );

  /// 本人那一段「業務狀態不是在線狀態」那句交代的識別鍵。
  static const Key statusScopeKey = ValueKey<String>(
    'member-directory-status-scope',
  );

  /// 某一行（或單筆詳情）業務狀態那一列的識別鍵。
  static Key statusRowKey(String memberId) =>
      ValueKey<String>('member-directory-status-$memberId');

  @override
  State<ActivityMemberDirectoryCard> createState() =>
      _ActivityMemberDirectoryCardState();
}

class _ActivityMemberDirectoryCardState
    extends State<ActivityMemberDirectoryCard> {
  late final ServerApi _api = AppScope.of(context).api;

  MemberDirectoryReport? _page;

  /// 目錄這一讀失敗那一句；非 null 時列表、篩選與分頁一律不長（不拿舊的一份冒充現值）。
  String? _notice;

  /// 這一次失敗是不是 1001（進不去這場活動的目錄）。它與其他失敗分開，
  /// 只因為處置不同：1001 換目標也不會變成另一句話，重讀不會改變結論。
  bool _unavailable = false;

  OwnMemberProfileReport? _profile;
  String? _profileNotice;

  final TextEditingController _keyword = TextEditingController();

  /// 已生效的關鍵字與陣營篩選（草稿欄的內容不算：只有按了搜尋才進查詢串）。
  String _appliedKeyword = '';
  String _appliedFactionId = '';
  int _pageNumber = 1;

  /// 詳情那一層：非 null 時整個卡轉成單筆受權詳情（按標識做 key，換人不留上一份）。
  String? _openMemberId;

  /// 本卡兩段讀法各自的請求序號：目錄與本人資料是兩筆並行的請求，
  /// 共用一枚計數器會讓先回的那一筆把後回的当成過期件（反之亦然）。
  int _directoryGeneration = 0;
  int _profileGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDirectory();
      _loadProfile();
    });
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀目錄一頁。
  ///
  /// 失敗時把這一份結果整段清掉：這一頁每一格都只在「這一次讀到的」時候出現，
  /// 留著上一批行讓人在失權之後還能讀見別人，是這一族讀法最不該發生的形態。
  Future<void> _loadDirectory() async {
    final int generation = ++_directoryGeneration;
    final String activityId = widget.activityId;
    setState(() => _notice = null);
    try {
      final MemberDirectoryReport report = await _api.playerMemberDirectory(
        activityId: activityId,
        page: _pageNumber,
        pageSize: kPlayerDirectoryPageSize,
        query: _appliedKeyword,
        factionId: _appliedFactionId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted || generation != _directoryGeneration) {
        return;
      }
      setState(() {
        _page = report;
        _unavailable = false;
      });
    } on ApiError catch (error) {
      if (!mounted || generation != _directoryGeneration) {
        return;
      }
      final AppLocalizations l10n = AppLocalizations.of(context);
      setState(() {
        _page = null;
        _unavailable = error.knownCode == ApiMachineCode.notFound;
        _notice = _unavailable
            ? l10n.playerDirectoryUnavailableNotice
            : apiErrorText(l10n, error);
      });
    }
  }

  /// 讀我自己的那份投影：它不經可見性判定，所以目錄收起時這一讀照舊成功。
  Future<void> _loadProfile() async {
    final int generation = ++_profileGeneration;
    try {
      final OwnMemberProfileReport report = await _api.playerOwnMemberProfile(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted || generation != _profileGeneration) {
        return;
      }
      setState(() {
        _profile = report;
        _profileNotice = null;
      });
    } on ApiError catch (error) {
      if (!mounted || generation != _profileGeneration) {
        return;
      }
      final AppLocalizations l10n = AppLocalizations.of(context);
      setState(() {
        // 本人那一讀失敗不該把目錄那一讀也抹掉，反之亦然：兩段各有各的失敗句。
        _profile = null;
        _profileNotice = error.knownCode == ApiMachineCode.notFound
            ? l10n.playerDirectoryUnavailableNotice
            : apiErrorText(l10n, error);
      });
    }
  }

  /// 目前沒有套任何關鍵字與陣營篩選：此時的一頁全空是「沒人可列」，
  /// 有篩選時才是「你看得見的人裡沒有符合的」——兩句在界面上分開。
  bool get _noFilterApplied =>
      _appliedKeyword.isEmpty && _appliedFactionId.isEmpty;

  /// 一次篩選變動：關鍵字與陣營都回到第一頁——頁碼屬「這一份結果集」的第幾頁，
  /// 換了結果集還留在第 3 頁，讀到的會是另一群人的中間一截。
  void _applyFilters({String? keyword, String? factionId}) {
    if (keyword != null) {
      _appliedKeyword = keyword.trim();
    }
    if (factionId != null) {
      _appliedFactionId = factionId;
    }
    _pageNumber = 1;
    _loadDirectory();
  }

  void _goToPage(int next) {
    if (next < 1 || next == _pageNumber) {
      return;
    }
    setState(() => _pageNumber = next);
    _loadDirectory();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    if (_openMemberId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OutlinedButton(
            key: ValueKey<String>('member-directory-detail-back'),
            onPressed: () => setState(() => _openMemberId = null),
            child: Text(l10n.playerDirectoryBackToRosterAction),
          ),
          const SizedBox(height: 12),
          PlayerMemberDetailCard(
            key: ValueKey<String>('member-detail-$_openMemberId'),
            activityId: widget.activityId,
            memberId: _openMemberId!,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ownProfileSection(l10n, theme),
        const SizedBox(height: 16),
        _directorySection(l10n, theme),
      ],
    );
  }

  /// 我自己的那一段：目錄收起時它仍是這卡上唯一確實有內容的地方。
  Widget _ownProfileSection(AppLocalizations l10n, ThemeData theme) {
    final OwnMemberProfileReport? profile = _profile;
    if (profile == null) {
      // 還在讀、或讀失敗：那一句寫在自己這段下面，不動目錄那一段。
      return Card(
        key: ActivityMemberDirectoryCard.profileKey,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.playerProfileSectionTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                _profileNotice ?? l10n.activityLoadingNotice,
                key: _profileNotice == null
                    ? null
                    : ActivityMemberDirectoryCard.profileFailedKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      key: ActivityMemberDirectoryCard.profileKey,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.playerProfileSectionTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            // 活動狀態與「這份目錄空不空」是兩件事：讀取路徑不受生命週期門禁約束（那道閘只管寫入），
            // 所以停止或歸檔的活動照舊列得出來。這一句寫在這裡，是為了讓玩家分得清
            // 「這場活動已經結束了」與「這場活動沒人看得見」——後端對兩者給的是不同的事實。
            Text(
              l10n.labelValuePair(
                l10n.activityStatusLabel,
                _statusLabel(l10n, profile.status),
              ),
              key: ActivityMemberDirectoryCard.statusKey,
              style: theme.textTheme.bodySmall,
            ),
            if (profile.status == 'closed' || profile.status == 'archived')
              Text(
                l10n.playerDirectoryFrozenReadNotice,
                key: ActivityMemberDirectoryCard.frozenKey,
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            // 那一格覆蓋只在「我把自己收起來」時多講一句：它是活動規則之外的第二層收緊。
            Text(
              l10n.labelValuePair(l10n.memberNicknameLabel, profile.nickname),
              style: theme.textTheme.bodyMedium,
            ),
            _factionLine(
              l10n,
              theme,
              profile.factionId,
              profile.factionName,
              profile.factionIcon,
              profile.factionColor,
              profile.factionAvailable,
            ),
            playerStatusLine(
              l10n,
              theme,
              businessStatus: profile.businessStatus,
              statusDisplayName: profile.statusDisplayName,
              customStatusName: profile.customStatusName,
              statusAvailable: profile.statusAvailable,
            ),
            // 本人這一讀也講一次兩者的分別：這一格由活動管理員維護，
            // 不是我連不連得上線；今日也沒有任何一格能隨請求或時間自己翻轉。
            Text(
              l10n.playerStatusNotConnectionNotice,
              key: ActivityMemberDirectoryCard.statusScopeKey,
              style: theme.textTheme.bodySmall,
            ),
            Text(
              l10n.labelValuePair(
                l10n.playerDirectoryJoinedAtLabel,
                _formatJoined(profile.joinedAt),
              ),
              style: theme.textTheme.bodySmall,
            ),
            Text(
              l10n.labelValuePair(
                l10n.playerDirectoryMemberIdLabel,
                profile.memberId,
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              profile.isSelfHidden
                  ? l10n.playerProfileHiddenByOverrideNotice
                  : l10n.playerProfileFollowsModeNotice,
              style: theme.textTheme.bodySmall,
            ),
            // TODO(待使用者批准新增簡介欄通路): 合同裡還沒有「簡介」這一欄，
            // 這一格只留佔位；落庫與白名單投影一併加時，把這行換成服務端讀回的那一份。
            _bioPlaceholder(l10n, theme),
          ],
        ),
      ),
    );
  }

  Widget _directorySection(AppLocalizations l10n, ThemeData theme) {
    if (_notice != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _notice!,
            key: _unavailable
                ? ActivityMemberDirectoryCard.unavailableKey
                : ActivityMemberDirectoryCard.failedKey,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: ActivityMemberDirectoryCard.reloadKey,
            onPressed: _loadDirectory,
            child: Text(l10n.activityReloadAction),
          ),
        ],
      );
    }
    final MemberDirectoryReport? page = _page;
    if (page == null) {
      return Text(
        l10n.activityLoadingNotice,
        key: ActivityMemberDirectoryCard.loadingKey,
        style: theme.textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.playerDirectoryCardTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        // 模式現值取回應（絕不在請求）：界面據它說得出「這一態本來就不列任何人」。
        Text(
          '${l10n.memberDirectoryCurrentModeLabel} '
          '${_modeLabel(l10n, page.memberDirectoryMode)}',
          key: ActivityMemberDirectoryCard.modeKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        _searchRow(l10n),
        const SizedBox(height: 6),
        _facetRow(l10n),
        const SizedBox(height: 10),
        if (page.isHiddenByPolicy)
          Text(
            l10n.playerDirectoryHiddenNotice,
            key: ActivityMemberDirectoryCard.hiddenKey,
            style: theme.textTheme.bodyMedium,
          )
        else if (page.total == 0)
          Text(
            _noFilterApplied
                ? l10n.playerDirectoryEmptyNotice
                : l10n.playerDirectoryNoMatchNotice,
            key: _noFilterApplied
                ? ActivityMemberDirectoryCard.emptyKey
                : ActivityMemberDirectoryCard.noMatchKey,
            style: theme.textTheme.bodyMedium,
          )
        else
          Column(
            key: ActivityMemberDirectoryCard.listKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final DirectoryMemberReport row in page.members)
                _row(l10n, theme, row, row.memberId == page.selfMemberId),
            ],
          ),
        const SizedBox(height: 8),
        _pageRow(l10n, page),
        const SizedBox(height: 6),
        Text(
          l10n.playerDirectoryPresenceNotice,
          key: ActivityMemberDirectoryCard.presenceKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        OutlinedButton(
          key: ActivityMemberDirectoryCard.reloadKey,
          onPressed: _loadDirectory,
          child: Text(l10n.activityReloadAction),
        ),
      ],
    );
  }

  /// 一行目錄項：暱稱與標識都可換行（窄欄不截斷），陣營靠展示值說話。
  Widget _row(
    AppLocalizations l10n,
    ThemeData theme,
    DirectoryMemberReport row,
    bool isSelf,
  ) {
    return Card(
      key: ActivityMemberDirectoryCard.rowKey(row.memberId),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _avatarPlaceholder(l10n),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      // 長暱稱靠換行而不是截斷：這一欄是展示值，被切掉就讀不出來。
                      Text(row.nickname, style: theme.textTheme.bodyLarge),
                      if (isSelf)
                        Text(
                          l10n.playerDirectorySelfLabel,
                          key: ActivityMemberDirectoryCard.selfBadgeKey,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  _factionLine(
                    l10n,
                    theme,
                    row.factionId,
                    row.factionName,
                    row.factionIcon,
                    row.factionColor,
                    row.factionAvailable,
                  ),
                  playerStatusLine(
                    l10n,
                    theme,
                    key: ActivityMemberDirectoryCard.statusRowKey(row.memberId),
                    businessStatus: row.businessStatus,
                    statusDisplayName: row.statusDisplayName,
                    customStatusName: row.customStatusName,
                    statusAvailable: row.statusAvailable,
                  ),
                  Text(
                    l10n.labelValuePair(
                      l10n.playerDirectoryJoinedAtLabel,
                      _formatJoined(row.joinedAt),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    l10n.labelValuePair(
                      l10n.playerDirectoryMemberIdLabel,
                      row.memberId,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: ActivityMemberDirectoryCard.detailKey(row.memberId),
              onPressed: () => setState(() => _openMemberId = row.memberId),
              child: Text(l10n.playerDirectoryOpenProfileAction),
            ),
          ],
        ),
      ),
    );
  }

  /// 陣營那一列：三種「讀不到歸屬」各有各的句子，不混成一句「已停用」。
  Widget _factionLine(
    AppLocalizations l10n,
    ThemeData theme,
    String factionId,
    String factionName,
    String factionIcon,
    String factionColor,
    bool factionAvailable,
  ) {
    if (factionId.isEmpty) {
      return Text(
        l10n.labelValuePair(
          l10n.memberFactionColumnLabel,
          l10n.playerCurrentFactionNone,
        ),
        style: theme.textTheme.bodySmall,
      );
    }
    if (factionName.isEmpty) {
      // 歸屬讀不到展示值屬資料形態缺陷：界面如實念標識並換一句說法，不替那個陣營編名字。
      return Text(
        '${l10n.memberFactionColumnLabel}: '
        '${l10n.playerDirectoryFactionUnreadableNotice}',
        style: theme.textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _factionBadge(factionIcon, factionColor),
        Text(
          l10n.labelValuePair(l10n.memberFactionColumnLabel, factionName),
          style: theme.textTheme.bodySmall,
        ),
        if (!factionAvailable)
          Text(
            l10n.playerDirectoryFactionDisabledSuffix,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  /// 搜尋列：草稿欄與已生效的關鍵字分開，只有送出那次進查詢串（口徑同管理側目錄）。
  Widget _searchRow(AppLocalizations l10n) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            key: ActivityMemberDirectoryCard.searchKey,
            controller: _keyword,
            textInputAction: TextInputAction.search,
            onSubmitted: (String value) => _applyFilters(keyword: value),
            decoration: InputDecoration(
              isDense: true,
              labelText: l10n.playerDirectorySearchLabel,
              hintText: l10n.playerDirectorySearchHint,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: ActivityMemberDirectoryCard.searchActionKey,
          onPressed: () => _applyFilters(keyword: _keyword.text),
          child: Text(l10n.playerDirectorySearchAction),
        ),
      ],
    );
  }

  /// 陣營篩選候選：那一行計數是「這個我看見幾個人」，與列表同一份結果集，不是全場人數。
  Widget _facetRow(AppLocalizations l10n) {
    final MemberDirectoryReport? page = _page;
    final List<DirectoryFacetReport> facets =
        page?.facets ?? const <DirectoryFacetReport>[];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        Text(
          l10n.playerDirectoryFilterLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        FilterChip(
          key: ActivityMemberDirectoryCard.filterAllKey,
          label: Text(l10n.playerDirectoryFilterAllAction),
          selected: _appliedFactionId.isEmpty,
          onSelected: (_) => _applyFilters(factionId: ''),
        ),
        for (final DirectoryFacetReport facet in facets)
          FilterChip(
            key: ActivityMemberDirectoryCard.facetKey(facet.factionId),
            label: Text('${facet.name} · ${facet.count}'),
            avatar: _factionBadge(facet.icon, facet.color),
            selected: _appliedFactionId == facet.factionId,
            onSelected: (bool selected) =>
                _applyFilters(factionId: selected ? facet.factionId : ''),
          ),
      ],
    );
  }

  /// 分頁列：頁碼、每頁筆數與總數全取後端回顯，界面不重排也不自己數行。
  Widget _pageRow(AppLocalizations l10n, MemberDirectoryReport page) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        OutlinedButton(
          key: ActivityMemberDirectoryCard.prevKey,
          onPressed: page.page > 1 ? () => _goToPage(page.page - 1) : null,
          child: Text(l10n.playerDirectoryPrevAction),
        ),
        Text(
          l10n.playerDirectoryPageSummary(
            page.page,
            page.totalPages,
            page.total,
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        OutlinedButton(
          key: ActivityMemberDirectoryCard.nextKey,
          onPressed: page.hasMore ? () => _goToPage(page.page + 1) : null,
          child: Text(l10n.playerDirectoryNextAction),
        ),
      ],
    );
  }

  /// 頭像佔位：合同裡沒有頭像欄位，因此這裡只放本地佔位圖標，不開上傳通路。
  Widget _avatarPlaceholder(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: l10n.playerDirectoryAvatarSemantics,
      child: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        foregroundColor: theme.colorScheme.onSurfaceVariant,
        child: const Icon(Icons.person_outline, size: 20),
      ),
    );
  }

  String _formatJoined(DateTime value) => value.toUtc().toIso8601String();

  /// 模式取值的人話名稱；表外值照實顯示原值，不靜默歸類成某一態。
  String _modeLabel(AppLocalizations l10n, String mode) {
    return switch (mode) {
      'hidden' => l10n.memberDirectoryModeHidden,
      'same_faction_only' => l10n.memberDirectoryModeSameFaction,
      'all_players_except_admin' => l10n.memberDirectoryModeExceptAdmin,
      'all_members' => l10n.memberDirectoryModeAllMembers,
      _ => l10n.memberDirectoryModeUnknown(mode),
    };
  }
}

/// 單筆詳情：重新問一次受權讀法，不拿列表那一行本地展開。
class PlayerMemberDetailCard extends StatefulWidget {
  /// 以活動與成員標識建立詳情卡。
  const PlayerMemberDetailCard({
    super.key,
    required this.activityId,
    required this.memberId,
  });

  /// 目標活動標識。
  final String activityId;

  /// 目標成員標識（路徑引數）。
  final String memberId;

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('member-detail-loading');

  /// 載入失敗識別鍵（其他原因）。
  static const Key failedKey = ValueKey<String>('member-detail-failed');

  /// 1001 那一態識別鍵：失權與查無同一句話，讀到的內容此時已全部清掉。
  static const Key unavailableKey = ValueKey<String>(
    'member-detail-unavailable',
  );

  /// 容器識別鍵。
  static const Key cardKey = ValueKey<String>('member-detail-card');

  @override
  State<PlayerMemberDetailCard> createState() => _PlayerMemberDetailCardState();
}

class _PlayerMemberDetailCardState extends State<PlayerMemberDetailCard> {
  late final ServerApi _api = AppScope.of(context).api;

  DirectoryMemberDetailReport? _view;
  String? _notice;
  bool _unavailable = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀單筆詳情。失敗時把已顯示的那一份清掉：下一次權威請求說「讀不到」之後，
  /// 上一批留下的內容就不再是內容，倉庫裡也沒有「離線緩存」能當授權依據。
  Future<void> _load() async {
    final int generation = ++_generation;
    final String activityId = widget.activityId;
    final String memberId = widget.memberId;
    setState(() {
      _notice = null;
      _view = null;
    });
    try {
      final DirectoryMemberDetailReport report = await _api
          .playerDirectoryMember(
            activityId: activityId,
            memberId: memberId,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted ||
          generation != _generation ||
          activityId != widget.activityId ||
          memberId != widget.memberId) {
        return;
      }
      setState(() {
        _view = report;
        _unavailable = false;
      });
    } on ApiError catch (error) {
      if (!mounted ||
          generation != _generation ||
          activityId != widget.activityId ||
          memberId != widget.memberId) {
        return;
      }
      final AppLocalizations l10n = AppLocalizations.of(context);
      setState(() {
        _unavailable = error.knownCode == ApiMachineCode.notFound;
        _notice = _unavailable
            ? l10n.playerDirectoryUnavailableNotice
            : apiErrorText(l10n, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    if (_notice != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _notice!,
            key: _unavailable
                ? PlayerMemberDetailCard.unavailableKey
                : PlayerMemberDetailCard.failedKey,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: ValueKey<String>('member-detail-reload'),
            onPressed: _load,
            child: Text(l10n.activityReloadAction),
          ),
        ],
      );
    }
    final DirectoryMemberDetailReport? view = _view;
    if (view == null) {
      return Text(
        l10n.activityLoadingNotice,
        key: PlayerMemberDetailCard.loadingKey,
        style: theme.textTheme.bodyMedium,
      );
    }
    final DirectoryMemberReport member = view.member;
    return Card(
      key: PlayerMemberDetailCard.cardKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.playerDetailTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  child: const Icon(Icons.person_outline, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  // 長暱稱在此換行：詳情是讀一個人的地方，截斷等於沒讀到。
                  child: Text(
                    member.nickname,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _line(
              l10n,
              theme,
              l10n.playerDirectoryMemberIdLabel,
              member.memberId,
            ),
            _line(
              l10n,
              theme,
              l10n.memberFactionColumnLabel,
              member.hasFaction
                  ? (member.hasFactionDisplay
                        ? member.factionName
                        : l10n.playerDirectoryFactionUnreadableNotice)
                  : l10n.playerCurrentFactionNone,
            ),
            if (member.hasFaction &&
                member.hasFactionDisplay &&
                !member.factionAvailable)
              Text(
                l10n.playerDirectoryFactionDisabledSuffix,
                style: theme.textTheme.bodySmall,
              ),
            playerStatusLine(
              l10n,
              theme,
              key: ActivityMemberDirectoryCard.statusRowKey(member.memberId),
              businessStatus: member.businessStatus,
              statusDisplayName: member.statusDisplayName,
              customStatusName: member.customStatusName,
              statusAvailable: member.statusAvailable,
            ),
            _line(
              l10n,
              theme,
              l10n.playerDirectoryJoinedAtLabel,
              member.joinedAt.toUtc().toIso8601String(),
            ),
            const SizedBox(height: 6),
            // 詳情這一段只列白名單投影那幾格；帳戶側事實從一開始就不在回應裡，
            // 界面因此沒有一格能「拿本地角色自己拼出後台欄位」。
            Text(
              l10n.playerDetailScopeNotice,
              style: theme.textTheme.bodySmall,
            ),
            // TODO(待使用者批准新增簡介欄通路): 同目錄那一段——合同裡還沒有「簡介」這一欄。
            _bioPlaceholder(l10n, theme),
            const SizedBox(height: 6),
            OutlinedButton(
              key: ValueKey<String>('member-detail-reload-again'),
              onPressed: _load,
              child: Text(l10n.activityReloadAction),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(
    AppLocalizations l10n,
    ThemeData theme,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        l10n.labelValuePair(label, value),
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

/// 陣營的小圓徽標：顏色讀不進來時落中性底色，圖標鍵不認識時落佔位圖標。
///
/// 任何界面都不得只靠顏色辨認一個陣營——名稱與標識才是（口徑同管理側那份徽章）。
Widget _factionBadge(String icon, String color) {
  return Builder(
    builder: (BuildContext context) {
      final ThemeData theme = Theme.of(context);
      final int? argb = _factionArgb(color);
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: argb == null
              ? theme.colorScheme.surfaceContainerHighest
              : Color(argb),
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Icon(
          factionIconData(icon),
          size: 12,
          color: argb == null
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onPrimary,
        ),
      );
    },
  );
}

/// 把 #RRGGBB 解析成 ARGB 整數；非法或空值回 null（呼叫端以中性佔位兜底）。
int? _factionArgb(String value) {
  if (value.length != 7 || !value.startsWith('#')) {
    return null;
  }
  final int? rgb = int.tryParse(value.substring(1), radix: 16);
  if (rgb == null) {
    return null;
  }
  return 0xFF000000 | rgb;
}

/// 生命週期狀態取值的人話名稱；表外值照實顯示原值，不靜默歸類成某一態
/// （口徑同管理側那兩份目錄：後端只增不刪，界面不得把認不得的值當成「已歸檔」）。
String _statusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'draft' => l10n.activityStatusDraftLabel,
    'active' => l10n.activityStatusActiveLabel,
    'closed' => l10n.activityStatusClosedLabel,
    'archived' => l10n.activityStatusArchivedLabel,
    _ => l10n.activityUnknownStatusLabel(status),
  };
}

/// 「簡介」那一格的佔位：合同裡還沒有這一欄，界面因此只說這件事，不空白也不編。
///
/// 這一格存在的理由只有一個——把「介面已經預留了位置」與「後端已經有這個欄位」
/// 分開。若不擺這段佔位，讀代碼的人會以為這一欄是界面漏畫了；若擺一個本地輸入框，
/// 又會讓人以為填了就會存進服務端。兩件都不對，所以這裡只放一句四語言的說明。
Widget _bioPlaceholder(AppLocalizations l10n, ThemeData theme) {
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.playerBioLabel, style: theme.textTheme.bodySmall),
        Text(
          l10n.playerBioNotWiredNotice,
          key: ValueKey<String>('player-bio-placeholder'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    ),
  );
}

/// 業務狀態那一列：顯示名一律取自服務端算好的展示值，沒有覆蓋才走四語言預設文案。
///
/// 三種「讀不到」各有各的說法：自訂定義讀不到時念「讀不到那個定義」而不編一個名稱，
/// 已停用的自訂定義仍是那一行的現值（界面講「已停用新的選用」而不是「人不見了」）。
/// 目錄行、單筆詳情與本人投影共用這一份換算，所以三處不可能各唸一套。
Widget playerStatusLine(
  AppLocalizations l10n,
  ThemeData theme, {
  Key? key,
  required String businessStatus,
  required String statusDisplayName,
  required String customStatusName,
  required bool statusAvailable,
}) {
  final String? label = businessStatusLabel(
    l10n: l10n,
    businessStatus: businessStatus,
    statusDisplayName: statusDisplayName,
    customStatusName: customStatusName,
  );
  return Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        l10n.labelValuePair(
          l10n.playerStatusFieldLabel,
          label ?? l10n.playerStatusCustomMissingNotice,
        ),
        style: theme.textTheme.bodySmall,
      ),
      if (!statusAvailable)
        Text(l10n.playerStatusDisabledNotice, style: theme.textTheme.bodySmall),
    ],
  );
}
