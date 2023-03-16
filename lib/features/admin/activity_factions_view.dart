/// 「單筆活動的陣營管理」卡：列表、建立與編輯（含可用性開關）。
///
/// 這張卡的邊界與它接的後端通路一一对应，寫在這裡是因為界面藏不住它們：
///
/// * 底稿只能來自本卡按活動標識讀回的列表：編輯表單預填的是上一次 GET 的那一行，
///   compare-and-set 的六個依據值也是它。目錄裡的印象與本地緩存都不夠格當底稿。
/// * 標識與歸屬不在任何一格裡：新建的陣營屬於哪場活動由路徑決定，編輯對象是哪一行
///   也由路徑決定。本卡沒有任何通路能改陣營 ID、挪動歸屬活動或刪除一行——
///   後端這一族沒有 DELETE（用戶批准：只有可用／停用，沒有刪除通路）。
/// * 按鈕只由服務端讀回的活动狀態決定：草稿與開放可寫（準備期本就該能設陣營）；
///   停止收起全部寫入控件並說明「重開後照常能改」——那一句（2033）是「現在不行」，
///   與歸檔的「這件事已經結束」（2029）分得開；歸檔同樣收起。表外狀態不長按鈕。
/// * 顏色與圖標是展示，不是身份：每一行都把名稱寫在色塊與圖標旁邊，未選色或未選圖標
///   以中性佔位呈現。同活動內名稱唯一（撞名拿到 2034 那一句「換個名字」），
///   其他活動的同名陣營與這一場無關——本卡讀的就是這個活動的列表，天然分書。
/// * 現值過期（2013）時收起寫入控件，只留「重新讀取這份列表」一個出口；
///   結果不明（連不上、逾時）絕不自動補發，由人重讀再決定。
/// * 成功句只在寫入回應回來之後出現：保存成功前不顯示「已完成」。
///
/// 停用與恢復那兩顆按鈕的邊界（與後端那一條 PUT 白名單一一對應）：
///
/// * 沒有第二條寫入通路：停用就是把那一欄翻成假、恢復就是翻回真，發的是同一個 PUT，
///   帶齊六欄新值與六欄依據值。後端沒有「陣營狀態子資源」，界面上那兩顆按鈕也只是
///   編輯的捷徑，不是另一套語意。
/// * 「當前狀態」與「操作結果」分兩處講：前者取自列表讀回的那一行（按鈕文案與確認框
///   首行都讀它），後者取自寫入回應回讀的現值。回應沒回來之前不寫「已停用」。
/// * 確認框念的是成員影響摘要：不再接收新分配、既有成員保留原歸屬且同陣營仍互見、
///   不踢出活動不凍結帳戶不刪行、日後可恢復。成員歸屬與歷史交易尚未接入本版本這件事
///   如實寫在摘要裡——這裡沒有成員名單，也不拿「0 位」或空清單冒充會被影響的人。
/// * 那一格 `accepts_new_members` 是服務端派生值，界面只讀不寫：活動停止或歸檔時，
///   連標記為可用的陣營也照實顯示「此刻不接收新分配」，界面不拿 available 自己去猜。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 陣營管理卡。
class ActivityFactionsCard extends StatefulWidget {
  /// 以端點介面、活動標識與活動現狀建立本卡。
  const ActivityFactionsCard({
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

  /// 排序值的界內上界（與後端域校驗同值；界面先擋是省一次注定 1004 的往返，
  /// 不是授權依據——真正的把關在服務端）。
  static const int maxSortOrder = 99999;

  /// 內建圖標鍵的封閉集合（與後端遷移 0013 的 CHECK 與 internal/activity 同清單，
  /// 漂移由契約測試各自點名）。每一個鍵都在本檔尾部的 `factionIconData` 有對應的
  /// 本地 Material 圖標；選鍵靠的是「這一版的 Flutter 一定画得出來」，不是名字好聽。
  static const List<String> iconKeys = <String>[
    '',
    'star',
    'bolt',
    'flame',
    'wave',
    'leaf',
    'moon',
    'sun',
    'snow',
    'drop',
    'shield',
    'storm',
    'diamond',
    'cloud',
    'trophy',
    'book',
    'eye',
    'anchor',
  ];

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('activity-factions-loading');

  /// 載入失敗識別鍵。
  static const Key failedKey = ValueKey<String>('activity-factions-failed');

  /// 重新讀取識別鍵（現值過期與載入失敗共用）。
  static const Key reloadKey = ValueKey<String>('activity-factions-reload');

  /// 空列表識別鍵。
  static const Key emptyKey = ValueKey<String>('activity-factions-empty');

  /// 列表容器識別鍵。
  static const Key listKey = ValueKey<String>('activity-factions-list');

  /// 停止說明列識別鍵。
  static const Key closedKey = ValueKey<String>('activity-factions-closed');

  /// 歸檔只讀列識別鍵。
  static const Key archivedKey = ValueKey<String>('activity-factions-archived');

  /// 列表某一行的識別鍵。
  static Key rowKey(String factionId) =>
      ValueKey<String>('activity-factions-row-$factionId');

  /// 行內「編輯」按鈕識別鍵。
  static Key editActionKey(String factionId) =>
      ValueKey<String>('activity-factions-edit-$factionId');

  /// 行內「停用／重新啟用」按鈕識別鍵（文案由服務端讀回的可用性決定）。
  static Key toggleActionKey(String factionId) =>
      ValueKey<String>('activity-factions-toggle-$factionId');

  /// 停用與恢復確認框的發起按鈕識別鍵。
  static const Key confirmActionKey = ValueKey<String>(
    'activity-factions-confirm-action',
  );

  /// 停用與恢復確認框的取消按鈕識別鍵（取消零請求）。
  static const Key confirmCancelKey = ValueKey<String>(
    'activity-factions-confirm-cancel',
  );

  /// 確認框裡的成員影響摘要列識別鍵。
  static const Key confirmSummaryKey = ValueKey<String>(
    'activity-factions-confirm-summary',
  );

  /// 建立區各控件識別鍵。
  static const Key createNameKey = ValueKey<String>(
    'activity-factions-create-name',
  );
  static const Key createDescriptionKey = ValueKey<String>(
    'activity-factions-create-description',
  );
  static const Key createIconKey = ValueKey<String>(
    'activity-factions-create-icon',
  );
  static const Key createColorKey = ValueKey<String>(
    'activity-factions-create-color',
  );
  static const Key createSortKey = ValueKey<String>(
    'activity-factions-create-sort',
  );
  static const Key createSubmitKey = ValueKey<String>(
    'activity-factions-create-submit',
  );

  /// 編輯區各控件識別鍵（同時只有一份在編）。
  static const Key editNameKey = ValueKey<String>(
    'activity-factions-edit-name',
  );
  static const Key editDescriptionKey = ValueKey<String>(
    'activity-factions-edit-description',
  );
  static const Key editIconKey = ValueKey<String>(
    'activity-factions-edit-icon',
  );
  static const Key editColorKey = ValueKey<String>(
    'activity-factions-edit-color',
  );
  static const Key editSortKey = ValueKey<String>(
    'activity-factions-edit-sort',
  );
  static const Key editAvailableKey = ValueKey<String>(
    'activity-factions-edit-available',
  );
  static const Key editSaveKey = ValueKey<String>(
    'activity-factions-edit-save',
  );
  static const Key editCancelKey = ValueKey<String>(
    'activity-factions-edit-cancel',
  );

  /// 提示列識別鍵（本地校驗與失敗轉述共用）。
  static const Key noticeKey = ValueKey<String>('activity-factions-notice');

  /// 寫入成功列識別鍵。
  static const Key savedKey = ValueKey<String>('activity-factions-saved');

  @override
  State<ActivityFactionsCard> createState() => _ActivityFactionsCardState();
}

class _ActivityFactionsCardState extends State<ActivityFactionsCard> {
  final TextEditingController _createName = TextEditingController();
  final TextEditingController _createDescription = TextEditingController();
  final TextEditingController _createColor = TextEditingController();
  final TextEditingController _createSort = TextEditingController();
  final TextEditingController _editName = TextEditingController();
  final TextEditingController _editDescription = TextEditingController();
  final TextEditingController _editColor = TextEditingController();
  final TextEditingController _editSort = TextEditingController();

  List<FactionReport> _factions = const <FactionReport>[];
  bool _loading = true;
  bool _writing = false;
  String? _notice;
  String? _saved;

  /// 現值過期（2013）：收起寫入控件，只留重讀出口（口徑同活動詳情卡）。
  bool _stale = false;

  /// 建立區的圖標選值（''＝未選）。
  String _createIcon = '';

  /// 正在編輯的陣營標識與它那行的服務端現值（依據值只能取自這裡）。
  String? _editingId;
  FactionReport? _editingBaseline;
  String _editIcon = '';
  bool _editAvailable = true;

  @override
  void initState() {
    super.initState();
    // 首讀排在第一幀之後，免得在 initState 裡讀 Localizations（同詳情卡手法）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _createName.dispose();
    _createDescription.dispose();
    _createColor.dispose();
    _createSort.dispose();
    _editName.dispose();
    _editDescription.dispose();
    _editColor.dispose();
    _editSort.dispose();
    super.dispose();
  }

  /// 目前介面語言對應的 Accept-Language 標記。
  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 本卡此刻准不准寫：只採信服務端讀回的活动狀態——已批准可寫的形態只有 draft
  /// 與 active 兩個名字，表外值（後端日後放寬集合時的多餘取值）一律當不可寫：
  /// 介面不替自己發明代術，也不拿「看起来不像終態」放行。
  bool get _canWrite =>
      (widget.activityStatus == 'draft' || widget.activityStatus == 'active') &&
      !_stale;

  /// 讀這份列表。失敗時整卡轉述那一句失敗，不顯示任何舊資料。
  Future<void> _load() async {
    setState(() => _loading = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final FactionListReport report = await widget.api.activityFactions(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _factions = report.factions;
        _stale = false;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _factions = const <FactionReport>[];
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  /// 走一次寫入並重讀列表：回應裡的那一筆是回讀的事實，而列表順序只有後端知道，
  /// 成功之後以一次 GET 收尾，不做本地拼裝（也不先於回應顯示「已完成」）。
  ///
  /// [successFor] 讓各條寫入自己決定成功句：可用性翻轉那兩次要唸出「已停用／已重新啟用」
  /// 並帶著回應回讀的名稱，其餘一律「已保存」。總之取回應、不取請求意圖。
  Future<void> _write<T>(
    Future<T> Function() request, {
    String Function(AppLocalizations l10n, T result)? successFor,
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
      final T result = await request();
      if (!mounted) {
        return;
      }
      final FactionListReport report = await widget.api.activityFactions(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _factions = report.factions;
        _saved = successFor == null
            ? l10n.factionSavedNotice
            : successFor(l10n, result);
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
        // 2013（資料現值過期）的處置是重讀這份列表；2033／2029 各是一句現狀說明，
        // 由統一對映轉述，界面據活动狀態早已收起控件，這裡只是兜住競態尾巴。
        _stale = error.knownCode == ApiMachineCode.profileConflict;
      });
    }
  }

  /// 寫入成功句：可用性這一欄翻轉時念出翻轉後的結果，其餘編輯念一般保存句。
  ///
  /// 兩個判斷都讀回應回讀的現值與本次提交的依據值，不讀本地推測——「當前狀態」屬列表，
  /// 「操作結果」屬這一次回應，界面兩處不混。
  String _availabilityOutcome(
    AppLocalizations l10n,
    bool availableBefore,
    FactionReport result,
  ) {
    if (availableBefore == result.available) {
      return l10n.factionSavedNotice;
    }
    return result.available
        ? l10n.factionEnabledNotice(result.name)
        : l10n.factionDisabledNotice(result.name);
  }

  /// 停用或重新啟用這一行：確認框先把成員影響摘要念完，確認後走同一條 PUT 白名單，
  /// 六欄新值只有可用性那一格翻轉，六欄依據值取自列表讀回的那一行。
  Future<void> _confirmAvailability(FactionReport faction) async {
    if (_writing || !_canWrite) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    // want 是「這一欄新的取值」；這次動作算停用還是恢復，看的是讀回來的現值：
    // 現值為真意味著這一次是把它的可用性翻下去，反過來才是恢復啟用。
    final bool want = !faction.available;
    final bool disabling = faction.available;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          disabling
              ? l10n.factionDisableConfirmTitle(faction.name)
              : l10n.factionEnableConfirmTitle(faction.name),
        ),
        content: Column(
          key: ActivityFactionsCard.confirmSummaryKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 當前狀態與此刻可否收新成員：兩行都唸服務端讀回的現值，操作還沒發生就先講清楚。
            Text(
              l10n.labelValuePair(
                l10n.factionConfirmCurrentStatusLabel,
                faction.available
                    ? l10n.factionAvailableLabel
                    : l10n.factionDisabledLabel,
              ),
            ),
            Text(
              l10n.labelValuePair(
                l10n.factionConfirmAcceptanceLabel,
                faction.acceptsNewMembers
                    ? l10n.factionAcceptanceYesLabel
                    : l10n.factionAcceptanceNoLabel,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              disabling
                  ? l10n.factionDisableConfirmBody(faction.name)
                  : l10n.factionEnableConfirmBody(faction.name),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.factionMemberImpactPendingNotice,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            key: ActivityFactionsCard.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.factionEditCancelAction),
          ),
          FilledButton(
            key: ActivityFactionsCard.confirmActionKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.factionConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _write(
      () => widget.api.updateFaction(
        activityId: widget.activityId,
        factionId: faction.factionId,
        name: faction.name,
        description: faction.description,
        icon: faction.icon,
        color: faction.color,
        sortOrder: faction.sortOrder,
        available: want,
        expectedName: faction.name,
        expectedDescription: faction.description,
        expectedIcon: faction.icon,
        expectedColor: faction.color,
        expectedSortOrder: faction.sortOrder,
        expectedAvailable: faction.available,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n, FactionWriteReport report) =>
          _availabilityOutcome(l10n, faction.available, report.faction),
    );
  }

  /// 把一次失敗換成一句話：欄位級結論點名是哪一欄，其餘交回統一對映。
  String _failureText(AppLocalizations l10n, ApiError error) {
    if (error.knownCode == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'name' => l10n.factionInvalidNameNotice,
        'description' => l10n.factionInvalidDescriptionNotice,
        'icon' => l10n.factionInvalidIconNotice,
        'color' => l10n.factionInvalidColorNotice,
        'sort_order' => l10n.factionInvalidSortNotice,
        _ => l10n.factionRejectedNotice,
      };
    }
    return apiErrorText(l10n, error);
  }

  /// 解析並校驗一欄顏色文本（空＝未選）。返回 null 表示不合法；本地先擋，
  /// 省一次注定 1004 的往返——但把關的仍是服務端。
  String? _normalizeColor(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return '';
    }
    final RegExp pattern = RegExp(r'^#[0-9a-fA-F]{6}$');
    if (!pattern.hasMatch(value)) {
      return null;
    }
    return value.toLowerCase();
  }

  /// 解析排序文本：空字串回 null（＝不發該欄，由後端排尾）；非數字或越界回哨兵 -1。
  int? _parseSort(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    final int? parsed = int.tryParse(value);
    if (parsed == null ||
        parsed < 0 ||
        parsed > ActivityFactionsCard.maxSortOrder) {
      return -1;
    }
    return parsed;
  }

  /// 送交一次建立：名稱必填，其餘欄位各按自己的規則（空即默認）。
  Future<void> _create() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _createName.text.trim();
    if (name.isEmpty) {
      setState(() => _notice = l10n.factionFormIncompleteNotice);
      return;
    }
    final String? color = _normalizeColor(_createColor.text);
    if (color == null) {
      setState(() => _notice = l10n.factionInvalidColorNotice);
      return;
    }
    final int? sort = _parseSort(_createSort.text);
    if (sort != null && sort == -1) {
      setState(() => _notice = l10n.factionInvalidSortNotice);
      return;
    }
    await _write(
      () => widget.api.createFaction(
        activityId: widget.activityId,
        name: name,
        description: _createDescription.text.trim(),
        icon: _createIcon,
        color: color,
        sortOrder: sort,
        acceptLanguage: _acceptLanguage,
      ),
    );
    if (mounted) {
      _createName.clear();
      _createDescription.clear();
      _createColor.clear();
      _createSort.clear();
      setState(() => _createIcon = '');
    }
  }

  /// 進入編輯態：表單與依據值同時取自那行的服務端現值（兩處必須同源）。
  void _beginEdit(FactionReport faction) {
    setState(() {
      _editingId = faction.factionId;
      _editingBaseline = faction;
      _editName.text = faction.name;
      _editDescription.text = faction.description;
      _editIcon = faction.icon;
      _editColor.text = faction.color;
      _editSort.text = faction.sortOrder.toString();
      _editAvailable = faction.available;
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

  /// 送交一次編輯：六欄新值帶著六欄依據值；本地先擋空名、壞顏色與壞排序。
  Future<void> _saveEdit() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FactionReport? baseline = _editingBaseline;
    if (baseline == null) {
      return;
    }
    final String name = _editName.text.trim();
    if (name.isEmpty) {
      setState(() => _notice = l10n.factionFormIncompleteNotice);
      return;
    }
    final String? color = _normalizeColor(_editColor.text);
    if (color == null) {
      setState(() => _notice = l10n.factionInvalidColorNotice);
      return;
    }
    final int? sort = _parseSort(_editSort.text);
    if (sort == null || sort == -1) {
      // 編輯沒有「留白＝排尾」的語意：排序值必須在欄位裡，缺了就是沒填。
      setState(() => _notice = l10n.factionInvalidSortNotice);
      return;
    }
    await _write(
      () => widget.api.updateFaction(
        activityId: widget.activityId,
        factionId: baseline.factionId,
        name: name,
        description: _editDescription.text.trim(),
        icon: _editIcon,
        color: color,
        sortOrder: sort,
        available: _editAvailable,
        expectedName: baseline.name,
        expectedDescription: baseline.description,
        expectedIcon: baseline.icon,
        expectedColor: baseline.color,
        expectedSortOrder: baseline.sortOrder,
        expectedAvailable: baseline.available,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n, FactionWriteReport report) =>
          _availabilityOutcome(l10n, baseline.available, report.faction),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    if (_loading) {
      return Text(
        l10n.factionLoadingNotice,
        key: ActivityFactionsCard.loadingKey,
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.factionSectionTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.factionSectionIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        if (widget.activityStatus == 'archived') ...<Widget>[
          Text(
            l10n.factionArchivedNotice,
            key: ActivityFactionsCard.archivedKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ] else if (widget.activityStatus == 'closed') ...<Widget>[
          Text(
            l10n.factionClosedNotice,
            key: ActivityFactionsCard.closedKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        if (_stale) ...<Widget>[
          Text(l10n.factionStaleNotice, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: ActivityFactionsCard.reloadKey,
              onPressed: _load,
              child: Text(l10n.activityReloadAction),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_factions.isEmpty)
          Text(
            l10n.factionEmptyNotice,
            key: ActivityFactionsCard.emptyKey,
            style: theme.textTheme.bodySmall,
          )
        else
          Column(
            key: ActivityFactionsCard.listKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final FactionReport faction in _factions)
                Card(
                  key: ActivityFactionsCard.rowKey(faction.factionId),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _FactionBadge(faction: faction),
                    title: Text(faction.name),
                    subtitle: _FactionSubtitle(faction: faction),
                    trailing: _canWrite
                        ? Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            alignment: WrapAlignment.end,
                            children: <Widget>[
                              // 停用與恢復各長在自己那一行的服務端現值上：可用性為真才給
                              // 「停用」，為假才給「重新啟用」——界面不替自己發明第二套狀態。
                              TextButton(
                                key: ActivityFactionsCard.toggleActionKey(
                                  faction.factionId,
                                ),
                                onPressed: _writing
                                    ? null
                                    : () => _confirmAvailability(faction),
                                child: Text(
                                  faction.available
                                      ? l10n.factionDisableAction
                                      : l10n.factionEnableAction,
                                ),
                              ),
                              OutlinedButton(
                                key: ActivityFactionsCard.editActionKey(
                                  faction.factionId,
                                ),
                                onPressed: _writing
                                    ? null
                                    : () => _beginEdit(faction),
                                child: Text(l10n.factionEditAction),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
            ],
          ),
        if (_editingId != null && _canWrite) ...<Widget>[
          const SizedBox(height: 8),
          _FactionEditForm(
            l10n: l10n,
            nameController: _editName,
            descriptionController: _editDescription,
            colorController: _editColor,
            sortController: _editSort,
            icon: _editIcon,
            available: _editAvailable,
            busy: _writing,
            onIconChanged: (String value) => setState(() => _editIcon = value),
            onAvailableChanged: (bool value) =>
                setState(() => _editAvailable = value),
            onSave: _saveEdit,
            onCancel: _cancelEdit,
          ),
        ],
        if (_canWrite) ...<Widget>[
          const SizedBox(height: 12),
          _FactionCreateForm(
            l10n: l10n,
            nameController: _createName,
            descriptionController: _createDescription,
            colorController: _createColor,
            sortController: _createSort,
            icon: _createIcon,
            busy: _writing,
            onIconChanged: (String value) =>
                setState(() => _createIcon = value),
            onSubmit: _create,
          ),
        ],
        if (_saved != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _saved!,
            key: ActivityFactionsCard.savedKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_notice != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _notice!,
            key: ActivityFactionsCard.noticeKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// 行首的圖標＋色塊：顏色與圖標都只是展示，名稱永遠同時在場（不以顏色單獨表達身份）。
///
/// 未選色與非法殘值（歷史髒資料或後端放寬前的兜底）一律落到中性底色占位，
/// 圖標鍵讀不出來時以通用佔位圖標顯示——界面不崩、不空白、也不假裝認得那個鍵。
class _FactionBadge extends StatelessWidget {
  const _FactionBadge({required this.faction});

  final FactionReport faction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? argb = _parseHexColor(faction.color);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: argb == null
            ? theme.colorScheme.surfaceContainerHighest
            : Color(argb),
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Icon(
        factionIconData(faction.icon),
        size: 20,
        // 有選色時圖標走反色，未選色時走中性前景：兩種都不只靠顏色說話。
        color: argb == null
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onPrimary,
      ),
    );
  }
}

/// 行副標：「可用性 · 排序 N」，狀態以文字說而不是只變色。
///
/// 第二列只在服務端派生值與旗標不一致時出現（活動停止或歸檔、陣營本身仍可用）：
/// 這一句讲的是門禁對「此刻收不收新成員」的影響，不是另一個可用性——兩句分開講，
/// 操作者才不會以為管理員把這個陣營停用了。
class _FactionSubtitle extends StatelessWidget {
  const _FactionSubtitle({required this.faction});

  final FactionReport faction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String state = faction.available
        ? l10n.factionAvailableLabel
        : l10n.factionDisabledLabel;
    final String line = l10n.labelValuePair(l10n.factionStatusLabel, state);
    final Text first = faction.description.isEmpty
        ? Text('$line · ${l10n.factionSortLabel}: ${faction.sortOrder}')
        : Text(
            '$line · ${l10n.factionSortLabel}: ${faction.sortOrder} · ${faction.description}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
    if (faction.available && faction.acceptsNewMembers) {
      return first;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        first,
        if (faction.available && !faction.acceptsNewMembers)
          Text(
            l10n.factionNotAcceptingWhileActivityFrozen,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// 圖標鍵到本地 Material 圖標的對應（前端唯一的一張表；未知鍵落佔位）。
///
/// 這張表與後端的封閉集合由契約測試各自釘住：後端放寬集合而這裡沒跟時，
/// 界面以佔位圖標兜底並把原始鍵留在下拉裡可見，不崩也不裝認識。
IconData factionIconData(String key) {
  return switch (key) {
    'star' => Icons.star,
    'bolt' => Icons.bolt,
    'flame' => Icons.local_fire_department,
    'wave' => Icons.waves,
    'leaf' => Icons.forest,
    'moon' => Icons.nightlight_round,
    'sun' => Icons.wb_sunny,
    'snow' => Icons.ac_unit,
    'drop' => Icons.water_drop,
    'shield' => Icons.shield,
    'storm' => Icons.thunderstorm,
    'diamond' => Icons.diamond,
    'cloud' => Icons.cloud,
    'trophy' => Icons.emoji_events,
    'book' => Icons.menu_book,
    'eye' => Icons.visibility,
    'anchor' => Icons.anchor,
    _ => Icons.category_outlined,
  };
}

/// 把 #RRGGBB 解析成 ARGB 整數；非法或空回 null（呼叫端以中性佔位兜底）。
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

/// 圖標下拉：封閉集合逐項以「本地图標＋鍵名」呈現；'' 那一項是四語言的「未選」。
/// 鍵名是機器標識而非文案，直接顯示不違反介面文字唯一來源——它與帳戶標識同一性質。
class _FactionIconDropdown extends StatelessWidget {
  const _FactionIconDropdown({
    required this.value,
    required this.busy,
    required this.itemKey,
    required this.onChanged,
    required this.noneLabel,
  });

  final String value;
  final bool busy;
  final Key itemKey;
  final ValueChanged<String> onChanged;
  final String noneLabel;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      key: itemKey,
      value: value,
      isExpanded: true,
      items: <DropdownMenuItem<String>>[
        for (final String key in ActivityFactionsCard.iconKeys)
          DropdownMenuItem<String>(
            value: key,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  key.isEmpty ? Icons.category_outlined : factionIconData(key),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(key.isEmpty ? noneLabel : key)),
              ],
            ),
          ),
      ],
      // DropdownButton 的清除語意在這一族裡不存在（'' 就是列表裡的「未選圖標」那一項），
      // null 只可能來自框架的清空回呼：收斂成 '' 而不是把可空性漏給呼叫端。
      onChanged: busy ? null : (String? selected) => onChanged(selected ?? ''),
    );
  }
}

/// 建立表單：名稱必填，描述／圖標／顏色可空，排序留空即「排到最後」。
class _FactionCreateForm extends StatelessWidget {
  const _FactionCreateForm({
    required this.l10n,
    required this.nameController,
    required this.descriptionController,
    required this.colorController,
    required this.sortController,
    required this.icon,
    required this.busy,
    required this.onIconChanged,
    required this.onSubmit,
  });

  final AppLocalizations l10n;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController colorController;
  final TextEditingController sortController;
  final String icon;
  final bool busy;
  final ValueChanged<String> onIconChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.factionCreateTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          key: ActivityFactionsCard.createNameKey,
          controller: nameController,
          enabled: !busy,
          decoration: InputDecoration(labelText: l10n.factionNameLabel),
        ),
        const SizedBox(height: 10),
        TextField(
          key: ActivityFactionsCard.createDescriptionKey,
          controller: descriptionController,
          enabled: !busy,
          decoration: InputDecoration(labelText: l10n.factionDescriptionLabel),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: <Widget>[
            SizedBox(
              width: 220,
              child: _FactionIconDropdown(
                itemKey: ActivityFactionsCard.createIconKey,
                value: icon,
                busy: busy,
                onChanged: onIconChanged,
                noneLabel: l10n.factionNoIconLabel,
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                key: ActivityFactionsCard.createColorKey,
                controller: colorController,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: l10n.factionColorLabel,
                  hintText: l10n.factionColorHint,
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                key: ActivityFactionsCard.createSortKey,
                controller: sortController,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.factionSortLabel,
                  hintText: l10n.factionSortOptionalHint,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: ActivityFactionsCard.createSubmitKey,
            onPressed: busy ? null : onSubmit,
            child: Text(l10n.factionCreateSubmitAction),
          ),
        ),
      ],
    );
  }
}

/// 編輯表單：六欄白名單一次帶齊，依據值藏在呼叫端（本表單不持有依據值來源）。
class _FactionEditForm extends StatelessWidget {
  const _FactionEditForm({
    required this.l10n,
    required this.nameController,
    required this.descriptionController,
    required this.colorController,
    required this.sortController,
    required this.icon,
    required this.available,
    required this.busy,
    required this.onIconChanged,
    required this.onAvailableChanged,
    required this.onSave,
    required this.onCancel,
  });

  final AppLocalizations l10n;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController colorController;
  final TextEditingController sortController;
  final String icon;
  final bool available;
  final bool busy;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<bool> onAvailableChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.factionEditTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        // 把「編輯動的是哪一格的身分」講在表單上：標識只在路徑裡，這裡沒有那顆欄位。
        Text(l10n.factionEditTargetHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(
          key: ActivityFactionsCard.editNameKey,
          controller: nameController,
          enabled: !busy,
          decoration: InputDecoration(labelText: l10n.factionNameLabel),
        ),
        const SizedBox(height: 10),
        TextField(
          key: ActivityFactionsCard.editDescriptionKey,
          controller: descriptionController,
          enabled: !busy,
          decoration: InputDecoration(labelText: l10n.factionDescriptionLabel),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: <Widget>[
            SizedBox(
              width: 220,
              child: _FactionIconDropdown(
                itemKey: ActivityFactionsCard.editIconKey,
                value: icon,
                busy: busy,
                onChanged: onIconChanged,
                noneLabel: l10n.factionNoIconLabel,
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                key: ActivityFactionsCard.editColorKey,
                controller: colorController,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: l10n.factionColorLabel,
                  hintText: l10n.factionColorHint,
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                key: ActivityFactionsCard.editSortKey,
                controller: sortController,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.factionSortLabel),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Switch(
                  key: ActivityFactionsCard.editAvailableKey,
                  value: available,
                  onChanged: busy ? null : onAvailableChanged,
                ),
                Text(l10n.factionAvailableSwitchLabel),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              key: ActivityFactionsCard.editCancelKey,
              onPressed: busy ? null : onCancel,
              child: Text(l10n.factionEditCancelAction),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: ActivityFactionsCard.editSaveKey,
              onPressed: busy ? null : onSave,
              child: Text(l10n.factionEditSaveAction),
            ),
          ],
        ),
      ],
    );
  }
}
