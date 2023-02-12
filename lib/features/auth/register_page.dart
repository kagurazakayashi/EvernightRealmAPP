/// 匿名自註冊頁：把「自己選一個口令、換一個普通帳戶」這件事送交此刻生效的那臺伺服器。
///
/// 這一頁只走後端已發布的一條端點（`POST /auth/register`），它是登入前入口能力
/// （`sign_up_open`）放開後才在入口層出現的通路；能不能建由後端在寫入那一刻現讀策略
/// 並校驗生效模式決定——界面不預讀、也預讀不到那筆結論（入口能力只決定「要不要顯示這扇門」，
/// 從不代替提交時的二次判定）。開關關閉、模式尚未落地、名字被佔用、寫法不合規、來源被限流
/// 各自回不同的機器碼，這一頁照實轉述，不把它們合併成一句「註冊失敗」。
///
/// 提交成功後講的是伺服器回傳的那個 `status`，不是這一頁的假設：
/// * `active`——開放自註冊的既定語意，口令是本人自選的，現在就能去登入；
/// * `pending`——這臺伺服器要管理員先批准。摘要因此改口為「申請已提交，尚未獲准登入」，
///   不再擺「前往登入」那顆按鈕（按下去只會換來一句「憑據無效」），改成導向本人的申請
///   狀態查詢頁。界面不知道、也不該猜生效模式是哪一個：匿名入口從不透露模式名字，
///   「可用還是等待」這句話只有寫入那一刻的伺服器有資格說。
/// * 其他值（合同日後多出來的狀態）——不猜成可用、也不猜成等待，如實說認不得。
///
/// 呈現上守住的幾條界線：
/// * 請求本體只有登入名、顯示名與自選口令三個欄位：後端合同裡沒有角色／類型／狀態／活動
///   標識的格子，這一頁因此也不放任何這類控件；把自己「註冊成管理員」在協定層就沒有一個
///   可以填的地方（多帶即 1004）。
/// * 口令不在本層留下任何痕跡：只在這一次送交的參數裡存在，不寫進狀態、不顯示、不進日誌；
///   成功後三個欄位一律清空。回應本體也不含口令（合同就沒有這個欄位）。
/// * 自註冊建的按定義是普通帳戶：不帶任何伺服器級授予、沒有活動身份與資產。「已建立」
///   不等於「已加入活動」，成功摘要把這件事講在第一線。
/// * 註冊成功刻意不簽發會話：這一頁既不寫 Cookie 也不保存令牌，登入仍走 `/auth/login`
///   那條既有認證邊界——包括待審批在內，這一頁不複製第二套憑據分發，
///   只把人送進目錄並交出對應的下一步（去登入，或去查本人的申請狀態）。
///
/// 內容為不滾動的 Column：垂直滾動由應用殼統一承擔。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../app/app_dependencies.dart';
import '../../app/app_router.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 提交的階段性結果（頁面據此停用按鈕，同一時間只准有一趟請求）。
enum _SubmitPhase { idle, submitting }

/// 匿名自註冊頁。
class RegisterPage extends StatefulWidget {
  /// 建立頁面。
  const RegisterPage({super.key});

  /// 登入名輸入框的測試識別鍵。
  static const Key loginNameKey = ValueKey<String>('register-login');

  /// 顯示名輸入框的測試識別鍵。
  static const Key displayNameKey = ValueKey<String>('register-display');

  /// 口令輸入框的測試識別鍵。
  static const Key passwordKey = ValueKey<String>('register-password');

  /// 提交按鈕的測試識別鍵。
  static const Key submitKey = ValueKey<String>('register-submit');

  /// 失敗或本地校驗提示列的測試識別鍵。
  static const Key noticeKey = ValueKey<String>('register-notice');

  /// 註冊成功摘要的測試識別鍵。
  static const Key createdKey = ValueKey<String>('register-created');

  /// 「前往登入」按鈕的測試識別鍵。
  static const Key goSignInKey = ValueKey<String>('register-go-signin');

  /// 「查詢我的申請狀態」按鈕的測試識別鍵（待審批那一支摘要唯一的那顆寫入後導航按鈕）。
  static const Key checkStatusKey = ValueKey<String>('register-check-status');

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _loginName = TextEditingController();
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _password = TextEditingController();

  _SubmitPhase _phase = _SubmitPhase.idle;

  /// 一行提示：本地校驗與失敗轉述共用同一條；成功後清空。
  String? _notice;

  /// 最近一次註冊成功的結果（可展示事實，不含任何口令）。
  SelfRegisterReport? _created;

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

  /// 送交一次自註冊：本地只擋「明顯沒填」，其餘規則以服務端為準。
  ///
  /// 登入名的正規化與禁字、口令強度都屬後端領域（NFKC、大小寫折疊、控制字元、Argon2id
  /// 前置的形狀閘），前端複製一份必然漂移；因此這裡只做非空檢查，把不合規的輸入交回去，
  /// 再依 1004 的 `details.invalid_field` 說出差在哪一個欄位。准入、重名、限流的結論
  /// 全部來自伺服器對這次提交的回話，界面不自備一份判定。
  Future<void> _submit() async {
    if (_phase == _SubmitPhase.submitting) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String loginName = _loginName.text.trim();
    final String displayName = _displayName.text.trim();
    final String password = _password.text;
    if (loginName.isEmpty || displayName.isEmpty || password.isEmpty) {
      setState(() => _notice = l10n.registerFormIncompleteNotice);
      return;
    }

    setState(() {
      _phase = _SubmitPhase.submitting;
      _notice = null;
    });
    try {
      final SelfRegisterReport report = await AppScope.of(context).api.register(
        loginName: loginName,
        displayName: displayName,
        password: password,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      // 成功後三個欄位一律清空：留著口令等於把自選憑據多留在記憶體裡一會兒，
      // 留著登入名只會讓「再點一次」變成拿同一個名字撞第二次（2019）。
      _loginName.clear();
      _displayName.clear();
      _password.clear();
      setState(() {
        _phase = _SubmitPhase.idle;
        _created = report;
      });
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

  /// 把一次失敗換成一句話：寫法不合規按點名的欄位各成一句，其餘交給機器碼映射。
  ///
  /// 2019（名字被佔用）、2017（策略未開放）、2016（模式未落地）、2006（來源被限流）
  /// 由 [apiErrorText] 按碼各唸一句——它們的處置互不相同（換名字、等 Root 打開、等通路
  /// 上線、等一會兒），合併成「註冊失敗」會把人推去做一件註定無效的事。
  String _failureText(AppLocalizations l10n, ApiError error) {
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'login_name' => l10n.registerInvalidLoginNameNotice,
        'display_name' => l10n.registerInvalidDisplayNameNotice,
        'password' => l10n.registerInvalidPasswordNotice,
        _ => l10n.registerFormIncompleteNotice,
      };
    }
    return apiErrorText(l10n, error);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final SelfRegisterReport? created = _created;
    final bool submitting = _phase == _SubmitPhase.submitting;
    final bool addressAvailable =
        AppScope.of(context).api.config.address != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(l10n.registerSummary, style: theme.textTheme.bodySmall),
        ),
        if (created == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  key: RegisterPage.loginNameKey,
                  controller: _loginName,
                  enabled: !submitting,
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.registerLoginNameLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: RegisterPage.displayNameKey,
                  controller: _displayName,
                  enabled: !submitting,
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.registerDisplayNameLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: RegisterPage.passwordKey,
                  controller: _password,
                  enabled: !submitting,
                  obscureText: true,
                  maxLines: 1,
                  autofillHints: const <String>[AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: l10n.registerPasswordLabel,
                    helperText: l10n.registerPasswordHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: FilledButton(
                    key: RegisterPage.submitKey,
                    // 進行中一律停用：防連點產生第二次註冊（第二次多半只換到 2019）。
                    // 沒有位址時也不給按：沒有伺服器就談不上建立。
                    onPressed: submitting || !addressAvailable ? null : _submit,
                    child: submitting
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(child: Text(l10n.registerSubmitting)),
                            ],
                          )
                        : Text(l10n.registerSubmitAction),
                  ),
                ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _notice!,
                      key: RegisterPage.noticeKey,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _CreatedSummary(
              report: created,
              onGoSignIn: () => Navigator.of(context).pushNamed(kLoginRoute),
              onCheckStatus: () =>
                  Navigator.of(context).pushNamed(kApplicationStatusRoute),
            ),
          ),
      ],
    );
  }
}

/// 註冊／提交成功摘要：點名伺服器回傳的事實，先把「能不能登入」講在第一線。
///
/// 這張卡講哪一句，依據只有一個：回應裡的 `status`。界面不預讀模式、也不猜——
/// `active` 說「現在就能用這組口令登入」，`pending` 說「申請已提交、尚未獲准登入」，
/// 其餘值（合同日後多出來的狀態）如實說認不得。兩種情況下「還沒有活動身份與資產」都成立，
/// 所以那句照常留著：已建立、甚至已批准，都不等於被誰邀請進某個活動。
class _CreatedSummary extends StatelessWidget {
  /// 以成功結果與兩條導航回呼建立。
  const _CreatedSummary({
    required this.report,
    required this.onGoSignIn,
    required this.onCheckStatus,
  });

  /// 自註冊成功回應裡的可展示事實。
  final SelfRegisterReport report;

  /// 按下「前往登入」的回呼：走既有 `/auth/login` 通路，這一頁不簽發任何會話。
  final VoidCallback onGoSignIn;

  /// 按下「查詢我的申請狀態」的回呼：通往本人的受限狀態通路（每次都重新驗憑據）。
  final VoidCallback onCheckStatus;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    // 三種結局各自成句；判定的輸入是伺服器回傳的原字串，不是本地假設。
    final bool pending = report.status == 'pending';
    final bool known = pending || report.status == 'active';
    final TextStyle? noteStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Container(
      key: RegisterPage.createdKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            // 標題點名的是伺服器回傳的登入名原值；待審批時說的是「申請已提交」。
            pending
                ? l10n.registerPendingTitle(report.loginName)
                : l10n.registerCreatedTitle(report.loginName),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.labelValuePair(
              l10n.registerDisplayNameLabel,
              report.displayName,
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.labelValuePair(
              // 同一個時刻，兩種說法：open 時它是「建立於」，approval 時它是「提交於」。
              pending
                  ? l10n.applicationStatusSubmittedLabel
                  : l10n.adminListCreatedLabel,
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
          // 第一句永遠是「你現在能不能進去」，其次才是「你還欠什麼」。
          if (pending)
            Text(l10n.registerPendingNote, style: noteStyle)
          else if (!known)
            Text(l10n.applicationStatusUnknownNote, style: noteStyle)
          else
            Text(
              // 旗標取自伺服器回應而不是本地假設：自註冊由本人自選口令，合同上恆為 false，
              // 界面仍只轉述讀到的值。真出現預期外的 true（未來的其他通路），也講誠實的那一句。
              report.mustChangePassword
                  ? l10n.adminProvisionOneTimePasswordReminder
                  : l10n.registerUsableNowNote,
              style: noteStyle,
            ),
          const SizedBox(height: 4),
          Text(l10n.registerNoActivityNotice, style: noteStyle),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: FilledButton(
              // 待審批的人不擺「前往登入」：按下去只換來一句「憑據無效」，
              // 那是一條注定失敗的路。要給的出口是查本人的申請狀態。
              key: pending
                  ? RegisterPage.checkStatusKey
                  : RegisterPage.goSignInKey,
              onPressed: pending ? onCheckStatus : onGoSignIn,
              child: Text(
                pending
                    ? l10n.registerCheckStatusAction
                    : l10n.registerGoSignInAction,
              ),
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
