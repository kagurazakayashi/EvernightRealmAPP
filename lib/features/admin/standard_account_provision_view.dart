/// 「管理員建立普通帳戶」的表單卡：一張建立表與它的成功摘要。
///
/// 界線全部落在後端合同上，這裡只做呈現與如實轉述：
///
/// * 誰能建人、此刻准不准建，都由後端判定：這張表只對持有伺服器級管理權的
///   會話生效（普通帳戶與匿名拿到 2011），而「管理員建立普通帳戶」開關關閉時
///   一律 2017——包括 Root。界面不預讀開關（後端也沒有這條讀路）：
///   判定只發生在提交那一刻的交易裡，這裡照實轉述服務端的回話。
/// * 請求本體只有三個欄位（登入名、顯示名、一次性初始口令）：後端的合同裡沒有
///   角色／類型／狀態／活動標識的格子，因此這裡也不放任何這類輸入控件；
///   多帶會被後端打成 1004。
/// * 口令不在本層留下任何痕跡：它只在這一次送交的參數裡存在，不寫進狀態、不顯示、
///   不進日誌與診斷輸出；成功回應裡也沒有它（合同就沒有這個欄位）。
/// * 「已建立」不等於「已加入活動」：成功摘要點名這是帳戶事實，並明說他還沒有
///   任何活動身份與資產——界面不得把建號說成套了活動。
/// * 「查不了」與「被拒」各說各句：連不上、逾時、會話失效、登入名已佔用、
///   欄位不合規、權限不足、策略未開放，是各不相同的句子，不合併成「操作失敗」。
///
/// 結果不明時不得自動補發：2012 收斂重複提交，但「送出後斷線、不知成沒成」的
/// 重發可能換到第二次成功（換了名字）或一個被誤會的衝突——由人看一眼目錄再決定。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 建立的階段性結果（頁面據此轉述，不自行判定）。
enum _SubmitPhase { idle, submitting }

/// 「管理員建立普通帳戶」表單卡。
class StandardAccountProvisionCard extends StatefulWidget {
  /// 以端點介面建立表單卡。
  const StandardAccountProvisionCard({
    super.key,
    required this.api,
    this.onCreated,
  });

  /// 統一端點存取介面（由頁面自 [AppDependencies] 取得後顯式帶入）。
  final ServerApi api;

  /// 建立成功的回呼：頁面據此重讀目錄。
  ///
  /// 這裡只遞「發生了一次成功」這個信號，不遞那份資料——目錄要的是服務端的結果，
  /// 拿回應本體去拼一行會繞過「清單以重讀為準」這條約定。
  final VoidCallback? onCreated;

  /// 登入名輸入框識別鍵。
  static const Key loginNameKey = ValueKey<String>(
    'std-account-provision-login',
  );

  /// 顯示名輸入框識別鍵。
  static const Key displayNameKey = ValueKey<String>(
    'std-account-provision-display',
  );

  /// 初始口令輸入框識別鍵。
  static const Key passwordKey = ValueKey<String>(
    'std-account-provision-password',
  );

  /// 提交按鈕識別鍵。
  static const Key submitKey = ValueKey<String>('std-account-provision-submit');

  /// 失敗或本地校驗提示列識別鍵。
  static const Key noticeKey = ValueKey<String>('std-account-provision-notice');

  /// 建立成功摘要識別鍵。
  static const Key createdKey = ValueKey<String>(
    'std-account-provision-created',
  );

  /// 「尚未加入活動」說明列識別鍵（成功摘要的一部分）。
  static const Key noActivityKey = ValueKey<String>(
    'std-account-provision-no-activity',
  );

  @override
  State<StandardAccountProvisionCard> createState() =>
      _StandardAccountProvisionCardState();
}

class _StandardAccountProvisionCardState
    extends State<StandardAccountProvisionCard> {
  final TextEditingController _loginName = TextEditingController();
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _password = TextEditingController();

  _SubmitPhase _phase = _SubmitPhase.idle;

  /// 一行提示：本地校驗、失敗轉述都用同一條；成功後清空。
  String? _notice;

  /// 最近一次建立成功的結果（可展示事實，不含任何口令）。
  CreatedStandardAccountReport? _created;

  @override
  void dispose() {
    _loginName.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 目前介面語言對應的 Accept-Language 標記。
  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 送交一次建立：本地只擋「明顯沒填」，其餘規則以服務端為準。
  ///
  /// 登入名的正規化與禁字規則屬後端領域（NFKC、大小寫折疊、空白／控制／格式字元），
  /// 前端複製一份必然會漂移；因此這裡只做非空檢查，把不合規的輸入交回去，
  /// 再依 1004 的 `details.invalid_field` 說出差是哪一個欄位。
  Future<void> _submit() async {
    if (_phase == _SubmitPhase.submitting) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String loginName = _loginName.text.trim();
    final String displayName = _displayName.text.trim();
    final String password = _password.text;
    if (loginName.isEmpty || displayName.isEmpty || password.isEmpty) {
      setState(() => _notice = l10n.adminProvisionFormIncompleteNotice);
      return;
    }

    setState(() {
      _phase = _SubmitPhase.submitting;
      _notice = null;
    });
    try {
      final CreatedStandardAccountReport report = await widget.api
          .createStandardAccount(
            loginName: loginName,
            displayName: displayName,
            password: password,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      // 成功後三個欄位一律清空：留著登入名只會讓下一次點按變成「同一個名字再交一次」，
      // 而那會收到 2012；留著口令則等於把一次性憑據多留在記憶體裡一會兒。
      _loginName.clear();
      _displayName.clear();
      _password.clear();
      setState(() {
        _phase = _SubmitPhase.idle;
        _created = report;
      });
      widget.onCreated?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _SubmitPhase.idle;
        _notice = _failureText(l10n, error);
      });
    }
  }

  /// 把一次失敗換成一句話：機器碼優先，其次才是失敗類別。
  ///
  /// 2017（策略未開放）與 2011（權限不足）由 [apiErrorText] 按碼各成一句：
  /// 一個要等 Root 打開開關，另一個換身分也不會變——合併成「沒有權限」是兩句謊話。
  String _failureText(AppLocalizations l10n, ApiError error) {
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'login_name' => l10n.adminProvisionInvalidLoginNameNotice,
        'display_name' => l10n.adminProvisionInvalidDisplayNameNotice,
        'password' => l10n.adminProvisionInvalidPasswordNotice,
        _ => l10n.adminProvisionRejectedNotice,
      };
    }
    return apiErrorText(l10n, error);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final CreatedStandardAccountReport? created = _created;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.stdAccountProvisionTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l10n.stdAccountProvisionPolicyNotice,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.adminProvisionDeliveryNotice,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          key: StandardAccountProvisionCard.loginNameKey,
          controller: _loginName,
          enabled: _phase == _SubmitPhase.idle,
          decoration: InputDecoration(
            labelText: l10n.adminProvisionLoginNameLabel,
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          key: StandardAccountProvisionCard.displayNameKey,
          controller: _displayName,
          enabled: _phase == _SubmitPhase.idle,
          decoration: InputDecoration(
            labelText: l10n.adminProvisionDisplayNameLabel,
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          key: StandardAccountProvisionCard.passwordKey,
          controller: _password,
          enabled: _phase == _SubmitPhase.idle,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.adminProvisionInitialPasswordLabel,
            helperText: l10n.adminProvisionInitialPasswordHint,
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: StandardAccountProvisionCard.submitKey,
            onPressed: _phase == _SubmitPhase.submitting ? null : _submit,
            child: _phase == _SubmitPhase.submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.stdAccountProvisionSubmitAction),
          ),
        ),
        if (_notice != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _notice!,
            key: StandardAccountProvisionCard.noticeKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (created != null) ...<Widget>[
          const SizedBox(height: 12),
          _CreatedSummary(report: created),
        ],
      ],
    );
  }
}

/// 建立成功摘要：只呈現後端回傳的可展示事實，並把「還沒有活動」講在第一線。
class _CreatedSummary extends StatelessWidget {
  const _CreatedSummary({required this.report});

  final CreatedStandardAccountReport report;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Container(
      key: StandardAccountProvisionCard.createdKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            // 「帳戶已建立」是本卡對外的說法：點名的是伺服器回傳的登入名原值。
            l10n.stdAccountProvisionCreatedTitle(report.loginName),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.labelValuePair(
              l10n.adminProvisionDisplayNameLabel,
              report.displayName,
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.labelValuePair(
              l10n.adminListCreatedLabel,
              _formatUtcMinute(report.createdAt),
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.labelValuePair(
              l10n.adminProvisionAccountIdLabel,
              report.accountId,
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            // 旗標取自伺服器回應而不是本地假設：合同上它此刻恆為 true，
            // 但界面只轉述讀到的值，不把自己當成事實來源。
            report.mustChangePassword
                ? l10n.adminProvisionOneTimePasswordReminder
                : l10n.adminProvisionNoPasswordChangeReminder,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.stdAccountProvisionNoActivityNotice,
            key: StandardAccountProvisionCard.noActivityKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 以「年-月-日 時:分 UTC」呈現，與其餘清單同一寫法：不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}
