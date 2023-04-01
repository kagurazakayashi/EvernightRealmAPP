/// 「單筆活動的玩家業務狀態定義」卡：讀目錄、改內建狀態的顯示名稱、
/// 建立與編輯自訂狀態（改名與停用）。
///
/// 這張卡的邊界與它接的後端通路一一對應，寫在這裡是因為界面藏不住它們：
///
/// * 底稿只能來自本卡按活動標識讀回的目錄：比對用的 `expected_*` 全部取自上一次 GET
///   的那一行。本地湊一份依據值等於把 2013 那道併發把關做成擺設。
/// * 七個內建值是封閉集合：界面沒有「新增一個內建狀態」那一格，也沒有刪除那一格。
///   能改的只有顯示名稱；改它不動內部值，也不動任何人的目前狀態或歷史引用。
/// * 顯示名稱留空是「恢復四語言預設文案」，不是刪除那個狀態——這句話寫在確認框裡，
///   因為「清空一格」在直覺上很容易被讀成「把那個狀態拿掉」。
/// * 自訂狀態只停用、不刪除（用戶批准於本步）：停用只讓它不再接收新的選用，
///   已經帶著它的人保留原狀態並照樣看得到名稱；重新啟用是可逆的，也不自動搬動任何人。
/// * 業務狀態不是連線狀態：這一欄不會因為請求抵達、頁面開啟或時間流逝而改變，
///   日後若真有在線指示也會另做並分開顯示。這句話寫在卡上而不是藏在錯誤訊息裡。
/// * 狀態名不帶任何未批准的副作用：界面不把 dead／arrested／eliminated 唸成
///   「他会冻结」「资产会被清空」或「他会退出活动」——本版今日没有那些行为。
/// * 內建狀態的顯示文字是用戶端四語言預設，自訂名稱與覆蓋是管理人打的純文字：
///   兩者一律走 `Text`，界面沒有把任何一格交給 HTML 或富文本渲染的通路。
/// * 按鈕只由服務端讀回的活動狀態決定：停止態仍可準備定義與顯示名稱（那是活動自己的
///   配置，與自選開關、目錄模式同一側），歸檔收起全部寫入控件並說「這件事已結束」（2029）。
/// * 現值過期（2013）與目錄讀不到都只留「重新讀取這份目錄」一個出口；
///   結果不明（連不上、逾時）絕不自動補發。成功句只在寫入回應回來之後出現。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';
import '../business_status_labels.dart';

/// 活動的玩家業務狀態定義卡。
class PlayerStatusConfigCard extends StatefulWidget {
  /// 以端點介面、活動標識與活動現狀建立本卡。
  const PlayerStatusConfigCard({
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

  /// 名稱的碼位上界（與後端域校驗同值；界面先擋是省一次注定 1004 的往返，
  /// 不是授權依據——真正的把關在服務端）。
  static const int maxNameRunes = 64;

  /// 「讀取狀態定義」按鈕識別鍵（目錄不自動載入：這張卡可以与名冊同屏，
  /// 而沒有要改狀態的人不該被迫多敲一條請求）。
  static const Key loadKey = ValueKey<String>('player-status-load');

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('player-status-loading');

  /// 重新讀取識別鍵（現值過期與載入失敗共用）。
  static const Key reloadKey = ValueKey<String>('player-status-reload');

  /// 內建那一組的容器識別鍵。
  static const Key builtinKey = ValueKey<String>('player-status-builtin');

  /// 自訂那一組的容器識別鍵。
  static const Key customKey = ValueKey<String>('player-status-custom');

  /// 自訂清單為空那句識別鍵。
  static const Key emptyKey = ValueKey<String>('player-status-empty');

  /// 內建某一行識別鍵（顯示名稱與改名按鈕都在這行裡）。
  static Key builtinRowKey(String statusKey) =>
      ValueKey<String>('player-status-builtin-row-$statusKey');

  /// 內建某一行的改名按鈕識別鍵。
  static Key builtinRenameKey(String statusKey) =>
      ValueKey<String>('player-status-builtin-rename-$statusKey');

  /// 自訂某一行的識別鍵。
  static Key customRowKey(String statusId) =>
      ValueKey<String>('player-status-custom-row-$statusId');

  /// 自訂某一行的改名按鈕識別鍵。
  static Key customRenameKey(String statusId) =>
      ValueKey<String>('player-status-custom-rename-$statusId');

  /// 自訂某一行的「停用／重新啟用」按鈕識別鍵（文案由服務端讀回的可用性決定）。
  static Key customToggleKey(String statusId) =>
      ValueKey<String>('player-status-custom-toggle-$statusId');

  /// 建立區各控件識別鍵。
  static const Key createNameKey = ValueKey<String>(
    'player-status-create-name',
  );
  static const Key createSubmitKey = ValueKey<String>(
    'player-status-create-submit',
  );

  /// 名稱編輯對話框各控件識別鍵。
  static const Key editNameKey = ValueKey<String>('player-status-edit-name');
  static const Key editSaveKey = ValueKey<String>('player-status-edit-save');
  static const Key editCancelKey = ValueKey<String>(
    'player-status-edit-cancel',
  );

  /// 「恢復預設名稱」按鈕識別鍵（確認框在按下之後才送出清空那一次寫入）。
  static const Key resetLabelKey = ValueKey<String>(
    'player-status-reset-label',
  );

  /// 確認框的肯定／取消按鈕識別鍵（停用、恢復、恢復預設名稱共用）。
  static const Key confirmKey = ValueKey<String>('player-status-confirm');
  static const Key confirmCancelKey = ValueKey<String>(
    'player-status-confirm-cancel',
  );

  /// 提示列識別鍵（本地校驗與失敗轉述共用）。
  static const Key noticeKey = ValueKey<String>('player-status-notice');

  /// 寫入成功列識別鍵。
  static const Key savedKey = ValueKey<String>('player-status-saved');

  /// 邊界交代列識別鍵（連線狀態、無副作用、無刪除、無快取四句）。
  static const Key connectivityKey = ValueKey<String>(
    'player-status-connectivity',
  );
  static const Key sideEffectKey = ValueKey<String>(
    'player-status-side-effect',
  );
  static const Key noDeleteKey = ValueKey<String>('player-status-no-delete');
  static const Key noCacheKey = ValueKey<String>('player-status-no-cache');

  /// 歸檔只讀列識別鍵。
  static const Key archivedKey = ValueKey<String>('player-status-archived');

  @override
  State<PlayerStatusConfigCard> createState() => _PlayerStatusConfigCardState();
}

class _PlayerStatusConfigCardState extends State<PlayerStatusConfigCard> {
  final TextEditingController _createName = TextEditingController();

  /// 目錄現值；null 表示還沒讀過（本卡不自動載入，理由見 `loadKey` 的說明）。
  PlayerStatusCatalogReport? _catalog;

  bool _loading = false;
  bool _writing = false;
  bool _stale = false;
  String? _notice;
  String? _saved;

  /// 正在改名那一行的底稿：內建行帶狀態鍵，自订行帶定義標識。
  _NameEditTarget? _editing;

  @override
  void dispose() {
    _createName.dispose();
    super.dispose();
  }

  /// 目前介面語言對應的 Accept-Language 標記。
  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 本卡此刻准不准寫：只採信服務端讀回的活動狀態——歸檔是終態一律收起控件，
  /// 其餘三態都能準備狀態定義與顯示名稱（口徑同目錄配置卡與自選開關卡）。
  bool get _canWrite => !_isArchived && !_stale && !_loading;

  /// 是否已歸檔（界面要如實說那一句，而不是靜默收起控件讓人以為載入壞了）。
  bool get _isArchived => widget.activityStatus == 'archived';

  /// 讀一次目錄（首次、每次寫入成功之後、以及 2013 與載入失敗的那個出口）。
  Future<void> _load() async {
    if (_loading) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _notice = null;
    });
    try {
      final PlayerStatusCatalogReport report = await widget.api
          .playerStatusCatalog(
            activityId: widget.activityId,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _catalog = report;
        _stale = false;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _catalog = null;
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  /// 名稱的本地校驗：剔首尾空白後非空、不超 64 碼位、不含控制或格式字元。
  ///
  /// 空字串在這裡是「沒有填」，而「恢復預設」走另一條路（確認框裡那顆按鈕），
  /// 兩句不能共用同一格輸入，否則清空輸入框會被讀成一次改名。
  String? _checkedName(String raw) {
    final String value = raw.trim();
    if (value.isEmpty ||
        value.runes.length > PlayerStatusConfigCard.maxNameRunes) {
      return null;
    }
    for (final int rune in value.runes) {
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

  /// 走一次寫入並以一次重讀收尾：回應那一筆是「這次操作的結果」，列表那一行是
  /// 「當前狀態」，兩處分開顯示，介面不拿提交時的意圖冒充現值。
  Future<void> _write(
    Future<Object?> Function() request, {
    required String Function(AppLocalizations l10n) successFor,
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
      await request();
      final PlayerStatusCatalogReport report = await widget.api
          .playerStatusCatalog(
            activityId: widget.activityId,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _catalog = report;
        _saved = successFor(l10n);
        _editing = null;
        _stale = false;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _editing = null;
        _notice = apiErrorText(l10n, error);
        // 2013 的處置只有重讀這份目錄；2029／2042／1004 由統一對映轉述。
        _stale = error.knownCode == ApiMachineCode.profileConflict;
      });
    }
  }

  /// 建立一個自訂狀態定義：本體只有名稱一格（可用性與標識都由服務端決定）。
  Future<void> _create() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? name = _checkedName(_createName.text);
    if (name == null) {
      setState(() => _notice = l10n.statusFormIncompleteNotice);
      return;
    }
    await _write(
      () => widget.api.createPlayerStatus(
        activityId: widget.activityId,
        name: name,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n) => l10n.statusCreatedNotice,
    );
    if (mounted) {
      _createName.clear();
    }
  }

  /// 改一個內建狀態在本活動的顯示名稱（空字串＝恢復四語言預設）。
  Future<void> _saveBuiltinLabel(
    PlayerBuiltinStatusReport row,
    String displayName,
  ) async {
    await _write(
      () => widget.api.updatePlayerStatusLabel(
        activityId: widget.activityId,
        statusKey: row.statusKey,
        displayName: displayName,
        expectedDisplayName: row.displayName,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n) => l10n.statusSavedNotice,
    );
  }

  /// 改名一個自訂狀態定義（本體恰好四格，含兩個依據值）。
  Future<void> _saveCustomName(
    PlayerCustomStatusReport row,
    String name,
  ) async {
    await _write(
      () => widget.api.updatePlayerStatus(
        activityId: widget.activityId,
        statusId: row.customStatusId,
        name: name,
        available: row.available,
        expectedName: row.name,
        expectedAvailable: row.available,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n) => l10n.statusSavedNotice,
    );
  }

  /// 翻一個自訂狀態的可用性（停用＝擋新的選用；既有歸屬一個字都不動）。
  Future<void> _toggleCustom(PlayerCustomStatusReport row) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool disabling = row.available;
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          disabling
              ? l10n.statusDisableConfirmTitle
              : l10n.statusEnableConfirmTitle,
        ),
        content: Text(
          disabling
              ? l10n.statusDisableConfirmBody
              : l10n.statusEnableConfirmBody,
        ),
        actions: <Widget>[
          TextButton(
            key: PlayerStatusConfigCard.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.activityConfirmCancelAction),
          ),
          FilledButton(
            key: PlayerStatusConfigCard.confirmKey,
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
      () => widget.api.updatePlayerStatus(
        activityId: widget.activityId,
        statusId: row.customStatusId,
        name: row.name,
        available: !row.available,
        expectedName: row.name,
        expectedAvailable: row.available,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n) => l10n.statusSavedNotice,
    );
  }

  /// 進入改名態：底稿與依據值同時取自目錄裡讀到的那一行。
  void _beginEditName(_NameEditTarget target) {
    setState(() {
      _editing = target;
      _notice = null;
      _saved = null;
    });
  }

  /// 送交對話框裡那一次改名（內建行走顯示名稱通路，自訂行走定義名稱通路）。
  Future<void> _submitNameEdit(String raw) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final _NameEditTarget? target = _editing;
    if (target == null) {
      return;
    }
    final String value = raw.trim();
    // 「清空＝恢復預設」只對內建那一句成立：自訂定義的名稱不能空。
    if (value.isEmpty && target.kind == _NameEditKind.builtinLabel) {
      await _saveBuiltinLabel(target.row!, '');
      return;
    }
    final String? name = _checkedName(value);
    if (name == null) {
      setState(() => _notice = l10n.statusInvalidNameNotice);
      return;
    }
    switch (target.kind) {
      case _NameEditKind.builtinLabel:
        await _saveBuiltinLabel(target.row!, name);
      case _NameEditKind.customName:
        await _saveCustomName(target.custom!, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final PlayerStatusCatalogReport? catalog = _catalog;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.statusSectionTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.statusSectionIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: <Widget>[
            if (catalog == null && !_loading)
              FilledButton(
                key: PlayerStatusConfigCard.loadKey,
                onPressed: _loading ? null : _load,
                child: Text(l10n.statusReloadAction),
              ),
            if (catalog != null)
              OutlinedButton(
                key: PlayerStatusConfigCard.reloadKey,
                onPressed: _loading ? null : _load,
                child: Text(l10n.statusReloadAction),
              ),
          ],
        ),
        if (_loading)
          Text(
            l10n.statusLoadingNotice,
            key: PlayerStatusConfigCard.loadingKey,
            style: theme.textTheme.bodySmall,
          ),
        if (_isArchived && catalog != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            l10n.statusArchivedNotice,
            key: PlayerStatusConfigCard.archivedKey,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (_stale) ...<Widget>[
          const SizedBox(height: 6),
          Text(l10n.statusStaleNotice, style: theme.textTheme.bodySmall),
        ],
        if (_notice != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            _notice!,
            key: PlayerStatusConfigCard.noticeKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (_saved != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            _saved!,
            key: PlayerStatusConfigCard.savedKey,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (catalog != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(l10n.statusBuiltinGroupTitle, style: theme.textTheme.titleSmall),
          Column(
            key: PlayerStatusConfigCard.builtinKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final PlayerBuiltinStatusReport row
                  in catalog.builtinStatuses)
                _BuiltinStatusRow(
                  row: row,
                  l10n: l10n,
                  busy: _writing || _loading,
                  canWrite: _canWrite,
                  onRename: () =>
                      _beginEditName(_NameEditTarget.builtin(row: row)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l10n.statusCustomGroupTitle, style: theme.textTheme.titleSmall),
          if (catalog.customStatuses.isEmpty)
            Text(
              l10n.statusCustomEmptyNotice,
              key: PlayerStatusConfigCard.emptyKey,
              style: theme.textTheme.bodySmall,
            )
          else
            Column(
              key: PlayerStatusConfigCard.customKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final PlayerCustomStatusReport row
                    in catalog.customStatuses)
                  _CustomStatusRow(
                    row: row,
                    l10n: l10n,
                    busy: _writing || _loading,
                    canWrite: _canWrite,
                    onRename: () =>
                        _beginEditName(_NameEditTarget.custom(custom: row)),
                    onToggle: () => _toggleCustom(row),
                  ),
              ],
            ),
          if (_canWrite) ...<Widget>[
            const SizedBox(height: 12),
            Text(l10n.statusCreateAction, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            TextField(
              key: PlayerStatusConfigCard.createNameKey,
              controller: _createName,
              decoration: InputDecoration(
                labelText: l10n.statusNameLabel,
                helperText: l10n.statusCustomGroupTitle,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: PlayerStatusConfigCard.createSubmitKey,
                onPressed: _writing ? null : _create,
                child: Text(l10n.statusCreateAction),
              ),
            ),
          ],
          if (_editing != null) ...<Widget>[
            const SizedBox(height: 12),
            _NameEditForm(
              target: _editing!,
              l10n: l10n,
              busy: _writing,
              onSubmit: _submitNameEdit,
              onCancel: () => setState(() => _editing = null),
            ),
          ],
        ],
        const SizedBox(height: 12),
        // 四句邊界常驻在卡下方：它們講的是「這一欄不會做什麼」，
        // 留在一顆按鈕後面就等於讓人在按下之前讀不到。
        Text(
          l10n.statusConnectivityNotice,
          key: PlayerStatusConfigCard.connectivityKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.statusNoSideEffectNotice,
          key: PlayerStatusConfigCard.sideEffectKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.statusNoDeleteNotice,
          key: PlayerStatusConfigCard.noDeleteKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.statusNoCacheNotice,
          key: PlayerStatusConfigCard.noCacheKey,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// 改名那一筆的底稿形態：內建狀態改的是顯示名稱，自訂狀態改的是定義名稱。
enum _NameEditKind { builtinLabel, customName }

/// 一次改名對話框的目標（帶著它自己的服務端現值當依據值）。
class _NameEditTarget {
  /// 以內建狀態那一行建立一份底稿。
  const _NameEditTarget.builtin({required this.row})
    : custom = null,
      kind = _NameEditKind.builtinLabel;

  /// 以自訂狀態那一行建立一份底稿。
  const _NameEditTarget.custom({required this.custom})
    : row = null,
      kind = _NameEditKind.customName;

  final PlayerBuiltinStatusReport? row;
  final PlayerCustomStatusReport? custom;
  final _NameEditKind kind;

  /// 對話框預填的現值（也是提交時的依據值）。
  String get currentName => switch (kind) {
    _NameEditKind.builtinLabel => row?.displayName ?? '',
    _NameEditKind.customName => custom?.name ?? '',
  };

  /// 這一行在界面上怎麼被稱呼（確認句與標題都用現讀的名稱，不拿內部值冒充）。
  String titleFor(AppLocalizations l10n) {
    final String? label = businessStatusLabel(
      l10n: l10n,
      businessStatus: row?.statusKey ?? '',
      statusDisplayName: currentName,
      customStatusName: currentName,
    );
    return label ?? row?.statusKey ?? custom?.customStatusId ?? '';
  }
}

/// 內建狀態的一行：內部值、此刻的顯示名稱，以及改名／恢復預設兩顆按鈕。
class _BuiltinStatusRow extends StatelessWidget {
  /// 以一行現值與動作建立。
  const _BuiltinStatusRow({
    required this.row,
    required this.l10n,
    required this.busy,
    required this.canWrite,
    required this.onRename,
  });

  /// 服務端讀回的那一行展示現值。
  final PlayerBuiltinStatusReport row;

  /// 目前語言的語彙。
  final AppLocalizations l10n;

  /// 有寫入在飛：不允許第二次提交。
  final bool busy;

  /// 現在准不准寫。
  final bool canWrite;

  /// 進入改名態的回呼。
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String defaultLabel =
        builtinBusinessStatusLabel(l10n, row.statusKey) ?? row.statusKey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        key: PlayerStatusConfigCard.builtinRowKey(row.statusKey),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  row.displayName.isEmpty ? defaultLabel : row.displayName,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (canWrite)
                OutlinedButton(
                  key: PlayerStatusConfigCard.builtinRenameKey(row.statusKey),
                  onPressed: busy ? null : onRename,
                  child: Text(l10n.statusRenameAction),
                ),
            ],
          ),
          // 內部值是這行的身份；顯示名稱只是陪襯。兩者同行並列，
          // 介面就不可能把「改了名稱」讀成「改了內部值」。
          Text(
            l10n.labelValuePair(l10n.statusIdLabel, row.statusKey),
            style: theme.textTheme.bodySmall,
          ),
          if (row.usesDefaultDisplayName)
            Text(
              l10n.statusDefaultLabelNotice,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

/// 自訂狀態的一行：名稱、標識、可用性，以及改名與停用／重新啟用兩顆按鈕（沒有刪除）。
class _CustomStatusRow extends StatelessWidget {
  /// 以一行現值與動作建立。
  const _CustomStatusRow({
    required this.row,
    required this.l10n,
    required this.busy,
    required this.canWrite,
    required this.onRename,
    required this.onToggle,
  });

  /// 服務端讀回的那一行定義。
  final PlayerCustomStatusReport row;

  /// 目前語言的語彙。
  final AppLocalizations l10n;

  /// 有寫入在飛：不允許第二次提交。
  final bool busy;

  /// 現在准不准寫。
  final bool canWrite;

  /// 進入改名態的回呼。
  final VoidCallback onRename;

  /// 送一次可用性翻轉（確認框在卡那一側）的回呼。
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        key: PlayerStatusConfigCard.customRowKey(row.customStatusId),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 自訂名稱是管理人打的純文字：一律走 Text，不經任何 HTML 通路。
                    Text(row.name, style: theme.textTheme.bodyMedium),
                    Text(
                      l10n.labelValuePair(
                        l10n.statusIdLabel,
                        row.customStatusId,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      l10n.labelValuePair(
                        l10n.statusAvailableLabel,
                        row.available
                            ? l10n.statusEnabledLabel
                            : l10n.statusDisabledLabel,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (canWrite)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    OutlinedButton(
                      key: PlayerStatusConfigCard.customRenameKey(
                        row.customStatusId,
                      ),
                      onPressed: busy ? null : onRename,
                      child: Text(l10n.statusRenameAction),
                    ),
                    OutlinedButton(
                      key: PlayerStatusConfigCard.customToggleKey(
                        row.customStatusId,
                      ),
                      onPressed: busy ? null : onToggle,
                      child: Text(
                        row.available
                            ? l10n.statusDisableAction
                            : l10n.statusEnableAction,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 名稱編輯區：底稿是目錄讀到的那一行，提交時帶著它所依據的現值。
///
/// 內建那一種允許把輸入留空——空字串在後端那條通路上的語意是「恢復四語言預設」，
/// 界面把這句話寫在 helper 裡，而不是讓操作者以為自己刪除了那個狀態。
class _NameEditForm extends StatefulWidget {
  /// 以底稿與動作建立。
  const _NameEditForm({
    required this.target,
    required this.l10n,
    required this.busy,
    required this.onSubmit,
    required this.onCancel,
  });

  /// 要改的那一行（含它的現值）。
  final _NameEditTarget target;

  /// 目前語言的語彙。
  final AppLocalizations l10n;

  /// 有寫入在飛：不允許第二次提交。
  final bool busy;

  /// 提交（帶著未正規化的原始輸入；正規化與校驗在卡那一側）。
  final ValueSetter<String> onSubmit;

  /// 放棄這次編輯（零請求）。
  final VoidCallback onCancel;

  @override
  State<_NameEditForm> createState() => _NameEditFormState();
}

class _NameEditFormState extends State<_NameEditForm> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.target.currentName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = widget.l10n;
    final ThemeData theme = Theme.of(context);
    final bool isLabel = widget.target.kind == _NameEditKind.builtinLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.statusRenameDialogTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(widget.target.titleFor(l10n), style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(
          key: PlayerStatusConfigCard.editNameKey,
          controller: _controller,
          decoration: InputDecoration(
            labelText: l10n.statusDisplayNameLabel,
            helperText: isLabel ? l10n.statusDefaultLabelNotice : null,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            FilledButton(
              key: PlayerStatusConfigCard.editSaveKey,
              onPressed: widget.busy
                  ? null
                  : () => widget.onSubmit(_controller.text),
              child: Text(l10n.activitySaveAction),
            ),
            OutlinedButton(
              key: PlayerStatusConfigCard.editCancelKey,
              onPressed: widget.busy ? null : widget.onCancel,
              child: Text(l10n.activityConfirmCancelAction),
            ),
            // 「恢復預設」是一顆明確的按鈕，而不是「把輸入框清空再保存」：
            // 兩句在同一格裡長得一樣，而後端那條通路的語意完全不同。
            if (isLabel && widget.target.currentName.isNotEmpty)
              OutlinedButton(
                key: PlayerStatusConfigCard.resetLabelKey,
                onPressed: widget.busy
                    ? null
                    : () async {
                        final AppLocalizations l10n = AppLocalizations.of(
                          context,
                        );
                        final bool? answer = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext dialogContext) => AlertDialog(
                            title: Text(l10n.statusResetLabelConfirmTitle),
                            content: Text(l10n.statusResetLabelConfirmBody),
                            actions: <Widget>[
                              TextButton(
                                key: PlayerStatusConfigCard.confirmCancelKey,
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: Text(l10n.activityConfirmCancelAction),
                              ),
                              FilledButton(
                                key: PlayerStatusConfigCard.confirmKey,
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: Text(l10n.activityConfirmOkAction),
                              ),
                            ],
                          ),
                        );
                        if (answer == true) {
                          widget.onSubmit('');
                        }
                      },
                child: Text(l10n.statusResetLabelAction),
              ),
          ],
        ),
      ],
    );
  }
}
