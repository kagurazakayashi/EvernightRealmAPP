/// 「Root 帳戶建立策略」卡：三個建立入口的開關、自註冊模式，以及它們此刻對外的結果。
///
/// 這張卡要把三件事落在結構上，而不是落在文案上：
///
/// * 底稿只有一個來源：構造時 GET `/root/account-policy` 讀服務端現值。讀取失敗就停在
///   「讀不到」這一態，畫面不顯示任何猜測值——把「查不出來」畫成「全關」會讓一次
///   資料庫缺陷看起來像 Root 做過的決定。
/// * 保存交出去的是完整的三份值，而且刻意沒有依據值欄位：這是一份只有 Root 會寫的單例
///   文件，重複提交不是「依據陳舊」而是「又確認一次」。因此結果不明時界面絕不自動補發，
///   而且保存必經確認對話框——對話框要把「值本身不會讓訪客多做任何事」講完，
///   操作者才是在知道自己在改意圖、不是在開門。
/// * 策略值與對外答案並列顯示：兩個布林取的是服務端 `entry` 的回傳值，界面不自己推算。
///   「保存了 open 但對外仍是關」是這一步的正確狀態（通路尚未實作），
///   所以這句話要顯示在同一張卡上，而不是讓 Root 去猜功能壞了。
/// * 例外講在介面上：`admin_create_standard` 從不套到 Root 開設管理員與本機憑據命令。
///   這一句不是修辭——少了它，關掉開關的人會以為自己能讓整個伺服器開不出任何人。
/// * 模式選項與後端「本版本寫得進」那份清單同步：`closed`、`open`、`approval` 與 `invite`
///   （後兩者各自收待審批的申請、以及憑有效邀請碼自行註冊）。這四個名字的准入通路如今都已落地，
///   少列一個能寫的模式不是保守，而是會害人——這張卡交的是完整的三份值，Root 為了改別欄而保存時
///   就會把服務端原本的 `approval`／`invite` 頂成自己清單上的某一個，等於悄悄關掉那條准入。
/// * 現值是這張卡給得出的四個名字之外的（未來多出的那一個）時如實顯示那個原字並說明
///   「本版本選不了它」，不預填、不降級成 closed；直接送出那種值的請求由後端以 2016 拒絕，
///   界面據此另成一句，與 1004 分開。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 策略讀取階段。
enum _PolicyPhase { loading, ready, loadFailed }

/// 帳戶建立策略卡。
class AccountPolicyCard extends StatefulWidget {
  /// 建立策略卡。
  const AccountPolicyCard({super.key, required this.api});

  /// 統一端點存取介面。
  final ServerApi api;

  /// 標題識別鍵。
  static const Key titleKey = ValueKey<String>('account-policy-title');

  /// 「管理員建立普通帳戶」開關識別鍵。
  static const Key adminCreateKey = ValueKey<String>(
    'account-policy-admin-create',
  );

  /// 「訪客帳戶」開關識別鍵。
  static const Key guestKey = ValueKey<String>('account-policy-guest');

  /// 自註冊模式 closed 選項識別鍵。
  static const Key modeClosedKey = ValueKey<String>(
    'account-policy-mode-closed',
  );

  /// 自註冊模式 open 選項識別鍵。
  static const Key modeOpenKey = ValueKey<String>('account-policy-mode-open');

  /// 自註冊模式 approval 選項識別鍵（收待審批的申請）。
  static const Key modeApprovalKey = ValueKey<String>(
    'account-policy-mode-approval',
  );

  /// 選中 approval 時的補充說明識別鍵。
  static const Key approvalHintKey = ValueKey<String>(
    'account-policy-approval-hint',
  );

  /// 自註冊模式 invite 選項識別鍵（持有效邀請碼者自行註冊）。
  static const Key modeInviteKey = ValueKey<String>(
    'account-policy-mode-invite',
  );

  /// 選中 invite 時的補充說明識別鍵。
  static const Key inviteHintKey = ValueKey<String>(
    'account-policy-invite-hint',
  );

  /// 現值為不可選模式時的說明識別鍵。
  static const Key modeExternalKey = ValueKey<String>(
    'account-policy-mode-external',
  );

  /// 修改時刻列識別鍵（從未修改與有時刻共用這一個鍵）。
  static const Key updatedKey = ValueKey<String>('account-policy-updated');

  /// 對外入口答案列識別鍵。
  static const Key entryKey = ValueKey<String>('account-policy-entry');

  /// 「策略不等於能力」說明列識別鍵。
  static const Key capabilityKey = ValueKey<String>(
    'account-policy-capability',
  );

  /// 保存按鈕識別鍵。
  static const Key submitKey = ValueKey<String>('account-policy-save');

  /// 提示列（本地與寫入失敗共用）識別鍵。
  static const Key noticeKey = ValueKey<String>('account-policy-notice');

  /// 保存成功摘要識別鍵。
  static const Key savedKey = ValueKey<String>('account-policy-saved');

  /// 確認對話框肯定按鈕識別鍵。
  static const Key confirmKey = ValueKey<String>('account-policy-confirm');

  /// 確認對話框取消按鈕識別鍵。
  static const Key confirmCancelKey = ValueKey<String>('account-policy-cancel');

  /// 重讀按鈕識別鍵。
  static const Key reloadKey = ValueKey<String>('account-policy-reload');

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>('account-policy-loading');

  @override
  State<AccountPolicyCard> createState() => _AccountPolicyCardState();
}

class _AccountPolicyCardState extends State<AccountPolicyCard> {
  _PolicyPhase _phase = _PolicyPhase.loading;

  /// 上一次從伺服器讀到的完整現值（也是成功後替換進畫面的那份）。
  AccountPolicyReport? _policy;

  /// 三個待送出的值：初值一律來自服務端回應，界面不自行給預設。
  bool _adminCreate = false;
  String _mode = 'closed';
  bool _guest = false;

  /// 寫入進行中：它不只是防手滑——每一次成功保存都是又寫一次、又留一條稽核。
  bool _saving = false;

  String? _notice;
  String? _savedNotice;

  /// 讀取失敗的句子（失敗態仍要有重讀與說明，不能只剩一片空白）。
  String? _loadFailureText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀取（或重讀）策略：成功時以回應填三個值，失敗時停在失敗態不顯示任何猜測值。
  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = _PolicyPhase.loading;
      _notice = null;
      _savedNotice = null;
    });
    try {
      final AccountPolicyReport report = await widget.api.accountPolicy(
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _policy = report;
        _adminCreate = report.adminCreateStandard;
        _mode = report.selfRegisterMode;
        _guest = report.guestEnabled;
        _loadFailureText = null;
        _phase = _PolicyPhase.ready;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadFailureText = _readFailureText(error);
        _phase = _PolicyPhase.loadFailed;
      });
    }
  }

  /// 讀取失敗分流：端點不存在、不是 Root、會話類、其他各說各句。
  String _readFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    return switch (code) {
      ApiMachineCode.notFound => l10n.accountPolicyNotFoundNotice,
      ApiMachineCode.permissionDenied => l10n.accountPolicyDeniedNotice,
      ApiMachineCode.notAuthenticated ||
      ApiMachineCode.sessionInvalid ||
      ApiMachineCode.sessionStale ||
      ApiMachineCode.passwordChangeRequired =>
        l10n.accountPolicyStaleRejectedNotice,
      _ => l10n.accountPolicyLoadFailedNotice,
    };
  }

  /// 送出前的一記確認：講完「會發生什麼」與「不會發生什麼」才准保存。
  Future<void> _submit() async {
    if (_saving || _phase != _PolicyPhase.ready) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool confirmed = await _confirmDialog(l10n);
    if (!confirmed || !mounted) {
      return;
    }
    await _save();
  }

  /// 確認對話框：取消時一個請求都不發。
  Future<bool> _confirmDialog(AppLocalizations l10n) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.accountPolicyConfirmTitle),
        content: Text(l10n.accountPolicyConfirmBody),
        actions: <Widget>[
          TextButton(
            key: AccountPolicyCard.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.accountPolicyConfirmCancel),
          ),
          FilledButton(
            key: AccountPolicyCard.confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.accountPolicyConfirmOk),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 整份 PUT：三個值一次送出；成功後畫面換成的仍是回應。
  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _notice = null;
      _savedNotice = null;
    });
    try {
      final AccountPolicyReport report = await widget.api.updateAccountPolicy(
        adminCreateStandard: _adminCreate,
        selfRegisterMode: _mode,
        guestEnabled: _guest,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _policy = report;
        // 三個值都以回應為準：後端可能整理過寫法，也可能本來就拒了某一項。
        _adminCreate = report.adminCreateStandard;
        _mode = report.selfRegisterMode;
        _guest = report.guestEnabled;
        _savedNotice = l10n.accountPolicySavedNotice;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        // 失敗後畫面維持上一份伺服器真相：三個值都回到那次讀到的現值，
        // 而不是留著一組「按了但沒生效」的編輯態。
        final AccountPolicyReport? last = _policy;
        if (last != null) {
          _adminCreate = last.adminCreateStandard;
          _mode = last.selfRegisterMode;
          _guest = last.guestEnabled;
        }
        _notice = _writeFailureText(error);
      });
    }
  }

  /// 寫入失敗分流：2016 與 1004 必須是兩句話。
  String _writeFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.accountPolicyModeUnavailable) {
      return l10n.accountPolicyModeRejectedNotice;
    }
    return switch (code) {
      ApiMachineCode.permissionDenied => l10n.accountPolicyDeniedNotice,
      ApiMachineCode.notAuthenticated ||
      ApiMachineCode.sessionInvalid ||
      ApiMachineCode.sessionStale ||
      ApiMachineCode.passwordChangeRequired =>
        l10n.accountPolicyStaleRejectedNotice,
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
          l10n.accountPolicyTitle,
          key: AccountPolicyCard.titleKey,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(l10n.accountPolicyIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        switch (_phase) {
          _PolicyPhase.loading => Text(
            l10n.accountPolicyLoadingNotice,
            key: AccountPolicyCard.loadingKey,
            style: theme.textTheme.bodyMedium,
          ),
          _PolicyPhase.loadFailed => _failedColumn(l10n),
          _PolicyPhase.ready => _readyBody(l10n, theme),
        },
      ],
    );
  }

  /// 失敗態：一句原因加一個重讀出口。
  Widget _failedColumn(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _loadFailureText ?? l10n.accountPolicyLoadFailedNotice,
          key: AccountPolicyCard.noticeKey,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: AccountPolicyCard.reloadKey,
            onPressed: () => _load(),
            child: Text(l10n.accountPolicyReloadAction),
          ),
        ),
      ],
    );
  }

  /// 就緒態：三個值、兩行事實（修改時刻與對外答案）、一句能力說明，以及一顆保存鈕。
  Widget _readyBody(AppLocalizations l10n, ThemeData theme) {
    final AccountPolicyReport? policy = _policy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _switchRow(
          label: l10n.accountPolicyAdminCreateLabel,
          hint: l10n.accountPolicyAdminCreateHint,
          key: AccountPolicyCard.adminCreateKey,
          value: _adminCreate,
          onChanged: _saving
              ? null
              : (bool value) => setState(() => _adminCreate = value),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.accountPolicySelfRegisterLabel,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              key: AccountPolicyCard.modeClosedKey,
              label: Text(l10n.accountPolicyModeClosedLabel),
              selected: _mode == 'closed',
              onSelected: _saving
                  ? null
                  : (_) => setState(() => _mode = 'closed'),
            ),
            ChoiceChip(
              key: AccountPolicyCard.modeOpenKey,
              label: Text(l10n.accountPolicyModeOpenLabel),
              selected: _mode == 'open',
              onSelected: _saving
                  ? null
                  : (_) => setState(() => _mode = 'open'),
            ),
            ChoiceChip(
              key: AccountPolicyCard.modeApprovalKey,
              label: Text(l10n.accountPolicyModeApprovalLabel),
              selected: _mode == 'approval',
              onSelected: _saving
                  ? null
                  : (_) => setState(() => _mode = 'approval'),
            ),
            ChoiceChip(
              key: AccountPolicyCard.modeInviteKey,
              label: Text(l10n.accountPolicyModeInviteLabel),
              selected: _mode == 'invite',
              onSelected: _saving
                  ? null
                  : (_) => setState(() => _mode = 'invite'),
            ),
          ],
        ),
        // 選了 approval 就多講一句它真正會做什麼、不會做什麼：這一句是這顆按鈕最容易
        // 被誤讀成「註冊關掉了」的地方，而它實際上是「照常收，但一個也不放行」。
        if (_mode == 'approval')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.accountPolicyApprovalHint,
              key: AccountPolicyCard.approvalHintKey,
              style: theme.textTheme.bodySmall,
            ),
          ),
        // 選了 invite 就講清這一句：只有帶著一枚有效邀請碼的人能自行註冊，換出的是可立即登入
        // 的普通帳戶（與開放模式同一條登入通路）；碼本身不給任何管理權限，發碼由「註冊邀請碼」那張卡管。
        if (_mode == 'invite')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.accountPolicyInviteHint,
              key: AccountPolicyCard.inviteHintKey,
              style: theme.textTheme.bodySmall,
            ),
          ),
        // 現值不是這張卡給得出的名字時如實說出那個名字：不預填、不降級成 closed。
        if (!_isWritableMode) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            l10n.accountPolicyModeExternalNotice(_mode),
            key: AccountPolicyCard.modeExternalKey,
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        _switchRow(
          label: l10n.accountPolicyGuestLabel,
          hint: l10n.accountPolicyGuestHint,
          key: AccountPolicyCard.guestKey,
          value: _guest,
          onChanged: _saving
              ? null
              : (bool value) => setState(() => _guest = value),
        ),
        const SizedBox(height: 12),
        Text(
          policy != null && policy.updatedAt != null
              ? l10n.accountPolicyUpdatedOnLabel(
                  _formatUtcMinute(policy.updatedAt!),
                )
              : l10n.accountPolicyUpdatedNeverLabel,
          key: AccountPolicyCard.updatedKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.accountPolicyEntryLabel(
            _word(l10n, policy?.entry.signUpOpen ?? false),
            _word(l10n, policy?.entry.guestOpen ?? false),
          ),
          key: AccountPolicyCard.entryKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.accountPolicyCapabilityNote,
          key: AccountPolicyCard.capabilityKey,
          style: theme.textTheme.bodySmall,
        ),
        if (_notice != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(_notice!),
        ],
        if (_savedNotice != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _savedNotice!,
            key: AccountPolicyCard.savedKey,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: AccountPolicyCard.submitKey,
            onPressed: _saving ? null : _submit,
            child: Text(l10n.accountPolicySaveAction),
          ),
        ),
      ],
    );
  }

  /// 現值是否是本版本可選的模式之一（判定只依這張卡的選項清單，不另猜一份）。
  ///
  /// 這份清單必須與後端「模式寫得進」的那一側同步：少一個就會做出上面頭注寫的那件壞事
  /// （保存時把服務端記錄的模式頂掉）。日後 invite 落地時，這裡要多一顆 ChoiceChip，
  /// 而那同時也是這張卡唯一需要跟著改的地方。
  bool get _isWritableMode =>
      _mode == 'closed' ||
      _mode == 'open' ||
      _mode == 'approval' ||
      _mode == 'invite';

  /// 布林的另一種說法：界面用詞由 ARB 給，不在這裡寫死「開／關」。
  String _word(AppLocalizations l10n, bool open) {
    return open ? l10n.accountPolicyOpenWord : l10n.accountPolicyClosedWord;
  }

  /// 一個開關：標籤與說明各一行，開關本體靠右（窄欄也不擠壓說明文字）。
  Widget _switchRow({
    required String label,
    required String hint,
    required Key key,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Switch(key: key, value: value, onChanged: onChanged),
          ],
        ),
        Text(hint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// 以「年-月-日 時:分 UTC」呈現，與目錄與詳情卡同一寫法：不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}
