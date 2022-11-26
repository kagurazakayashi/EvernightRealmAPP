/// 「Root 開設伺服器級管理員」的表單卡：一張開設表與它的成功摘要。
///
/// 界線全部落在後端合同上，這裡只做呈現與如實轉述：
///
/// * 誰能開人由後端判定：這張表只對 Root 的會話生效（普通帳戶與普通管理員拿到 2011）。
///   界面把路由限制在 Root 之下只是為了不誤導，不是把關——真正的把關在服務端。
/// * 請求本體只有三個欄位（登入名、顯示名、一次性初始口令）：後端的合同裡沒有一個
///   可以自報角色或主體類別的格子，因此這裡也不放任何這類輸入控件。
/// * 口令不在本層留下任何痕跡：它只在這一次送交的參數裡存在，不寫進狀態、不顯示、
///   不進日誌與診斷輸出；成功回應裡也沒有它（合同就沒有這個欄位）。
/// * 「查不了」與「被拒」各說各句：連不上、逾時、會話失效、登入名已佔用、
///   欄位不合規、權限不足，是六句不同的話，不合併成一句「操作失敗」。
///
/// 開設後的核實與改名在另一張卡（見 admin_directory_view.dart 的目錄與詳情）：
/// 本檔不再自帶「最小確認清單」——目錄本身就是它的那份清單。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 開設表单的階段性結果（頁面據此轉述，不自行判定）。
enum _SubmitPhase { idle, submitting }

/// 「Root 開設管理員」表单卡。
class AdminProvisionCard extends StatefulWidget {
  /// 以端點介面建立表单卡；[onCreated] 在開設成功後被呼叫一次。
  const AdminProvisionCard({super.key, required this.api, this.onCreated});

  /// 統一端點存取介面（由頁面自 [AppDependencies] 取得後顯式帶入）。
  final ServerApi api;

  /// 開設成功後的回呼：讓同一頁的目錄重新讀一次（新授予排在第一頁最前）。
  final VoidCallback? onCreated;

  /// 登入名輸入框識別鍵。
  static const Key loginNameKey = ValueKey<String>('admin-provision-login');

  /// 顯示名輸入框識別鍵。
  static const Key displayNameKey = ValueKey<String>('admin-provision-display');

  /// 初始口令輸入框識別鍵。
  static const Key passwordKey = ValueKey<String>('admin-provision-password');

  /// 提交按鈕識別鍵。
  static const Key submitKey = ValueKey<String>('admin-provision-submit');

  /// 失敗或本地校驗提示列識別鍵。
  static const Key noticeKey = ValueKey<String>('admin-provision-notice');

  /// 開設成功摘要識別鍵。
  static const Key createdKey = ValueKey<String>('admin-provision-created');

  @override
  State<AdminProvisionCard> createState() => _AdminProvisionCardState();
}

class _AdminProvisionCardState extends State<AdminProvisionCard> {
  final TextEditingController _loginName = TextEditingController();
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _password = TextEditingController();

  _SubmitPhase _phase = _SubmitPhase.idle;

  /// 一行提示：本地校驗、失敗轉述都用同一條；成功後清空。
  String? _notice;

  /// 最近一次開設成功的結果（可展示事實，不含任何口令）。
  CreatedAdminReport? _created;

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

  /// 送交一次開設：本地只擋「明顯沒填」，其餘規則以服務端為準。
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
      final CreatedAdminReport report = await widget.api.createAdmin(
        loginName: loginName,
        displayName: displayName,
        password: password,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      // 成功後三個欄位一律清空：留著登入名只會讓下一次點按變成「同一個名字再交一次」，
      // 而那會收到 2012；留著口令則等於把一次性憑據多留在記憶體裡一会儿。
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
  /// 初始口令不對嗎？它沒有「現值」可比——後端只在 Root 交入口令後做派生，
  /// 因此這裡不可能出现「口令錯誤」这一类结论，出現了也是 1004（形狀不合規）。
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
    final CreatedAdminReport? created = _created;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.adminProvisionDeliveryNotice,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          key: AdminProvisionCard.loginNameKey,
          controller: _loginName,
          enabled: _phase == _SubmitPhase.idle,
          decoration: InputDecoration(
            labelText: l10n.adminProvisionLoginNameLabel,
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          key: AdminProvisionCard.displayNameKey,
          controller: _displayName,
          enabled: _phase == _SubmitPhase.idle,
          decoration: InputDecoration(
            labelText: l10n.adminProvisionDisplayNameLabel,
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          key: AdminProvisionCard.passwordKey,
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
            key: AdminProvisionCard.submitKey,
            onPressed: _phase == _SubmitPhase.submitting ? null : _submit,
            child: _phase == _SubmitPhase.submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.adminProvisionSubmitAction),
          ),
        ),
        if (_notice != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _notice!,
            key: AdminProvisionCard.noticeKey,
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

/// 開設成功摘要：只呈現後端回傳的可展示事實。
class _CreatedSummary extends StatelessWidget {
  const _CreatedSummary({required this.report});

  final CreatedAdminReport report;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Container(
      key: AdminProvisionCard.createdKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.adminProvisionCreatedTitle(report.loginName),
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
        ],
      ),
    );
  }
}

/// 以「年-月-日 時:分 UTC」呈現，與裝置清單同一寫法：不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}
