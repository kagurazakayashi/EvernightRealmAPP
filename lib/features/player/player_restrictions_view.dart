/// 玩家端的「我的限制狀態」卡：先列我有成員行的活動，再讀那一場活動掛在我身上的
/// 六枚分項限制現值。
///
/// 這一卡是用戶批准的「本人獲准查看有效結果」那一側，也是被 `restrict_login` 擋下
/// 之後唯一還讀得動的活動通路——被限制的人必須能問出「我被限制的是哪些項」，
/// 否則 2043 對他自己就是一句無法核實的指控。界面因此刻意把這句話寫在按鈕之外：
///
/// * 六欄各存各的、各改各的：取消聊天不會順手取消私聊或進場。這一卡只念現值，
///   沒有一格能改——解除永遠由管理人經服務層通路做，請求裡沒有玩家的這一欄。
/// * 「禁止進場」只作用這一場活動：它不是帳戶停用——全域登入照舊、既有會話不停、
///   其他活動照常可用。這兩句分界寫在卡裡，因為收到 2043 的人最容易把它讀成
///   「我被全站趕出去了」。
/// * 聊天、私聊、交易、轉賬與使用物品還沒有上線：這一卡不擺任何「去試聊天」的
///   入口，也不宣稱那些業務已被擋下——旗標是服務端將來的判定依據，今日只被保存
///   與如實顯示（未實現的能力不得偽裝可用）。
/// * 沒有原因、操作者與時間：本人讀到的是六個布林。管理人的編輯留痕在活動審計裡，
///   而本倉庫沒有審計查詢的 HTTP 入口（批准邊界），內部原因不無條件外傳。
/// * 失效形態只有「下一筆請求按現值回答」：倉庫今日沒有實時層，這一卡不宣稱推送，
///   也不得把上一次讀到的結果留著當現值——失敗就整段清掉。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../app/app_dependencies.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';
import '../admin/activity_members_view.dart' show memberRestrictionFields;
import '../capability_labels.dart';

/// 玩家端的本人限制查閱通路（含本人的活動清單）。
class PlayerRestrictionsCard extends StatefulWidget {
  /// 建立玩家端限制通路。
  const PlayerRestrictionsCard({super.key});

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('player-restrictions-loading');

  /// 清單讀不到那句轉述的識別鍵。
  static const Key activitiesNoticeKey = ValueKey<String>(
    'player-restrictions-activities-notice',
  );

  /// 本人活動清單容器識別鍵。
  static const Key listKey = ValueKey<String>('player-restrictions-list');

  /// 清單某一行的識別鍵。
  static Key activityRowKey(String activityId) =>
      ValueKey<String>('player-restrictions-row-$activityId');

  /// 某一行「讀我的限制狀態」按鈕的識別鍵。
  static Key openActionKey(String activityId) =>
      ValueKey<String>('player-restrictions-open-$activityId');

  /// 某一行的「進場已被限制」小標識別鍵。
  static Key restrictedBadgeKey(String activityId) =>
      ValueKey<String>('player-restrictions-badge-$activityId');

  /// 單一欄位那一句的識別鍵（欄位名就是協定欄位名）。
  static Key fieldRowKey(String field) =>
      ValueKey<String>('player-restrictions-field-$field');

  /// 「沒有任何限制生效」那句的識別鍵。
  static const Key noneActiveKey = ValueKey<String>(
    'player-restrictions-none-active',
  );

  /// 「進場資格已被限制」那句的識別鍵。
  static const Key accessLineKey = ValueKey<String>(
    'player-restrictions-access-line',
  );

  /// 常駐邊界句的識別鍵。
  static const Key boundaryKey = ValueKey<String>(
    'player-restrictions-boundary',
  );

  /// 有效能力區標題識別鍵。
  static const Key capabilitiesSectionKey = ValueKey<String>(
    'player-capabilities-section',
  );

  /// 有效能力載入中識別鍵。
  static const Key capabilitiesLoadingKey = ValueKey<String>(
    'player-capabilities-loading',
  );

  /// 有效能力讀不到那句的識別鍵。
  static const Key capabilitiesNoticeKey = ValueKey<String>(
    'player-capabilities-notice',
  );

  /// 「進場被拒、其餘能力規則上仍可能允許」那句的識別鍵。
  static const Key capabilitiesAccessLineKey = ValueKey<String>(
    'player-capabilities-access-line',
  );

  /// 某一項能力那一行識別鍵。
  static Key capabilityRowKey(String capability) =>
      ValueKey<String>('player-capabilities-row-$capability');

  /// 規則版本那一行識別鍵。
  static const Key capabilitiesRevisionKey = ValueKey<String>(
    'player-capabilities-revision',
  );

  /// 有效能力常駐邊界句識別鍵。
  static const Key capabilitiesBoundaryKey = ValueKey<String>(
    'player-capabilities-boundary',
  );

  /// 返回清單按鈕的識別鍵。
  static const Key backKey = ValueKey<String>('player-restrictions-back');

  @override
  State<PlayerRestrictionsCard> createState() => _PlayerRestrictionsCardState();
}

class _PlayerRestrictionsCardState extends State<PlayerRestrictionsCard> {
  late final ServerApi _api = AppScope.of(context).api;

  List<MyActivityReport> _activities = const <MyActivityReport>[];
  bool _activitiesLoading = true;
  String? _activitiesNotice;

  /// 非 null 時顯示某一場活動掛在本人身上的限制現值。
  String? _openActivityId;

  OwnMemberRestrictionsReport? _restrictions;
  bool _restrictionsLoading = false;

  /// 限制那一讀失敗那一句；非 null 時結果一律不長（不拿上一批冒充現值）。
  String? _restrictionsNotice;

  /// 本人有效能力（與六枚手動限制是兩份讀法：一份讀旗標，一份讀組合結果）。
  OwnCapabilitiesReport? _capabilities;
  bool _capabilitiesLoading = false;
  String? _capabilitiesNotice;

  /// 三段讀法各自的請求序號：清單與單場查閱是幾筆獨立請求，
  /// 共用計數器會讓先回的那筆把後回的當成過期件。
  int _activitiesGeneration = 0;
  int _restrictionsGeneration = 0;
  int _capabilitiesGeneration = 0;

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

  /// 讀某一場活動掛在本人身上的六枚限制現值。
  ///
  /// 這是被限制的人也讀得動的一條路徑；其余失敗（2002 匿名、1001 不是成員、
  /// 傳輸級失敗）由統一對映念自己那一句。遲到的回應照例丟棄，失敗整段清掉。
  Future<void> _loadRestrictions(String activityId) async {
    final int generation = ++_restrictionsGeneration;
    setState(() {
      _restrictionsLoading = true;
      _restrictionsNotice = null;
      _restrictions = null;
    });
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final OwnMemberRestrictionsReport report = await _api
          .ownMemberRestrictions(
            activityId: activityId,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted ||
          generation != _restrictionsGeneration ||
          activityId != _openActivityId) {
        return;
      }
      setState(() {
        _restrictionsLoading = false;
        _restrictions = report;
      });
    } on ApiError catch (error) {
      if (!mounted ||
          generation != _restrictionsGeneration ||
          activityId != _openActivityId) {
        return;
      }
      setState(() {
        _restrictionsLoading = false;
        _restrictionsNotice = apiErrorText(l10n, error);
      });
    }
  }

  void _open(String activityId) {
    setState(() => _openActivityId = activityId);
    _loadRestrictions(activityId);
    _loadCapabilities(activityId);
  }

  void _back() {
    setState(() {
      _openActivityId = null;
      _restrictions = null;
      _restrictionsNotice = null;
      _capabilities = null;
      _capabilitiesNotice = null;
    });
  }

  /// 讀本人此刻的有效能力（組合了手動限制、狀態規則、生命週期與身份資格）。
  ///
  /// 這是被擋下的人也讀得動的一條路徑：它回答「哪幾項被拒絕、屬於哪一類來源」，
  /// 但沒有業務狀態、活動狀態、帳戶狀態、逐來源細節、原因、操作者或時刻。
  /// 失敗整段清掉，不拿上一批冒充現值。
  Future<void> _loadCapabilities(String activityId) async {
    final int generation = ++_capabilitiesGeneration;
    setState(() {
      _capabilitiesLoading = true;
      _capabilitiesNotice = null;
      _capabilities = null;
    });
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final OwnCapabilitiesReport report = await _api.ownCapabilities(
        activityId: activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted ||
          generation != _capabilitiesGeneration ||
          activityId != _openActivityId) {
        return;
      }
      setState(() {
        _capabilitiesLoading = false;
        _capabilities = report;
      });
    } on ApiError catch (error) {
      if (!mounted ||
          generation != _capabilitiesGeneration ||
          activityId != _openActivityId) {
        return;
      }
      setState(() {
        _capabilitiesLoading = false;
        _capabilitiesNotice = apiErrorText(l10n, error);
      });
    }
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    return switch (status) {
      'draft' => l10n.activityStatusDraftLabel,
      'active' => l10n.activityStatusActiveLabel,
      'closed' => l10n.activityStatusClosedLabel,
      'archived' => l10n.activityStatusArchivedLabel,
      _ => l10n.activityUnknownStatusLabel(status),
    };
  }

  /// 依協定欄位名取該欄的界面名（文案由 ARB 承擔，這裡只做映射；
  /// 與管理側同一份欄位清單，兩側不可能各講一套欄位）。
  String _fieldLabel(AppLocalizations l10n, String field) {
    switch (field) {
      case 'restrict_login':
        return l10n.memberRestrictionLoginLabel;
      case 'restrict_chat':
        return l10n.memberRestrictionChatLabel;
      case 'restrict_private_chat':
        return l10n.memberRestrictionPrivateChatLabel;
      case 'restrict_trade':
        return l10n.memberRestrictionTradeLabel;
      case 'restrict_transfer':
        return l10n.memberRestrictionTransferLabel;
      default:
        return l10n.memberRestrictionItemUseLabel;
    }
  }

  bool _fieldValue(OwnMemberRestrictionsReport report, String field) {
    switch (field) {
      case 'restrict_login':
        return report.restrictLogin;
      case 'restrict_chat':
        return report.restrictChat;
      case 'restrict_private_chat':
        return report.restrictPrivateChat;
      case 'restrict_trade':
        return report.restrictTrade;
      case 'restrict_transfer':
        return report.restrictTransfer;
      default:
        return report.restrictItemUse;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.playerRestrictionsCardTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_openActivityId == null)
          ..._buildList(l10n, theme)
        else
          ..._buildDetail(l10n, theme),
      ],
    );
  }

  List<Widget> _buildList(AppLocalizations l10n, ThemeData theme) {
    if (_activitiesLoading) {
      return <Widget>[
        Text(
          l10n.activityLoadingNotice,
          key: PlayerRestrictionsCard.loadingKey,
        ),
      ];
    }
    return <Widget>[
      if (_activitiesNotice != null)
        Text(
          _activitiesNotice!,
          key: PlayerRestrictionsCard.activitiesNoticeKey,
          style: theme.textTheme.bodySmall,
        ),
      if (_activitiesNotice == null && _activities.isEmpty)
        Text(
          l10n.playerActivitiesEmptyNotice,
          style: theme.textTheme.bodySmall,
        ),
      Column(
        key: PlayerRestrictionsCard.listKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final MyActivityReport entry in _activities)
            Card(
              key: PlayerRestrictionsCard.activityRowKey(entry.activityId),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(entry.name, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Text(
                      l10n.labelValuePair(
                        l10n.activityStatusLabel,
                        _statusLabel(l10n, entry.status),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    // 「這一場你進不去」說在敲壁之前：這一格是服務端現值投影，
                    // 界面不本地推測，也不因為它為真就把這一列藏起來。
                    if (entry.accessRestricted)
                      Text(
                        l10n.playerActivityAccessRestricted,
                        key: PlayerRestrictionsCard.restrictedBadgeKey(
                          entry.activityId,
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: OutlinedButton(
                        key: PlayerRestrictionsCard.openActionKey(
                          entry.activityId,
                        ),
                        onPressed: () => _open(entry.activityId),
                        child: Text(l10n.playerRestrictionsOpenAction),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      // 重新讀取：這一族沒有快取，界面上任何一行都只屬於發起它的那一次請求。
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(
          onPressed: _loadActivities,
          child: Text(l10n.activityReloadAction),
        ),
      ),
    ];
  }

  /// 六項能力的逐項結論（只列後端實際回來的項；認不得的鍵不編造一行）。
  List<Widget> _capabilityRows(AppLocalizations l10n, ThemeData theme) {
    final OwnCapabilitiesReport? report = _capabilities;
    if (report == null) {
      return const <Widget>[];
    }
    final List<Widget> rows = <Widget>[];
    for (final String capability in kCapabilityKeys) {
      final OwnCapabilityDecision? item = report.decisionFor(capability);
      if (item == null) {
        continue;
      }
      rows.add(
        Text(
          l10n.labelValuePair(
            capabilityLabel(l10n, capability),
            item.allowed
                ? l10n.capabilityAllowedValue
                : l10n.capabilityDeniedValue,
          ),
          key: PlayerRestrictionsCard.capabilityRowKey(capability),
          style: theme.textTheme.bodyMedium,
        ),
      );
      if (!item.allowed && item.sources.isNotEmpty) {
        rows.add(
          Text(
            capabilitySourcesLine(l10n, item.sources),
            style: theme.textTheme.bodySmall,
          ),
        );
      }
    }
    return rows;
  }

  List<Widget> _buildDetail(AppLocalizations l10n, ThemeData theme) {
    return <Widget>[
      if (_restrictionsLoading)
        Text(l10n.activityLoadingNotice, style: theme.textTheme.bodySmall),
      if (_restrictionsNotice != null)
        Text(_restrictionsNotice!, style: theme.textTheme.bodySmall),
      if (_restrictions != null) ...<Widget>[
        for (final String field in memberRestrictionFields)
          Text(
            l10n.labelValuePair(
              _fieldLabel(l10n, field),
              _fieldValue(_restrictions!, field)
                  ? l10n.playerRestrictionActiveValue
                  : l10n.playerRestrictionInactiveValue,
            ),
            key: PlayerRestrictionsCard.fieldRowKey(field),
            style: theme.textTheme.bodyMedium,
          ),
        const SizedBox(height: 6),
        if (!_restrictions!.hasAnyRestriction)
          Text(
            l10n.playerRestrictionsNoneActive,
            key: PlayerRestrictionsCard.noneActiveKey,
            style: theme.textTheme.bodySmall,
          ),
        if (_restrictions!.restrictLogin)
          Text(
            l10n.playerRestrictionsAccessLine,
            key: PlayerRestrictionsCard.accessLineKey,
            style: theme.textTheme.bodySmall,
          ),
      ],
      const SizedBox(height: 10),
      // 有效能力是六枚手動限制的組合結果：它另外合併了業務狀態規則、活動生命週期
      // 與身份資格。六個旗標只回答「手動限制」那一側；這一節回答「此刻實際如何」。
      Text(
        l10n.playerCapabilitiesSectionTitle,
        key: PlayerRestrictionsCard.capabilitiesSectionKey,
        style: theme.textTheme.titleSmall,
      ),
      const SizedBox(height: 4),
      if (_capabilitiesLoading)
        Text(
          l10n.activityLoadingNotice,
          key: PlayerRestrictionsCard.capabilitiesLoadingKey,
          style: theme.textTheme.bodySmall,
        ),
      if (_capabilitiesNotice != null)
        Text(
          _capabilitiesNotice!,
          key: PlayerRestrictionsCard.capabilitiesNoticeKey,
          style: theme.textTheme.bodySmall,
        ),
      if (_capabilities != null) ...<Widget>[
        if (!_capabilities!.accessAllowed)
          Text(
            l10n.playerCapabilitiesAccessDeniedNote,
            key: PlayerRestrictionsCard.capabilitiesAccessLineKey,
            style: theme.textTheme.bodySmall,
          ),
        ..._capabilityRows(l10n, theme),
        Text(
          l10n.capabilityRulesRevisionLine(_capabilities!.rulesRevision),
          key: PlayerRestrictionsCard.capabilitiesRevisionKey,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.playerCapabilitiesLifecycleNote,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.playerCapabilitiesNotWiredNote,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.playerCapabilitiesIndependentNote,
          key: PlayerRestrictionsCard.capabilitiesBoundaryKey,
          style: theme.textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 6),
      // 邊界句常駐：它不藏在任何一顆按鈕或錯誤之後——玩家最需要的時候
      // 恰恰是剛剛被擋下的時候。
      Text(
        l10n.playerRestrictionsBoundaryNote,
        key: PlayerRestrictionsCard.boundaryKey,
        style: theme.textTheme.bodySmall,
      ),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(
          key: PlayerRestrictionsCard.backKey,
          onPressed: _back,
          child: Text(l10n.playerBackToActivitiesAction),
        ),
      ),
    ];
  }
}
