/// 標準登入頁：把憑據交給「此刻生效的那一台伺服器」，並把結果如實分成幾種狀態。
///
/// 這一頁只走後端已發布的兩條登入端點（普通帳戶 `/auth/login`、Root
/// `/auth/root/login`），端點分流由伺服器承擔：表單上的方式選擇只決定打哪條路，
/// 不參與任何權限判定——成功後的身分一律取自伺服器回應（經 [SessionController]
/// 落地），本地從沒有一個可以「自報成 Root」的欄位。
///
/// 呈現上守住的幾條界線：
/// * 頁面頂部先講清楚「這次要登入的是哪台伺服器」：換了位址卻對著舊印象
///   輸入口令，是局域网多服務部署最容易吃虧的地方。
/// * 提交進行中按鈕停用且同一時間只准一趟請求：連點不會產生第二次登入，
///   也就不會把限流計數無故推向冷卻。
/// * 失敗文案取自機器碼的本地化映射（口令不符 2001、被限流 2006、連不上等），
///   不轉述伺服器原文、不回顯任何憑據；「查無此人」與「口令不符」外部同句，
///   這一頁也无從把它們分開。
/// * 本機不保存、不預填任何口令；會話秘密的去向只有會話層批准的安全儲存。
///
/// 內容為不滾動的 Column：垂直滾動由應用殼統一承擔。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../app/app_dependencies.dart';
import '../../app/app_router.dart';
import '../../app/connection_phase_labels.dart';
import '../../app/connection_scope.dart';
import '../../app/session_scope.dart';
import '../../core/api/api_error.dart';
import '../../core/api/connection_tracker.dart';
import '../../core/api/server_address.dart';
import '../../core/api/server_api.dart';
import '../../core/app_locale.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';

/// 表單上要打的登入端點。這是「送哪個端點」的選擇，不是身分宣稱。
enum _LoginMode {
  /// 普通帳戶：送 `/auth/login`，帶登入名與口令。
  account,

  /// Root：送 `/auth/root/login`，只帶口令。
  root,
}

/// 標準登入頁。
class LoginPage extends StatefulWidget {
  /// 建立頁面。
  const LoginPage({super.key});

  /// 登入方式切換的測試識別鍵。
  static const Key modeKey = ValueKey<String>('login-mode');

  /// 登入名輸入框的測試識別鍵。
  static const Key loginNameKey = ValueKey<String>('login-name');

  /// 口令輸入框的測試識別鍵。
  static const Key passwordKey = ValueKey<String>('login-password');

  /// 提交按鈕的測試識別鍵。
  static const Key submitKey = ValueKey<String>('login-submit');

  /// 失敗提示行的測試識別鍵。
  static const Key errorKey = ValueKey<String>('login-error');

  /// 伺服器資訊行的測試識別鍵。
  static const Key serverInfoKey = ValueKey<String>('login-server-info');

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  _LoginMode _mode = _LoginMode.root;

  final TextEditingController _loginName = TextEditingController();
  final TextEditingController _password = TextEditingController();

  /// 進行中的登入趟次；同一時間只准有一趟，重複點擊沿用同一個結果。
  Future<void>? _inFlight;

  /// 最近一次失敗的結構化原因（來自端點判定）。
  ApiError? _lastError;

  /// 失敗提示的另一個來源：本地攔截（欄位為空）或秘密落地異常的一句話。
  String? _localNote;

  /// 提交成功但秘密未能回傳／保存時的補充說明標記（取得 ARB 文字後顯示）。
  bool _missingCredential = false;

  @override
  void dispose() {
    _loginName.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 按一次提交：起點先做本地攔截，其後整趟走真實端點與會話層。
  Future<void> _submit() {
    final Future<void>? running = _inFlight;
    if (running != null) {
      return running;
    }
    late final Future<void> task;
    task = _runSubmit().whenComplete(() {
      if (identical(_inFlight, task)) {
        _inFlight = null;
      }
    });
    _inFlight = task;
    return task;
  }

  /// 實際提交：失敗一律收斂成提示，不向上拋——這一頁沒有任何「半成功」出口。
  Future<void> _runSubmit() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ServerApi api = AppScope.of(context).api;
    final SessionController session = SessionScope.of(context);

    final String password = _password.text;
    if (password.isEmpty) {
      setState(() {
        _lastError = null;
        _missingCredential = false;
        _localNote = l10n.loginPasswordRequired;
      });
      return;
    }
    final String loginName = _loginName.text.trim();
    if (_mode == _LoginMode.account && loginName.isEmpty) {
      setState(() {
        _lastError = null;
        _missingCredential = false;
        _localNote = l10n.loginLoginNameRequired;
      });
      return;
    }

    // 問的是哪台伺服器，事後就要用哪台來綁定：以本趟實際打去的位址為準。
    final ServerAddress? asked = api.config.address;
    if (asked == null) {
      setState(() {
        _lastError = ApiError(
          kind: ApiErrorKind.notConfigured,
          path: _mode == _LoginMode.root ? kAuthRootLoginPath : kAuthLoginPath,
        );
        _missingCredential = false;
        _localNote = null;
      });
      return;
    }

    final AppLocale locale = resolveAppLocale(Localizations.localeOf(context));
    setState(() {
      _lastError = null;
      _localNote = null;
      _missingCredential = false;
    });

    LoginExchange exchange;
    try {
      exchange = switch (_mode) {
        _LoginMode.root => await api.rootLogin(
          password: password,
          acceptLanguage: locale.tag,
        ),
        _LoginMode.account => await api.login(
          loginName: loginName,
          password: password,
          acceptLanguage: locale.tag,
        ),
      };
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastError = error;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    if (api.addressDisplay != asked.displayText) {
      // 位址在請求飛行中被換掉：這筆回應描述的是另一台伺服器，如實丟棄，
      // 不拿甲伺服器的登入結果去綁乙伺服器。
      setState(() {
        _localNote = l10n.sessionChangedDuringLoginHint;
      });
      return;
    }

    final SessionLoginOutcome outcome = await session.completeLogin(
      asked,
      exchange,
    );
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case SessionLoginOutcome.established:
      case SessionLoginOutcome.persistenceFailed:
        // persistenceFailed 照常進入：記憶體中的本機會話有效，重開才需重新登入；
        // 「保存不住」那一句由入口頁的會話卡據 lastStorageFailure 如實呈現。
        _goAfterSuccess(session);
      case SessionLoginOutcome.missingCredential:
        setState(() {
          _missingCredential = true;
        });
    }
  }

  /// 成功後的去處：只認帶過來的合法返回路由，其餘一律回入口層。
  ///
  /// 返回目標必須同時過兩道閘——在受保護清單內、且「伺服器確認過的身分」
  /// 允許開啟。任何一道不過就回入口層：那裡只會出現真實身分與已完成的入口。
  void _goAfterSuccess(SessionController session) {
    final NavigatorState navigator = Navigator.of(context);
    final String? returnRoute = AppRouter.parseReturnRoute(
      ModalRoute.of(context)?.settings.arguments,
    );
    if (returnRoute != null &&
        AppRouter.identityAllows(returnRoute, session.activeSession)) {
      navigator.pushNamedAndRemoveUntil(
        returnRoute,
        (Route<dynamic> route) => route.isFirst,
      );
      return;
    }
    navigator.popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ServerApi api = AppScope.of(context).api;
    final ConnectionTracker tracker = ConnectionScope.of(context);
    final bool submitting = _inFlight != null;
    final bool addressAvailable = api.config.address != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _ServerInfoCard(l10n: l10n, tracker: tracker),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.loginSummary, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                Text(l10n.loginModeLabel, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<_LoginMode>(
                    key: LoginPage.modeKey,
                    segments: <ButtonSegment<_LoginMode>>[
                      ButtonSegment<_LoginMode>(
                        value: _LoginMode.root,
                        label: Text(l10n.loginModeRoot),
                      ),
                      ButtonSegment<_LoginMode>(
                        value: _LoginMode.account,
                        label: Text(l10n.loginModeAccount),
                      ),
                    ],
                    selected: <_LoginMode>{_mode},
                    showSelectedIcon: false,
                    onSelectionChanged: submitting
                        ? null
                        : (Set<_LoginMode> selection) {
                            setState(() {
                              _mode = selection.first;
                              _lastError = null;
                              _localNote = null;
                              _missingCredential = false;
                            });
                          },
                  ),
                ),
                if (_mode == _LoginMode.account)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.loginAccountNote,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (_mode == _LoginMode.account)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      key: LoginPage.loginNameKey,
                      controller: _loginName,
                      enabled: !submitting,
                      maxLines: 1,
                      decoration: InputDecoration(
                        labelText: l10n.loginLoginNameLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextField(
                    key: LoginPage.passwordKey,
                    controller: _password,
                    enabled: !submitting,
                    obscureText: true,
                    maxLines: 1,
                    autofillHints: const <String>[AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: l10n.loginPasswordLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                if (_missingCredential)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.loginMissingCredentialNote,
                      key: LoginPage.errorKey,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else if (_lastError != null || _localNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _localNote ?? apiErrorText(l10n, _lastError!),
                      key: LoginPage.errorKey,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: FilledButton(
                    key: LoginPage.submitKey,
                    // 進行中一律停用：防連點產生第二趟登入請求。
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
                              Flexible(child: Text(l10n.loginSubmitting)),
                            ],
                          )
                        : Text(l10n.loginSubmitAction),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 登入目標那台伺服器的資訊卡：位址一定顯示，服務名與版本只在探測成功時顯示。
///
/// 這裡只陳述「連的是哪台、那台自報了什麼」，不提供修改位址的通路——
/// 位址的權威在入口層的位址卡，這一頁要的就是輸入前那一眼確認。
class _ServerInfoCard extends StatelessWidget {
  /// 以本地化資源與探測追蹤器建立。
  const _ServerInfoCard({required this.l10n, required this.tracker});

  /// 本地化資源。
  final AppLocalizations l10n;

  /// 連線探測狀態。
  final ConnectionTracker tracker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? address = tracker.api.addressDisplay;
    // 探測結果本身已自帶「對哪個位址探的」生命週期：位址一改舊結果即作廢，
    // 所以這裡只信 tracker.result，絕不把舊伺服器的名字掛在新位址下面顯示。
    final ServerProbeResult? probe = tracker.result;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.loginServerInfoTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            l10n.labelValuePair(
              l10n.serverAddressEffectiveLabel,
              address ?? l10n.serverAddressNotSet,
            ),
            key: LoginPage.serverInfoKey,
            style: theme.textTheme.bodyMedium,
          ),
          if (probe != null)
            Text(
              l10n.labelValuePair(
                l10n.serverProbeServiceLabel,
                '${probe.health.service} ${probe.health.version}',
              ),
              style: theme.textTheme.bodySmall,
            )
          else
            Text(
              connectionPhaseLabel(l10n, tracker.phase),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
