/// 本人的待審批申請狀態頁：用申請時的登入名與口令查「我那份申請現在怎麼樣了」。
///
/// 這一頁存在的理由是後端那條受限狀態通路的形態（POST `/auth/registration-status`）：
/// 待審批的人既不能登入，也不該拿到一枚能碰普通業務的憑據，於是他每次想知道結果
/// 都要重新交一次憑據。這一頁因此守著幾條界線：
///
/// * **不是登入，也不冒充登入**：成功只回一張寫著結局的卡片，不寫 Cookie、不保存令牌、
///   不經會話層，畫面其他部分不會因為查到了 `approved` 就變成已登入狀態。
///   要真的進去，仍要本人主動走 `/auth/login` 那條既有認證邊界。
/// * **每次都要重新交憑據**：沒有「上次的結果還留著」這回事——口令在每次送出後一律清空
///   （連失敗也清），刷新與離開都不留下任何可被複用的東西。這比少打一次口令要緊：
///   這條通路唯一的准入依據就是「你此刻持有這組憑據」。
/// * **秘密不進 URL**：只用 POST 本體送兩個欄位；這條路徑在協定層就沒有 GET，
///   查詢字串、瀏覽歷史與複製位址欄都不會出現口令。
/// * **認不得的結果不猜**：合同日後多出一種結局時，這一頁如實說「本版本還不認識」，
///   不會把它當成「還在等」或「已批准」——兩個猜測各自會把人送去一條錯路。
/// * **不洩漏別人的東西**：回應只有申請人自己的結局與兩個時刻；審核人是誰、為什麼被拒、
///   排到第幾位都不在這張卡上（那些屬伺服器內部狀態，其中理由連審批那一步都還沒落地）。
///
/// 失敗各自成句：查無此名、口令不符與訪客帳戶都得到 2001 那一句（與登入同形，
/// 這條通路對「誰的名字存在」不新增信號）；2020 說的是「這組憑據有效，但這一筆不是申請」，
/// 處置是改用登入；2006 要等的是冷卻；1004 點名是哪個欄位寫法不合規。
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

/// 查詢的階段性結果（頁面據此停用按鈕，同一時間只准有一趟請求）。
enum _QueryPhase { idle, querying }

/// 本人申請狀態頁。
class ApplicationStatusPage extends StatefulWidget {
  /// 建立頁面。
  const ApplicationStatusPage({super.key});

  /// 登入名輸入框的測試識別鍵。
  static const Key loginNameKey = ValueKey<String>('application-status-login');

  /// 口令輸入框的測試識別鍵。
  static const Key passwordKey = ValueKey<String>(
    'application-status-password',
  );

  /// 查詢按鈕的測試識別鍵。
  static const Key submitKey = ValueKey<String>('application-status-submit');

  /// 失敗或本地校驗提示列的測試識別鍵。
  static const Key noticeKey = ValueKey<String>('application-status-notice');

  /// 查詢結果卡的測試識別鍵。
  static const Key resultKey = ValueKey<String>('application-status-result');

  /// 結果卡上的「前往登入」按鈕測試識別鍵（只在已批准時出現）。
  static const Key goSignInKey = ValueKey<String>('application-status-signin');

  @override
  State<ApplicationStatusPage> createState() => _ApplicationStatusPageState();
}

class _ApplicationStatusPageState extends State<ApplicationStatusPage> {
  final TextEditingController _loginName = TextEditingController();
  final TextEditingController _password = TextEditingController();

  _QueryPhase _phase = _QueryPhase.idle;

  /// 一行提示：本地校驗與失敗轉述共用同一條；成功後清空。
  String? _notice;

  /// 最近一次查到的結果（可展示事實，不含任何憑據）。
  ApplicationStatusReport? _result;

  @override
  void dispose() {
    _loginName.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 目前介面語言對應的 Accept-Language 標記。
  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 送交一次查詢：本地只擋「明顯沒填」，憑據能不能成立完全由伺服器說。
  ///
  /// 登入名的正規化（NFKC、大小寫折疊）與口令形狀界線都屬後端領域，前端複製一份必然漂移；
  /// 因此這裡只做非空檢查，其餘交回去，再依 1004 的 `details.invalid_field` 說差在哪一欄。
  ///
  /// 口令一律在請求發出前就從控制器裡清掉：它只活在這一次調用的參數裡，
  /// 成功或失敗都不回填。這一頁不設「再查一次」的捷徑復用舊值——那等於把憑據留成一份狀態。
  Future<void> _query() async {
    if (_phase == _QueryPhase.querying) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String loginName = _loginName.text.trim();
    final String password = _password.text;
    if (loginName.isEmpty || password.isEmpty) {
      setState(() => _notice = l10n.applicationStatusIncompleteNotice);
      return;
    }

    setState(() {
      _phase = _QueryPhase.querying;
      _notice = null;
    });
    _password.clear();
    try {
      final ApplicationStatusReport report = await AppScope.of(context).api
          .applicationStatus(
            loginName: loginName,
            password: password,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _QueryPhase.idle;
        _result = report;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _QueryPhase.idle;
        _result = null;
        _notice = _failureText(l10n, error);
      });
    }
  }

  /// 把一次失敗換成一句話：寫法不合規按點名欄位各成一句，其餘交給機器碼映射。
  ///
  /// 2001（憑據不成立）、2020（不是申請，去登入）、2006（來源冷卻）與連不上、逾時
  /// 各有不同的處置，由 [apiErrorText] 按碼各唸一句；合併成「查詢失敗」會把人推去
  /// 反覆做一件註定無效的事，而那正是這條通路最容易被限流擋住的用法。
  String _failureText(AppLocalizations l10n, ApiError error) {
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'login_name' => l10n.registerInvalidLoginNameNotice,
        _ => l10n.applicationStatusIncompleteNotice,
      };
    }
    return apiErrorText(l10n, error);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool querying = _phase == _QueryPhase.querying;
    final bool addressAvailable =
        AppScope.of(context).api.config.address != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            l10n.applicationStatusSummary,
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: ApplicationStatusPage.loginNameKey,
                controller: _loginName,
                enabled: !querying,
                maxLines: 1,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.applicationStatusLoginNameLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: ApplicationStatusPage.passwordKey,
                controller: _password,
                enabled: !querying,
                obscureText: true,
                maxLines: 1,
                // 這是一次讀取用的憑據，不是要新建的口令：不建議瀏覽器自動填入。
                autofillHints: const <String>[AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _query(),
                decoration: InputDecoration(
                  labelText: l10n.applicationStatusPasswordLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: FilledButton(
                  key: ApplicationStatusPage.submitKey,
                  // 進行中一律停用：防連點產生多趟憑據校驗（第二趟多半只換到 2006）。
                  // 沒有位址時也不給按：沒有伺服器就談不上查詢。
                  onPressed: querying || !addressAvailable ? null : _query,
                  child: querying
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(l10n.applicationStatusQuerying),
                            ),
                          ],
                        )
                      : Text(l10n.applicationStatusQueryAction),
                ),
              ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _notice!,
                    key: ApplicationStatusPage.noticeKey,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_result case final ApplicationStatusReport report)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _ResultCard(
              report: report,
              onGoSignIn: () => Navigator.of(context).pushNamed(kLoginRoute),
            ),
          ),
      ],
    );
  }
}

/// 查詢結果卡：只講申請人自己的三個事實，並把「已批准」導向既有登入通路。
class _ResultCard extends StatelessWidget {
  /// 以查到的結果與「前往登入」回呼建立。
  const _ResultCard({required this.report, required this.onGoSignIn});

  /// 狀態查詢回應裡的可展示事實。
  final ApplicationStatusReport report;

  /// 按下「前往登入」的回呼：批准只給登入資格，這一頁不代為登入。
  final VoidCallback onGoSignIn;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final TextStyle? noteStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // 四種結局各成一句；認不得的值不猜成等待、也不猜成批准。
    final String outcomeText = switch (report.outcome) {
      'pending' => l10n.applicationStatusPendingNote,
      'approved' => l10n.applicationStatusApprovedNote,
      'rejected' => l10n.applicationStatusRejectedNote,
      _ => l10n.applicationStatusUnknownNote,
    };
    final bool approved = report.outcome == 'approved';

    return Container(
      key: ApplicationStatusPage.resultKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.applicationStatusTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            l10n.labelValuePair(
              l10n.applicationStatusSubmittedLabel,
              _formatUtcMinute(report.submittedAt),
            ),
            style: theme.textTheme.bodySmall,
          ),
          // 決定時刻只在「已經有決定」時出現：還沒有人做過決定時不擺一個空值冒充事實。
          if (report.reviewedAt case final DateTime reviewedAt)
            Text(
              l10n.labelValuePair(
                l10n.applicationStatusDecidedLabel,
                _formatUtcMinute(reviewedAt),
              ),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 6),
          Text(outcomeText, style: noteStyle),
          if (approved) ...<Widget>[
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: FilledButton(
                key: ApplicationStatusPage.goSignInKey,
                onPressed: onGoSignIn,
                child: Text(l10n.registerGoSignInAction),
              ),
            ),
          ],
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
