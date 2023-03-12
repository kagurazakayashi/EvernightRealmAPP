/// 「單筆活動詳情、資料編輯、狀態轉換與管理人名冊」卡。
///
/// 這張卡的四個動作各自一條白名單，而且互斥不並發提交（一次只讓一條寫入在途）：
///
/// * 底稿只能來自本卡按標識讀回的現值：編輯表單預填的是 PUT 前那次 GET 的結果，
///   compare-and-set 的依據值也是它。目錄行與本地印象都不夠格當底稿。
/// * 名稱與描述走 `/admin/activities/{id}`；狀態走 `/status` 子資源。兩條通路各認各的欄位，
///   因此「儲存資料順手把歸檔的活動改回開放」在協定層就不是被拒，而是沒有一個可以填的格子。
/// * 按鈕只由服務端讀回的狀態決定：表外值不長出任何按鈕，已歸檔的目標收起全部寫入控制元件
///   （2029 那一句話是「這件事已經結束」，不是「現在不行」）。
/// * 歸檔要確認，因為它沒有出口：確認框一次講完三件效果（不再接受資料編輯、
///   不再接受狀態轉換、名冊也不再增減）與一件不會發生（這不是停止，停止可以重開）。
/// * 名冊的讀與寫分屬兩道閘：管理人讀得到自己活動還有誰在管（`/admin`），
///   但加人與刪人只在 Root 那一側（`/root`，介面據 `canManageManagers` 決定長不長那顆按鈕）。
///   被指派者必須已是伺服器級管理員，因此這張卡不提供「就地開設管理員」的捷徑。
/// * 結果不明（連不上、逾時）時絕不自動補發：資料編輯與狀態轉換的現值可能已經被別人改過，
///   由人重讀這一份再決定。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 活動詳情卡。
class ActivityProfileCard extends StatefulWidget {
  /// 以端點介面與活動標識建立詳情卡。
  const ActivityProfileCard({
    super.key,
    required this.api,
    required this.activityId,
    this.canManageManagers = false,
    this.onClosed,
    this.onSaved,
  });

  /// 統一端點存取介面。
  final ServerApi api;

  /// 本卡要呈現與編集的活動標識（身分只在這裡，不在名稱上）。
  final String activityId;

  /// 是否顯示管理人的增減控制元件：只有 Root 控制檯傳 `true`。
  ///
  /// 這一個布林不構成任何授權——後端自己判 NeedRoot；它只決定介面長不長那兩顆按鈕，
  /// 而介面藏按鈕永遠不能代替服務端那道閘。
  final bool canManageManagers;

  /// 關閉本卡（回到目錄）。
  final VoidCallback? onClosed;

  /// 任意一次寫入成功的回呼：頁面據此重讀目錄。
  final VoidCallback? onSaved;

  /// 載入中說明識別鍵。
  static const Key loadingKey = ValueKey<String>('activity-profile-loading');

  /// 載入失敗提示識別鍵。
  static const Key failedKey = ValueKey<String>('activity-profile-failed');

  /// 重新讀取識別鍵（2013／2030 之後唯一的出口）。
  static const Key reloadKey = ValueKey<String>('activity-profile-reload');

  /// 名稱輸入框識別鍵。
  static const Key nameKey = ValueKey<String>('activity-profile-name');

  /// 描述輸入框識別鍵。
  static const Key descriptionKey = ValueKey<String>(
    'activity-profile-description',
  );

  /// 儲存資料按鈕識別鍵。
  static const Key saveKey = ValueKey<String>('activity-profile-save');

  /// 歸檔橫幅識別鍵（終態只讀的宣告）。
  static const Key archivedKey = ValueKey<String>('activity-profile-archived');

  /// 停止說明列識別鍵。
  static const Key closedKey = ValueKey<String>('activity-profile-closed');

  /// 依狀態而定的轉換按鈕識別鍵。
  static Key transitionKey(String target) =>
      ValueKey<String>('activity-profile-transition-$target');

  /// 歸檔確認對話方塊的肯定按鈕識別鍵。
  static const Key archiveConfirmKey = ValueKey<String>(
    'activity-profile-archive-confirm',
  );

  /// 名冊識別鍵。
  static const Key rosterKey = ValueKey<String>('activity-profile-roster');

  /// 名冊某一行的識別鍵。
  static Key managerRowKey(String accountId) =>
      ValueKey<String>('activity-profile-manager-$accountId');

  /// 撤銷按鈕識別鍵。
  static Key revokeKey(String accountId) =>
      ValueKey<String>('activity-profile-revoke-$accountId');

  /// 指派用的帳戶標識輸入框識別鍵。
  static const Key assignAccountKey = ValueKey<String>(
    'activity-profile-assign-account',
  );

  /// 指派按鈕識別鍵。
  static const Key assignKey = ValueKey<String>('activity-profile-assign');

  /// 提示列識別鍵（本地校驗與失敗轉述共用）。
  static const Key noticeKey = ValueKey<String>('activity-profile-notice');

  /// 寫入成功列識別鍵（只在回應成功之後才出現，不先於回應顯示「已完成」）。
  static const Key savedKey = ValueKey<String>('activity-profile-saved');

  @override
  State<ActivityProfileCard> createState() => _ActivityProfileCardState();
}

class _ActivityProfileCardState extends State<ActivityProfileCard> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _assignAccountId = TextEditingController();

  ActivityReport? _activity;
  List<ActivityManagerReport> _managers = const <ActivityManagerReport>[];
  bool _loading = true;

  /// 一次寫入的在途狀態：四條寫入通路共用一把，互斥不並發。
  bool _writing = false;

  /// 一行提示：本地校驗與失敗轉述共用同一條；成功後清空。
  String? _notice;

  /// 最近一次寫入成功的陳述（只在寫入成功後出現，絕不先於回應顯示）。
  String? _saved;

  /// 最近一次寫入因現值過期而失敗（2013／2030）：這時界面收起那兩顆寫入鈕，
  /// 只留「重讀這份資料」一個出口——讓人在一份注定再次衝突的畫面上連點不是處置。
  bool _stale = false;

  /// 最近一次由服務端讀回的現值（compare-and-set 的依據值只能取自這裡）。
  String _expectedName = '';
  String _expectedDescription = '';

  @override
  void initState() {
    super.initState();
    // 同目錄卡：首讀排在第一幀之後，免得在 initState 裡讀 Localizations。
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _assignAccountId.dispose();
    super.dispose();
  }

  /// 目前介面語言對應的 Accept-Language 標記。
  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀回這份資料（詳情＋名冊）。
  ///
  /// 兩條讀取刻意各自成句：名冊讀不到不該讓整張卡變成「詳情也不可用」，
  /// 但它也絕不能靜默顯示成「還沒有管理人」——那是把一次失敗讀成一個事實。
  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final ActivityDetailReport detail = await widget.api.activityDetail(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      final ActivityManagerRosterReport roster = await widget.api
          .activityManagers(
            activityId: widget.activityId,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _activity = detail.activity;
        _managers = roster.managers;
        _applyBaseline(detail.activity);
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _activity = null;
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  /// 把服務端現值同時放進表單與依據值：兩處必須同源，否則儲存的是「我以為的現值」。
  void _applyBaseline(ActivityReport activity) {
    _expectedName = activity.name;
    _expectedDescription = activity.description;
    _name.text = activity.name;
    _description.text = activity.description;
  }

  /// 走一次寫入並把回應換成新的現值；回應帶著資料庫現值，不是請求的迴音。
  Future<void> _write(
    Future<ActivityDetailReport> Function() request, {
    bool reloadRoster = false,
  }) async {
    if (_writing) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _writing = true;
      _notice = null;
      _saved = null;
      _stale = false;
    });
    try {
      final ActivityDetailReport report = await request();
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _activity = report.activity;
        _saved = AppLocalizations.of(context).activitySavedNotice;
        _applyBaseline(report.activity);
      });
      if (reloadRoster) {
        final ActivityManagerRosterReport roster = await widget.api
            .activityManagers(
              activityId: widget.activityId,
              acceptLanguage: _acceptLanguage,
            );
        if (!mounted) {
          return;
        }
        setState(() => _managers = roster.managers);
      }
      widget.onSaved?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _notice = _failureText(l10n, error);
        final ApiMachineCode? code = error.knownCode;
        _stale =
            code == ApiMachineCode.profileConflict ||
            code == ApiMachineCode.activityStatusConflict;
      });
    }
  }

  /// 把一次失敗換成一句話：欄位級結論點名是哪一欄，其餘交回統一對映。
  String _failureText(AppLocalizations l10n, ApiError error) {
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'name' => l10n.activityInvalidNameNotice,
        'description' => l10n.activityInvalidDescriptionNotice,
        'status' => l10n.activityInvalidStatusNotice,
        'account_id' => l10n.activityInvalidAccountIdNotice,
        _ => l10n.activityRejectedNotice,
      };
    }
    // 2013（資料現值已過期）與 2030（狀態現值衝突）的處置是同一件事：重讀這份資料。
    // 介面因此只給那顆「重新讀取」的出口，不把「再點一次儲存」留成第二條路。
    return apiErrorText(l10n, error);
  }

  /// 送交一次資料編輯（白名單兩欄，帶著它們各自依據的現值）。
  Future<void> _saveProfile() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _notice = l10n.activityFormIncompleteNotice);
      return;
    }
    await _write(
      () => widget.api.updateActivityProfile(
        activityId: widget.activityId,
        name: name,
        description: _description.text.trim(),
        expectedName: _expectedName,
        expectedDescription: _expectedDescription,
        acceptLanguage: _acceptLanguage,
      ),
    );
  }

  /// 送交一次狀態轉換；歸檔要先確認（它沒有出口）。
  Future<void> _transition(String target) async {
    final ActivityReport? activity = _activity;
    if (activity == null) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (target == 'archived') {
      final bool? confirmed = await _confirmArchive(l10n, activity);
      if (confirmed != true || !mounted) {
        return;
      }
    }
    await _write(
      () => widget.api.updateActivityStatus(
        activityId: widget.activityId,
        status: target,
        acceptLanguage: _acceptLanguage,
      ),
    );
  }

  /// 歸檔確認框：一次讀完才準提交，講完三件效果與「這不是停止」。
  Future<bool?> _confirmArchive(
    AppLocalizations l10n,
    ActivityReport activity,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.activityArchiveConfirmTitle),
        content: Text(l10n.activityArchiveConfirmBody(activity.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.activityConfirmCancelAction),
          ),
          FilledButton(
            key: ActivityProfileCard.archiveConfirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.activityConfirmOkAction),
          ),
        ],
      ),
    );
  }

  /// 撤銷一筆指派的確認框：點名目標，並講明這不是刪除那個帳戶。
  Future<bool?> _confirmRevoke(
    AppLocalizations l10n,
    ActivityManagerReport manager,
  ) {
    final String target = manager.displayName.isEmpty
        ? manager.accountId
        : manager.displayName;
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.activityRevokeConfirmTitle),
        content: Text(l10n.activityRevokeConfirmBody(target)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.activityConfirmCancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.activityConfirmOkAction),
          ),
        ],
      ),
    );
  }

  /// 送交一次指派（Root 那側；目標必須已是可用的伺服器級管理員）。
  Future<void> _assign() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String accountId = _assignAccountId.text.trim();
    if (accountId.isEmpty) {
      setState(() => _notice = l10n.activityAssignIncompleteNotice);
      return;
    }
    await _write(
      () => widget.api.assignActivityManager(
        activityId: widget.activityId,
        accountId: accountId,
        acceptLanguage: _acceptLanguage,
      ),
      reloadRoster: true,
    );
    if (mounted) {
      _assignAccountId.clear();
    }
  }

  /// 送交一次撤銷。
  Future<void> _revoke(ActivityManagerReport manager) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await _confirmRevoke(l10n, manager);
    if (confirmed != true || !mounted) {
      return;
    }
    await _write(
      () => widget.api.revokeActivityManager(
        activityId: widget.activityId,
        accountId: manager.accountId,
        acceptLanguage: _acceptLanguage,
      ),
      reloadRoster: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    if (_loading) {
      return Text(
        l10n.activityLoadingNotice,
        key: ActivityProfileCard.loadingKey,
        style: theme.textTheme.bodySmall,
      );
    }
    final ActivityReport? activity = _activity;
    if (activity == null) {
      // 載入失敗時這張卡只轉述那一句失敗，不顯示任何舊資料：
      // 「不知道現值」與「現值是上一份」是兩件不同的事，後者會讓人對著過期畫面提交。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _notice ?? l10n.activityNotLoadedNotice,
            key: ActivityProfileCard.failedKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: ActivityProfileCard.reloadKey,
              onPressed: _load,
              child: Text(l10n.activityReloadAction),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l10n.activityProfileTitle(activity.name),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (widget.onClosed != null)
              TextButton(
                onPressed: widget.onClosed,
                child: Text(l10n.activityCloseCardAction),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _Facts(activity: activity),
        if (activity.isArchived) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            activity.archivedAt == null
                ? l10n.activityArchivedBanner
                : l10n.activityArchivedBannerAt(
                    _formatUtcMinute(activity.archivedAt!),
                  ),
            key: ActivityProfileCard.archivedKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ] else if (activity.status == 'closed') ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l10n.activityClosedNotice,
            key: ActivityProfileCard.closedKey,
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        if (activity.isArchived)
          // 終態：沒有表單、也沒有轉換鈕，只有一句「這裡沒有可編輯的東西」。
          Text(l10n.activityReadOnlyNotice, style: theme.textTheme.bodySmall)
        else if (_stale)
          // 現值過期時唯一的出口：重讀。讓使用者對著過期畫面再點一次保存不是出路。
          OutlinedButton(
            key: ActivityProfileCard.reloadKey,
            onPressed: _load,
            child: Text(l10n.activityReloadAction),
          )
        else
          _ProfileForm(
            nameController: _name,
            descriptionController: _description,
            busy: _writing,
            onSave: _saveProfile,
          ),
        const SizedBox(height: 16),
        _Transitions(
          activity: activity,
          busy: _writing || _stale,
          onRun: _transition,
        ),
        if (_saved != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _saved!,
            key: ActivityProfileCard.savedKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_notice != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _notice!,
            key: ActivityProfileCard.noticeKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 20),
        _Roster(
          managers: _managers,
          l10n: l10n,
          busy: _writing,
          canManage: widget.canManageManagers && !activity.isArchived,
          assignController: _assignAccountId,
          onAssign: _assign,
          onRevoke: _revoke,
        ),
      ],
    );
  }
}

/// 活動的既有事實：標識、狀態、建立者與三個時刻——全部取自服務端回應。
class _Facts extends StatelessWidget {
  const _Facts({required this.activity});

  final ActivityReport activity;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final List<Widget> lines = <Widget>[
      Text(
        l10n.labelValuePair(l10n.activityIdLabel, activity.activityId),
        style: theme.textTheme.bodySmall,
      ),
      Text(
        l10n.labelValuePair(
          l10n.activityStatusLabel,
          _statusLabel(l10n, activity.status),
        ),
        style: theme.textTheme.bodySmall,
      ),
      Text(
        l10n.labelValuePair(
          l10n.activityManagerCountLabel,
          activity.managerCount.toString(),
        ),
        style: theme.textTheme.bodySmall,
      ),
      Text(
        l10n.labelValuePair(
          l10n.activityCreatedLabel,
          _formatUtcMinute(activity.createdAt),
        ),
        style: theme.textTheme.bodySmall,
      ),
      Text(
        l10n.labelValuePair(
          l10n.activityUpdatedLabel,
          _formatUtcMinute(activity.updatedAt),
        ),
        style: theme.textTheme.bodySmall,
      ),
      // 建立者那一格缺席是「由 Root 建立」：Root 不在 accounts 表裡，沒有帳戶標識。
      activity.createdByAccountId == null
          ? Text(
              l10n.activityCreatedByRootNotice,
              style: theme.textTheme.bodySmall,
            )
          : Text(
              l10n.labelValuePair(
                l10n.activityCreatorLabel,
                activity.createdByAccountId!,
              ),
              style: theme.textTheme.bodySmall,
            ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }
}

/// 資料編輯表單：白名單兩欄（名稱與描述）。
class _ProfileForm extends StatelessWidget {
  const _ProfileForm({
    required this.nameController,
    required this.descriptionController,
    required this.busy,
    required this.onSave,
  });

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.activityEditTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextField(
          key: ActivityProfileCard.nameKey,
          controller: nameController,
          enabled: !busy,
          decoration: InputDecoration(labelText: l10n.activityNameLabel),
        ),
        const SizedBox(height: 10),
        TextField(
          key: ActivityProfileCard.descriptionKey,
          controller: descriptionController,
          enabled: !busy,
          maxLines: 3,
          decoration: InputDecoration(labelText: l10n.activityDescriptionLabel),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: ActivityProfileCard.saveKey,
            onPressed: busy ? null : onSave,
            child: Text(l10n.activitySaveAction),
          ),
        ),
      ],
    );
  }
}

/// 狀態轉換區：按鈕集合完全由服務端讀回的現值決定。
///
/// 四條合法路徑是 draft→active、active→closed、closed→active、任意非歸檔→archived。
/// 表外狀態（後端日後放寬集合時的多餘取值）不長出任何按鈕：介面不替自己發明代術。
class _Transitions extends StatelessWidget {
  const _Transitions({
    required this.activity,
    required this.busy,
    required this.onRun,
  });

  final ActivityReport activity;
  final bool busy;
  final void Function(String target) onRun;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final List<Widget> buttons = <Widget>[];
    switch (activity.status) {
      case 'draft':
        buttons.add(
          _button(l10n.activityOpenTransitionAction, 'active', context),
        );
        // 草稿也能直接歸檔（後端四條路徑之一）：建錯一場又還留在草稿時，
        // 唯一的出路不該是「先開放再歸檔」那種多此一舉的轉換。
        buttons.add(
          _button(l10n.activityArchiveTransitionAction, 'archived', context),
        );
      case 'active':
        buttons.add(
          _button(l10n.activityCloseTransitionAction, 'closed', context),
        );
        buttons.add(
          _button(l10n.activityArchiveTransitionAction, 'archived', context),
        );
      case 'closed':
        buttons.add(
          _button(l10n.activityReopenTransitionAction, 'active', context),
        );
        buttons.add(
          _button(l10n.activityArchiveTransitionAction, 'archived', context),
        );
      case 'archived':
        // 終態：這裡一個按鈕都不長。2029 那句「這件事已經結束」不該被一顆
        // 按下去只會拿到拒絕的按鈕反覆驗證。
        break;
      default:
        break;
    }
    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.activityStatusTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: buttons),
      ],
    );
  }

  Widget _button(String label, String target, BuildContext context) {
    return OutlinedButton(
      key: ActivityProfileCard.transitionKey(target),
      onPressed: busy ? null : () => onRun(target),
      child: Text(label),
    );
  }
}

/// 管理人名冊：讀取部分人人相同，增減控制元件只在 Root 那一側長出來。
class _Roster extends StatelessWidget {
  const _Roster({
    required this.managers,
    required this.l10n,
    required this.busy,
    required this.canManage,
    required this.assignController,
    required this.onAssign,
    required this.onRevoke,
  });

  final List<ActivityManagerReport> managers;
  final AppLocalizations l10n;
  final bool busy;
  final bool canManage;
  final TextEditingController assignController;
  final VoidCallback onAssign;
  final void Function(ActivityManagerReport manager) onRevoke;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.activityManagersTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        // 這一行把「讀與寫分屬兩道閘」講在名冊旁邊，而不是等用戶敲到 2011 才知道。
        Text(
          canManage
              ? l10n.activityManagersRootNotice
              : l10n.activityManagersReadOnlyNotice,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (managers.isEmpty)
          Text(
            l10n.activityManagerEmptyNotice,
            key: const ValueKey<String>('activity-profile-roster-empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          Column(
            key: ActivityProfileCard.rosterKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final ActivityManagerReport manager in managers)
                Card(
                  key: ActivityProfileCard.managerRowKey(manager.accountId),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      // 顯示名讀不到時（指向的帳戶行已被物理清理）照實說，不編造名字。
                      manager.displayName.isEmpty
                          ? l10n.activityManagerUnknownNameNotice
                          : manager.displayName,
                    ),
                    subtitle: Text(_managerSubtitle(l10n, manager)),
                    trailing: canManage
                        ? OutlinedButton(
                            key: ActivityProfileCard.revokeKey(
                              manager.accountId,
                            ),
                            onPressed: busy ? null : () => onRevoke(manager),
                            child: Text(l10n.activityRevokeAction),
                          )
                        : null,
                  ),
                ),
            ],
          ),
        if (canManage) ...<Widget>[
          const SizedBox(height: 12),
          Text(l10n.activityAssignTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(l10n.activityAssignHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: ActivityProfileCard.assignAccountKey,
                  controller: assignController,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: l10n.activityAssignAccountIdLabel,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: ActivityProfileCard.assignKey,
                onPressed: busy ? null : onAssign,
                child: Text(l10n.activityAssignAction),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 名冊一行的副標：「帳戶狀態：xxx · 指派於 …」。
///
/// 湊成一句而不是塞三個欄位進 ListTile，是因為窄屏（360 px）上這三者都得同可讀；
/// 狀態一律轉述服務端給的原值，介面不替它發明代術。
String _managerSubtitle(AppLocalizations l10n, ActivityManagerReport manager) {
  final String status = l10n.labelValuePair(
    l10n.activityManagerStatusLabel,
    manager.accountStatus,
  );
  return '$status · ${_formatUtcMinute(manager.grantedAt)}';
}

/// 以「年-月-日 時:分 UTC」呈現，與其餘清單同一寫法：不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}

/// 狀態取值到介面文字的對應（與目錄卡同一份說法；兩處各自保留私有實作）。
String _statusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'draft' => l10n.activityStatusDraftLabel,
    'active' => l10n.activityStatusActiveLabel,
    'closed' => l10n.activityStatusClosedLabel,
    'archived' => l10n.activityStatusArchivedLabel,
    _ => l10n.activityUnknownStatusLabel(status),
  };
}
