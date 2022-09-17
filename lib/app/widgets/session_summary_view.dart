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
import '../../core/session/session_controller.dart';
import '../../core/session/session_status.dart';
import '../../l10n/app_localizations.dart';
import '../app_dependencies.dart';
import '../app_router.dart';
import '../nav_context.dart';
import '../session_scope.dart';

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

  /// 本機儲存異常說明的測試識別鍵。
  static const Key storageNoteKey = ValueKey<String>('session-storage-note');

  @override
  State<SessionSummaryView> createState() => _SessionSummaryViewState();
}

class _SessionSummaryViewState extends State<SessionSummaryView> {
  /// 進行中的重新驗證；同一時間只准有一趟，連點沿用同一個結果。
  Future<void>? _inFlight;

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
    if (AppRouter.identityAllows(NavContext.rootConsole.routeName, active)) {
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
