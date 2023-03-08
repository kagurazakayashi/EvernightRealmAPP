/// 「管理員端普通帳戶目錄」卡：分頁列舉不帶伺服器級授予的帳戶，
/// 帶狀態、來源與名稱三種篩選，以及單筆詳情入口。
///
/// 這是一張轉述伺服器事實的目錄卡，規則與全應用同形：
///
/// * 行、總數與回顯的頁碼全部來自 `GET /admin/accounts` 的回應；本地不排序、不補行、
///   不拿本頁筆數冒充總數。頁碼邊界（上一頁／下一頁的可點性）由伺服器回顯的
///   page／total／page_size 推出，本地不自算第二份真相。
/// * 三種篩選都只有後端開放的那些取值：狀態（all／active／disabled）、
///   來源（all／standard／guest）、名稱關鍵字（一段原字串比對）。非法取值由後端
///   打成 1004，界面因此不預先擋掉任何「看起來奇怪但合法」的輸入。
/// * 這本目錄列不到管理員，也列不到 Root：前者的範圍归 Root 的管理員目錄，
///   後者根本不在 accounts 表裡。空目錄那句說明講的就是這件事，不假裝少了一行可撈。
/// * 「查看／編輯」把選中的標識交給詳情卡（standard_account_profile_view.dart），
///   由它按標識重讀單筆真相；目錄行本身不夠格當編輯底稿——行是投影，詳情才過實體校驗。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 階段：載入中、就緒、載入失敗（查不了）。
enum _ListPhase { loading, ready, failed }

/// 普通帳戶目錄卡。
class StandardAccountDirectoryCard extends StatefulWidget {
  /// 以端點介面建立目錄卡；[reloadToken] 變動時重讀當前頁。
  const StandardAccountDirectoryCard({
    super.key,
    required this.api,
    this.reloadToken = 0,
    this.onSelected,
  });

  /// 統一端點存取介面。
  final ServerApi api;

  /// 重新載入的觸發計數（建立或編輯成功後由頁面加一）。
  final int reloadToken;

  /// 點行內「查看／編輯」的回呼：把該筆標識交給詳情卡按標識重讀。
  final ValueChanged<StandardAccountReport>? onSelected;

  /// 某一行的刪除時刻標籤鍵：以標識參數化，與本卡其他行內鍵同一取向
  /// （同一張目錄同時出現好幾筆已刪者時，測試與界面都要能點名是哪一筆）。
  static Key deletedAtKey(String accountId) =>
      ValueKey<String>('std-account-deleted-at-$accountId');

  /// 狀態篩選「全部」識別鍵。
  static const Key filterStatusAllKey = ValueKey<String>(
    'std-account-directory-filter-status-all',
  );

  /// 狀態篩選「啟用」識別鍵。
  static const Key filterStatusActiveKey = ValueKey<String>(
    'std-account-directory-filter-status-active',
  );

  /// 狀態篩選「已停用」識別鍵。
  static const Key filterStatusDisabledKey = ValueKey<String>(
    'std-account-directory-filter-status-disabled',
  );

  /// 「已刪除」狀態篩選chip。用戶批准的刪除後展示策略把已刪者留在這本目錄裡
  /// （行留著正是為了被讀到），所以篩選集合必須認得他；缺這一顆時操作者只能
  /// 在全部行裡自己找，而那會把「已刪除」顯示成一個沒有名字的狀態。
  static const Key filterStatusDeletedKey = ValueKey<String>(
    'std-account-filter-status-deleted',
  );

  /// 來源篩選「全部」識別鍵。
  static const Key filterTypeAllKey = ValueKey<String>(
    'std-account-directory-filter-type-all',
  );

  /// 來源篩選「普通帳戶」識別鍵。
  static const Key filterTypeStandardKey = ValueKey<String>(
    'std-account-directory-filter-type-standard',
  );

  /// 來源篩選「訪客帳戶」識別鍵。
  static const Key filterTypeGuestKey = ValueKey<String>(
    'std-account-directory-filter-type-guest',
  );

  /// 名稱關鍵字輸入框識別鍵。
  static const Key searchKey = ValueKey<String>('std-account-directory-search');

  /// 名稱關鍵字送出鈕識別鍵。
  static const Key searchActionKey = ValueKey<String>(
    'std-account-directory-search-action',
  );

  /// 分頁摘要識別鍵。
  static const Key summaryKey = ValueKey<String>(
    'std-account-directory-summary',
  );

  /// 上一頁按鈕識別鍵。
  static const Key prevKey = ValueKey<String>('std-account-directory-prev');

  /// 下一頁按鈕識別鍵。
  static const Key nextKey = ValueKey<String>('std-account-directory-next');

  /// 載入中的中性提示識別鍵。
  static const Key loadingKey = ValueKey<String>(
    'std-account-directory-loading',
  );

  /// 空頁提示識別鍵。
  static const Key emptyKey = ValueKey<String>('std-account-directory-empty');

  /// 重試按鈕識別鍵。
  static const Key retryKey = ValueKey<String>('std-account-directory-retry');

  /// 載入失敗提示識別鍵。
  static const Key failedKey = ValueKey<String>('std-account-directory-failed');

  /// 依帳戶標識產生該列的識別鍵。
  static Key rowKey(String accountId) =>
      ValueKey<String>('std-account-list-$accountId');

  /// 依帳戶標識產生「查看／編輯」按鈕的識別鍵。
  static Key actionKey(String accountId) =>
      ValueKey<String>('std-account-row-$accountId-action');

  @override
  State<StandardAccountDirectoryCard> createState() =>
      _StandardAccountDirectoryCardState();
}

class _StandardAccountDirectoryCardState
    extends State<StandardAccountDirectoryCard> {
  _ListPhase _phase = _ListPhase.loading;
  StandardAccountDirectoryReport? _report;

  /// 讀取失敗那一句話（依機器碼分流；未收錄的碼交給 [apiErrorText] 的通用句）。
  String? _failureText;

  /// 當前頁碼與三份篩選條件：任一篩選變動都回到第一頁
  /// （帶著舊條件看到的頁碼在新條件下沒有意義）。
  int _page = 1;
  String _status = 'all';
  String _type = 'all';

  /// 名稱關鍵字底稿：與「已送出的那一份」分開保存，
  /// 否則打了一半的字就會讓清單跟着變，那不是我點篩選的語意。
  final TextEditingController _keyword = TextEditingController();

  /// 已送出的關鍵字（空字串＝不篩選）。
  String _appliedKeyword = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StandardAccountDirectoryCard oldWidget) {
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
    setState(() {
      _phase = _ListPhase.loading;
      _failureText = null;
    });
    try {
      final StandardAccountDirectoryReport report = await widget.api
          .standardAccountsDirectory(
            page: _page,
            status: _status,
            type: _type,
            query: _appliedKeyword,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _report = report;
        _phase = _ListPhase.ready;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      // 失敗態的那句話按機器碼分流：「你沒有這個權限」與「伺服器此刻查不了」
      // 與「你被登出了」是三種處置，混成一句通用失敗就是把選擇丟給使用者猜。
      setState(() {
        _phase = _ListPhase.failed;
        _failureText = _readFailureText(error);
      });
    }
  }

  /// 讀取失敗 → 介面文字：2011 說權限那一句、會話與門閂那一簇說重登那一句，
  /// 其餘（含未收錄的碼與連線類失敗）交給 [apiErrorText] 按碼或按類別給。
  String _readFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (error.knownCode) {
      ApiMachineCode.permissionDenied => l10n.stdAccountProfileDeniedNotice,
      ApiMachineCode.notAuthenticated ||
      ApiMachineCode.sessionInvalid ||
      ApiMachineCode.sessionStale ||
      ApiMachineCode.passwordChangeRequired =>
        l10n.adminProfileStaleRejectedNotice,
      _ => apiErrorText(l10n, error),
    };
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

  void _setType(String type) {
    if (_type == type && _page == 1) {
      return;
    }
    setState(() {
      _type = type;
      _page = 1;
    });
    _load();
  }

  /// 送出關鍵字：去首尾空白後與現行已送出的值相同時不重發請求
  /// （那是一次注定結果相同的讀取，多發一次只會讓清單閃一下）。
  void _applyKeyword() {
    final String trimmed = _keyword.text.trim();
    if (trimmed == _appliedKeyword && _page == 1) {
      return;
    }
    setState(() {
      _appliedKeyword = trimmed;
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
        Text(l10n.stdAccountDirectoryTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            ChoiceChip(
              key: StandardAccountDirectoryCard.filterStatusAllKey,
              label: Text(l10n.adminStatusFilterAll),
              selected: _status == 'all',
              onSelected: (_) => _setStatus('all'),
            ),
            ChoiceChip(
              key: StandardAccountDirectoryCard.filterStatusActiveKey,
              label: Text(l10n.adminStatusFilterActive),
              selected: _status == 'active',
              onSelected: (_) => _setStatus('active'),
            ),
            ChoiceChip(
              key: StandardAccountDirectoryCard.filterStatusDisabledKey,
              label: Text(l10n.adminStatusFilterDisabled),
              selected: _status == 'disabled',
              onSelected: (_) => _setStatus('disabled'),
            ),
            ChoiceChip(
              key: StandardAccountDirectoryCard.filterStatusDeletedKey,
              label: Text(l10n.adminStatusFilterDeleted),
              selected: _status == 'deleted',
              onSelected: (_) => _setStatus('deleted'),
            ),
            ChoiceChip(
              key: StandardAccountDirectoryCard.filterTypeAllKey,
              label: Text(l10n.stdAccountTypeFilterAll),
              selected: _type == 'all',
              onSelected: (_) => _setType('all'),
            ),
            ChoiceChip(
              key: StandardAccountDirectoryCard.filterTypeStandardKey,
              label: Text(l10n.stdAccountTypeFilterStandard),
              selected: _type == 'standard',
              onSelected: (_) => _setType('standard'),
            ),
            // 訪客帳戶在本伺服器還是一條未開放的建立通路（策略開關之外沒有實作），
            // 但目錄讀得到既存的那些筆，篩選因此照給不誤——列出來不是偽裝那條通路可用。
            ChoiceChip(
              key: StandardAccountDirectoryCard.filterTypeGuestKey,
              label: Text(l10n.stdAccountTypeFilterGuest),
              selected: _type == 'guest',
              onSelected: (_) => _setType('guest'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: StandardAccountDirectoryCard.searchKey,
                controller: _keyword,
                decoration: InputDecoration(
                  labelText: l10n.stdAccountDirectorySearchLabel,
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _applyKeyword(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: StandardAccountDirectoryCard.searchActionKey,
              onPressed: _applyKeyword,
              child: Text(l10n.stdAccountDirectorySearchAction),
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
            l10n.stdAccountDirectoryLoadingHint,
            key: StandardAccountDirectoryCard.loadingKey,
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
          _failureText ?? l10n.adminDirectoryUnavailableNotice,
          key: StandardAccountDirectoryCard.failedKey,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: StandardAccountDirectoryCard.retryKey,
          onPressed: _load,
          child: Text(l10n.adminDirectoryRetryAction),
        ),
      ],
    );
  }

  Widget _readyBody(AppLocalizations l10n, ThemeData theme) {
    final StandardAccountDirectoryReport? report = _report;
    if (report == null) {
      return const SizedBox.shrink();
    }
    final int totalPages = report.totalPages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (report.accounts.isEmpty)
          Text(
            l10n.stdAccountDirectoryEmptyNotice,
            key: StandardAccountDirectoryCard.emptyKey,
            style: theme.textTheme.bodyMedium,
          )
        else
          ...report.accounts.map(
            (StandardAccountReport account) => _row(l10n, theme, account),
          ),
        const SizedBox(height: 6),
        Text(
          l10n.adminDirectoryPageSummary(report.page, totalPages, report.total),
          key: StandardAccountDirectoryCard.summaryKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            OutlinedButton(
              key: StandardAccountDirectoryCard.prevKey,
              onPressed: report.page > 1
                  ? () => _goPage(report.page - 1)
                  : null,
              child: Text(l10n.adminDirectoryPrevAction),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              key: StandardAccountDirectoryCard.nextKey,
              onPressed: report.hasMore ? () => _goPage(report.page + 1) : null,
              child: Text(l10n.adminDirectoryNextAction),
            ),
          ],
        ),
      ],
    );
  }

  /// 一行只呈現後端給出的事實：來源、狀態與「是否還欠首次改密」都是原值轉述，
  /// 本地不推測、不補上任何「看起來更完整」的說明，也不放任何活動／資產欄位。
  Widget _row(
    AppLocalizations l10n,
    ThemeData theme,
    StandardAccountReport account,
  ) {
    return Column(
      key: StandardAccountDirectoryCard.rowKey(account.accountId),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          account.loginName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListDisplayNameLabel,
            account.displayName,
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.stdAccountSourceLabel,
            _typeText(l10n, account.accountType),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListStatusLabel,
            _statusText(l10n, account.status),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListCreatedLabel,
            _formatUtcMinute(account.createdAt),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListLastLoginLabel,
            account.lastLoginAt == null
                ? l10n.adminListNeverLoggedInValue
                : _formatUtcMinute(account.lastLoginAt!),
          ),
          style: theme.textTheme.bodySmall,
        ),
        // 刪除時刻只讀服務端那一欄：沒被刪過就不出現，界面不拿別的時間湊數，
        // 也不拿「他不在名冊上」的那種沉默替代「他於何時被刪」這個事實。
        if (account.deletedAt != null)
          Text(
            l10n.labelValuePair(
              l10n.stdAccountDeletedAtLabel,
              _formatUtcMinute(account.deletedAt!),
            ),
            key: StandardAccountDirectoryCard.deletedAtKey(account.accountId),
            style: theme.textTheme.bodySmall,
          ),
        if (account.mustChangePassword)
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
            key: StandardAccountDirectoryCard.actionKey(account.accountId),
            onPressed: () => widget.onSelected?.call(account),
            child: Text(l10n.adminRowAction(account.loginName)),
          ),
        ),
        const Divider(),
      ],
    );
  }
}

/// 狀態原字串 → 顯示文字；未知值原樣顯示（後端日後多一種狀態不至於顯示空白）。
///
/// `deleted` 與 `retired` 如今都在這一頁讀得到的範圍之內（用戶批准的刪除後展示策略：
/// 已刪者仍列出，好讓歷史身分指得回來），所以兩態各有自己的標籤，
/// 而不是被當成一個不會出現的備用值。
String _statusText(AppLocalizations l10n, String status) {
  return switch (status) {
    'active' => l10n.adminStatusActive,
    'disabled' => l10n.adminStatusDisabled,
    // 兩種終態現在都是這一頁讀得到的事實（已刪者仍列出、已綁走的訪戶也仍列出），
    // 留給「未知值原樣顯示」只會讓界面在該講清楚的地方給出一個機器字串。
    'deleted' => l10n.adminStatusDeleted,
    'retired' => l10n.adminStatusRetired,
    _ => status,
  };
}

/// 來源原字串 → 顯示文字；未知值原樣顯示（同上，本地不收緊成枚舉）。
String _typeText(AppLocalizations l10n, String accountType) {
  return switch (accountType) {
    'standard' => l10n.stdAccountTypeStandard,
    'guest' => l10n.stdAccountTypeGuest,
    _ => accountType,
  };
}

/// 以「年-月-日 時:分 UTC」呈現，與裝置清單與管理員目錄同一寫法：不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}
