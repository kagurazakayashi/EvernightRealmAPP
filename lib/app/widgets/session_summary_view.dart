/// 入口層的「登入與會話」卡：把會話控制器的事實如實呈現，並只給真實可用的出口。
///
/// 這張卡是啟動後看見自己身分的地方，界線全部由會話層與路由表承擔：
///
/// * 身分列顯示的每一欄都來自伺服器對 `/auth/login` 或 `/auth/session` 的回應，
///   這裡不從本地讀任何「假設的身分」，也不因為表單選過 Root 就宣稱 Root。
/// * 未登入、已失效、查不了、驗證中各說各句：把「查不了」混成「沒登入」會無緣無故
///   把人當外人，混成「已登入」更危險，所以五個狀態一一對應到不同的呈現。
/// * 已登入的主頁只呈現真實身分與「以該身分真的能開啟」的入口：入口按鈕只是
///   導航捷徑，真正的放行判定仍由 SessionGate 依伺服器身分執行——藏按鈕從來
///   不是授權。尚未開發的管理模組由目標頁面自己如實說明，這張卡不替它們背書。
///
/// 內容為不滾動的 Column：垂直滾動由應用殼統一承擔。
library;

import 'package:flutter/material.dart';

import '../../core/api/server_address.dart';
import '../../core/app_locale.dart';
import '../../core/session/session_controller.dart';
import '../../core/session/session_status.dart';
import '../../l10n/app_localizations.dart';
import '../app_dependencies.dart';
import '../app_router.dart';
import '../nav_context.dart';
import '../session_scope.dart';
import 'device_manager_view.dart';
import 'password_change_view.dart';

/// 入口層的會話摘要卡。
class SessionSummaryView extends StatefulWidget {
  /// 建立卡片。
  const SessionSummaryView({super.key});

  /// 「前往登入」按鈕的測試識別鍵。
  static const Key goLoginKey = ValueKey<String>('session-go-login');

  /// 「重新驗證會話」按鈕的測試識別鍵。
  static const Key revalidateKey = ValueKey<String>('session-revalidate');

  /// 狀態結論行的測試識別鍵。
  static const Key statusKey = ValueKey<String>('session-status');

  /// 已登入身分標題行的測試識別鍵。
  static const Key identityKey = ValueKey<String>('session-identity');

  /// 「進入 Root 控制台」按鈕的測試識別鍵。
  static const Key rootConsoleKey = ValueKey<String>('session-root-console');

  /// 「登出」按鈕的測試識別鍵。
  static const Key logoutKey = ValueKey<String>('session-logout');

  /// 「輪換會話秘密」按鈕的測試識別鍵。
  static const Key rotateKey = ValueKey<String>('session-rotate');

  /// 「我的裝置」按鈕的測試識別鍵。
  static const Key deviceManagerKey = ValueKey<String>('session-devices');

  /// 「變更密碼」按鈕的測試識別鍵。
  static const Key passwordChangeKey = ValueKey<String>('session-password');

  /// 強制改密提示行的測試識別鍵。
  static const Key passwordRequiredKey = ValueKey<String>(
    'session-password-required',
  );

  /// 本機儲存異常說明的測試識別鍵。
  static const Key storageNoteKey = ValueKey<String>('session-storage-note');

  @override
  State<SessionSummaryView> createState() => _SessionSummaryViewState();
}

class _SessionSummaryViewState extends State<SessionSummaryView> {
  /// 進行中的重新驗證；同一時間只准有一趟，連點沿用同一個結果。
  Future<void>? _inFlight;

  /// 登出進行中标記：進行中按鈕停用，防連點產生第二趟登出請求。
  bool _signingOut = false;

  /// 輪換進行中標記：進行中按鈕停用並改顯示進行中文案。
  bool _rotating = false;

  Future<void> _revalidate(SessionController session) {
    final Future<void>? running = _inFlight;
    if (running != null) {
      return running;
    }
    late final Future<void> task;
    task = session.restore().whenComplete(() {
      if (identical(_inFlight, task)) {
        _inFlight = null;
      }
    });
    _inFlight = task;
    return task;
  }

  /// 一次登出：先讓控制器向伺服器請求撤銷，再依結果分類提示。
  ///
  /// 界線全部交給 [SessionController.signOut] 承擔；這一層只做三件事：
  /// * 進行中停用（連點不會產生第二趟撤銷，也不會在冪等端點上刷出多筆審計）；
  /// * 依 [SessionSignOutOutcome] 決定提示那一句——撤銷確認與「本機已清理但
  ///   伺服器未確認」兩句分開，後者絕不能滑向「所有設備已下線」；
  /// * 提示經 [ScaffoldMessenger] 送達：登出後卡片本身會被換成未登入態，
  ///   SnackBar 才能講完那半句「本機已清理、伺服器未確認」的話。
  Future<void> _signOut(SessionController session) async {
    if (_signingOut) {
      return;
    }
    setState(() => _signingOut = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppLocale locale = resolveAppLocale(Localizations.localeOf(context));
    final SessionSignOutOutcome outcome = await session.signOut(
      acceptLanguage: locale.tag,
    );
    if (!mounted) {
      return;
    }
    setState(() => _signingOut = false);
    final String notice = outcome == SessionSignOutOutcome.revoked
        ? l10n.sessionSignOutSuccessNotice
        : l10n.sessionSignOutUnconfirmedNotice;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
  }

  /// 一次輪換：請控制器向伺服器換發新秘密，再依結果分類提示。
  ///
  /// 界線全部交給 [SessionController.rotate] 承擔；這一層只做三件事：
  /// * 進行中停用並改顯示進行中文案（控制器本身也已把併發呼叫合併到同一趟）；
  /// * 依 [SessionRotationOutcome] 決定彈哪一句——成功、倒序丟棄、存不住、被拒、
  ///   沒發生、結果不明各有自己的話，不把它們一律說成失敗或成功；
  /// * 提示經 [ScaffoldMessenger] 送達：被拒時卡片會換成失效態，SnackBar 才能
  ///   把那句「請重新登入」講完。
  Future<void> _rotate(SessionController session) async {
    if (_rotating) {
      return;
    }
    setState(() => _rotating = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppLocale locale = resolveAppLocale(Localizations.localeOf(context));
    final SessionRotationOutcome outcome = await session.rotate(
      acceptLanguage: locale.tag,
    );
    if (!mounted) {
      return;
    }
    setState(() => _rotating = false);
    final String? notice = _rotationNotice(l10n, outcome);
    if (notice != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  /// 把輪換結果對應到一句提示；沒有話可講時回 `null`（不彈空 SnackBar）。
  String? _rotationNotice(
    AppLocalizations l10n,
    SessionRotationOutcome outcome,
  ) {
    return switch (outcome) {
      SessionRotationOutcome.rotated => l10n.sessionRotateSuccessNotice,
      SessionRotationOutcome.superseded => l10n.sessionRotateSupersededNotice,
      SessionRotationOutcome.persistenceFailed =>
        l10n.sessionRotatePersistenceFailedNotice,
      // 「拿不到新秘密」與「被伺服器拒絕」對使用者的處置同一個：重新登入。
      SessionRotationOutcome.rejected ||
      SessionRotationOutcome.missingCredential =>
        l10n.sessionRotateRejectedNotice,
      SessionRotationOutcome.noEffect => l10n.sessionRotateNoEffectNotice,
      SessionRotationOutcome.unconfirmed => l10n.sessionRotateUnconfirmedNotice,
      // 未登入根本看不到這顆按鈕；真的走到這裡也沒有可以說給人聽的話。
      SessionRotationOutcome.notSignedIn => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final SessionController session = SessionScope.of(context);
    final ServerAddress? address = AppScope.of(context).api.config.address;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.sessionCardTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          ..._body(l10n, theme, session, address),
        ],
      ),
    );
  }

  /// 依會話狀態給出那一段呈現；每個 case 只講自己那一句。
  List<Widget> _body(
    AppLocalizations l10n,
    ThemeData theme,
    SessionController session,
    ServerAddress? address,
  ) {
    // 「位址不可用」優先於狀態：沒有伺服器可就談不上會話，也不該顯示登入按鈕。
    // 已登入是唯一例外——那塊身分卡描述的是綁定過的那台伺服器，照實顯示。
    if (address == null && !session.isSignedIn) {
      return <Widget>[
        Text(
          l10n.sessionNotConfiguredHint,
          key: SessionSummaryView.statusKey,
          style: theme.textTheme.bodySmall,
        ),
      ];
    }

    switch (session.status) {
      case SessionStatus.signedIn:
        return _signedInBody(l10n, theme, session);
      case SessionStatus.verifying:
        return <Widget>[
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.sessionVerifyingHint,
                  key: SessionSummaryView.statusKey,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ];
      case SessionStatus.signedOut:
        return <Widget>[
          Text(
            l10n.sessionSignedOutHint,
            key: SessionSummaryView.statusKey,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          const _GoLoginButton(),
        ];
      case SessionStatus.expired:
        // 與未登入分開講：曾經登入過但伺服器已判定無效，處置是重新登入，
        // 這句提示也是「失效返回登入」那條路徑留下的可理解痕跡。
        return <Widget>[
          Text(
            l10n.sessionExpiredNotice,
            key: SessionSummaryView.statusKey,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          const _GoLoginButton(),
        ];
      case SessionStatus.unknown:
        final List<Widget> widgets = <Widget>[
          Text(
            l10n.sessionUnknownHint,
            key: SessionSummaryView.statusKey,
            style: theme.textTheme.bodyMedium,
          ),
        ];
        if (session.lastStorageFailure != null) {
          widgets.add(
            Text(
              l10n.sessionStorageFailureNote,
              key: SessionSummaryView.storageNoteKey,
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        // 未知不是「沒登入」：給再驗證（重新問一次）與直接換憑據登入兩條路，
        // 由人決定節奏，卡片自己不輪詢。
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: SessionSummaryView.revalidateKey,
                  onPressed: () => _revalidate(session),
                  child: Text(l10n.sessionRevalidateAction),
                ),
                const _GoLoginButton(),
              ],
            ),
          ),
        );
        return widgets;
    }
  }

  /// 已登入：身分列全部取自伺服器回應，入口只給該身分真的能開的那一個。
  List<Widget> _signedInBody(
    AppLocalizations l10n,
    ThemeData theme,
    SessionController session,
  ) {
    final ActiveSession? active = session.activeSession;
    if (active == null) {
      // 狀態說已登入卻沒有主體事實：這是內部矛盾，寧可如實停住也不猜。
      return <Widget>[
        Text(
          l10n.sessionUnknownHint,
          key: SessionSummaryView.statusKey,
          style: theme.textTheme.bodyMedium,
        ),
      ];
    }

    final List<Widget> rows = <Widget>[
      Text(
        l10n.sessionIdentityTitle,
        key: SessionSummaryView.identityKey,
        style: theme.textTheme.bodyMedium,
      ),
      Text(
        l10n.labelValuePair(
          l10n.statusServerLabel,
          session.boundServerDisplay ?? l10n.valueNotProvided,
        ),
        style: theme.textTheme.bodySmall,
      ),
      Text(
        l10n.labelValuePair(
          l10n.sessionSubjectLabel,
          active.isRoot ? l10n.sessionSubjectRoot : l10n.sessionSubjectAccount,
        ),
        style: theme.textTheme.bodySmall,
      ),
      if (!active.isRoot)
        Text(
          l10n.labelValuePair(
            l10n.sessionAccountIdLabel,
            active.accountId ?? l10n.valueNotProvided,
          ),
          style: theme.textTheme.bodySmall,
        ),
      Text(
        l10n.labelValuePair(l10n.sessionDeviceLabel, active.deviceId),
        style: theme.textTheme.bodySmall,
      ),
      Text(
        l10n.labelValuePair(
          l10n.sessionExpiresLabel,
          _formatUtcMinute(active.expiresAt),
        ),
        style: theme.textTheme.bodySmall,
      ),
    ];

    if (session.lastStorageFailure != null) {
      rows.add(
        Text(
          l10n.sessionStorageFailureNote,
          key: SessionSummaryView.storageNoteKey,
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    // 入口只依「伺服器確認過的身分」出現；按下去仍要過 SessionGate 的判定。
    // 欠改密的帳戶例外：受保護功能在服務端本來就被 2010 擋著，這裡不呈現
    // 一個注定被拒的入口——門在後端，界面只負責不撒謊。
    if (!session.mustChangePassword &&
        AppRouter.identityAllows(NavContext.rootConsole.routeName, active)) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 40,
            child: FilledButton(
              key: SessionSummaryView.rootConsoleKey,
              onPressed: () =>
                  Navigator.of(context)
                      .pushNamed(NavContext.rootConsole.routeName),
              child: Text(l10n.sessionRootConsoleAction),
            ),
          ),
        ),
      );
    }

    // 強制改密態：把伺服器現讀的旗標原樣呈現，並只留「變更密碼」與「登出」
    // 兩組必要入口。真正的把關在後端（受保護端點回 2010），這裡不呈現
    // 一個注定被拒的入口，也不把「還欠改密」說成一句可忽略的提示。
    if (session.mustChangePassword) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l10n.passwordChangeRequiredNotice,
            key: SessionSummaryView.passwordRequiredKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }

    // 登出入口：已登入態一律呈現，不區分 Root／帳戶——只要有一份綁定的會話，
    // 就需要一個「讓這一份失效」的出口。進行中停用：連點不會產生第二趟撤銷，
    // 也不會把冪等端點刷成多筆審計寫入。
    // 這一層不寫任何「已登出」的假象：`signOut` 完成前狀態仍是 signedIn，
    // 完成後控制器 notify 讓卡片換成 signedOut 態並由 SnackBar 補上結果那一句。
    //
    // 「變更密碼」與輪換緊鄰：改密成功即名下全部會話退出（含這一臺），會話層
    // 統一收斂為退出態；輪換按鈕只對已還清改密義務的主體呈現（強制態下它在
    // 後端本來就被 2010 擋下）。進行中各自停用並改顯示進行中文案。
    rows.add(
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            // 「我的裝置」：管理本人名下的會話清單。它是一个只對已登入主體開放的
            // 入口（同 Root 控制台一樣，放行判定在後端與會話層，這裡只導航）；
            // 面板內部再依伺服器給的 current 標記當前裝置，並把撤銷當前裝置導向退出態。
            // 欠改密時不呈現：那條路在服務端會被 2010 擋下。
            if (!session.mustChangePassword)
              SizedBox(
                height: 40,
                child: OutlinedButton(
                  key: SessionSummaryView.deviceManagerKey,
                  onPressed: () => showMyDevicesDialog(context, session),
                  child: Text(l10n.sessionDevicesAction),
                ),
              ),
            SizedBox(
              height: 40,
              child: OutlinedButton(
                key: SessionSummaryView.passwordChangeKey,
                onPressed: () => showChangePasswordDialog(context, session),
                child: Text(l10n.sessionPasswordChangeAction),
              ),
            ),
            if (!session.mustChangePassword)
              SizedBox(
                height: 40,
                child: OutlinedButton(
                  key: SessionSummaryView.rotateKey,
                  onPressed: _rotating ? null : () => _rotate(session),
                  child: _rotating
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: Text(l10n.sessionRotatingAction)),
                          ],
                        )
                      : Text(l10n.sessionRotateAction),
                ),
              ),
            SizedBox(
              height: 40,
              child: OutlinedButton(
                key: SessionSummaryView.logoutKey,
                onPressed: _signingOut ? null : () => _signOut(session),
                child: _signingOut
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Flexible(child: Text(l10n.sessionLoggingOutAction)),
                        ],
                      )
                    : Text(l10n.sessionLogoutAction),
              ),
            ),
          ],
        ),
      ),
    );
    return rows;
  }

  /// 以「年-月-日 時:分 UTC」呈現伺服器給的到期時刻。
  ///
  /// 刻意不換算成本機時區：本機時鐘與時區不參與業務時間的呈現基準，
  /// 而伺服器回的就是 UTC，直接標註 UTC 是最少一層誤會的寫法。
  static String _formatUtcMinute(DateTime utc) {
    final String iso = utc.toUtc().toIso8601String();
    // 形如 2026-09-30T12:34:56.789Z → 取到分。
    return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
  }
}

/// 「前往登入」按鈕：只負責導航，權限判定全部在會話層與閘裡。
class _GoLoginButton extends StatelessWidget {
  /// 建立按鈕。
  const _GoLoginButton();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 40,
      child: FilledButton(
        key: SessionSummaryView.goLoginKey,
        onPressed: () => Navigator.of(context).pushNamed(kLoginRoute),
        child: Text(l10n.sessionGoLoginAction),
      ),
    );
  }
}
