/// 「用憑證綁定訪戶」面板：讓一名普通正式帳戶**本人**把伺服器管理員准過的一名訪戶
/// 併入自己的帳戶。這是今日整個產品裡唯一的綁定執行入口，而它只承認一件事：
/// 按下去的人是憑證上釘著的那個目標。
///
/// 這張卡的界線全部落在後端合同上，界面只做呈現與確認：
///
/// * 先預覽、再確認是兩趟請求，不是一趟加一個本地勾選框。預覽那趟回的是**此刻**重做的
///   判定（來源與目標現值、將產生的影響、會被判出的源會話數、資料庫版本、失效時刻），
///   而不是簽發時那份快照的回音——中隔十分鐘之後事實可以整個變掉。確認那趟在同一筆
///   交易裡再核一次才寫入；兩者之間事實漂了，後端以 2026 回絕並要求重新預檢。
///   因此「已看过影响」是「確認」按鈕能按的前提：預覽跑完後改過憑證欄，那颗按鈕就收起，
///   界面上不留下「拿一份舊的准許去按新的動作」的路徑。
/// * 只讀這一欄 `ticket`：來源與目標都不是界面能填的格子（他們釘在憑證行上），
///   而「我是誰」由本次會話決定。沒有「我以誰的身分綁定」這一欄，就沒有自報即生效的空隙。
/// * 提交後沒有拿到回應（離線、逾時）時，這裡說的從來不是「失敗」也不是「成功」，
///   而是「結果待確認」，並立刻重讀下方那份本人清單——那一行留痕才是完成與否的證據。
///   重發同一枚憑證只會得到「憑證不可用」（它已被用掉），所以界面也不自動補發。
/// * 訪客名下的會話在綁定那一刻被撤銷；這一動不會把源令牌變成能開目標家門的令牌，
///   本面板也不提供那樣的东西——本人的會話始终是只有自己這一枚。
///
/// 內容在對話框內自行滾動：對話框是一條覆蓋式路由，不歸應用殼的滾動區管。
library;

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';
import '../api_error_labels.dart';
import '../app_dependencies.dart';

/// 從現有上下文開啟「用憑證綁定訪戶」面板。
Future<void> showGuestBindDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext _) => const GuestBindDialog(),
  );
}

/// 「用憑證綁定訪戶」對話框。
class GuestBindDialog extends StatelessWidget {
  /// 建立對話框。
  const GuestBindDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context).guestBindEntryTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: GuestBindView(api: AppScope.of(context).api),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            AppLocalizations.of(context).adminStatusConfirmCancelAction,
          ),
        ),
      ],
    );
  }
}

/// 面板本體：憑證欄 → 只讀預覽 → 單獨確認 → 本人已完成清單。
class GuestBindView extends StatefulWidget {
  /// 以 API 客戶端建立面板。
  const GuestBindView({super.key, required this.api});

  /// 三條本人通路的唯一出口（範圍全部由後端按本次會話決定，界面不傳任何主體標識）。
  final ServerApi api;

  /// 範圍句識別鍵（這張卡只做一件事：由本人確認綁定）。
  static const Key scopeKey = ValueKey<String>('guest-bind-scope');

  /// 憑證輸入框識別鍵。
  static const Key ticketKey = ValueKey<String>('guest-bind-ticket');

  /// 預覽按鈕識別鍵。
  static const Key previewKey = ValueKey<String>('guest-bind-preview');

  /// 確認執行按鈕識別鍵（只在預覽成功且憑證欄未改動時可按）。
  static const Key confirmKey = ValueKey<String>('guest-bind-confirm');

  /// 預覽結果面板識別鍵（首句是「尚未綁定」的顯著標示）。
  static const Key previewResultKey = ValueKey<String>(
    'guest-bind-preview-result',
  );

  /// 執行完成後的结果句識別鍵。
  static const Key doneKey = ValueKey<String>('guest-bind-done');

  /// 「結果待確認」那一句的識別鍵（回應遺失時呈現）。
  static const Key pendingResultKey = ValueKey<String>(
    'guest-bind-pending-result',
  );

  /// 已完成綁定清單識別鍵。
  static const Key ledgerKey = ValueKey<String>('guest-bind-ledger');

  /// 清單為空那一句的識別鍵。
  static const Key ledgerEmptyKey = ValueKey<String>('guest-bind-ledger-empty');

  /// 重讀清單按鈕識別鍵。
  static const Key reloadKey = ValueKey<String>('guest-bind-reload');

  /// 一般提示（本地攔截與失敗分流共用一格）。
  static const Key noticeKey = ValueKey<String>('guest-bind-notice');

  /// 確認對話框的肯定按鈕識別鍵。
  static const Key confirmDialogKey = ValueKey<String>(
    'guest-bind-confirm-dialog',
  );

  /// 確認對話框的取消按鈕識別鍵。
  static const Key confirmDialogCancelKey = ValueKey<String>(
    'guest-bind-confirm-dialog-cancel',
  );

  @override
  State<GuestBindView> createState() => _GuestBindViewState();
}

class _GuestBindViewState extends State<GuestBindView> {
  final TextEditingController _ticket = TextEditingController();

  /// 當前的核銷前預覽（null 代表沒有可依據的預覽）。
  GuestBindClaimPreviewReport? _preview;

  /// 預覽是為哪一枚憑證做的：輸入欄一旦改動，那份預覽就不再是「這一次的依據」。
  String? _previewedFor;

  /// 最近一次成功執行的結果（只服務那一句完成句，數字一律取自回應）。
  GuestBindResultReport? _done;

  /// 本人的已完成綁定清單；null 代表還沒讀過或讀失敗（不拿空清單冒充「沒有過」）。
  List<GuestBindingItem>? _bindings;

  bool _previewing = false;
  bool _confirming = false;
  bool _loadingLedger = false;

  /// 提交出去了但沒拿到回應：處置是「結果待確認＋重讀清單」，不是宣稱失敗或成功。
  bool _resultUnknown = false;

  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLedger());
  }

  @override
  void dispose() {
    _ticket.dispose();
    super.dispose();
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀本人的已完成清單。失敗只在提示格說一句「讀不到」，不把清單清成空的——
  /// 「查不了」與「還沒有過」是兩句話（後者是一個事實，前者不是）。
  Future<void> _loadLedger() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (_loadingLedger) {
      return;
    }
    setState(() {
      _loadingLedger = true;
      _notice = null;
    });
    try {
      final GuestBindingListReport report = await widget.api.guestBindingsList(
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingLedger = false;
        _bindings = report.bindings;
        // 這裡刻意不因「清單有東西」就收回「結果待確認」：那幾行可能是更早的綁定，
        // 拿它證明「剛剛那一趟落地了」是界面在編故事。待確認那句話自己指向清單，
        // 由操作者看新的一行有沒有出現——證據在那一行上，不在這顆開關上。
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingLedger = false;
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  /// 只讀預覽：把這枚憑證按當前事實會做什麼念出來。它不核銷任何东西。
  Future<void> _runPreview() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String ticket = _ticket.text.trim();
    if (_previewing || _confirming) {
      return;
    }
    if (ticket.isEmpty) {
      setState(() => _notice = l10n.guestBindIncompleteNotice);
      return;
    }
    setState(() {
      _previewing = true;
      _notice = null;
      // 新的預覽開跑，舊的那份與那一次的結果句都退場：兩份「上次結論」並存是第三種真相。
      _preview = null;
      _previewedFor = null;
      _done = null;
      _resultUnknown = false;
    });
    try {
      final GuestBindClaimPreviewReport report = await widget.api
          .guestBindPreview(ticket: ticket, acceptLanguage: _acceptLanguage);
      if (!mounted) {
        return;
      }
      setState(() {
        _previewing = false;
        _preview = report;
        _previewedFor = ticket;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _previewing = false;
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  /// 確認執行前先問一次：對話框把「動的是誰、他名下幾枚會話會被登出、
  /// 你自己的什麼不會變」完整唸出來，確認才發 POST。這是整個綁定通路唯一動真資料的地方。
  Future<void> _confirmBinding() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final GuestBindClaimPreviewReport? preview = _preview;
    if (preview == null ||
        _confirming ||
        _previewedFor != _ticket.text.trim()) {
      // 沒有「已驗證的影響」可唸時這顆按鈕本就不呈現；這裡的守衛只兜併發與狀態漂移。
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.guestBindConfirmTitle),
        content: Text(
          l10n.guestBindConfirmBody(
            preview.source.loginName,
            preview.sourceOpenSessions,
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: GuestBindView.confirmDialogCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminStatusConfirmCancelAction),
          ),
          FilledButton(
            key: GuestBindView.confirmDialogKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.guestBindConfirmOkAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _applyBinding(_previewedFor!);
  }

  /// 執行綁定。成功：完成句的數字取自回應，並重讀清單讓留痕自己說話。
  /// 拿不到回應（離線／逾時）：說「結果待確認」並重讀清單，絕不自動補發。
  Future<void> _applyBinding(String ticket) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _confirming = true;
      _notice = null;
    });
    try {
      final GuestBindResultReport report = await widget.api.guestBindConfirm(
        ticket: ticket,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _confirming = false;
        _done = report;
        _preview = null;
        _previewedFor = null;
        _resultUnknown = false;
        _ticket.clear();
      });
      await _loadLedger();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      final bool outcomeUnknown =
          error.kind == ApiErrorKind.unreachable ||
          error.kind == ApiErrorKind.timeout;
      setState(() {
        _confirming = false;
        if (outcomeUnknown) {
          // 請求可能已經在服務端落地：這一刻唯一誠實的說法是「結果待確認」，
          // 而答案在本人那份清單裡，不在重按一顆按鈕上（憑證若已被用掉，重發只得到 2025）。
          _resultUnknown = true;
          _preview = null;
          _previewedFor = null;
        } else {
          _notice = apiErrorText(l10n, error);
        }
      });
      if (outcomeUnknown) {
        await _loadLedger();
      }
    }
  }

  /// 影響記號 → 界面句子。與管理員那側共用同一組句子：同一枚記號在兩處唸同一句話，
  /// 認不得的記號如實承認認不得（合同只增不刪，舊界面不拿舊句子套新事實）。
  String _impactText(AppLocalizations l10n, String token, int openSessions) {
    return switch (token) {
      'revoke_source_sessions' => l10n.stdAccountBindPreflightImpactRevoke(
        openSessions,
      ),
      'retire_source_account' => l10n.stdAccountBindPreflightImpactRetire,
      'keep_history_references' =>
        l10n.stdAccountBindPreflightImpactKeepHistory,
      'transfer_future_attribution' =>
        l10n.stdAccountBindPreflightImpactFutureAttribution,
      'target_unchanged' => l10n.stdAccountBindPreflightImpactTargetUnchanged,
      _ => l10n.stdAccountBindPreflightUnknownToken(token),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool busy = _previewing || _confirming || _loadingLedger;
    // 「已驗證的影響」是執行按鈕的唯一依據：沒跑過預覽、或憑證欄在預覽後被改過，
    // 界面上就沒有那一動的位置——這跟後端在交易內重做判定是同一件事的兩側。
    final bool canConfirm =
        _preview != null &&
        _previewedFor == _ticket.text.trim() &&
        !_confirming &&
        !_previewing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.guestBindScopeHint,
          key: GuestBindView.scopeKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          key: GuestBindView.ticketKey,
          controller: _ticket,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: l10n.guestBindTicketFieldLabel,
            helperText: l10n.guestBindTicketHelpNotice,
            isDense: true,
          ),
          maxLength: 22,
          onChanged: (_) {
            // 輸入一改，那份預覽就不再是這一次的依據：把確認的依據收回來。
            if (_previewedFor != _ticket.text.trim() && _preview != null) {
              setState(() {
                _preview = null;
                _previewedFor = null;
              });
            }
          },
        ),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: <Widget>[
            FilledButton(
              key: GuestBindView.previewKey,
              onPressed: busy ? null : _runPreview,
              child: Text(
                _previewing
                    ? l10n.guestBindWorkingHint
                    : l10n.guestBindPreviewAction,
              ),
            ),
            if (canConfirm)
              FilledButton(
                key: GuestBindView.confirmKey,
                onPressed: _confirmBinding,
                child: Text(l10n.guestBindConfirmAction),
              ),
            OutlinedButton(
              key: GuestBindView.reloadKey,
              onPressed: _loadingLedger ? null : _loadLedger,
              child: Text(l10n.guestBindReloadAction),
            ),
          ],
        ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _notice!,
              key: GuestBindView.noticeKey,
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_resultUnknown)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.guestBindPendingResultNotice,
              key: GuestBindView.pendingResultKey,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_done != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.guestBindDoneNotice(
                _done!.source.loginName,
                _done!.revokedSessions,
              ),
              key: GuestBindView.doneKey,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_preview != null) _previewPanel(theme, l10n, _preview!),
        const Divider(),
        Text(l10n.guestBindLedgerTitle, style: theme.textTheme.bodyMedium),
        // 清單尚未讀到（首次載入失敗）時不在這裡再添一句：那一欄的說明在上方提示格，
        // 而「查不了」與「還沒有過」是兩句話，界面不拿空清單冒充前者。
        if (_bindings != null) ...<Widget>[
          if (_bindings!.isEmpty)
            Text(
              l10n.guestBindLedgerEmptyNotice,
              key: GuestBindView.ledgerEmptyKey,
              style: theme.textTheme.bodySmall,
            ),
          if (_bindings!.isNotEmpty)
            Column(
              key: GuestBindView.ledgerKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final GuestBindingItem item in _bindings!)
                  Text(
                    l10n.guestBindLedgerRow(
                      item.sourceLoginName,
                      item.boundAt.toUtc().toIso8601String(),
                      item.revokedSessions,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
        ],
      ],
    );
  }

  /// 預覽面板：第一句就是「尚未綁定」，其後逐條唸已驗證的影響，收尾講同意形態、
  /// 失效時刻與這份預覽按哪一版資料庫跑——三處都把「這一步什麼都沒改」講完。
  Widget _previewPanel(
    ThemeData theme,
    AppLocalizations l10n,
    GuestBindClaimPreviewReport report,
  ) {
    final List<Widget> lines = <Widget>[
      Text(
        l10n.guestBindNotBoundNotice,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(
        l10n.guestBindPreviewHead(
          report.source.loginName,
          report.sourceOpenSessions,
        ),
        style: theme.textTheme.bodySmall,
      ),
    ];
    for (final String token in report.impacts) {
      lines.add(
        Text(
          _impactText(l10n, token, report.sourceOpenSessions),
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    lines.add(
      Text(l10n.guestBindConsentNotice, style: theme.textTheme.bodySmall),
    );
    lines.add(
      Text(
        l10n.guestBindExpiresNotice(report.expiresAt.toUtc().toIso8601String()),
        style: theme.textTheme.bodySmall,
      ),
    );
    lines.add(
      Text(
        l10n.stdAccountBindPreflightDataVersion(report.schemaVersion),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        key: GuestBindView.previewResultKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }
}
