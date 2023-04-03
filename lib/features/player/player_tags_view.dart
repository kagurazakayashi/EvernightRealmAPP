/// 玩家端的「本活動公開標籤定義」卡：先列我有成員行的活動，再讀那一場活動被管理人
/// 對外公開的標籤定義本身。
///
/// 這一頁的每一句都來自服務端回讀，寫在這裡是因為界面藏不住它們：
///
/// * 能讀不讀得到由會話決定：這一族路徑沒有「哪個玩家」這格可填，頁面也不帶帳戶標識。
///   準入問的是「這次請求的憑據換出的那個帳戶在這場活動有沒有成員行」——非成員與 Root
///   拿到的是同一句 1001，匿名拿到 2002：兩句各說各的，由統一對映轉述，界面不混用。
/// * 讀到的是白名單投影，只有定義本身與展示四值：回應裡沒有可用性、沒有公開旗標、
///   沒有時刻、也沒有任何計數。界面因此不可能把「這一枚停用了」念出來——那一格對玩家
///   讀不到，也不是他該知道的內部事實；把本地推測填進去就是憑空發明事實。
/// * 「有這枚標籤、只是沒被設成公開」「從未有過這個標識」「它屬於另一場活動」是同一句
///   1001：這條路徑不當內部定義的存在性探測器，界面也不能據回應分辨三者，
///   因此只給一句不可分辨的話，不多說「其實存在但對你不列」。
/// * 公開那一欄只決定這份定義讀不讀得到：它不是角色、不是權限，也不改變誰能在目錄裡
///   被看見（那一件事由活動的目錄規則與成員那一行的覆蓋決定）。這句話寫在清單下方，
///   因為玩家最容易把「這份定義對外了」讀成「我被對外介紹了」。
/// * 「誰帶著哪個標籤」尚未落地：這一頁沒有成員名單、沒有一行計數、也沒有把標籤畫在
///   目錄某一行上，只擺一句「這一份只有定義」，不拿空清單或 0 冒充已經有了。
/// * 請求綁在發起它的那一場活動：每一次載入都帶著自己的序號，遲到的那一份
///   （換了活動、回到清單、按了重新讀取）一律丟掉，不准它覆蓋新頁面的結果。
/// * 倉庫裡沒有快取層也沒有實時層：失效形態只有「下一筆請求按新規則判定」，
///   這句話寫在界面上，不讓人以為管理人收回公開後自己螢幕上那一行會自己消失。
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

/// 玩家端的公開標籤通路（含本人的活動清單）。
class PlayerTagsCard extends StatefulWidget {
  /// 建立玩家端標籤通路。
  const PlayerTagsCard({super.key});

  /// 活動清單載入中識別鍵。
  static const Key activitiesLoadingKey = ValueKey<String>(
    'player-tags-activities-loading',
  );

  /// 活動清單載入失敗識別鍵。
  static const Key activitiesFailedKey = ValueKey<String>(
    'player-tags-activities-failed',
  );

  /// 活動清單重新讀取識別鍵。
  static const Key activitiesReloadKey = ValueKey<String>(
    'player-tags-activities-reload',
  );

  /// 本人沒有參加任何活動的識別鍵（與「讀不到標籤」是兩件事）。
  static const Key activitiesEmptyKey = ValueKey<String>(
    'player-tags-activities-empty',
  );

  /// 活動清單容器識別鍵。
  static const Key activitiesListKey = ValueKey<String>(
    'player-tags-activities-list',
  );

  /// 活動清單某一行的識別鍵。
  static Key activityRowKey(String activityId) =>
      ValueKey<String>('player-tags-activity-row-$activityId');

  /// 某一場活動的進入按鈕識別鍵。
  static Key openKey(String activityId) =>
      ValueKey<String>('player-tags-open-$activityId');

  /// 標籤那一讀的載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('player-tags-loading');

  /// 標籤那一讀的失敗識別鍵（1001 之外的其他原因）。
  static const Key failedKey = ValueKey<String>('player-tags-failed');

  /// 1001 那一態識別鍵：非成員、跨活動、未公開、查無標識四種原因同一句話。
  static const Key unavailableKey = ValueKey<String>('player-tags-unavailable');

  /// 標籤讀取的重新讀取識別鍵（本卡唯一的失效出口）。
  static const Key reloadKey = ValueKey<String>('player-tags-reload');

  /// 回到活動清單識別鍵。
  static const Key backKey = ValueKey<String>('player-tags-back');

  /// 「這場活動還沒公開任何定義」識別鍵（空清單是可表達的事實，不是錯誤）。
  static const Key emptyKey = ValueKey<String>('player-tags-empty');

  /// 標籤列表容器識別鍵。
  static const Key listKey = ValueKey<String>('player-tags-list');

  /// 列表某一行的識別鍵。
  static Key rowKey(String tagId) => ValueKey<String>('player-tags-row-$tagId');

  /// 「這一份只有定義」那句交代列識別鍵。
  static const Key definitionsOnlyKey = ValueKey<String>(
    'player-tags-definitions-only',
  );

  /// 「貼標籤尚未落地」那句交代列識別鍵。
  static const Key assignmentPendingKey = ValueKey<String>(
    'player-tags-assignment-pending',
  );

  /// 「誰能被看見由目錄規則決定，不由標籤決定」識別鍵。
  static const Key directoryScopeKey = ValueKey<String>(
    'player-tags-directory-scope',
  );

  /// 「沒有快取，下一筆請求重讀」識別鍵。
  static const Key noCacheKey = ValueKey<String>('player-tags-no-cache');

  @override
  State<PlayerTagsCard> createState() => _PlayerTagsCardState();
}

class _PlayerTagsCardState extends State<PlayerTagsCard> {
  late final ServerApi _api = AppScope.of(context).api;

  List<MyActivityReport> _activities = const <MyActivityReport>[];
  bool _activitiesLoading = true;
  String? _activitiesNotice;

  /// 非 null 時顯示某一場活動的公開標籤清單（只由清單那一行按標識進入，不做本地推測）。
  String? _openActivityId;

  List<PublicTagReport> _tags = const <PublicTagReport>[];
  bool _tagsLoading = false;

  /// 標籤那一讀失敗那一句；非 null 時列表一律不長（不拿上一批冒充現值）。
  String? _tagsNotice;

  /// 這一次失敗是不是 1001（讀不到那一場活動的公開定義）。它與其他失敗分開，
  /// 只因為處置不同：1001 換目標也不會變成另一句話，重讀不改變結論。
  bool _tagsUnavailable = false;

  /// 兩段讀法各自的請求序號：活動清單與標籤清單是兩筆獨立的請求，
  /// 共用一枚計數器會讓先回的那一筆把後回的當成過期件。
  int _activitiesGeneration = 0;
  int _tagsGeneration = 0;

  @override
  void initState() {
    super.initState();
    // 首讀排在第一幀之後，免得在 initState 裡讀 Localizations（同目錄卡手法）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActivities());
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀本人的活動清單。失敗時整段轉述那一句失敗，不顯示任何舊清單。
  Future<void> _loadActivities() async {
    final int generation = ++_activitiesGeneration;
    setState(() => _activitiesLoading = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final MyActivityListReport report = await _api.myActivities(
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted || generation != _activitiesGeneration) {
        return;
      }
      setState(() {
        _activitiesLoading = false;
        _activities = report.activities;
        _activitiesNotice = null;
      });
    } on ApiError catch (error) {
      if (!mounted || generation != _activitiesGeneration) {
        return;
      }
      setState(() {
        _activitiesLoading = false;
        _activities = const <MyActivityReport>[];
        _activitiesNotice = apiErrorText(l10n, error);
      });
    }
  }

  /// 讀某一場活動被對外公開的標籤定義。
  ///
  /// 序號與活動標識兩個條件都要核對：換了活動之後才回來的舊回應既不屬於眼前這一頁，
  /// 也不屬於它自己那一頁（這一族沒有第二份權威讀法能讓它落地），必須被丟棄。
  /// 失敗時把這一份結果整段清掉：倉庫裡沒有離線緩存能當授權依據，留著上一批行
  /// 讓人在失權之後還能讀見內容，是這一族讀法最不該發生的形態。
  Future<void> _loadTags(String activityId) async {
    final int generation = ++_tagsGeneration;
    setState(() {
      _tagsLoading = true;
      _tagsNotice = null;
      _tags = const <PublicTagReport>[];
    });
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final PublicTagListReport report = await _api.publicActivityTags(
        activityId: activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted ||
          generation != _tagsGeneration ||
          activityId != _openActivityId) {
        return;
      }
      setState(() {
        _tagsLoading = false;
        _tags = report.tags;
        _tagsUnavailable = false;
      });
    } on ApiError catch (error) {
      if (!mounted ||
          generation != _tagsGeneration ||
          activityId != _openActivityId) {
        return;
      }
      setState(() {
        _tagsLoading = false;
        _tagsUnavailable = error.knownCode == ApiMachineCode.notFound;
        // 1001 那一句由界面自己說而不轉述通用映射：四種原因（不是成員、跨活動、
        // 未公開、查無）在外頭就是同一句，那句裡不能出現「其實存在但對你不列」。
        // 其餘失敗（2002 匿名、2011、傳輸級失敗）各由統一對映念自己那一句。
        _tagsNotice = _tagsUnavailable
            ? l10n.playerTagsUnavailableNotice
            : apiErrorText(l10n, error);
      });
    }
  }

  /// 進入某一場活動：清單那一份結果留在原地，標籤那一讀按標識重新問一次。
  void _open(String activityId) {
    setState(() => _openActivityId = activityId);
    _loadTags(activityId);
  }

  /// 回到清單：先讓這一場活動那筆還壓著的回應變成過期件（序號與標識都對不上），
  /// 再把清單那一段換成新的可選目標。
  void _backToActivities() {
    _tagsGeneration++;
    setState(() {
      _openActivityId = null;
      _tags = const <PublicTagReport>[];
      _tagsNotice = null;
      _tagsUnavailable = false;
      _tagsLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String? activityId = _openActivityId;
    if (activityId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OutlinedButton(
            key: PlayerTagsCard.backKey,
            onPressed: _backToActivities,
            child: Text(l10n.playerBackToActivitiesAction),
          ),
          const SizedBox(height: 12),
          // 失敗與清單都掛在「活動標識」這一段下面：上一場的回應留不下來。
          _tagsSection(l10n, theme, activityId),
        ],
      );
    }
    return _activitiesSection(l10n, theme);
  }

  /// 本人的活動清單：後端已經按會話筛過（只列他有成員行的活動），界面不重排也不自查。
  Widget _activitiesSection(AppLocalizations l10n, ThemeData theme) {
    if (_activitiesLoading) {
      return Text(
        l10n.activityLoadingNotice,
        key: PlayerTagsCard.activitiesLoadingKey,
        style: theme.textTheme.bodyMedium,
      );
    }
    if (_activitiesNotice != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _activitiesNotice!,
            key: PlayerTagsCard.activitiesFailedKey,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: PlayerTagsCard.activitiesReloadKey,
            onPressed: _loadActivities,
            child: Text(l10n.activityReloadAction),
          ),
        ],
      );
    }
    if (_activities.isEmpty) {
      // 「我沒有参加任何活動」與「這場活動沒公開標籤」是兩件事：這一段只說前一件，
      // 後一句留在標籤卡那一段，兩處不互相冒充。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.playerActivitiesEmptyNotice,
            key: PlayerTagsCard.activitiesEmptyKey,
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
        Text(l10n.playerTagsSectionTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.playerTagsSectionIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        Column(
          key: PlayerTagsCard.activitiesListKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final MyActivityReport entry in _activities)
              Card(
                key: PlayerTagsCard.activityRowKey(entry.activityId),
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
                      // 「這一場進不去」說在敲壁之前：這一格是服務端現值投影
                      // （access_restricted），界面不本地推測，也不因為它為真就把這一列藏起來。
                      if (entry.accessRestricted)
                        Text(
                          l10n.playerActivityAccessRestricted,
                          key: ValueKey<String>(
                            'player-tags-restricted-${entry.activityId}',
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton(
                          key: PlayerTagsCard.openKey(entry.activityId),
                          onPressed: () => _open(entry.activityId),
                          child: Text(l10n.playerTagsOpenAction),
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
          l10n.playerTagsDirectoryScopeNotice,
          key: PlayerTagsCard.directoryScopeKey,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.playerFactionRemainingNotice,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// 某一場活動的公開定義清單：載入、失敗、空、四種狀態各有各的一句。
  Widget _tagsSection(
    AppLocalizations l10n,
    ThemeData theme,
    String activityId,
  ) {
    if (_tagsLoading) {
      return Text(
        l10n.playerTagsLoadingNotice,
        key: PlayerTagsCard.loadingKey,
        style: theme.textTheme.bodyMedium,
      );
    }
    if (_tagsNotice != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _tagsNotice!,
            key: _tagsUnavailable
                ? PlayerTagsCard.unavailableKey
                : PlayerTagsCard.failedKey,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: PlayerTagsCard.reloadKey,
            onPressed: () => _loadTags(activityId),
            child: Text(l10n.activityReloadAction),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.playerTagsCardTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.playerTagsCardIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        if (_tags.isEmpty)
          Text(
            l10n.playerTagsEmptyNotice,
            key: PlayerTagsCard.emptyKey,
            style: theme.textTheme.bodyMedium,
          )
        else
          Column(
            key: PlayerTagsCard.listKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final PublicTagReport tag in _tags) _row(l10n, theme, tag),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          l10n.playerTagsDefinitionsOnlyNotice,
          key: PlayerTagsCard.definitionsOnlyKey,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.playerTagsAssignmentPendingNotice,
          key: PlayerTagsCard.assignmentPendingKey,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.playerTagsDirectoryScopeNotice,
          key: PlayerTagsCard.directoryScopeKey,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.playerTagsNoCacheNotice,
          key: PlayerTagsCard.noCacheKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          key: PlayerTagsCard.reloadKey,
          onPressed: () => _loadTags(activityId),
          child: Text(l10n.playerRefreshAction),
        ),
      ],
    );
  }

  /// 一行定義：圖標與顏色只是展示，名稱永遠以文字同時在場。
  ///
  /// 這一行只列玩家讀得到的那幾格（標識、名稱、描述、圖標、顏色、排序）：
  /// 沒有可用性可念、沒有公開旗標可念、也沒有計數可念——回應裡根本沒有那些格子，
  /// 界面不拿空白或 0 冒充它們存在而為空。
  Widget _row(AppLocalizations l10n, ThemeData theme, PublicTagReport tag) {
    return Card(
      key: PlayerTagsCard.rowKey(tag.tagId),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _TagBadge(icon: tag.icon, color: tag.color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 長名稱靠換行而不是截斷：這一欄是定義本身，被切掉就讀不完整。
                  Text(tag.name, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    tag.description.isEmpty
                        ? l10n.playerTagsNoDescriptionLabel
                        : tag.description,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.labelValuePair(l10n.playerTagsIdLabel, tag.tagId),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 狀態取值的人話名稱；表外值照實顯示原值，不靜默歸類成某一態
  /// （口徑同管理側那兩份目錄：後端只增不刪，界面不得把認不得值當成某一態）。
  String _statusLabel(AppLocalizations l10n, String status) {
    return switch (status) {
      'draft' => l10n.activityStatusDraftLabel,
      'active' => l10n.activityStatusActiveLabel,
      'closed' => l10n.activityStatusClosedLabel,
      'archived' => l10n.activityStatusArchivedLabel,
      _ => l10n.activityUnknownStatusLabel(status),
    };
  }
}

/// 標籤的小圓徽標：顏色讀不進來時落中性底色，圖標鍵不認識時落佔位圖標。
///
/// 任何界面都不得只靠顏色辨認一枚標籤——名稱與標識才是（口徑同管理側那份徽章）。
class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.icon, required this.color});

  final String icon;
  final String color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? argb = _parseHexColor(color);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: argb == null
            ? theme.colorScheme.surfaceContainerHighest
            : Color(argb),
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Icon(
        factionIconData(icon),
        size: 16,
        color: argb == null
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onPrimary,
      ),
    );
  }
}

/// 把 #RRGGBB 解析成 ARGB 整數；非法或空值回 null（呼叫端以中性佔位兜底）。
int? _parseHexColor(String value) {
  if (value.length != 7 || !value.startsWith('#')) {
    return null;
  }
  final int? rgb = int.tryParse(value.substring(1), radix: 16);
  if (rgb == null) {
    return null;
  }
  return 0xFF000000 | rgb;
}
