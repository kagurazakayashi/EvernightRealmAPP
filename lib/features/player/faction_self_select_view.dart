/// 玩家端「我的陣營」通路：讀我參加了哪些活動、讀我在某一場活動裡的陣營現況，
/// 以及在這場活動允許時自己把歸屬選下去。
///
/// 這一頁的每一句都來自服務端回讀，寫在這裡是因為界面藏不住它們：
///
/// * 主體由會話決定：這一族路徑沒有「哪個玩家」這格可填，頁面也不帶帳戶標識。
///   登入的是誰就是誰，因此這一頁永遠只顯示「我的」歸屬；別人的歸屬不在任何一份回應裡。
/// * 底稿只能來自本卡讀回的現值：自選提交的 `expected_faction_id` 是上一次 GET 讀到的
///   那一個（空字串＝我此刻尚未分組）。本地印象與清單裡的舊行都不夠格當依據值。
/// * `can_select_now` 是後端派生值，只決定界面長不長那顆按鈕；寫入通路在服務端
///   自己的交易內重新問同樣的幾句話。藏按鈕永遠不代替那道閘，所以失敗句也照實轉述。
/// * 停用與表外狀態不藏起來：已停用的陣營照樣列在候選裡並標成「不再接收新成員」，
///   因為既有歸屬保留是已批準的語意，界面把這件事顯示出來比消失更好解釋。
/// * 自選只能設定歸屬，不能清空：本版本沒有把陣營改回「尚未分組」的通路，
///   頁面因此不擺那顆按鈕，也把這句話寫在限制說明裡（而不是讓人試錯試出一句 1001）。
/// * 結果不明（連不上、逾時）絕不自動補發：同一份過期依據值重發只會拿回 2013，
///   界面因此只給「重新讀取我的現值」一個出口。
/// * 活動內的其他一切（錢包、聊天、文件、階段）都不屬於這個版本：這一頁不列它們，
///   也不拿空清單或 0 冒充已經有了。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../app/app_dependencies.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 玩家端的陣營自選入口（含本人的活動清單）。
class PlayerFactionSurface extends StatefulWidget {
  /// 建立玩家端陣營通路。
  const PlayerFactionSurface({super.key});

  /// 清單容器識別鍵。
  static const Key listKey = ValueKey<String>('player-activities-list');

  /// 空清單識別鍵。
  static const Key emptyKey = ValueKey<String>('player-activities-empty');

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('player-activities-loading');

  /// 載入失敗識別鍵。
  static const Key failedKey = ValueKey<String>('player-activities-failed');

  /// 重新讀取識別鍵。
  static const Key reloadKey = ValueKey<String>('player-activities-reload');

  /// 某一行活動的識別鍵。
  static Key rowKey(String activityId) =>
      ValueKey<String>('player-activities-row-$activityId');

  /// 某一行的進入按鈕識別鍵。
  static Key openKey(String activityId) =>
      ValueKey<String>('player-activities-open-$activityId');

  /// 現況卡容器識別鍵（null 表示還在清單層）。
  static const Key detailKey = ValueKey<String>('player-faction-detail');

  @override
  State<PlayerFactionSurface> createState() => _PlayerFactionSurfaceState();
}

class _PlayerFactionSurfaceState extends State<PlayerFactionSurface> {
  late final ServerApi _api = AppScope.of(context).api;

  List<MyActivityReport> _activities = const <MyActivityReport>[];
  bool _loading = true;
  String? _notice;

  /// 非 null 時顯示某一場活動的現況卡（只由清單那一行按標識進入，不做本地推測）。
  String? _openActivityId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀本人的活動清單。失敗時整卡轉述那一句失敗，不顯示任何舊清單。
  Future<void> _load() async {
    setState(() => _loading = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final MyActivityListReport report = await _api.myActivities(
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _activities = report.activities;
        _notice = null;
      });
    } on ApiError catch (error) {
      if (!mounted) {
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
            key: ValueKey<String>('player-faction-back'),
            onPressed: () => setState(() => _openActivityId = null),
            child: Text(l10n.playerBackToActivitiesAction),
          ),
          const SizedBox(height: 12),
          // 按「活動標識」做 key：換一場活動就整張重建，依據值不可能留上一場的現值。
          FactionSelfSelectCard(
            key: ValueKey<String>('player-faction-detail-$_openActivityId'),
            activityId: _openActivityId!,
          ),
        ],
      );
    }
    if (_loading) {
      return Text(
        l10n.activityLoadingNotice,
        key: PlayerFactionSurface.loadingKey,
        style: theme.textTheme.bodyMedium,
      );
    }
    if (_notice != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _notice!,
            key: PlayerFactionSurface.failedKey,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: PlayerFactionSurface.reloadKey,
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
            key: PlayerFactionSurface.emptyKey,
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
        Text(l10n.playerActivitiesTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Column(
          key: PlayerFactionSurface.listKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final MyActivityReport entry in _activities)
              Card(
                key: PlayerFactionSurface.rowKey(entry.activityId),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(entry.name, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 4),
                      // 暱稱、狀態與模式全取服務端回顯：這一頁不重排、不翻譯取值，
                      // 表外值照實念出來（口徑同活動目錄的狀態呈現）。
                      Text(
                        l10n.labelValuePair(
                          l10n.memberNicknameLabel,
                          entry.nickname,
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      // 清單行不顯示陣營名稱：清單只帶標識，名稱屬那一場活動的候選清單，
                      // 抄一份過來就是第二個答案來源。要看「我此刻屬於哪一組」請進入現況卡，
                      // 那裡的名稱與可選性同源自同一份讀回。
                      Text(
                        l10n.labelValuePair(
                          l10n.factionSelectCurrentModeLabel,
                          _modeLabel(l10n, entry.factionSelectMode),
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton(
                          key: PlayerFactionSurface.openKey(entry.activityId),
                          onPressed: () => setState(
                            () => _openActivityId = entry.activityId,
                          ),
                          child: Text(l10n.playerActivityOpenAction),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(l10n.playerFactionScopeNotice, style: theme.textTheme.bodySmall),
        Text(
          l10n.playerFactionRemainingNotice,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// 模式取值的人話名稱；表外值照實顯示原值，不靜默歸類成某一態。
  String _modeLabel(AppLocalizations l10n, String mode) {
    return switch (mode) {
      'disabled' => l10n.factionSelectModeDisabled,
      'first_only' => l10n.factionSelectModeFirstOnly,
      'free' => l10n.factionSelectModeFree,
      _ => l10n.factionSelectModeUnknown(mode),
    };
  }
}

/// 某一場活動的自選卡：現值、候選清單與一次自選寫入。
class FactionSelfSelectCard extends StatefulWidget {
  /// 以活動標識建立本卡。
  const FactionSelfSelectCard({super.key, required this.activityId});

  /// 目標活動標識（路徑引數）。
  final String activityId;

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('player-faction-loading');

  /// 載入失敗識別鍵。
  static const Key failedKey = ValueKey<String>('player-faction-failed');

  /// 重新讀取識別鍵（載入失敗與 2013 共用那一個出口）。
  static const Key reloadKey = ValueKey<String>('player-faction-reload');

  /// 現值列識別鍵。
  static const Key currentKey = ValueKey<String>('player-faction-current');

  /// 候選項識別鍵。
  static Key optionKey(String factionId) =>
      ValueKey<String>('player-faction-option-$factionId');

  /// 候選項上的選擇按鈕識別鍵。
  static Key chooseKey(String factionId) =>
      ValueKey<String>('player-faction-choose-$factionId');

  /// 確認框肯定按鈕識別鍵。
  static const Key confirmKey = ValueKey<String>('player-faction-confirm');

  /// 取消按鈕識別鍵。
  static const Key cancelKey = ValueKey<String>('player-faction-cancel');

  /// 提示列識別鍵。
  static const Key noticeKey = ValueKey<String>('player-faction-notice');

  /// 成功列識別鍵。
  static const Key savedKey = ValueKey<String>('player-faction-saved');

  /// 此刻不能自選的說明列識別鍵。
  static const Key blockedKey = ValueKey<String>('player-faction-blocked');

  /// 「不能清空」那句限制列識別鍵。
  static const Key noClearKey = ValueKey<String>('player-faction-no-clear');

  @override
  State<FactionSelfSelectCard> createState() => _FactionSelfSelectCardState();
}

class _FactionSelfSelectCardState extends State<FactionSelfSelectCard> {
  late final ServerApi _api = AppScope.of(context).api;

  FactionSelectionReport? _view;
  bool _loading = true;
  bool _writing = false;

  /// 現值過期（2013）：收起寫入控件，只留重讀出口（口徑同管理側那幾張卡）。
  bool _stale = false;
  String? _notice;
  String? _saved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀我的陣營現況。失敗時不顯示任何舊資料：這一卡的每個控件都跟著服務端現值。
  Future<void> _load() async {
    setState(() => _loading = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final FactionSelectionReport report = await _api.myFactionSelection(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _view = report;
        _stale = false;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _view = null;
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  /// 走一次自選並以一次重讀收尾：回應那一筆是回讀的事實，而「此刻能不能選」
  /// 屬服務端派生值，本地不拼裝、也不先於回應顯示「已完成」。
  Future<void> _choose(FactionOptionReport option) async {
    if (_writing || _view == null) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String expected = _view!.factionId;
    setState(() {
      _writing = true;
      _notice = null;
      _saved = null;
    });
    try {
      await _api.selectOwnFaction(
        activityId: widget.activityId,
        factionId: option.factionId,
        expectedFactionId: expected,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      final FactionSelectionReport report = await _api.myFactionSelection(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _view = report;
        _saved = l10n.playerSelectSuccessNotice;
        _stale = false;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _notice = apiErrorText(l10n, error);
        // 2013 的出口是重讀；2036／2037／2038／2039 各是一句現狀說明，
        // 由統一對映轉述——界面早按派生值收起控件，這裡兜的是繞過界面與競態的尾巴。
        _stale = error.knownCode == ApiMachineCode.profileConflict;
      });
    }
  }

  /// 最小確認清單：一次講完動的是誰、範圍多大，以及兩件不會發生的事。
  Future<bool> _confirm(
    AppLocalizations l10n,
    FactionOptionReport option,
  ) async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.playerSelectConfirmTitle),
        content: Text(l10n.playerSelectConfirmBody(option.name)),
        actions: <Widget>[
          TextButton(
            key: FactionSelfSelectCard.cancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.activityConfirmCancelAction),
          ),
          FilledButton(
            key: FactionSelfSelectCard.confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.activityConfirmOkAction),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// 「此刻為什麼不能選」那一句：依服務端讀回的狀態與模式如實分岔，
  /// 而不是對四種完全不同的處置念同一句「現在不行」。
  String? _blockedReason(AppLocalizations l10n, FactionSelectionReport view) {
    final String? byStatus = switch (view.status) {
      'draft' => l10n.playerSelectBlockedNotOpen,
      'closed' => l10n.playerSelectBlockedClosed,
      'archived' => l10n.playerSelectBlockedArchived,
      _ => null,
    };
    if (byStatus != null) {
      return byStatus;
    }
    if (view.factionSelectMode == 'disabled') {
      return l10n.playerSelectBlockedDisabled;
    }
    // 狀態與開關都放行、卻仍然不能選：只剩「僅首次且已選過」這一種形態。
    // 這句話要單獨說得出來——重讀不會改變結論，處置在管理側那條尚未落地的通路。
    if (view.hasFaction && view.factionSelectMode == 'first_only') {
      return l10n.playerSelectLockedInNotice;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    if (_loading) {
      return Text(
        l10n.activityLoadingNotice,
        key: FactionSelfSelectCard.loadingKey,
        style: theme.textTheme.bodyMedium,
      );
    }
    final FactionSelectionReport? view = _view;
    if (view == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _notice ?? l10n.playerFactionTitle,
            key: FactionSelfSelectCard.failedKey,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: FactionSelfSelectCard.reloadKey,
            onPressed: _load,
            child: Text(l10n.activityReloadAction),
          ),
        ],
      );
    }
    final bool canSelect = view.canSelectNow && !_stale && !_writing;
    final String? blocked = canSelect ? null : _blockedReason(l10n, view);
    return Card(
      key: PlayerFactionSurface.detailKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.playerFactionTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(view.name, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text(
              l10n.labelValuePair(
                l10n.playerCurrentFactionLabel,
                view.hasFaction
                    ? (view.optionById(view.factionId)?.name ?? view.factionId)
                    : l10n.playerCurrentFactionNone,
              ),
              key: FactionSelfSelectCard.currentKey,
              style: theme.textTheme.bodySmall,
            ),
            Text(
              l10n.labelValuePair(
                l10n.factionSelectCurrentModeLabel,
                _modeLabel(l10n, view.factionSelectMode),
              ),
              style: theme.textTheme.bodySmall,
            ),
            if (blocked != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                blocked,
                key: FactionSelfSelectCard.blockedKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Text(
              l10n.playerFactionOptionsTitle,
              style: theme.textTheme.bodyMedium,
            ),
            if (view.factions.isEmpty)
              Text(l10n.memberEmptyNotice, style: theme.textTheme.bodySmall),
            for (final FactionOptionReport option in view.factions)
              Padding(
                key: FactionSelfSelectCard.optionKey(option.factionId),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(option.name),
                          if (!option.selectable)
                            Text(
                              option.available
                                  ? blocked ?? l10n.playerSelectBlockedDisabled
                                  : l10n.playerFactionOptionUnavailable,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    FilledButton(
                      key: FactionSelfSelectCard.chooseKey(option.factionId),
                      // 不可選的項不長按鈕：這裡收的是控件，後端在交易內重新問規則——
                      // 兩件事分開寫才不會讓人以為藏了按鈕就等於擋住了請求。
                      onPressed:
                          canSelect &&
                              option.selectable &&
                              option.factionId != view.factionId
                          ? () async {
                              if (await _confirm(l10n, option)) {
                                await _choose(option);
                              }
                            }
                          : null,
                      child: Text(l10n.playerSelectAction),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              l10n.playerNoClearNotice,
              key: FactionSelfSelectCard.noClearKey,
              style: theme.textTheme.bodySmall,
            ),
            if (_saved != null)
              Text(
                _saved!,
                key: FactionSelfSelectCard.savedKey,
                style: theme.textTheme.bodySmall,
              ),
            if (_notice != null)
              Text(
                _notice!,
                key: FactionSelfSelectCard.noticeKey,
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: FactionSelfSelectCard.reloadKey,
              onPressed: _load,
              child: Text(l10n.playerRefreshAction),
            ),
          ],
        ),
      ),
    );
  }

  /// 模式取值的人話名稱；表外值照實顯示原值。
  String _modeLabel(AppLocalizations l10n, String mode) {
    return switch (mode) {
      'disabled' => l10n.factionSelectModeDisabled,
      'first_only' => l10n.factionSelectModeFirstOnly,
      'free' => l10n.factionSelectModeFree,
      _ => l10n.factionSelectModeUnknown(mode),
    };
  }
}
