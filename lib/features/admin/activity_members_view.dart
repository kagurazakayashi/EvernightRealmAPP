/// 「單筆活動的成員名冊」卡：讀名冊、把一個既有帳戶加入活動、更改活動內暱稱。
///
/// 這張卡的邊界與它接的後端通路一一對應，寫在這裡是因為界面藏不住它們：
///
/// * 底稿只能來自本卡按活動標識讀回的名冊：編輯表單預填的是上一次 GET 的那一行，
///   compare-and-set 的唯一依據值（`expected_nickname`）也是它。目錄裡的印象與
///   本地緩存都不夠格當底稿。
/// * 一個帳戶在一場活動裡只有一份檔案：重複提交由後端回 2035，界面不謊報成功，
///   也不拿「再按一次」去試——要改那份既有檔案就走改名那條路。
/// * 身分三欄不在任何一格裡：加入的人是誰由那張卡上填的帳戶標識決定（型別與狀態
///   由服務端現讀），屬於哪場活動由路徑決定，成员標識由服務端產生。本卡沒有任何
///   通路能改成員標識、改指向的帳戶、把一個人挪到另一場活動——後端這一族沒有 DELETE
///   （用戶批准：沒有把成員移出活動的通路），也沒有能把人改成別人身分的通路。
/// * 陣營歸屬在本版本只讀且恆為「尚未分組」：分配通路尚未落地，因此界面不擺任何
///   一颗「分到某組」的按鈕，也不拿空清單或 0 冒充已經有分配。這一句寫在
///   `memberFactionPendingNotice` 上，用的是服務端回讀的值而不是本地推測。
/// * 按鈕只由服務端讀回的活動狀態決定：草稿與開放可寫（開放前就能備名單）；
///   停止收起全部寫入控件並說明「重開後照常能改」（2033），歸檔收起並說「這件事已結束」
///   （2029）；表外狀態一律當不可寫。
/// * 現值過期（2013）時收起寫入控件，只留「重新讀取這份名冊」一個出口；
///   結果不明（連不上、逾時）絕不自動補發，由人重讀再決定。
/// * 成功句只在寫入回應回來之後出現，內容取回應回讀的現值：保存成功前不顯示「已完成」。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 活動成員名冊卡。
class ActivityMembersCard extends StatefulWidget {
  /// 以端點介面、活動標識與活動現狀建立本卡。
  const ActivityMembersCard({
    super.key,
    required this.api,
    required this.activityId,
    required this.activityStatus,
  });

  /// 統一端點存取介面。
  final ServerApi api;

  /// 歸屬活動的標識（路徑引數；請求本體沒有這一格）。
  final String activityId;

  /// 服務端讀回的活動狀態：本卡的寫入控件只由它決定，不由本地推測。
  final String activityStatus;

  /// 暱稱的碼位上界（與後端域校驗同值；界面先擋是省一次注定 1004 的往返，
  /// 不是授權依據——真正的把關在服務端）。
  static const int maxNicknameRunes = 64;

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('activity-members-loading');

  /// 載入失敗識別鍵。
  static const Key failedKey = ValueKey<String>('activity-members-failed');

  /// 重新讀取識別鍵（現值過期與載入失敗共用）。
  static const Key reloadKey = ValueKey<String>('activity-members-reload');

  /// 空名冊識別鍵。
  static const Key emptyKey = ValueKey<String>('activity-members-empty');

  /// 名冊容器識別鍵。
  static const Key listKey = ValueKey<String>('activity-members-list');

  /// 停止說明列識別鍵。
  static const Key closedKey = ValueKey<String>('activity-members-closed');

  /// 歸檔只讀列識別鍵。
  static const Key archivedKey = ValueKey<String>('activity-members-archived');

  /// 「陣營分配尚未落地」那句交代列的識別鍵。
  static const Key factionPendingKey = ValueKey<String>(
    'activity-members-faction-pending',
  );

  /// 名冊某一行的識別鍵。
  static Key rowKey(String memberId) =>
      ValueKey<String>('activity-members-row-$memberId');

  /// 行內「改名」按鈕識別鍵。
  static Key renameActionKey(String memberId) =>
      ValueKey<String>('activity-members-rename-$memberId');

  /// 某一行的「目錄可見性」開關識別鍵（收緊與放回同一顆按鈕，語意取自那一行的現值）。
  static Key visibilityActionKey(String memberId) =>
      ValueKey<String>('activity-members-visibility-$memberId');

  /// 某一行的目錄可見性交代列識別鍵（含「他此刻是不是管理員身分」那一句）。
  static Key visibilityLabelKey(String memberId) =>
      ValueKey<String>('activity-members-visibility-label-$memberId');

  /// 可見性確認框的肯定／取消按鈕識別鍵。
  static const Key visibilityConfirmKey = ValueKey<String>(
    'activity-members-visibility-confirm',
  );

  /// 可見性確認框的取消按鈕識別鍵。
  static const Key visibilityCancelKey = ValueKey<String>(
    'activity-members-visibility-cancel',
  );

  /// 建立區各控件識別鍵。
  static const Key createAccountKey = ValueKey<String>(
    'activity-members-create-account',
  );
  static const Key createNicknameKey = ValueKey<String>(
    'activity-members-create-nickname',
  );
  static const Key createSubmitKey = ValueKey<String>(
    'activity-members-create-submit',
  );

  /// 編輯區各控件識別鍵（同時只有一份在編）。
  static const Key editNicknameKey = ValueKey<String>(
    'activity-members-edit-nickname',
  );
  static const Key editSaveKey = ValueKey<String>('activity-members-edit-save');
  static const Key editCancelKey = ValueKey<String>(
    'activity-members-edit-cancel',
  );

  /// 提示列識別鍵（本地校驗與失敗轉述共用）。
  static const Key noticeKey = ValueKey<String>('activity-members-notice');

  /// 寫入成功列識別鍵。
  static const Key savedKey = ValueKey<String>('activity-members-saved');

  @override
  State<ActivityMembersCard> createState() => _ActivityMembersCardState();
}

class _ActivityMembersCardState extends State<ActivityMembersCard> {
  final TextEditingController _createAccount = TextEditingController();
  final TextEditingController _createNickname = TextEditingController();
  final TextEditingController _editNickname = TextEditingController();

  List<MemberReport> _members = const <MemberReport>[];
  bool _loading = true;
  bool _writing = false;
  String? _notice;
  String? _saved;

  /// 現值過期（2013）：收起寫入控件，只留重讀出口（口徑同陣營卡與詳情卡）。
  bool _stale = false;

  /// 正在編輯的那一行標識與它的服務端現值（依據值只能取自這裡）。
  String? _editingId;
  MemberReport? _editingBaseline;

  @override
  void initState() {
    super.initState();
    // 首讀排在第一幀之後，免得在 initState 裡讀 Localizations（同陣營卡手法）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _createAccount.dispose();
    _createNickname.dispose();
    _editNickname.dispose();
    super.dispose();
  }

  /// 目前介面語言對應的 Accept-Language 標記。
  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 本卡此刻准不准寫：只採信服務端讀回的活動狀態——已批准可寫的形態只有 draft
  /// 與 active 兩個名字，表外值（後端日後放寬集合時的多餘取值）一律當不可寫。
  bool get _canWrite =>
      (widget.activityStatus == 'draft' || widget.activityStatus == 'active') &&
      !_stale;

  /// 讀這份名冊。失敗時整卡轉述那一句失敗，不顯示任何舊資料。
  Future<void> _load() async {
    setState(() => _loading = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final MemberListReport report = await widget.api.activityMembers(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _members = report.members;
        _stale = false;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _members = const <MemberReport>[];
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  /// 走一次寫入並重讀名冊：回應裡那一筆是回讀的事實，而順序只有後端知道，
  /// 成功之後以一次 GET 收尾，不做本地拼裝（也不先於回應顯示「已完成」）。
  Future<void> _write(
    Future<MemberWriteReport> Function() request, {
    required String Function(AppLocalizations l10n, MemberWriteReport result)
    successFor,
  }) async {
    if (_writing) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _writing = true;
      _notice = null;
      _saved = null;
    });
    try {
      final MemberWriteReport result = await request();
      if (!mounted) {
        return;
      }
      final MemberListReport report = await widget.api.activityMembers(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _members = report.members;
        _saved = successFor(l10n, result);
        _editingId = null;
        _editingBaseline = null;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _notice = _failureText(l10n, error);
        // 2013 的處置是重讀這份名冊；2035／2033／2029 各是一句現狀說明，
        // 由統一對映轉述——界面早按活動狀態收起控件，這裡兜的是繞過界面與競態的尾巴。
        _stale = error.knownCode == ApiMachineCode.profileConflict;
      });
    }
  }

  /// 失敗轉述：2035 那句另起一句人話（他已經是成員了），其餘走統一對映。
  String _failureText(AppLocalizations l10n, ApiError error) {
    if (error.knownCode == ApiMachineCode.activityMemberTaken) {
      return l10n.errorCodeActivityMemberTaken;
    }
    return apiErrorText(l10n, error);
  }

  /// 暱稱的本地校驗：剔首尾空白後非空、不超 64 碼位、不含控制或格式字元。
  ///
  /// 合法時回正規化值，非法回 null 並由呼叫端念那一句——把關仍在服務端，
  /// 本地先擋只省一次注定 1004 的往返。
  String? _checkedNickname(String raw) {
    final String value = raw.trim();
    if (value.isEmpty ||
        value.runes.length > ActivityMembersCard.maxNicknameRunes) {
      return null;
    }
    for (final int rune in value.runes) {
      // 控制字元（U+0000–U+001F、U+007F–U+009F）與格式字元（Cf）都不屬於一個給人讀的名字。
      if ((rune <= 0x1F) ||
          (rune >= 0x7F && rune <= 0x9F) ||
          rune == 0x200B ||
          rune == 0x200E ||
          rune == 0x200F ||
          rune == 0xFEFF ||
          rune == 0x2060) {
        return null;
      }
    }
    return value;
  }

  /// 送交一次加入：帳戶標識必填（格式由後端判定，非法與查無同形回 1001），
  /// 暱稱走本地先擋。本卡沒有陣營那一格——今日無處可填，也不該填。
  Future<void> _create() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String accountId = _createAccount.text.trim();
    if (accountId.isEmpty) {
      setState(() => _notice = l10n.memberFormIncompleteNotice);
      return;
    }
    final String? nickname = _checkedNickname(_createNickname.text);
    if (nickname == null) {
      setState(() => _notice = l10n.memberInvalidNicknameNotice);
      return;
    }
    await _write(
      () => widget.api.createMember(
        activityId: widget.activityId,
        accountId: accountId,
        nickname: nickname,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n, MemberWriteReport report) =>
          l10n.memberCreatedNotice(report.member.nickname),
    );
    if (mounted) {
      _createAccount.clear();
      _createNickname.clear();
    }
  }

  /// 進入編輯態：表單與依據值同時取自那行的服務端現值（兩處必須同源）。
  void _beginEdit(MemberReport member) {
    setState(() {
      _editingId = member.memberId;
      _editingBaseline = member;
      _editNickname.text = member.nickname;
      _notice = null;
      _saved = null;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _editingBaseline = null;
    });
  }

  /// 送交一次改名：新值加上它所依據的現值。身份三欄與陣營都不在這條通路上。
  Future<void> _saveEdit() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MemberReport? baseline = _editingBaseline;
    if (baseline == null) {
      return;
    }
    final String? nickname = _checkedNickname(_editNickname.text);
    if (nickname == null) {
      setState(() => _notice = l10n.memberInvalidNicknameNotice);
      return;
    }
    await _write(
      () => widget.api.updateMemberNickname(
        activityId: widget.activityId,
        memberId: baseline.memberId,
        nickname: nickname,
        expectedNickname: baseline.nickname,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n, MemberWriteReport report) =>
          l10n.memberNicknameSavedNotice(report.member.nickname),
    );
  }

  /// 送交一次目錄可見性覆蓋：本體恰好兩格（新值與它所依據的現值），對象由路徑決定。
  ///
  /// 這一格只能往「更看不見」的方向走（取值集合就只有 inherit｜hidden），
  /// 界面上也不提供第三種寫法：一格能繞過整個活動規則的開關就不是覆蓋，是第二套規則。
  /// 它收的是「其他普通玩家在目錄裡讀不讀得到這一行的投影」——
  /// 不影響管理名冊（這一讀本來就是管理面，仍列、可讀），也不影響本人那條通路；
  /// 那兩句要在按下去之前講清楚，否則這顆按鈕會被讀成「把人移出活動」。
  Future<void> _toggleVisibility(MemberReport member) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (_writing) {
      return;
    }
    final bool hiding = member.directoryVisibility != 'hidden';
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.memberVisibilityConfirmTitle),
        content: Text(
          hiding
              ? l10n.memberVisibilityHideConfirmBody(member.nickname)
              : l10n.memberVisibilityRestoreConfirmBody(member.nickname),
        ),
        actions: <Widget>[
          TextButton(
            key: ActivityMembersCard.visibilityCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.activityConfirmCancelAction),
          ),
          FilledButton(
            key: ActivityMembersCard.visibilityConfirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.activityConfirmOkAction),
          ),
        ],
      ),
    );
    if (answer != true || !mounted) {
      return;
    }
    await _write(
      () => widget.api.updateMemberDirectoryVisibility(
        activityId: widget.activityId,
        memberId: member.memberId,
        visibility: hiding ? 'hidden' : 'inherit',
        // 依據值只取自這一行剛讀回的現值——本地湊一份「應該是 inherit」會把 2013
        // 那道併發把關變成擺設（同一時刻另一位管理人可能已經動過這一格）。
        expectedVisibility: member.directoryVisibility,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n, MemberWriteReport report) => hiding
          ? l10n.memberVisibilityHiddenNotice(report.member.nickname)
          : l10n.memberVisibilityRestoredNotice(report.member.nickname),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    if (_loading) {
      return Text(
        l10n.memberLoadingNotice,
        key: ActivityMembersCard.loadingKey,
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.memberSectionTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.memberSectionIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        if (widget.activityStatus == 'archived') ...<Widget>[
          Text(
            l10n.memberArchivedNotice,
            key: ActivityMembersCard.archivedKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ] else if (widget.activityStatus == 'closed') ...<Widget>[
          Text(
            l10n.memberClosedNotice,
            key: ActivityMembersCard.closedKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        if (_stale) ...<Widget>[
          Text(l10n.memberStaleNotice, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: ActivityMembersCard.reloadKey,
              onPressed: _load,
              child: Text(l10n.activityReloadAction),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_notice != null) ...<Widget>[
          Text(
            _notice!,
            key: ActivityMembersCard.noticeKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_saved != null) ...<Widget>[
          Text(
            _saved!,
            key: ActivityMembersCard.savedKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        if (_members.isEmpty)
          Text(
            l10n.memberEmptyNotice,
            key: ActivityMembersCard.emptyKey,
            style: theme.textTheme.bodySmall,
          )
        else
          Column(
            key: ActivityMembersCard.listKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final MemberReport member in _members)
                _MemberRow(
                  member: member,
                  l10n: l10n,
                  busy: _writing,
                  canWrite: _canWrite,
                  onRename: () => _beginEdit(member),
                  onToggleVisibility: () => _toggleVisibility(member),
                ),
            ],
          ),
        // 「尚未分組」是本版本的現值，這句話跟著列表出現而不是藏在某顆按鈕後面：
        // 用戶要的是一眼看得出「這裡還沒有分配這回事」，不是一份看起來空卻被當故障的清單。
        Text(
          l10n.memberFactionPendingNotice,
          key: ActivityMembersCard.factionPendingKey,
          style: theme.textTheme.bodySmall,
        ),
        if (_canWrite) ...<Widget>[
          const SizedBox(height: 16),
          _createForm(l10n, theme),
        ],
        if (_canWrite && _editingId != null) ...<Widget>[
          const SizedBox(height: 16),
          _editForm(l10n, theme),
        ],
      ],
    );
  }

  /// 加入區：兩欄（帳戶標識與活動內暱稱）。沒有陣營那一格——今日無處可填。
  Widget _createForm(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.memberAddTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.memberTargetAccountHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(
          key: ActivityMembersCard.createAccountKey,
          controller: _createAccount,
          decoration: InputDecoration(labelText: l10n.memberTargetAccountLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          key: ActivityMembersCard.createNicknameKey,
          controller: _createNickname,
          decoration: InputDecoration(
            labelText: l10n.memberNicknameLabel,
            helperText: l10n.memberNicknameHint,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: ActivityMembersCard.createSubmitKey,
            onPressed: _writing ? null : _create,
            child: Text(l10n.memberAddAction),
          ),
        ),
      ],
    );
  }

  /// 改名區：只有暱稱一欄，依據值取自那行讀回的現值。
  Widget _editForm(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.memberEditNicknameTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.memberNicknameEditHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(
          key: ActivityMembersCard.editNicknameKey,
          controller: _editNickname,
          decoration: InputDecoration(labelText: l10n.memberNicknameLabel),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            FilledButton(
              key: ActivityMembersCard.editSaveKey,
              onPressed: _writing ? null : _saveEdit,
              child: Text(l10n.factionEditSaveAction),
            ),
            OutlinedButton(
              key: ActivityMembersCard.editCancelKey,
              onPressed: _writing ? null : _cancelEdit,
              child: Text(l10n.memberCancelAction),
            ),
          ],
        ),
      ],
    );
  }
}

/// 名冊的一行：暱稱是主詞，其餘都是陪襯的現值，全部取自服務端回應。
///
/// 三個刻意：不拿顏色或圖標單獨承載身分；「尚未分組」講成一句取值而不是留白；
/// 帳戶行讀不回時唸通用句，不編一個名字、也不把整份名冊判死。
class _MemberRow extends StatelessWidget {
  /// 以一行現值與界面語彙建立。
  const _MemberRow({
    required this.member,
    required this.l10n,
    required this.busy,
    required this.canWrite,
    required this.onRename,
    required this.onToggleVisibility,
  });

  /// 那一行的服務端現值。
  final MemberReport member;

  /// 目前語言的語彙。
  final AppLocalizations l10n;

  /// 有寫入在飛：不允許第二次提交。
  final bool busy;

  /// 現在准不准寫（活動狀態與是否過期決定）。
  final bool canWrite;

  /// 進入編輯態的回呼。
  final VoidCallback onRename;

  /// 送一次目錄可見性覆蓋的回呼（收緊與放回同一顆按鈕，語意取自行現值）。
  final VoidCallback onToggleVisibility;

  /// 狀態取值：active 與 disabled 各有批准過的一句人話，其餘（含deleted／retired／
  /// pending／rejected 與未來新增的任何取值）一律如實唸出服務端的機器值而不猜意思——
  /// 界面不替自己發明第二套狀態語意。
  String _statusText(AppLocalizations l10n) {
    switch (member.accountStatus) {
      case 'active':
        return l10n.memberStatusActiveLabel;
      case 'disabled':
        return l10n.memberStatusDisabledLabel;
      case '':
        return l10n.memberAccountUnreadableNotice;
      default:
        return l10n.memberStatusRawLabel(member.accountStatus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // 暱稱是这一行身分的承擔者；兩处都可能很長，窄欄一律靠 Wrap 換行而非截斷。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        key: ActivityMembersCard.rowKey(member.memberId),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(member.nickname, style: theme.textTheme.bodyLarge),
              ),
              if (canWrite)
                OutlinedButton(
                  key: ActivityMembersCard.renameActionKey(member.memberId),
                  onPressed: busy ? null : onRename,
                  child: Text(l10n.memberNicknameAction),
                ),
            ],
          ),
          Text(
            l10n.labelValuePair(
              l10n.memberAccountStatusLabel,
              _statusText(l10n),
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            // 有陣營時唸標識（本版本永遠走不到這一支）；空字串是「尚未分組」這個合法現值。
            l10n.labelValuePair(
              l10n.memberFactionColumnLabel,
              member.hasFaction
                  ? member.factionId
                  : l10n.memberFactionUnassignedLabel,
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            member.displayName.isEmpty
                ? l10n.memberAccountUnreadableNotice
                : l10n.labelValuePair(
                    l10n.memberAccountLineLabel,
                    '${member.displayName}／${member.accountId}',
                  ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            // 這一行的覆蓋現值與「此刻是不是管理員身分」都取自服務端讀回的投影：
            // 前者回答「其他玩家在目錄裡讀不讀得到他」，後者回答
            // all_players_except_admin 那一態收起來的是誰。雨者都不是昵稱或標籤。
            l10n.labelValuePair(
              l10n.memberVisibilityColumnLabel,
              member.directoryVisibility == 'hidden'
                  ? l10n.memberVisibilityHiddenLabel
                  : l10n.memberVisibilityInheritLabel,
            ),
            key: ActivityMembersCard.visibilityLabelKey(member.memberId),
            style: theme.textTheme.bodySmall,
          ),
          if (member.adminIdentity)
            Text(
              l10n.memberAdminIdentityNotice,
              style: theme.textTheme.bodySmall,
            ),
          if (canWrite)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: OutlinedButton(
                key: ActivityMembersCard.visibilityActionKey(member.memberId),
                onPressed: busy ? null : onToggleVisibility,
                child: Text(
                  member.directoryVisibility == 'hidden'
                      ? l10n.memberVisibilityRestoreAction
                      : l10n.memberVisibilityHideAction,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
