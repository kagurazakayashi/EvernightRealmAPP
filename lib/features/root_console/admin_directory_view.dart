/// 「Root 管理員目錄」卡：分頁列舉持有 server_admin 的帳戶，帶狀態篩選與單筆入口。
///
/// 這是一張轉述伺服器事實的目錄卡，規則與全應用同形：
///
/// * 行、總數與回顯的頁碼全部來自 `GET /root/admins` 的回應；本地不排序、不補行、
///   不拿本頁筆數冒充總數。頁碼邊界（上一页／下一页的可點性）由伺服器回顯的
///   page／total／page_size 推出，本地不自算第二份真相。
/// * 篩選只有後端開放的一項：狀態（all／active／disabled）。登入名搜尋屬後續的
///   維護台能力，這裡不擺一個打了不會有結果的輸入框。
/// * 配置 Root 不是這裡的一行：目錄的成員資格來自授予表，Root 從不落授予表。
///   空目錄時界面那句說明就是講這件事，不假裝少了一行可撈。
/// * 「查看／編輯」把選中的這一行交給詳情卡（admin_profile_view.dart），由它按
///   標識重讀單筆真相；目錄行本身不夠格當編輯底稿——行是投影，詳情才過實體校驗。
library;

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 階段：載入中、就緒、載入失敗（查不了）。
enum _ListPhase { loading, ready, failed }

/// 管理員目錄卡。
class AdminDirectoryCard extends StatefulWidget {
  /// 以端點介面建立目錄卡；[reloadToken] 變動時重讀當前頁。
  const AdminDirectoryCard({
    super.key,
    required this.api,
    this.reloadToken = 0,
    this.onSelected,
  });

  /// 統一端點存取介面。
  final ServerApi api;

  /// 重新載入的觸發計數（開設或編輯成功後由頁面加一）。
  final int reloadToken;

  /// 點行內「查看／編輯」的回呼：把該行交給詳情卡按標識重讀。
  final ValueChanged<AdminAccountReport>? onSelected;

  /// 狀態篩選「全部」識別鍵。
  static const Key filterAllKey = ValueKey<String>(
    'admin-directory-filter-all',
  );

  /// 狀態篩選「啟用」識別鍵。
  static const Key filterActiveKey = ValueKey<String>(
    'admin-directory-filter-active',
  );

  /// 狀態篩選「已停用」識別鍵。
  static const Key filterDisabledKey = ValueKey<String>(
    'admin-directory-filter-disabled',
  );

  /// 分頁摘要識別鍵。
  static const Key summaryKey = ValueKey<String>('admin-directory-summary');

  /// 上一頁按鈕識別鍵。
  static const Key prevKey = ValueKey<String>('admin-directory-prev');

  /// 下一頁按鈕識別鍵。
  static const Key nextKey = ValueKey<String>('admin-directory-next');

  /// 載入中的中性提示識別鍵。
  static const Key loadingKey = ValueKey<String>('admin-directory-loading');

  /// 空頁提示識別鍵。
  static const Key emptyKey = ValueKey<String>('admin-directory-empty');

  /// 重試按鈕識別鍵。
  static const Key retryKey = ValueKey<String>('admin-directory-retry');

  /// 載入失敗提示識別鍵。
  static const Key failedKey = ValueKey<String>('admin-directory-failed');

  /// 依帳戶標識產生該列的識別鍵。
  static Key rowKey(String accountId) =>
      ValueKey<String>('admin-list-$accountId');

  /// 依帳戶標識產生「查看／編輯」按鈕的識別鍵。
  static Key actionKey(String accountId) =>
      ValueKey<String>('admin-row-$accountId-action');

  @override
  State<AdminDirectoryCard> createState() => _AdminDirectoryCardState();
}

class _AdminDirectoryCardState extends State<AdminDirectoryCard> {
  _ListPhase _phase = _ListPhase.loading;
  AdminDirectoryReport? _report;

  /// 當前頁碼與狀態篩選：篩選變動回到第一頁。
  int _page = 1;
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant AdminDirectoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      _load();
    }
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() => _phase = _ListPhase.loading);
    try {
      final AdminDirectoryReport report = await widget.api.adminsDirectory(
        page: _page,
        status: _status,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _report = report;
        _phase = _ListPhase.ready;
      });
    } on ApiError {
      // 「查不了」與「查到了但被拒」都停在失敗態：這一段只呈現一句
      // apiErrorText 給出的話，不猜是連不上還是權限問題。
      if (!mounted) {
        return;
      }
      setState(() => _phase = _ListPhase.failed);
    }
  }

  void _setStatus(String status) {
    if (_status == status && _page == 1) {
      return;
    }
    setState(() {
      _status = status;
      _page = 1;
    });
    _load();
  }

  void _goPage(int page) {
    if (page < 1 || page == _page) {
      return;
    }
    setState(() => _page = page);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              key: AdminDirectoryCard.filterAllKey,
              label: Text(l10n.adminStatusFilterAll),
              selected: _status == 'all',
              onSelected: (_) => _setStatus('all'),
            ),
            ChoiceChip(
              key: AdminDirectoryCard.filterActiveKey,
              label: Text(l10n.adminStatusFilterActive),
              selected: _status == 'active',
              onSelected: (_) => _setStatus('active'),
            ),
            ChoiceChip(
              key: AdminDirectoryCard.filterDisabledKey,
              label: Text(l10n.adminStatusFilterDisabled),
              selected: _status == 'disabled',
              onSelected: (_) => _setStatus('disabled'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        switch (_phase) {
          _ListPhase.loading => _loadingRow(l10n, theme),
          _ListPhase.failed => _failedColumn(l10n),
          _ListPhase.ready => _readyBody(l10n, theme),
        },
      ],
    );
  }

  Widget _loadingRow(AppLocalizations l10n, ThemeData theme) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.adminDirectoryLoadingHint,
            key: AdminDirectoryCard.loadingKey,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _failedColumn(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.adminDirectoryUnavailableNotice,
          key: AdminDirectoryCard.failedKey,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: AdminDirectoryCard.retryKey,
          onPressed: _load,
          child: Text(l10n.adminDirectoryRetryAction),
        ),
      ],
    );
  }

  Widget _readyBody(AppLocalizations l10n, ThemeData theme) {
    final AdminDirectoryReport? report = _report;
    if (report == null) {
      return const SizedBox.shrink();
    }
    final int totalPages = report.totalPages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (report.admins.isEmpty)
          Text(
            l10n.adminDirectoryEmptyNotice,
            key: AdminDirectoryCard.emptyKey,
            style: theme.textTheme.bodyMedium,
          )
        else
          ...report.admins.map((AdminAccountReport a) => _row(l10n, theme, a)),
        const SizedBox(height: 6),
        Text(
          l10n.adminDirectoryPageSummary(report.page, totalPages, report.total),
          key: AdminDirectoryCard.summaryKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            OutlinedButton(
              key: AdminDirectoryCard.prevKey,
              onPressed: report.page > 1
                  ? () => _goPage(report.page - 1)
                  : null,
              child: Text(l10n.adminDirectoryPrevAction),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              key: AdminDirectoryCard.nextKey,
              onPressed: report.hasMore ? () => _goPage(report.page + 1) : null,
              child: Text(l10n.adminDirectoryNextAction),
            ),
          ],
        ),
      ],
    );
  }

  /// 一行只呈現後端給出的事實：狀態與「是否還欠首次改密」都是原值轉述，
  /// 本地不推測、也不補上任何「看起來更完整」的說明。
  Widget _row(
    AppLocalizations l10n,
    ThemeData theme,
    AdminAccountReport admin,
  ) {
    return Column(
      key: AdminDirectoryCard.rowKey(admin.accountId),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          admin.loginName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListDisplayNameLabel,
            admin.displayName,
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListStatusLabel,
            _statusText(l10n, admin.status),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminGrantedAtLabel,
            _formatUtcMinute(admin.grantedAt),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListLastLoginLabel,
            admin.lastLoginAt == null
                ? l10n.adminListNeverLoggedInValue
                : _formatUtcMinute(admin.lastLoginAt!),
          ),
          style: theme.textTheme.bodySmall,
        ),
        if (admin.mustChangePassword)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.adminListMustChangeBadge,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: AdminDirectoryCard.actionKey(admin.accountId),
            onPressed: () => widget.onSelected?.call(admin),
            child: Text(l10n.adminRowAction(admin.loginName)),
          ),
        ),
        const Divider(),
      ],
    );
  }
}

/// 狀態原字串 → 顯示文字；未知值原樣顯示（後端日後多一種狀態不至於顯示空白）。
String _statusText(AppLocalizations l10n, String status) {
  return switch (status) {
    'active' => l10n.adminStatusActive,
    'disabled' => l10n.adminStatusDisabled,
    _ => status,
  };
}

/// 以「年-月-日 時:分 UTC」呈現，與裝置清單同一寫法：不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}
