/// 「管理員端註冊申請審批」卡：分頁列出走審批通路的申請，並對還在等的那一筆
/// 做出批准或拒絕。
///
/// 這是一張轉述伺服器事實的目錄卡加一顆寫入按鈕，規則與全應用同形：
///
/// * 行、總數與回顯的頁碼全部來自 `GET /admin/registrations`；本地不排序、不補行、
///   不拿本頁筆數冒充總數。頁碼邊界由伺服器回顯的 page／total／page_size 推出。
/// * 這本名冊與普通帳戶目錄是兩句話：這裡列「還在等決定的」與「已被拒絕的」，
///   而普通帳戶目錄按定義把那兩態排在門外。被批准的人不在這一頁——他帶著決定時刻
///   離開審批鏈，此後的停用、重置與改名都在那一側。
/// * 按鈕只由服務端讀回的狀態決定：`pending` 才擺那兩顆，`rejected` 只如實說明
///   「決定已做過，而今日沒有改判通路」。界面不拿「沒有決定時刻」推斷還能按，
///   也不為未來可能多出的狀態預留一顆按鈕——那正是 2021 要擋的那種註定落敗的請求。
/// * 確認對話框先把「動的是誰、落下什麼、不會發生什麼」講完才準提交；取消是一條
///   正經出路（一請求都不發，界面停在上一份伺服器真相）。
/// * 批准不等於替他登入：這一步不簽發任何會話，他能不能進去由他自己拿口令走
///   既有登入通路決定。界面因此不寫「已讓他上線」這種話，也不放任何通知出口——
///   本伺服器今日沒有通知模組，審核結果今日只能由本人重新交憑據去查。
/// * 沒有「理由」欄位，也沒有「內部備註」欄位：後端今日那兩格都不落庫，
///   界面擺一個填了也不會被保存的格子，比不擺更糟。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 階段：載入中、就緒、載入失敗（查不了）。
enum _RosterPhase { loading, ready, failed }

/// 註冊申請審批卡。
class RegistrationReviewCard extends StatefulWidget {
  /// 以端點介面建立審批卡；[reloadToken] 變動時重讀當前頁。
  const RegistrationReviewCard({
    super.key,
    required this.api,
    this.reloadToken = 0,
  });

  /// 統一端點存取介面。
  final ServerApi api;

  /// 重新載入的觸發計數（留給同頁其他卡：本卡的寫入自己會重讀）。
  final int reloadToken;

  /// 狀態篩選「全部」識別鍵。
  static const Key filterAllKey = ValueKey<String>(
    'registration-review-filter-all',
  );

  /// 狀態篩選「待審批」識別鍵。
  static const Key filterPendingKey = ValueKey<String>(
    'registration-review-filter-pending',
  );

  /// 狀態篩選「已拒絕」識別鍵。
  static const Key filterRejectedKey = ValueKey<String>(
    'registration-review-filter-rejected',
  );

  /// 名稱關鍵字輸入框識別鍵。
  static const Key searchKey = ValueKey<String>('registration-review-search');

  /// 名稱關鍵字送出鈕識別鍵。
  static const Key searchActionKey = ValueKey<String>(
    'registration-review-search-action',
  );

  /// 分頁摘要識別鍵。
  static const Key summaryKey = ValueKey<String>('registration-review-summary');

  /// 上一頁按鈕識別鍵。
  static const Key prevKey = ValueKey<String>('registration-review-prev');

  /// 下一頁按鈕識別鍵。
  static const Key nextKey = ValueKey<String>('registration-review-next');

  /// 載入中的中性提示識別鍵。
  static const Key loadingKey = ValueKey<String>('registration-review-loading');

  /// 空頁提示識別鍵。
  static const Key emptyKey = ValueKey<String>('registration-review-empty');

  /// 載入失敗提示識別鍵。
  static const Key failedKey = ValueKey<String>('registration-review-failed');

  /// 重試按鈕識別鍵。
  static const Key retryKey = ValueKey<String>('registration-review-retry');

  /// 依申請標識產生該列的識別鍵。
  static Key rowKey(String accountId) =>
      ValueKey<String>('registration-review-list-$accountId');

  /// 依申請標識產生「批准」按鈕的識別鍵。
  static Key approveKey(String accountId) =>
      ValueKey<String>('registration-review-$accountId-approve');

  /// 依申請標識產生「拒絕」按鈕的識別鍵。
  static Key rejectKey(String accountId) =>
      ValueKey<String>('registration-review-$accountId-reject');

  /// 依申請標識產生「已被拒絕」那句說明的識別鍵。
  static Key rejectedNoteKey(String accountId) =>
      ValueKey<String>('registration-review-$accountId-rejected-note');

  /// 確認對話框的確認鈕識別鍵。
  static const Key confirmKey = ValueKey<String>('registration-review-confirm');

  /// 確認對話框的取消鈕識別鍵。
  static const Key confirmCancelKey = ValueKey<String>(
    'registration-review-confirm-cancel',
  );

  /// 決定成功那一句話的識別鍵。
  static const Key decisionNoticeKey = ValueKey<String>(
    'registration-review-decision-notice',
  );

  /// 決定失敗那一句話的識別鍵。
  static const Key decisionFailureKey = ValueKey<String>(
    'registration-review-decision-failure',
  );

  /// 重新讀取名冊的出口識別鍵（2021 的處置就是這一句）。
  static const Key reloadKey = ValueKey<String>('registration-review-reload');

  /// 影響範圍那句常駐說明的識別鍵。
  static const Key scopeHintKey = ValueKey<String>(
    'registration-review-scope-hint',
  );

  @override
  State<RegistrationReviewCard> createState() => _RegistrationReviewCardState();
}

class _RegistrationReviewCardState extends State<RegistrationReviewCard> {
  _RosterPhase _phase = _RosterPhase.loading;
  RegistrationRosterReport? _report;

  /// 讀取失敗那一句話（依機器碼分流；未收錄的碼交給 [apiErrorText] 的通用句）。
  String? _failureText;

  /// 當前頁碼、狀態篩選與已送出的關鍵字：任一篩選變動都回到第一頁
  /// （帶著舊條件看到的頁碼在新條件下沒有意義）。
  int _page = 1;
  String _status = 'all';
  final TextEditingController _keyword = TextEditingController();
  String _appliedKeyword = '';

  /// 決定正在提交中的申請標識：同一筆不並發提交，也不讓另一顆按鈕插進來。
  String? _pendingAccountId;

  /// 決定成功那一句話（全部取自 PUT 回應，不是本地意圖的迴音）。
  String? _decisionNotice;

  /// 決定失敗那一句話。
  String? _decisionFailure;

  /// 上一次決定落敗在 2021（已有決定）：那時只給「重新讀取名冊」這一個出口，
  /// 把那顆按鈕再點一次對這句話不是答案。
  bool _decisionConflict = false;

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
  void didUpdateWidget(covariant RegistrationReviewCard oldWidget) {
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
      _phase = _RosterPhase.loading;
      _failureText = null;
    });
    try {
      final RegistrationRosterReport report = await widget.api
          .registrationRoster(
            page: _page,
            status: _status,
            query: _appliedKeyword,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _report = report;
        _phase = _RosterPhase.ready;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      // 失敗態的那句話按機器碼分流：「你沒有這個權限」「你被登出了」
      // 與「伺服器此刻查不了」是三種處置，混成一句通用失敗就是把選擇丟給使用者猜。
      setState(() {
        _phase = _RosterPhase.failed;
        _failureText = _readFailureText(error);
      });
    }
  }

  /// 讀取失敗 → 介面文字：2011 說權限那一句、會話與門閂那一簇說重登那一句，
  /// 其餘交給 [apiErrorText] 按碼或按類別給。
  String _readFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (error.knownCode) {
      ApiMachineCode.permissionDenied => l10n.registrationReviewDeniedNotice,
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

  /// 送出關鍵字：去首尾空白後與現行已送出的值相同時不重發請求。
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

  /// 確認對話框：先把「動的是誰、落下什麼、不會發生什麼」講完才準提交。
  ///
  /// 取消是一條正經出路（一請求都不發，界面停在上一份伺服器真相）；
  /// 「批准一個人進入這臺伺服器」不該有一條手滑直達的路徑。
  Future<void> _confirmDecision(
    RegistrationApplicationReport application,
    String decision,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (_pendingAccountId != null) {
      return;
    }
    final bool approving = decision == 'approve';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          approving
              ? l10n.registrationReviewConfirmTitleApprove
              : l10n.registrationReviewConfirmTitleReject,
        ),
        content: Text(
          approving
              ? l10n.registrationReviewConfirmBodyApprove(application.loginName)
              : l10n.registrationReviewConfirmBodyReject(application.loginName),
        ),
        actions: <Widget>[
          TextButton(
            key: RegistrationReviewCard.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.registrationReviewConfirmCancelAction),
          ),
          FilledButton(
            key: RegistrationReviewCard.confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              approving
                  ? l10n.registrationReviewConfirmOkApproveAction
                  : l10n.registrationReviewConfirmOkRejectAction,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _applyDecision(application, decision);
  }

  /// 提交決定：本體只有 decision 一欄（沒有依據值可湊），成功後的展示一律換成
  /// PUT 回應；失敗則界面原地不動，逐碼分流。
  Future<void> _applyDecision(
    RegistrationApplicationReport application,
    String decision,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _pendingAccountId = application.accountId;
      _decisionNotice = null;
      _decisionFailure = null;
      _decisionConflict = false;
    });
    try {
      final RegistrationDecisionReport report = await widget.api
          .reviewRegistration(
            accountId: application.accountId,
            decision: decision,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      // 成功句的主詞是服務端回顯的那個決定，而不是本地按下的是哪顆按鈕：
      // 「你批准了這一份」這句話，只有在回應確實回顯 approve 時才敢說。
      setState(() {
        _pendingAccountId = null;
        _decisionNotice = report.isApproved
            ? l10n.registrationReviewApprovedNotice(
                report.application.loginName,
              )
            : l10n.registrationReviewRejectedNotice(
                report.application.loginName,
              );
      });
      // 名冊重讀：批准之後他已經不在這本書上，本地把那行留著就等於多養一份真相。
      await _load();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingAccountId = null;
        _decisionConflict =
            error.knownCode == ApiMachineCode.applicationDecided;
        _decisionFailure = _decisionFailureText(error);
      });
    }
  }

  /// 決定失敗分流：2021 要人重讀名冊（那顆按鈕對他已不存在）、1001 是目標根本不在
  /// 這本名冊、2011 是主體不對，其餘交給機器碼的通用句。
  String _decisionFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (error.knownCode) {
      ApiMachineCode.applicationDecided => l10n.registrationReviewDecidedNotice,
      ApiMachineCode.notFound => l10n.registrationReviewGoneNotice,
      ApiMachineCode.permissionDenied => l10n.registrationReviewDeniedNotice,
      ApiMachineCode.notAuthenticated ||
      ApiMachineCode.sessionInvalid ||
      ApiMachineCode.sessionStale ||
      ApiMachineCode.passwordChangeRequired =>
        l10n.adminProfileStaleRejectedNotice,
      _ => apiErrorText(l10n, error),
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.registrationReviewTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          l10n.registrationReviewScopeHint,
          key: RegistrationReviewCard.scopeHintKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            ChoiceChip(
              // 「全部」那顆沿用其餘名冊同一個標籤鍵：同一句話不另開一份文案。
              // 識別鍵各自給齊，測試才不必用「文字相符」去找一顆會與別頁同名的 chip。
              key: RegistrationReviewCard.filterAllKey,
              label: Text(l10n.adminStatusFilterAll),
              selected: _status == 'all',
              onSelected: (_) => _setStatus('all'),
            ),
            ChoiceChip(
              key: RegistrationReviewCard.filterPendingKey,
              label: Text(l10n.registrationReviewFilterPending),
              selected: _status == 'pending',
              onSelected: (_) => _setStatus('pending'),
            ),
            ChoiceChip(
              key: RegistrationReviewCard.filterRejectedKey,
              label: Text(l10n.registrationReviewFilterRejected),
              selected: _status == 'rejected',
              onSelected: (_) => _setStatus('rejected'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: RegistrationReviewCard.searchKey,
                controller: _keyword,
                decoration: InputDecoration(
                  labelText: l10n.registrationReviewSearchLabel,
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _applyKeyword(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: RegistrationReviewCard.searchActionKey,
              onPressed: _applyKeyword,
              child: Text(l10n.registrationReviewSearchAction),
            ),
          ],
        ),
        const SizedBox(height: 10),
        switch (_phase) {
          _RosterPhase.loading => _loadingRow(l10n, theme),
          _RosterPhase.failed => _failedColumn(l10n),
          _RosterPhase.ready => _readyBody(l10n, theme),
        },
        if (_decisionNotice != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _decisionNotice!,
            key: RegistrationReviewCard.decisionNoticeKey,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (_decisionFailure != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _decisionFailure!,
            key: RegistrationReviewCard.decisionFailureKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          if (_decisionConflict) ...<Widget>[
            const SizedBox(height: 6),
            OutlinedButton(
              key: RegistrationReviewCard.reloadKey,
              onPressed: _load,
              child: Text(l10n.registrationReviewReloadAction),
            ),
          ],
        ],
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
            l10n.registrationReviewLoadingHint,
            key: RegistrationReviewCard.loadingKey,
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
          _failureText ?? l10n.registrationReviewUnavailableNotice,
          key: RegistrationReviewCard.failedKey,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: RegistrationReviewCard.retryKey,
          onPressed: _load,
          child: Text(l10n.adminDirectoryRetryAction),
        ),
      ],
    );
  }

  Widget _readyBody(AppLocalizations l10n, ThemeData theme) {
    final RegistrationRosterReport? report = _report;
    if (report == null) {
      return const SizedBox.shrink();
    }
    final int totalPages = report.totalPages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (report.applications.isEmpty)
          Text(
            l10n.registrationReviewEmptyNotice,
            key: RegistrationReviewCard.emptyKey,
            style: theme.textTheme.bodyMedium,
          )
        else
          ...report.applications.map(
            (RegistrationApplicationReport application) =>
                _row(l10n, theme, application),
          ),
        const SizedBox(height: 6),
        Text(
          // 分頁摘要沿用其餘兩本名冊那一個鍵：同一句話不另開一份文案，
          // 三個數字全部取伺服器回顯。
          l10n.adminDirectoryPageSummary(report.page, totalPages, report.total),
          key: RegistrationReviewCard.summaryKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            OutlinedButton(
              key: RegistrationReviewCard.prevKey,
              onPressed: report.page > 1
                  ? () => _goPage(report.page - 1)
                  : null,
              child: Text(l10n.adminDirectoryPrevAction),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              key: RegistrationReviewCard.nextKey,
              onPressed: report.hasMore ? () => _goPage(report.page + 1) : null,
              child: Text(l10n.adminDirectoryNextAction),
            ),
          ],
        ),
      ],
    );
  }

  /// 一行只呈現後端給出的事實：他是誰、他在審批鏈的哪一站、等了多久、
  /// 有沒有已經落地的決定。按鈕只由 status 決定，本地不推測、不補行。
  Widget _row(
    AppLocalizations l10n,
    ThemeData theme,
    RegistrationApplicationReport application,
  ) {
    final bool busy = _pendingAccountId == application.accountId;
    final bool anyPending = _pendingAccountId != null;
    return Column(
      key: RegistrationReviewCard.rowKey(application.accountId),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          application.loginName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListDisplayNameLabel,
            application.displayName,
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListStatusLabel,
            _statusText(l10n, application.status),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.registrationReviewSubmittedLabel,
            _formatUtcMinute(application.submittedAt),
          ),
          style: theme.textTheme.bodySmall,
        ),
        if (application.reviewedAt != null)
          Text(
            l10n.labelValuePair(
              l10n.registrationReviewDecidedAtLabel,
              _formatUtcMinute(application.reviewedAt!),
            ),
            style: theme.textTheme.bodySmall,
          ),
        // 還在等的人有兩顆按鈕；已經被拒絕的人只有一句實話（今日沒有改判通路）。
        if (application.isPending)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: <Widget>[
                FilledButton(
                  key: RegistrationReviewCard.approveKey(application.accountId),
                  onPressed: busy || anyPending
                      ? null
                      : () => _confirmDecision(application, 'approve'),
                  child: Text(l10n.registrationReviewApproveAction),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  key: RegistrationReviewCard.rejectKey(application.accountId),
                  onPressed: busy || anyPending
                      ? null
                      : () => _confirmDecision(application, 'reject'),
                  child: Text(l10n.registrationReviewRejectAction),
                ),
              ],
            ),
          )
        else if (application.isRejected)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.registrationReviewAlreadyRejectedNotice,
              key: RegistrationReviewCard.rejectedNoteKey(
                application.accountId,
              ),
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.registrationReviewUnknownStatusNotice(application.status),
              key: RegistrationReviewCard.rejectedNoteKey(
                application.accountId,
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 4),
        const Divider(),
      ],
    );
  }
}

/// 狀態原字串 → 顯示文字；未知值原樣顯示（後端日後多一種狀態不至於顯示空白）。
String _statusText(AppLocalizations l10n, String status) {
  return switch (status) {
    'pending' => l10n.registrationReviewStatusPending,
    'rejected' => l10n.registrationReviewStatusRejected,
    _ => status,
  };
}

/// 以「年-月-日 時:分 UTC」呈現，與目錄與詳情卡同一寫法：不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}
