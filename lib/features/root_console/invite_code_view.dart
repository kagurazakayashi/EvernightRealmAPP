/// 「Root 伺服器級註冊邀請碼管理」卡：簽發一枚碼、分頁看名冊的元數據、並撤銷一枚碼。
///
/// 這是一張轉述伺服器事實、並帶一條一次性秘密交付的目錄卡，規則與全應用同形，但多了
/// 「受控一次性展示」這一層，那層要把四件事落在結構上而不是落在文案上：
///
/// * 名冊那一側與審批名冊同形：行、總數與回顯頁碼全部來自 `GET /root/invite-codes`，本地不排序、
///   不補行、不自己派生狀態——「這枚碼現在算哪種狀態」是後端用注入時鐘算的，界面只轉述。
///   按鈕（撤銷）只由服務端讀回的 `status != 'revoked'` 決定；已撤銷的目標不再擺那顆按鈕。
/// * 明文碼只出現一次：`POST` 成功回應裡的 `code` 是唯一允許它露面的一格，界面把它放進一個
///   SelectableText 供操作者自己選中抄下——不擺「複製」鈕、不做二維碼（用戶明確要求本步不引入）。
///   一旦收起（或離開本頁）就再也看不到：庫裡只有它的驗證材料，沒有任何讀法能把 code 翻回來，
///   丟了只能重新簽發一枚。名冊的每一行都不帶 code 欄位，這條「不反覆回顯秘密」因此成立在回應形狀上。
/// * 簽發與撤銷都必經確認對話框，講完「這是什麼、不會發生什麼」才準提交；取消是一條正經出路
///   （一請求都不發，界面停在上一份服務器真相）。結果不明時絕不自動補發——重發簽發是又籤一枚新碼，
///   重發撤銷對一枚已撤銷的碼是 2022，兩者都不是「重試」。
/// * 這張卡不偽裝「邀請碼已經能用」：本版本 invite 模式仍未落地、也沒有任何核銷端點，
///   名冊裡出現一枚 active 只意味著「Root 簽了這把路條」，不意味著它此刻能換出帳戶。
///   這句邊界寫在常駐的範圍說明裡，讓讀的人不會把「簽發成功」誤讀成「註冊通道開了」。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 階段：載入中、就緒、載入失敗（查不了）。
enum _InvitePhase { loading, ready, failed }

/// 服務器級註冊邀請碼管理卡。
class InviteCodeCard extends StatefulWidget {
  /// 以端點介面建立邀請碼卡；[reloadToken] 變動時重讀當前頁。
  const InviteCodeCard({super.key, required this.api, this.reloadToken = 0});

  /// 統一端點存取介面。
  final ServerApi api;

  /// 重新載入的觸發計數（留給同頁其他卡：本卡的寫入自己會重讀）。
  final int reloadToken;

  static const Key titleKey = ValueKey<String>('invite-code-title');
  static const Key scopeHintKey = ValueKey<String>('invite-code-scope-hint');
  static const Key loadingKey = ValueKey<String>('invite-code-loading');
  static const Key failedKey = ValueKey<String>('invite-code-failed');
  static const Key retryKey = ValueKey<String>('invite-code-retry');
  static const Key emptyKey = ValueKey<String>('invite-code-empty');
  static const Key summaryKey = ValueKey<String>('invite-code-summary');
  static const Key prevKey = ValueKey<String>('invite-code-prev');
  static const Key nextKey = ValueKey<String>('invite-code-next');

  static const Key filterAllKey = ValueKey<String>('invite-code-filter-all');
  static const Key filterActiveKey = ValueKey<String>(
    'invite-code-filter-active',
  );
  static const Key filterExpiredKey = ValueKey<String>(
    'invite-code-filter-expired',
  );
  static const Key filterExhaustedKey = ValueKey<String>(
    'invite-code-filter-exhausted',
  );
  static const Key filterRevokedKey = ValueKey<String>(
    'invite-code-filter-revoked',
  );
  static const Key searchKey = ValueKey<String>('invite-code-search');
  static const Key searchActionKey = ValueKey<String>(
    'invite-code-search-action',
  );

  // 簽發區。
  static const Key issueSectionKey = ValueKey<String>(
    'invite-code-issue-section',
  );
  static const Key labelFieldKey = ValueKey<String>('invite-code-label-field');
  static const Key maxUsesFieldKey = ValueKey<String>(
    'invite-code-max-uses-field',
  );
  static const Key expiresFieldKey = ValueKey<String>(
    'invite-code-expires-field',
  );
  static const Key issueActionKey = ValueKey<String>(
    'invite-code-issue-action',
  );
  static const Key issueNoticeKey = ValueKey<String>(
    'invite-code-issue-notice',
  );
  static const Key confirmKey = ValueKey<String>('invite-code-confirm');
  static const Key confirmCancelKey = ValueKey<String>(
    'invite-code-confirm-cancel',
  );

  // 一次性展示區。
  static const Key issuedCodeKey = ValueKey<String>('invite-code-issued-code');
  static const Key issuedHintKey = ValueKey<String>('invite-code-issued-hint');
  static const Key issuedDoneKey = ValueKey<String>('invite-code-issued-done');

  // 撤銷與衝突。
  static const Key revokeNoticeKey = ValueKey<String>(
    'invite-code-revoke-notice',
  );
  static const Key revokeFailureKey = ValueKey<String>(
    'invite-code-revoke-failure',
  );
  static const Key revokeReloadKey = ValueKey<String>(
    'invite-code-revoke-reload',
  );
  static const Key revokeConfirmKey = ValueKey<String>(
    'invite-code-revoke-confirm',
  );
  static const Key revokeConfirmCancelKey = ValueKey<String>(
    'invite-code-revoke-confirm-cancel',
  );

  /// 依碼標識產生該列的識別鍵。
  static Key rowKey(String codeId) =>
      ValueKey<String>('invite-code-list-$codeId');

  /// 依碼標識產生「撤銷」按鈕的識別鍵。
  static Key revokeKey(String codeId) =>
      ValueKey<String>('invite-code-$codeId-revoke');

  /// 依碼標識產生「已被撤銷」說明的識別鍵。
  static Key revokedNoteKey(String codeId) =>
      ValueKey<String>('invite-code-$codeId-revoked-note');

  @override
  State<InviteCodeCard> createState() => _InviteCodeCardState();
}

class _InviteCodeCardState extends State<InviteCodeCard> {
  _InvitePhase _phase = _InvitePhase.loading;
  InviteCodeRosterReport? _report;
  String? _failureText;

  int _page = 1;
  String _status = 'all';
  final TextEditingController _keyword = TextEditingController();
  String _appliedKeyword = '';

  // 簽發區暫存。
  final TextEditingController _label = TextEditingController();
  final TextEditingController _maxUses = TextEditingController();
  final TextEditingController _expires = TextEditingController();
  bool _issuing = false;
  String? _issueNotice;

  /// 一次性明文碼：只在簽發成功後停留在這裡，收起即永久消失（界面不留第二份）。
  String? _revealedCode;

  // 撤銷區。
  String? _pendingCodeId;
  String? _revokeNotice;
  String? _revokeFailure;
  bool _revokeConflict = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _keyword.dispose();
    _label.dispose();
    _maxUses.dispose();
    _expires.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InviteCodeCard oldWidget) {
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
      _phase = _InvitePhase.loading;
      _failureText = null;
    });
    try {
      final InviteCodeRosterReport report = await widget.api.inviteCodeRoster(
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
        _phase = _InvitePhase.ready;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _InvitePhase.failed;
        _failureText = _readFailureText(error);
      });
    }
  }

  String _readFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (error.knownCode) {
      ApiMachineCode.permissionDenied => l10n.inviteCodeDeniedNotice,
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

  /// 解析額度輸入：空→null（後端默認單次）；非法（非正整數）→以本地校驗攔下，不發請求。
  ///
  /// 這一層只擋「明顯填壞」的寫法，真正的額度邊界（>=1、不超上界）仍由後端判並回 1004，
  /// 界面不另抄一份上界——抄了就會和後端漂移。
  int? _parseMaxUses(AppLocalizations l10n) {
    final String raw = _maxUses.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    final int? parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) {
      setState(() => _issueNotice = l10n.inviteCodeLabelRequiredNotice);
      return -1; // 哨兵：調用端據此中止，不與「未填」的 null 混為一談。
    }
    return parsed;
  }

  /// 簽發：確認框講完邊界才 POST；成功後把明文放進一次性展示區，並重讀名冊。
  Future<void> _confirmIssue() async {
    if (_issuing) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _issueNotice = l10n.inviteCodeLabelRequiredNotice);
      return;
    }
    final int? maxUses = _parseMaxUses(l10n);
    if (maxUses == -1) {
      return;
    }
    final String expiresRaw = _expires.text.trim();
    final String expiresFragment = expiresRaw.isEmpty
        ? l10n.inviteCodeExpiresNeverWord
        : l10n.inviteCodeExpiresAtWord(expiresRaw);
    final bool confirmed = await _issueConfirmDialog(
      l10n,
      label,
      maxUses?.toString() ?? '1',
      expiresFragment,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _issue(label, maxUses, expiresRaw);
  }

  Future<bool> _issueConfirmDialog(
    AppLocalizations l10n,
    String label,
    String maxUses,
    String expires,
  ) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.inviteCodeIssueConfirmTitle),
        content: Text(l10n.inviteCodeIssueConfirmBody(label, maxUses, expires)),
        actions: <Widget>[
          TextButton(
            key: InviteCodeCard.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.inviteCodeIssueConfirmCancelAction),
          ),
          FilledButton(
            key: InviteCodeCard.confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.inviteCodeIssueConfirmOkAction),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _issue(String label, int? maxUses, String expiresRaw) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _issuing = true;
      _issueNotice = null;
    });
    try {
      final IssuedInviteCodeReport report = await widget.api.issueInviteCode(
        label: label,
        maxUses: maxUses,
        expiresAt: expiresRaw.isEmpty ? null : expiresRaw,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      // 明文只從這一次回應取出，放進受控展示；表單三項隨之清空，避免舊值被誤當成下一枚的意圖。
      setState(() {
        _issuing = false;
        _revealedCode = report.code;
        _issueNotice = l10n.inviteCodeIssuedNotice(report.invite.label);
        _label.clear();
        _maxUses.clear();
        _expires.clear();
      });
      await _load();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _issuing = false;
        _issueNotice = apiErrorText(l10n, error);
      });
    }
  }

  /// 收起一次性展示：收起後那枚碼就永久看不到了——界面無從把它「再翻出來」。
  void _dismissReveal() {
    setState(() {
      _revealedCode = null;
      _issueNotice = null;
    });
  }

  Future<void> _confirmRevoke(InviteCodeReport code) async {
    if (_pendingCodeId != null) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.inviteCodeRevokeConfirmTitle),
        content: Text(l10n.inviteCodeRevokeConfirmBody(code.label)),
        actions: <Widget>[
          TextButton(
            key: InviteCodeCard.revokeConfirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.inviteCodeRevokeConfirmCancelAction),
          ),
          FilledButton(
            key: InviteCodeCard.revokeConfirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.inviteCodeRevokeConfirmOkAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _revoke(code);
  }

  Future<void> _revoke(InviteCodeReport code) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _pendingCodeId = code.codeId;
      _revokeNotice = null;
      _revokeFailure = null;
      _revokeConflict = false;
    });
    try {
      final InviteCodeMutationReport report = await widget.api.revokeInviteCode(
        codeId: code.codeId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      // 成功句取 DELETE 回應（撤銷後的現值），不是本地按下按鈕的迴音。
      setState(() {
        _pendingCodeId = null;
        _revokeNotice = l10n.inviteCodeRevokedNotice(report.invite.label);
      });
      await _load();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingCodeId = null;
        _revokeConflict =
            error.knownCode == ApiMachineCode.inviteAlreadyRevoked;
        _revokeFailure = _revokeFailureText(error);
      });
    }
  }

  String _revokeFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (error.knownCode) {
      ApiMachineCode.inviteAlreadyRevoked =>
        l10n.inviteCodeAlreadyRevokedNotice,
      ApiMachineCode.notFound => l10n.inviteCodeNotFoundNotice,
      ApiMachineCode.permissionDenied => l10n.inviteCodeDeniedNotice,
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
        Text(
          l10n.inviteCodeTitle,
          key: InviteCodeCard.titleKey,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          l10n.inviteCodeScopeHint,
          key: InviteCodeCard.scopeHintKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _issueForm(l10n, theme),
        if (_revealedCode != null) ...<Widget>[
          const SizedBox(height: 10),
          _revealPanel(l10n, theme),
        ],
        if (_issueNotice != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_issueNotice!, key: InviteCodeCard.issueNoticeKey),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            ChoiceChip(
              key: InviteCodeCard.filterAllKey,
              label: Text(l10n.adminStatusFilterAll),
              selected: _status == 'all',
              onSelected: (_) => _setStatus('all'),
            ),
            ChoiceChip(
              key: InviteCodeCard.filterActiveKey,
              label: Text(l10n.inviteCodeFilterActive),
              selected: _status == 'active',
              onSelected: (_) => _setStatus('active'),
            ),
            ChoiceChip(
              key: InviteCodeCard.filterExpiredKey,
              label: Text(l10n.inviteCodeFilterExpired),
              selected: _status == 'expired',
              onSelected: (_) => _setStatus('expired'),
            ),
            ChoiceChip(
              key: InviteCodeCard.filterExhaustedKey,
              label: Text(l10n.inviteCodeFilterExhausted),
              selected: _status == 'exhausted',
              onSelected: (_) => _setStatus('exhausted'),
            ),
            ChoiceChip(
              key: InviteCodeCard.filterRevokedKey,
              label: Text(l10n.inviteCodeFilterRevoked),
              selected: _status == 'revoked',
              onSelected: (_) => _setStatus('revoked'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: InviteCodeCard.searchKey,
                controller: _keyword,
                decoration: InputDecoration(
                  labelText: l10n.inviteCodeSearchLabel,
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _applyKeyword(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: InviteCodeCard.searchActionKey,
              onPressed: _applyKeyword,
              child: Text(l10n.inviteCodeSearchAction),
            ),
          ],
        ),
        const SizedBox(height: 10),
        switch (_phase) {
          _InvitePhase.loading => _loadingRow(l10n, theme),
          _InvitePhase.failed => _failedColumn(l10n),
          _InvitePhase.ready => _readyBody(l10n, theme),
        },
        if (_revokeNotice != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _revokeNotice!,
            key: InviteCodeCard.revokeNoticeKey,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (_revokeFailure != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _revokeFailure!,
            key: InviteCodeCard.revokeFailureKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          if (_revokeConflict) ...<Widget>[
            const SizedBox(height: 6),
            OutlinedButton(
              key: InviteCodeCard.revokeReloadKey,
              onPressed: _load,
              child: Text(l10n.inviteCodeReloadAction),
            ),
          ],
        ],
      ],
    );
  }

  /// 簽發表單：標籤必填、額度與有效期皆可留空（各走後端默認）。不擺任何複製/分享/二維碼控件。
  Widget _issueForm(AppLocalizations l10n, ThemeData theme) {
    final bool busy = _issuing;
    return Column(
      key: InviteCodeCard.issueSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.inviteCodeIssueSectionTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        TextField(
          key: InviteCodeCard.labelFieldKey,
          controller: _label,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: l10n.inviteCodeLabelFieldLabel,
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: InviteCodeCard.maxUsesFieldKey,
          controller: _maxUses,
          enabled: !busy,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.inviteCodeMaxUsesFieldLabel,
            helperText: l10n.inviteCodeMaxUsesFieldHint,
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: InviteCodeCard.expiresFieldKey,
          controller: _expires,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: l10n.inviteCodeExpiresFieldLabel,
            helperText: l10n.inviteCodeExpiresFieldHint,
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: InviteCodeCard.issueActionKey,
            onPressed: busy ? null : _confirmIssue,
            child: Text(l10n.inviteCodeIssueAction),
          ),
        ),
      ],
    );
  }

  /// 一次性展示：SelectableText 讓操作者自己選中抄寫，但沒有複製鈕、沒有二維碼。
  Widget _revealPanel(AppLocalizations l10n, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SelectableText(
            _revealedCode ?? '',
            key: InviteCodeCard.issuedCodeKey,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.inviteCodeIssuedOneTimeHint,
            key: InviteCodeCard.issuedHintKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: InviteCodeCard.issuedDoneKey,
              onPressed: _dismissReveal,
              child: Text(l10n.inviteCodeIssuedDoneAction),
            ),
          ),
        ],
      ),
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
            l10n.inviteCodeLoadingHint,
            key: InviteCodeCard.loadingKey,
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
          _failureText ?? l10n.inviteCodeUnavailableNotice,
          key: InviteCodeCard.failedKey,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: InviteCodeCard.retryKey,
          onPressed: _load,
          child: Text(l10n.adminDirectoryRetryAction),
        ),
      ],
    );
  }

  Widget _readyBody(AppLocalizations l10n, ThemeData theme) {
    final InviteCodeRosterReport? report = _report;
    if (report == null) {
      return const SizedBox.shrink();
    }
    final int totalPages = report.totalPages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (report.invites.isEmpty)
          Text(
            l10n.inviteCodeEmptyNotice,
            key: InviteCodeCard.emptyKey,
            style: theme.textTheme.bodyMedium,
          )
        else
          ...report.invites.map(
            (InviteCodeReport code) => _row(l10n, theme, code),
          ),
        const SizedBox(height: 6),
        Text(
          l10n.adminDirectoryPageSummary(report.page, totalPages, report.total),
          key: InviteCodeCard.summaryKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            OutlinedButton(
              key: InviteCodeCard.prevKey,
              onPressed: report.page > 1
                  ? () => _goPage(report.page - 1)
                  : null,
              child: Text(l10n.adminDirectoryPrevAction),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              key: InviteCodeCard.nextKey,
              onPressed: report.hasMore ? () => _goPage(report.page + 1) : null,
              child: Text(l10n.adminDirectoryNextAction),
            ),
          ],
        ),
      ],
    );
  }

  /// 一行只轉述後端給出的元數據：標籤、狀態、額度、簽發/到期/撤銷時刻。絕不含明文碼。
  /// 撤銷按鈕只由「尚未 revoked」決定；已撤銷的只留一句歷史說明。
  Widget _row(AppLocalizations l10n, ThemeData theme, InviteCodeReport code) {
    final bool busy = _pendingCodeId == code.codeId;
    final bool anyPending = _pendingCodeId != null;
    final String expiresText = code.expiresAt == null
        ? l10n.inviteCodeExpiresNeverLabel
        : _formatUtcMinute(code.expiresAt!);
    return Column(
      key: InviteCodeCard.rowKey(code.codeId),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          code.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListStatusLabel,
            _statusText(l10n, code.status),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.inviteCodeQuotaLabel(
            code.usedCount.toString(),
            code.maxUses.toString(),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.inviteCodeIssuedOnLabel(_formatUtcMinute(code.createdAt)),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          code.expiresAt == null
              ? l10n.inviteCodeExpiresNeverLabel
              : l10n.inviteCodeExpiresOnLabel(expiresText),
          style: theme.textTheme.bodySmall,
        ),
        if (code.revokedAt != null)
          Text(
            l10n.inviteCodeRevokedOnLabel(_formatUtcMinute(code.revokedAt!)),
            style: theme.textTheme.bodySmall,
          ),
        if (!code.isRevoked)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: OutlinedButton(
              key: InviteCodeCard.revokeKey(code.codeId),
              onPressed: busy || anyPending ? null : () => _confirmRevoke(code),
              child: Text(l10n.inviteCodeRevokeAction),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.inviteCodeAlreadyRevokedNotice,
              key: InviteCodeCard.revokedNoteKey(code.codeId),
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 4),
        const Divider(),
      ],
    );
  }
}

/// 狀態原字串 → 顯示文字；未知值原樣顯示（後端日後多一種派生態不至於顯示空白）。
String _statusText(AppLocalizations l10n, String status) {
  return switch (status) {
    'active' => l10n.inviteCodeStatusActive,
    'expired' => l10n.inviteCodeStatusExpired,
    'exhausted' => l10n.inviteCodeStatusExhausted,
    'revoked' => l10n.inviteCodeStatusRevoked,
    _ => l10n.inviteCodeStatusUnknown(status),
  };
}

/// 以「年-月-日 時:分 UTC」呈現，與其餘名冊卡同一寫法：不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}
