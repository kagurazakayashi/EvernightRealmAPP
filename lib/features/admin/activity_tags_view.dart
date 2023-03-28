/// 「單筆活動的標籤定義管理」卡：列表、建立與編輯（含可用性與玩家公開兩個開關）。
///
/// 這張卡的邊界與它接的後端通路一一對應，寫在這裡是因為界面藏不住它們：
///
/// * 底稿只能來自本卡按活動標識讀回的列表：編輯表單預填的是上一次 GET 的那一行，
///   compare-and-set 的七個依據值也是它。目錄裡的印象與本地緩存都不夠格當底稿。
/// * 標識與歸屬不在任何一格裡：新建的標籤屬於哪場活動由路徑決定，編輯對象是哪一行
///   也由路徑決定。本卡沒有任何通路能改標籤 ID、挪動歸屬活動或刪除一行——
///   後端這一族沒有 DELETE（用戶批准：只有可用／停用，沒有刪除通路，也不級聯清空歷史）。
/// * `public` 不在建立白名單裡：新建一律是管理員的內部資訊，要對外必須是建好之後
///   那一跳明確的編輯。因此建立表單沒有一格能宣稱「保存時順手勾公開」，
///   而這句話本身也寫在表單上——介面不能讓操作者以為出生即公開是漏畫了控件。
/// * 公開只改變「這份定義讀不讀得到」：它不是角色、不是權限，也不放大目錄裡誰能被看見
///   （那一件事由活動的目錄規則與成員那一行的覆蓋決定）。確認框把這幾件不會發生的事
///   與會發生的那一件一起唸完，因為「把一欄翻成真」在直覺上很容易被讀成「把人放出去」。
/// * 按鈕只由服務端讀回的活動狀態決定：草稿與開放可寫；停止收起全部寫入控件並說明
///   「重開後照常能改」（2033 是「現在不行」），歸檔同樣收起（2029 是「已經結束」）。
///   表外狀態不長按鈕。
/// * 顏色與圖標是展示，不是身份：每一行都把名稱寫在色塊與圖標旁邊，未選色或未選圖標
///   以中性佔位呈現。同活動內名稱唯一（撞名拿到 2040 那句「換個名字」），
///   其他活動的同名標籤與這一場無關——本卡讀的就是這個活動的列表，天然分書。
/// * `accepts_new_assignments` 是服務端派生值（可用**且**活動接受業務寫入）：請求本體
///   沒有這一格，界面只讀不寫，也永不自己拿 available 跟活動狀態拼第二次結論。
///   它講的是「當前狀態」，寫入回應回讀的那一筆講的是「這次操作的結果」，兩處分開顯示。
/// * 現值過期（2013）時收起寫入控件，只留「重新讀取這份列表」一個出口；
///   結果不明（連不上、逾時）絕不自動補發，由人重讀再決定。
/// * 成功句只在寫入回應回來之後出現：保存成功前不顯示「已完成」。
/// * 「誰帶著哪個標籤」這件事尚未落地：本卡因此沒有一行名單、沒有一個計數，
///   也不拿空清單或 0 冒充會被貼標的人。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';
// 圖標鍵與圖標對應表都直接向陣營卡取用：兩族後端 CHECK 的是同一個封閉集合，
// 在這裡另寫一份清單或另一張表就是第二個答案來源，放寬集合時必然只改到一半。
import 'activity_factions_view.dart' show ActivityFactionsCard, factionIconData;

/// 標籤定義管理卡。
class ActivityTagsCard extends StatefulWidget {
  /// 以端點介面、活動標識與活動現狀建立本卡。
  const ActivityTagsCard({
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

  /// 內建圖標鍵的封閉集合：與陣營共用同一份清單（後端 0013 與 0017 的 CHECK 同集合），
  /// 刻意不複製一份——兩處各寫一次就會在後端放寬集合時只改到一半。
  static const List<String> iconKeys = ActivityFactionsCard.iconKeys;

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('activity-tags-loading');

  /// 重新讀取識別鍵（現值過期與載入失敗共用）。
  static const Key reloadKey = ValueKey<String>('activity-tags-reload');

  /// 空列表識別鍵。
  static const Key emptyKey = ValueKey<String>('activity-tags-empty');

  /// 列表容器識別鍵。
  static const Key listKey = ValueKey<String>('activity-tags-list');

  /// 停止說明列識別鍵。
  static const Key closedKey = ValueKey<String>('activity-tags-closed');

  /// 歸檔只讀列識別鍵。
  static const Key archivedKey = ValueKey<String>('activity-tags-archived');

  /// 「貼標籤尚未落地」那句交代列識別鍵（列表下方常驻，空列表時也在）。
  static const Key pendingNoticeKey = ValueKey<String>(
    'activity-tags-assignment-pending',
  );

  /// 列表某一行的識別鍵。
  static Key rowKey(String tagId) =>
      ValueKey<String>('activity-tags-row-$tagId');

  /// 行內「編輯」按鈕識別鍵。
  static Key editActionKey(String tagId) =>
      ValueKey<String>('activity-tags-edit-$tagId');

  /// 行內「停用／重新啟用」按鈕識別鍵（文案由服務端讀回的可用性決定）。
  static Key toggleActionKey(String tagId) =>
      ValueKey<String>('activity-tags-toggle-$tagId');

  /// 行內「公開／收回公開」按鈕識別鍵（文案由服務端讀回的公開旗標決定）。
  static Key publicActionKey(String tagId) =>
      ValueKey<String>('activity-tags-public-$tagId');

  /// 確認框的發起按鈕識別鍵（停用、恢復、公開、收回四種確認共用這一顆）。
  static const Key confirmActionKey = ValueKey<String>(
    'activity-tags-confirm-action',
  );

  /// 確認框的取消按鈕識別鍵（取消零請求）。
  static const Key confirmCancelKey = ValueKey<String>(
    'activity-tags-confirm-cancel',
  );

  /// 確認框裡的影響摘要容器識別鍵。
  static const Key confirmSummaryKey = ValueKey<String>(
    'activity-tags-confirm-summary',
  );

  /// 建立表單「新建一律內部」那句說明列識別鍵。
  static const Key createInternalNoteKey = ValueKey<String>(
    'activity-tags-create-internal-note',
  );

  /// 建立區各控件識別鍵（刻意沒有一格能宣稱「公開」：建立白名單沒有那一欄）。
  static const Key createNameKey = ValueKey<String>(
    'activity-tags-create-name',
  );
  static const Key createDescriptionKey = ValueKey<String>(
    'activity-tags-create-description',
  );
  static const Key createIconKey = ValueKey<String>(
    'activity-tags-create-icon',
  );
  static const Key createColorKey = ValueKey<String>(
    'activity-tags-create-color',
  );
  static const Key createSortKey = ValueKey<String>(
    'activity-tags-create-sort',
  );
  static const Key createSubmitKey = ValueKey<String>(
    'activity-tags-create-submit',
  );

  /// 編輯區各控件識別鍵（同時只有一份在編）。
  static const Key editNameKey = ValueKey<String>('activity-tags-edit-name');
  static const Key editDescriptionKey = ValueKey<String>(
    'activity-tags-edit-description',
  );
  static const Key editIconKey = ValueKey<String>('activity-tags-edit-icon');
  static const Key editColorKey = ValueKey<String>('activity-tags-edit-color');
  static const Key editSortKey = ValueKey<String>('activity-tags-edit-sort');
  static const Key editAvailableKey = ValueKey<String>(
    'activity-tags-edit-available',
  );
  static const Key editPublicKey = ValueKey<String>(
    'activity-tags-edit-public',
  );
  static const Key editSaveKey = ValueKey<String>('activity-tags-edit-save');
  static const Key editCancelKey = ValueKey<String>(
    'activity-tags-edit-cancel',
  );

  /// 提示列識別鍵（本地校驗與失敗轉述共用）。
  static const Key noticeKey = ValueKey<String>('activity-tags-notice');

  /// 寫入成功列識別鍵。
  static const Key savedKey = ValueKey<String>('activity-tags-saved');

  @override
  State<ActivityTagsCard> createState() => _ActivityTagsCardState();
}

class _ActivityTagsCardState extends State<ActivityTagsCard> {
  final TextEditingController _createName = TextEditingController();
  final TextEditingController _createDescription = TextEditingController();
  final TextEditingController _createColor = TextEditingController();
  final TextEditingController _createSort = TextEditingController();
  final TextEditingController _editName = TextEditingController();
  final TextEditingController _editDescription = TextEditingController();
  final TextEditingController _editColor = TextEditingController();
  final TextEditingController _editSort = TextEditingController();

  List<TagReport> _tags = const <TagReport>[];
  bool _loading = true;
  bool _writing = false;
  String? _notice;
  String? _saved;

  /// 現值過期（2013）：收起寫入控件，只留重讀出口（口徑同陣營卡與詳情卡）。
  bool _stale = false;

  /// 建立區的圖標選值（''＝未選）。
  String _createIcon = '';

  /// 正在編輯的標籤標識與它那行的服務端現值（依據值只能取自這裡）。
  String? _editingId;
  TagReport? _editingBaseline;
  String _editIcon = '';
  bool _editAvailable = true;
  bool _editPublic = false;

  @override
  void initState() {
    super.initState();
    // 首讀排在第一幀之後，免得在 initState 裡讀 Localizations（同陣營卡手法）。
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

  /// 本卡此刻准不准寫：只採信服務端讀回的活動狀態——已批准可寫的形態只有 draft
  /// 與 active 兩個名字，表外值（後端日後放寬集合時的多餘取值）一律當不可寫：
  /// 介面不替自己發明代術，也不拿「看起來不像終態」放行。
  bool get _canWrite =>
      (widget.activityStatus == 'draft' || widget.activityStatus == 'active') &&
      !_stale;

  /// 讀這份列表。失敗時整卡轉述那一句失敗，不顯示任何舊資料。
  Future<void> _load() async {
    setState(() => _loading = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final TagListReport report = await widget.api.activityTags(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _tags = report.tags;
        _stale = false;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _tags = const <TagReport>[];
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  /// 走一次寫入並重讀列表：回應裡那一筆是回讀的事實，而列表順序只有後端知道，
  /// 成功之後以一次 GET 收尾，不做本地拼裝（也不先於回應顯示「已完成」）。
  ///
  /// [successFor] 讓各條寫入自己決定成功句：可用性與公開兩欄翻轉時要唸出翻轉後的
  /// 結果並帶著回應回讀的名稱，其餘一律「已保存」。總之取回應、不取請求意圖。
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
      final TagListReport report = await widget.api.activityTags(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _tags = report.tags;
        _saved = successFor == null
            ? l10n.tagSavedNotice
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
        // 2013（現值過期）的處置是重讀這份列表；2033／2029 各是一句現狀說明，
        // 由統一對映轉述，界面據活動狀態早已收起控件，這裡只兜住競態尾巴。
        _stale = error.knownCode == ApiMachineCode.profileConflict;
      });
    }
  }

  /// 寫入成功句：可用性與公開這兩欄各自翻轉時念出翻轉後的結果，其餘編輯念一般保存句。
  ///
  /// 判斷讀的是回應回讀的現值與本次提交的依據值，不讀本地推測——「當前狀態」屬列表，
  /// 「操作結果」屬這一次回應，界面兩處不混。可用性優先級高於公開：一次 PUT 只翻
  /// 捷徑按鈕對應的那一欄，若兩欄同時不同（編輯表單），唸出來的是可用性那一句，
  /// 公開的變化仍由列表那一行如實顯示，不靠一句成功文案同時宣稱兩件事。
  String _writeOutcome(
    AppLocalizations l10n, {
    required bool availableBefore,
    required bool publicBefore,
    required TagReport result,
  }) {
    if (availableBefore != result.available) {
      return result.available
          ? l10n.tagEnabledNotice(result.name)
          : l10n.tagDisabledNotice(result.name);
    }
    if (publicBefore != result.public) {
      return result.public
          ? l10n.tagPublishedNotice(result.name)
          : l10n.tagUnpublishedNotice(result.name);
    }
    return l10n.tagSavedNotice;
  }

  /// 確認框：先把「動的是哪一枚、當前狀態與此刻能否貼出去」唸完，再唸影響摘要。
  ///
  /// 四種確認（停用、恢復、公開、收回）共用這一個殼，摘要各自一句；回傳 null 表示
  /// 對話框被以框架方式關閉（點外層、返回鍵），與回傳 false 一樣都不發請求。
  Future<bool?> _confirm({
    required String title,
    required TagReport tag,
    required String body,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          key: ActivityTagsCard.confirmSummaryKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 當前狀態三行全取列表讀回的現值：操作還沒發生就先講清楚，
            // 而「此刻貼不貼得出去」取派生值，界面不拿那兩欄自己拼。
            Text(
              l10n.labelValuePair(
                l10n.tagConfirmCurrentStatusLabel,
                tag.available ? l10n.tagAvailableLabel : l10n.tagDisabledLabel,
              ),
            ),
            Text(
              l10n.labelValuePair(
                l10n.tagConfirmVisibilityLabel,
                tag.public ? l10n.tagPublicLabel : l10n.tagInternalLabel,
              ),
            ),
            Text(
              l10n.labelValuePair(
                l10n.tagConfirmAcceptanceLabel,
                tag.acceptsNewAssignments
                    ? l10n.tagAcceptanceYesLabel
                    : l10n.tagAcceptanceNoLabel,
              ),
            ),
            const SizedBox(height: 8),
            Text(body),
            const SizedBox(height: 6),
            // 「誰帶著哪個標籤」尚未落地這件事如實寫在摘要裡：這裡沒有名單，
            // 也不拿「0 人」或空清單冒充會被影響的人。
            Text(
              l10n.tagAssignmentPendingNotice,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            key: ActivityTagsCard.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.tagEditCancelAction),
          ),
          FilledButton(
            key: ActivityTagsCard.confirmActionKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.tagConfirmAction),
          ),
        ],
      ),
    );
  }

  /// 翻轉可用性（停用或重新啟用）：確認後發的是同一條 PUT 白名單，
  /// 七欄新值只有可用性那一格翻轉，七欄依據值取自列表讀回的那一行。
  Future<void> _confirmAvailability(TagReport tag) async {
    if (_writing || !_canWrite) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    // disabling 看的是讀回來的現值：現值為真意味著這一次是把可用性翻下去。
    final bool disabling = tag.available;
    final bool? confirmed = await _confirm(
      title: disabling
          ? l10n.tagDisableConfirmTitle(tag.name)
          : l10n.tagEnableConfirmTitle(tag.name),
      tag: tag,
      body: disabling
          ? l10n.tagDisableConfirmBody(tag.name)
          : l10n.tagEnableConfirmBody(tag.name),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _write(
      () => widget.api.updateTag(
        activityId: widget.activityId,
        tagId: tag.tagId,
        name: tag.name,
        description: tag.description,
        icon: tag.icon,
        color: tag.color,
        sortOrder: tag.sortOrder,
        available: !tag.available,
        public: tag.public,
        expectedName: tag.name,
        expectedDescription: tag.description,
        expectedIcon: tag.icon,
        expectedColor: tag.color,
        expectedSortOrder: tag.sortOrder,
        expectedAvailable: tag.available,
        expectedPublic: tag.public,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n, TagWriteReport report) =>
          _writeOutcome(
            l10n,
            availableBefore: tag.available,
            publicBefore: tag.public,
            result: report.tag,
          ),
    );
  }

  /// 翻轉公開旗標（對外公開或收回公開）：走同一條 PUT 白名單，只動 `public` 那一格。
  ///
  /// 這一切換的後果比可用性更容易被讀錯（它動的是「別人讀不讀得到這份定義」），
  /// 所以摘要必須把四件不會發生的事一起唸完，而不是只唸「已公開」。
  Future<void> _confirmPublicSwitch(TagReport tag) async {
    if (_writing || !_canWrite) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool publishing = !tag.public;
    final bool? confirmed = await _confirm(
      title: publishing
          ? l10n.tagPublishConfirmTitle(tag.name)
          : l10n.tagUnpublishConfirmTitle(tag.name),
      tag: tag,
      body: publishing
          ? l10n.tagPublishConfirmBody(tag.name)
          : l10n.tagUnpublishConfirmBody(tag.name),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _write(
      () => widget.api.updateTag(
        activityId: widget.activityId,
        tagId: tag.tagId,
        name: tag.name,
        description: tag.description,
        icon: tag.icon,
        color: tag.color,
        sortOrder: tag.sortOrder,
        available: tag.available,
        public: publishing,
        expectedName: tag.name,
        expectedDescription: tag.description,
        expectedIcon: tag.icon,
        expectedColor: tag.color,
        expectedSortOrder: tag.sortOrder,
        expectedAvailable: tag.available,
        expectedPublic: tag.public,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n, TagWriteReport report) =>
          _writeOutcome(
            l10n,
            availableBefore: tag.available,
            publicBefore: tag.public,
            result: report.tag,
          ),
    );
  }

  /// 把一次失敗換成一句話：欄位級結論點名是哪一欄，其餘交回統一對映。
  ///
  /// 七欄白名單每一欄各一句（含 available／public 兩個開關）：把「這一欄的值不合法」
  /// 與「你的依據值過期」唸成同一句，操作者會去重讀一份本來就沒錯的列表。
  String _failureText(AppLocalizations l10n, ApiError error) {
    if (error.knownCode == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'name' => l10n.tagInvalidNameNotice,
        'description' => l10n.tagInvalidDescriptionNotice,
        'icon' => l10n.tagInvalidIconNotice,
        'color' => l10n.tagInvalidColorNotice,
        'sort_order' => l10n.tagInvalidSortNotice,
        'available' => l10n.tagInvalidAvailableNotice,
        'public' => l10n.tagInvalidPublicNotice,
        _ => l10n.tagRejectedNotice,
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
        parsed > ActivityTagsCard.maxSortOrder) {
      return -1;
    }
    return parsed;
  }

  /// 送交一次建立：名稱必填，其餘欄位各按自己的規則（空即默認）。
  ///
  /// 這裡沒有任何一格能宣稱公開與可用性：兩欄都不在建立白名單裡，出生形態
  /// （可用、內部）由後端決定，界面也不留一個「建好之後再改」的捷徑勾選框。
  Future<void> _create() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _createName.text.trim();
    if (name.isEmpty) {
      setState(() => _notice = l10n.tagFormIncompleteNotice);
      return;
    }
    final String? color = _normalizeColor(_createColor.text);
    if (color == null) {
      setState(() => _notice = l10n.tagInvalidColorNotice);
      return;
    }
    final int? sort = _parseSort(_createSort.text);
    if (sort != null && sort == -1) {
      setState(() => _notice = l10n.tagInvalidSortNotice);
      return;
    }
    await _write(
      () => widget.api.createTag(
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
  void _beginEdit(TagReport tag) {
    setState(() {
      _editingId = tag.tagId;
      _editingBaseline = tag;
      _editName.text = tag.name;
      _editDescription.text = tag.description;
      _editIcon = tag.icon;
      _editColor.text = tag.color;
      _editSort.text = tag.sortOrder.toString();
      _editAvailable = tag.available;
      _editPublic = tag.public;
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

  /// 送交一次編輯：七欄新值帶著七欄依據值；本地先擋空名、壞顏色與壞排序。
  ///
  /// `public` 這一次從讀回的值翻過去時必經確認框：公開與收回的後果寫在摘要裡，
  /// 取消則一個請求都不發（其餘欄的編輯不需要那一次確認）。
  Future<void> _saveEdit() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TagReport? baseline = _editingBaseline;
    if (baseline == null) {
      return;
    }
    final String name = _editName.text.trim();
    if (name.isEmpty) {
      setState(() => _notice = l10n.tagFormIncompleteNotice);
      return;
    }
    final String? color = _normalizeColor(_editColor.text);
    if (color == null) {
      setState(() => _notice = l10n.tagInvalidColorNotice);
      return;
    }
    final int? sort = _parseSort(_editSort.text);
    if (sort == null || sort == -1) {
      // 編輯沒有「留白＝排尾」的語意：排序值必須在欄位裡，缺了就是沒填。
      setState(() => _notice = l10n.tagInvalidSortNotice);
      return;
    }
    if (_editPublic != baseline.public) {
      final bool publishing = _editPublic;
      final bool? confirmed = await _confirm(
        title: publishing
            ? l10n.tagPublishConfirmTitle(baseline.name)
            : l10n.tagUnpublishConfirmTitle(baseline.name),
        tag: baseline,
        body: publishing
            ? l10n.tagPublishConfirmBody(baseline.name)
            : l10n.tagUnpublishConfirmBody(baseline.name),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    await _write(
      () => widget.api.updateTag(
        activityId: widget.activityId,
        tagId: baseline.tagId,
        name: name,
        description: _editDescription.text.trim(),
        icon: _editIcon,
        color: color,
        sortOrder: sort,
        available: _editAvailable,
        public: _editPublic,
        expectedName: baseline.name,
        expectedDescription: baseline.description,
        expectedIcon: baseline.icon,
        expectedColor: baseline.color,
        expectedSortOrder: baseline.sortOrder,
        expectedAvailable: baseline.available,
        expectedPublic: baseline.public,
        acceptLanguage: _acceptLanguage,
      ),
      successFor: (AppLocalizations l10n, TagWriteReport report) =>
          _writeOutcome(
            l10n,
            availableBefore: baseline.available,
            publicBefore: baseline.public,
            result: report.tag,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    if (_loading) {
      return Text(
        l10n.tagLoadingNotice,
        key: ActivityTagsCard.loadingKey,
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.tagSectionTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.tagSectionIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        if (widget.activityStatus == 'archived') ...<Widget>[
          Text(
            l10n.tagArchivedNotice,
            key: ActivityTagsCard.archivedKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ] else if (widget.activityStatus == 'closed') ...<Widget>[
          Text(
            l10n.tagClosedNotice,
            key: ActivityTagsCard.closedKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        if (_stale) ...<Widget>[
          Text(l10n.tagStaleNotice, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: ActivityTagsCard.reloadKey,
              onPressed: _load,
              child: Text(l10n.activityReloadAction),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_tags.isEmpty)
          Text(
            l10n.tagEmptyNotice,
            key: ActivityTagsCard.emptyKey,
            style: theme.textTheme.bodySmall,
          )
        else
          Column(
            key: ActivityTagsCard.listKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final TagReport tag in _tags) _row(l10n, theme, tag),
            ],
          ),
        // 「誰帶著哪個標籤」還沒落地這件事寫在列表下方而不是只寫在確認框裡：
        // 操作者第一個想問的就是「那我這裡能不能給人貼上」，那一格沒有控件時要有句子。
        const SizedBox(height: 8),
        Text(
          l10n.tagAssignmentPendingNotice,
          key: ActivityTagsCard.pendingNoticeKey,
          style: theme.textTheme.bodySmall,
        ),
        if (_editingId != null && _canWrite) ...<Widget>[
          const SizedBox(height: 8),
          _TagEditForm(
            l10n: l10n,
            nameController: _editName,
            descriptionController: _editDescription,
            colorController: _editColor,
            sortController: _editSort,
            icon: _editIcon,
            available: _editAvailable,
            publicFlag: _editPublic,
            busy: _writing,
            onIconChanged: (String value) => setState(() => _editIcon = value),
            onAvailableChanged: (bool value) =>
                setState(() => _editAvailable = value),
            onPublicChanged: (bool value) =>
                setState(() => _editPublic = value),
            onSave: _saveEdit,
            onCancel: _cancelEdit,
          ),
        ],
        if (_canWrite) ...<Widget>[
          const SizedBox(height: 12),
          _TagCreateForm(
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
            key: ActivityTagsCard.savedKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_notice != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _notice!,
            key: ActivityTagsCard.noticeKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  /// 一行標籤定義：身分、可用性、公開範圍與「此刻能否貼出去」都用文字說。
  ///
  /// 三個狀態共用這一張行卡而不各長一颗色點：顏色只是展示，把「內部／公開」画成
  /// 一個色塊就等於讓讀畫面的人猜規則；派生值那一列獨立成句，因為它講的是活動門禁
  /// 而不是這一枚標籤自己的旗標。
  Widget _row(AppLocalizations l10n, ThemeData theme, TagReport tag) {
    // 三個狀態各自用文字講完，再拼上排序與描述：副標是一整行組合句，
    // 拆成三個變量只是為了讓每一格都讀得到服務端現值而沒有本地推測混進去。
    final String visibility = l10n.labelValuePair(
      l10n.tagVisibilityLabel,
      tag.public ? l10n.tagPublicLabel : l10n.tagInternalLabel,
    );
    final String availability = l10n.labelValuePair(
      l10n.tagStatusLabel,
      tag.available ? l10n.tagAvailableLabel : l10n.tagDisabledLabel,
    );
    final String acceptance = l10n.labelValuePair(
      l10n.tagAcceptanceLabel,
      tag.acceptsNewAssignments
          ? l10n.tagAcceptanceYesLabel
          : l10n.tagAcceptanceNoLabel,
    );
    final String facts = tag.description.isEmpty
        ? '$availability · ${l10n.tagSortLabel}: ${tag.sortOrder}'
        : '$availability · ${l10n.tagSortLabel}: ${tag.sortOrder} · ${tag.description}';
    return Card(
      key: ActivityTagsCard.rowKey(tag.tagId),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _TagBadge(tag: tag),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 名稱永遠在場且可換行：窄欄不截斷展示值，否則讀不到就是沒讀到。
                      Text(tag.name, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 2),
                      Text(visibility, style: theme.textTheme.bodySmall),
                      Text(
                        facts,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      // 派生值單獨一列：它跟 available 不同值時（活動停止或歸檔）
                      // 界面要說得出「旗標還在、此刻貼不出去」，而不是讓人以為被停用了。
                      Text(acceptance, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (_canWrite) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: <Widget>[
                  // 四顆捷徑都長在服务端讀回的現值上：現值為真給「收回」，為假給「對外公開」——
                  // 界面不替自己發明第二套狀態，也不放一顆「再停用一次」的死按鈕。
                  TextButton(
                    key: ActivityTagsCard.toggleActionKey(tag.tagId),
                    onPressed: _writing
                        ? null
                        : () => _confirmAvailability(tag),
                    child: Text(
                      tag.available
                          ? l10n.tagDisableAction
                          : l10n.tagEnableAction,
                    ),
                  ),
                  TextButton(
                    key: ActivityTagsCard.publicActionKey(tag.tagId),
                    onPressed: _writing
                        ? null
                        : () => _confirmPublicSwitch(tag),
                    child: Text(
                      tag.public
                          ? l10n.tagUnpublishAction
                          : l10n.tagPublishAction,
                    ),
                  ),
                  OutlinedButton(
                    key: ActivityTagsCard.editActionKey(tag.tagId),
                    onPressed: _writing ? null : () => _beginEdit(tag),
                    child: Text(l10n.tagEditAction),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 行首的圖標＋色塊：顏色與圖標都只是展示，名稱永遠同時在場（不以顏色單獨表達身份）。
///
/// 未選色與非法殘值（歷史髒資料或後端放寬前的兜底）一律落到中性底色佔位，
/// 圖標鍵讀不出來時以通用佔位圖標顯示——界面不崩、不空白、也不假裝認得那個鍵。
class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.tag});

  final TagReport tag;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? argb = _parseHexColor(tag.color);
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
        factionIconData(tag.icon),
        size: 20,
        // 有選色時圖標走反色，未選色時走中性前景：兩種都不只靠顏色說話。
        color: argb == null
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onPrimary,
      ),
    );
  }
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

/// 圖標下拉：封閉集合逐項以「本地圖標＋鍵名」呈現；'' 那一項是四語言的「未選」。
/// 鍵名是機器標識而非文案，直接顯示不違反介面文字唯一來源——它與帳戶標識同一性質。
class _TagIconDropdown extends StatelessWidget {
  const _TagIconDropdown({
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
        for (final String key in ActivityTagsCard.iconKeys)
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
///
/// 這裡刻意沒有可用性與公開兩個開關：兩欄都不在建立白名單裡，出生形態由後端決定；
/// 少一句話說清楚，操作者就會去別處找那顆根本不該存在的勾選框。
class _TagCreateForm extends StatelessWidget {
  const _TagCreateForm({
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
        Text(l10n.tagCreateTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          l10n.tagCreateInternalNote,
          key: ActivityTagsCard.createInternalNoteKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          key: ActivityTagsCard.createNameKey,
          controller: nameController,
          enabled: !busy,
          decoration: InputDecoration(labelText: l10n.tagNameLabel),
        ),
        const SizedBox(height: 10),
        TextField(
          key: ActivityTagsCard.createDescriptionKey,
          controller: descriptionController,
          enabled: !busy,
          decoration: InputDecoration(labelText: l10n.tagDescriptionLabel),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: <Widget>[
            SizedBox(
              width: 220,
              child: _TagIconDropdown(
                itemKey: ActivityTagsCard.createIconKey,
                value: icon,
                busy: busy,
                onChanged: onIconChanged,
                noneLabel: l10n.tagNoIconLabel,
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                key: ActivityTagsCard.createColorKey,
                controller: colorController,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: l10n.tagColorLabel,
                  hintText: l10n.tagColorHint,
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                key: ActivityTagsCard.createSortKey,
                controller: sortController,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.tagSortLabel,
                  hintText: l10n.tagSortOptionalHint,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: ActivityTagsCard.createSubmitKey,
            onPressed: busy ? null : onSubmit,
            child: Text(l10n.tagCreateSubmitAction),
          ),
        ),
      ],
    );
  }
}

/// 編輯表單：七欄白名單一次帶齊，依據值藏在呼叫端（本表單不持有依據值來源）。
///
/// 公開開關在這裡、不在建立表單：這是「出生為內部、對外要明確編輯」那條領域規則
/// 在界面上的唯一落點。翻動它時呼叫端會先走確認框，本表單不自行送交。
class _TagEditForm extends StatelessWidget {
  const _TagEditForm({
    required this.l10n,
    required this.nameController,
    required this.descriptionController,
    required this.colorController,
    required this.sortController,
    required this.icon,
    required this.available,
    required this.publicFlag,
    required this.busy,
    required this.onIconChanged,
    required this.onAvailableChanged,
    required this.onPublicChanged,
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

  /// 公開旗標的草稿值（Dart 保留字 `public` 不能當欄位名，故取名 publicFlag）。
  final bool publicFlag;
  final bool busy;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<bool> onAvailableChanged;
  final ValueChanged<bool> onPublicChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.tagEditTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        // 把「編輯動的是哪一格的身分」講在表單上：標識只在路徑裡，這裡沒有那顆欄位。
        Text(l10n.tagEditTargetHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(
          key: ActivityTagsCard.editNameKey,
          controller: nameController,
          enabled: !busy,
          decoration: InputDecoration(labelText: l10n.tagNameLabel),
        ),
        const SizedBox(height: 10),
        TextField(
          key: ActivityTagsCard.editDescriptionKey,
          controller: descriptionController,
          enabled: !busy,
          decoration: InputDecoration(labelText: l10n.tagDescriptionLabel),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: <Widget>[
            SizedBox(
              width: 220,
              child: _TagIconDropdown(
                itemKey: ActivityTagsCard.editIconKey,
                value: icon,
                busy: busy,
                onChanged: onIconChanged,
                noneLabel: l10n.tagNoIconLabel,
              ),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                key: ActivityTagsCard.editColorKey,
                controller: colorController,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: l10n.tagColorLabel,
                  hintText: l10n.tagColorHint,
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                key: ActivityTagsCard.editSortKey,
                controller: sortController,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.tagSortLabel),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Switch(
                  key: ActivityTagsCard.editAvailableKey,
                  value: available,
                  onChanged: busy ? null : onAvailableChanged,
                ),
                Text(l10n.tagAvailableSwitchLabel),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Switch(
                  key: ActivityTagsCard.editPublicKey,
                  value: publicFlag,
                  onChanged: busy ? null : onPublicChanged,
                ),
                // 開關旁的文字把這一欄的後果講完一半：它是「誰讀得到這份定義」，
                // 不是角色也不是權限——那半句在翻動它時的確認框裡唸。
                Flexible(child: Text(l10n.tagPublicSwitchLabel)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              key: ActivityTagsCard.editCancelKey,
              onPressed: busy ? null : onCancel,
              child: Text(l10n.tagEditCancelAction),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: ActivityTagsCard.editSaveKey,
              onPressed: busy ? null : onSave,
              child: Text(l10n.tagEditSaveAction),
            ),
          ],
        ),
      ],
    );
  }
}
