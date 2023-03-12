/// 「活動目錄與建立」卡：一張建立表、一頁活動清單，與「選哪一個活動」這個信號。
///
/// 界線全部落在後端合同上，這裡只做呈現與如實轉述：
///
/// * 誰能看見哪些活動由服務端決定：持有伺服器級管理權但未被指派給任何活動的人，
///   拿到的是空的一頁而不是全部活動；Root 那一側不受指派限制，看到的才是全量。
///   介面因此不預判「他應該能看見幾筆」，頁碼、總數與有沒有後頁一律取回應回顯。
/// * 請求本體只有兩個欄位（名稱、描述）：狀態、建立者、活動標識與時刻都沒有格子，
///   多帶會被後端打成 1004 並點名是哪一欄，所以「我建的時候就把它寫成已開放」
///   在這裡沒有一個可以發生的形狀。
/// * 新建一律是草稿：這不是介面的預設值而是後端的領域規則，介面只轉述讀回的現值。
/// * 「建立完成」不等於「活動裡有東西」：成員、陣營、資產、聊天都不在今天後端的能力裡，
///   摘要與收尾句都要把這件事說清楚，不拿空清單或 0 冒充它們已存在。
/// * 「查不了」與「被拒」各說各句：連不上、會話失效、權限不足、欄位不合規、
///   活動已歸檔，是各不相同的句子，不合併成「操作失敗」。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 建立與載入的階段性結果（頁面據此轉述，不自行判定）。
enum _ActivityPhase { idle, submitting }

/// 狀態篩選的取值集合：`all` 加上後端那四態，寫死在這裡是介面的一層白名單，
/// 不是第二份領域規則——真正的判定在後端，越界取值它會回 1004。
const List<String> kActivityStatusFilters = <String>[
  'all',
  'draft',
  'active',
  'closed',
  'archived',
];

/// 「活動目錄與建立」卡。
class ActivityConsoleCard extends StatefulWidget {
  /// 以端點介面建立活動目錄卡。
  const ActivityConsoleCard({
    super.key,
    required this.api,
    this.reloadToken = 0,
    this.onCreated,
    this.onSelected,
  });

  /// 統一端點存取介面（由頁面自 [AppDependencies] 取得後顯式帶入）。
  final ServerApi api;

  /// 過載計數：頁面在任何一處活動寫入成功後加一，本卡據此重讀目錄。
  ///
  /// 遞的是「發生了一次該重讀的變化」這個信號而不是那份資料：目錄要顯示的
  /// 永遠是服務端回來的現值，拿回應去拼一行會繞過這條約定。
  final int reloadToken;

  /// 建立成功的回呼：頁面據此重讀目錄。
  ///
  /// 只遞「發生了一次成功」這個信號，不遞那份資料——目錄要的是服務端的結果。
  final VoidCallback? onCreated;

  /// 選中某筆活動的回呼：頁面據標識開啟詳情卡。
  final void Function(ActivityReport activity)? onSelected;

  /// 名稱輸入框識別鍵。
  static const Key nameKey = ValueKey<String>('activity-console-name');

  /// 描述輸入框識別鍵。
  static const Key descriptionKey = ValueKey<String>(
    'activity-console-description',
  );

  /// 建立按鈕識別鍵。
  static const Key createKey = ValueKey<String>('activity-console-create');

  /// 失敗或本地校驗提示列識別鍵。
  static const Key noticeKey = ValueKey<String>('activity-console-notice');

  /// 最近一次建立成功的摘要識別鍵。
  static const Key createdKey = ValueKey<String>('activity-console-created');

  /// 狀態篩選下拉識別鍵。
  static const Key statusFilterKey = ValueKey<String>(
    'activity-console-status-filter',
  );

  /// 關鍵字輸入框識別鍵。
  static const Key queryKey = ValueKey<String>('activity-console-query');

  /// 套用篩選（重讀目錄）按鈕識別鍵。
  static const Key reloadKey = ValueKey<String>('activity-console-reload');

  /// 目錄空清單說明識別鍵。
  static const Key emptyKey = ValueKey<String>('activity-console-empty');

  /// 上一頁按鈕識別鍵。
  static const Key previousKey = ValueKey<String>('activity-console-previous');

  /// 下一頁按鈕識別鍵。
  static const Key nextKey = ValueKey<String>('activity-console-next');

  /// 某一行的識別鍵字首（測試與截圖都按標識認行）。
  static Key rowKey(String activityId) =>
      ValueKey<String>('activity-console-row-$activityId');

  @override
  State<ActivityConsoleCard> createState() => _ActivityConsoleCardState();
}

class _ActivityConsoleCardState extends State<ActivityConsoleCard> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _query = TextEditingController();

  _ActivityPhase _phase = _ActivityPhase.idle;

  /// 一行提示：本地校驗與失敗轉述共用同一條；成功後清空。
  String? _notice;

  /// 最近一次建立成功的結果（可展示事實）。
  ActivityReport? _created;

  String _statusFilter = 'all';
  int _page = 1;
  ActivityDirectoryReport? _directory;
  bool _loading = false;
  ApiError? _loadError;

  /// 本次在途請求的世代代號：慢回應不得蓋掉更新的一次讀取結果。
  ///
  /// 目錄允許連點幾下下一頁，「最後送出的一次」才是用戶眼前那份意圖；
  /// 沒有這個代號，舊回應晚到會覆蓋新回應，介面顯示的是某一頁已經不是按鈕標的那一頁。
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    // 首讀排在第一幀之後：initState 裡碰 Localizations 屬「在依賴就緒前讀依賴」，
    // 框架會直接 assertion（這裡要的是語言標記對應的 Accept-Language）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 計數變動即重讀：詳情卡上的編輯與狀態轉換也要立刻反映到目錄行。
  @override
  void didUpdateWidget(ActivityConsoleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _query.dispose();
    super.dispose();
  }

  /// 目前介面語言對應的 Accept-Language 標記。
  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀一頁目錄：頁碼與篩選都以當前介面值為準，結果一律以服務端回顯為準。
  Future<void> _load() async {
    final int generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final ActivityDirectoryReport report = await widget.api
          .activitiesDirectory(
            page: _page,
            status: _statusFilter,
            query: _query.text,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _directory = report;
      });
    } on ApiError catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error;
        _directory = null;
      });
    }
  }

  /// 送交一次建立：本地只擋「明顯沒填」，其餘規則以服務端為準。
  ///
  /// 名稱與描述的長度、空白與禁字規則屬後端領域（碼位計、控制與格式字元），
  /// 前端複製一份必然漂移；因此這裡只做非空檢查，把不合規的輸入交回去，
  /// 再依 1004 的 `details.invalid_field` 說出差的是哪一欄。
  Future<void> _create() async {
    if (_phase == _ActivityPhase.submitting) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _notice = l10n.activityFormIncompleteNotice);
      return;
    }

    setState(() {
      _phase = _ActivityPhase.submitting;
      _notice = null;
    });
    try {
      final ActivityDetailReport report = await widget.api.createActivity(
        name: name,
        description: _description.text.trim(),
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      // 成功後兩欄清空：留著名稱只會讓下一次點按變成「同一個名字再交一次」，
      // 而活動名稱可重複，那不會報錯——卻會多出第二個用戶沒打算建的活動。
      _name.clear();
      _description.clear();
      setState(() {
        _phase = _ActivityPhase.idle;
        _created = report.activity;
      });
      widget.onCreated?.call();
      await _load();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _ActivityPhase.idle;
        _notice = _failureText(l10n, error);
      });
    }
  }

  /// 把一次失敗換成一句話：機器碼優先，欄位級結論再點名是哪一欄。
  String _failureText(AppLocalizations l10n, ApiError error) {
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'name' => l10n.activityInvalidNameNotice,
        'description' => l10n.activityInvalidDescriptionNotice,
        'status' => l10n.activityInvalidStatusNotice,
        'q' => l10n.activityInvalidQueryNotice,
        'page' => l10n.activityInvalidPageNotice,
        'page_size' => l10n.activityInvalidPageSizeNotice,
        _ => l10n.activityRejectedNotice,
      };
    }
    return apiErrorText(l10n, error);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ActivityReport? created = _created;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.activityConsoleTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.activityConsoleIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        _CreateForm(
          nameController: _name,
          descriptionController: _description,
          enabled: _phase == _ActivityPhase.idle,
          submitting: _phase == _ActivityPhase.submitting,
          onSubmit: _create,
        ),
        if (_notice != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _notice!,
            key: ActivityConsoleCard.noticeKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (created != null) ...<Widget>[
          const SizedBox(height: 12),
          _CreatedSummary(report: created),
        ],
        const SizedBox(height: 24),
        Text(l10n.activityDirectoryTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _Filters(
          statusFilter: _statusFilter,
          queryController: _query,
          busy: _loading,
          onStatusChanged: (String value) {
            setState(() {
              _statusFilter = value;
              _page = 1;
            });
            _load();
          },
          onReload: () {
            setState(() => _page = 1);
            _load();
          },
        ),
        const SizedBox(height: 12),
        if (_loading)
          Text(
            l10n.activityLoadingNotice,
            key: const ValueKey<String>('activity-console-loading'),
            style: theme.textTheme.bodySmall,
          )
        else if (_loadError != null)
          Text(
            _failureText(l10n, _loadError!),
            key: const ValueKey<String>('activity-console-load-failed'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (_directory == null)
          Text(l10n.activityNotLoadedNotice, style: theme.textTheme.bodySmall)
        else
          _Directory(
            report: _directory!,
            onPage: (int page) {
              setState(() => _page = page);
              _load();
            },
            onSelected: widget.onSelected,
          ),
      ],
    );
  }
}

/// 建立表單：只有名稱與描述兩個欄位（合同白名單）。
class _CreateForm extends StatelessWidget {
  const _CreateForm({
    required this.nameController,
    required this.descriptionController,
    required this.enabled,
    required this.submitting,
    required this.onSubmit,
  });

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final bool enabled;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.activityCreateTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextField(
          key: ActivityConsoleCard.nameKey,
          controller: nameController,
          enabled: enabled,
          decoration: InputDecoration(labelText: l10n.activityNameLabel),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          key: ActivityConsoleCard.descriptionKey,
          controller: descriptionController,
          enabled: enabled,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: l10n.activityDescriptionLabel,
            helperText: l10n.activityDescriptionHint,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: ActivityConsoleCard.createKey,
            onPressed: submitting ? null : onSubmit,
            child: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.activityCreateSubmitAction),
          ),
        ),
      ],
    );
  }
}

/// 建立成功摘要：點名這是活動事實，並把「裡面還沒有東西」講在第一線。
class _CreatedSummary extends StatelessWidget {
  const _CreatedSummary({required this.report});

  final ActivityReport report;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Container(
      key: ActivityConsoleCard.createdKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.activityCreatedTitle(report.name),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.labelValuePair(l10n.activityStatusLabel, report.status),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.labelValuePair(
              l10n.activityCreatedLabel,
              _formatUtcMinute(report.createdAt),
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.labelValuePair(
              l10n.activityManagerCountLabel,
              report.managerCount.toString(),
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            // 這一句是能力邊界，不是免責宣告：成員、陣營、資產與聊天都不在今天後端裡，
            // 介面不得把「建好一個活動」說成「活動可以使用了」。
            l10n.activityCreatedEmptyNotice,
            key: const ValueKey<String>('activity-console-created-empty'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 篩選列：狀態下拉與關鍵字，兩者都只發一個請求（改變狀態即重讀第一頁）。
class _Filters extends StatelessWidget {
  const _Filters({
    required this.statusFilter,
    required this.queryController,
    required this.busy,
    required this.onStatusChanged,
    required this.onReload,
  });

  final String statusFilter;
  final TextEditingController queryController;
  final bool busy;
  final void Function(String value) onStatusChanged;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // 窄欄以 Wrap 換行而非截斷（最小支援寬 360 px）。
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: <Widget>[
        DropdownButtonFormField<String>(
          key: ActivityConsoleCard.statusFilterKey,
          initialValue: statusFilter,
          decoration: InputDecoration(
            labelText: l10n.activityFilterStatusLabel,
          ),
          items: kActivityStatusFilters
              .map(
                (String value) => DropdownMenuItem<String>(
                  value: value,
                  child: Text(_statusLabel(l10n, value)),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (String? value) {
                  if (value != null) {
                    onStatusChanged(value);
                  }
                },
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: TextField(
            key: ActivityConsoleCard.queryKey,
            controller: queryController,
            enabled: !busy,
            decoration: InputDecoration(labelText: l10n.activityQueryLabel),
            onSubmitted: (_) => onReload(),
          ),
        ),
        OutlinedButton(
          key: ActivityConsoleCard.reloadKey,
          onPressed: busy ? null : onReload,
          child: Text(l10n.activitySearchAction),
        ),
      ],
    );
  }
}

/// 目錄本體：一行一筆活動，點選即交給頁面開啟詳情卡。
class _Directory extends StatelessWidget {
  const _Directory({
    required this.report,
    required this.onPage,
    this.onSelected,
  });

  final ActivityDirectoryReport report;

  /// 翻頁只遞頁碼給父卡：目錄的資料永遠來自重讀，不來自本地拼裝。
  final void Function(int page) onPage;
  final void Function(ActivityReport activity)? onSelected;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    if (report.activities.isEmpty) {
      // 空清單有兩種來路，介面上只有一個句子可說：服務端回的是「這一頁沒有行」。
      // 它可能是這臺伺服器還沒有活動，也可能是這個主體還沒被指派給任何活動——
      // 後端不把兩者分會說話（那不列舉任何東西），介面因此也不猜。
      return Text(
        l10n.activityEmptyNotice,
        key: ActivityConsoleCard.emptyKey,
        style: theme.textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final ActivityReport activity in report.activities)
          Card(
            key: ActivityConsoleCard.rowKey(activity.activityId),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(activity.name),
              subtitle: Text(
                '${_statusLabel(l10n, activity.status)} · '
                '${l10n.activityManagerCountLabel} ${activity.managerCount}',
              ),
              trailing: onSelected == null
                  ? null
                  : TextButton(
                      onPressed: () => onSelected!(activity),
                      child: Text(l10n.activityOpenAction),
                    ),
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            OutlinedButton(
              key: ActivityConsoleCard.previousKey,
              onPressed: report.page > 1 ? () => onPage(report.page - 1) : null,
              child: Text(l10n.activityPreviousPageAction),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.activityPagedNotice(
                report.page,
                report.totalPages,
                report.total,
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: ActivityConsoleCard.nextKey,
              onPressed: report.hasMore ? () => onPage(report.page + 1) : null,
              child: Text(l10n.activityNextPageAction),
            ),
          ],
        ),
      ],
    );
  }
}

/// 以「年-月-日 時:分 UTC」呈現，與其餘清單同一寫法：不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}

/// 狀態篩選與取值到介面文字的對應。
///
/// 四態之外的值一律照實顯示原值並標成「未認識」，不悄悄歸類到某一態：
/// 後端放寬集合時前端該看見的是「這個值我不認識」，介面不得把自己當成事實來源。
String _statusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'all' => l10n.activityFilterAllLabel,
    'draft' => l10n.activityStatusDraftLabel,
    'active' => l10n.activityStatusActiveLabel,
    'closed' => l10n.activityStatusClosedLabel,
    'archived' => l10n.activityStatusArchivedLabel,
    _ => l10n.activityUnknownStatusLabel(status),
  };
}
