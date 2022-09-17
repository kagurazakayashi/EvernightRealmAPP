/// 受保護路由的會話閘：依「伺服器確認過的會話狀態」決定放行、擋回或先驗證。
///
/// 這道閘存在的理由全部寫在會話層的既有界線上，這裡只做呈現端的執行：
///
/// * **不閃現**：狀態是驗證中或尚未問過伺服器時，這一頁只出中性提示，
///   受保護內容一個字都不畫——先畫再跳回去等於把「恢復失敗」當成沒發生。
/// * **不自報**：放行與否只讀 [SessionController.activeSession]，那欄位
///   只可能由 `/auth/login`、`/auth/root/login`、`/auth/session` 的伺服器回應填進；
///   登入表單選了哪種方式、本地存了什麼，都不在判定輸入裡。
/// * **不绕行**：失效（expired）與未登入（signedOut）都被換成登入頁，並把
///   原目標作為返回路由帶過去；帶過去的值只能是受保護清單裡的路由名稱，
///   換不到任何應用外的目標。
/// * **權限只是閘的下限**：閘通過不代表功能可用——頁面本身對未開發的後端能力
///   照實呈現佔位說明，這裡不替它們背書。
library;

import 'package:flutter/material.dart';

import '../core/session/session_controller.dart';
import '../core/session/session_status.dart';
import '../l10n/app_localizations.dart';
import 'app_router.dart';
import 'session_scope.dart';

/// 受保護路由外層的道閘。
class SessionGate extends StatefulWidget {
  /// 以目標路由名稱、是否要求 Root 身分與受護內容建立。
  const SessionGate({
    super.key,
    required this.targetRoute,
    required this.requireRoot,
    required this.child,
  });

  /// 本閘守護的路由名稱：作為登入頁的返回目標原樣帶過去。
  final String targetRoute;

  /// 是否只准 Root 主體開啟（依伺服器回報的主體類別判定）。
  final bool requireRoot;

  /// 放行時呈現的受保護內容。
  final Widget child;

  /// 中性等待畫面的測試識別鍵。
  static const Key checkingKey = ValueKey<String>('session-gate-checking');

  /// 身分不合擋回畫面的測試識別鍵。
  static const Key blockedKey = ValueKey<String>('session-gate-blocked');

  /// 返回入口按鈕的測試識別鍵。
  static const Key backHomeKey = ValueKey<String>('session-gate-back-home');

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  /// 是否已經排過一次自動恢復：只准排一次，不做輪詢。
  bool _restoreRequested = false;

  /// 是否已經換去登入頁：一次導覽只准換一趟，避免狀態翻轉競態時疊層。
  bool _redirected = false;

  void _redirectToLogin(SessionController session) {
    if (_redirected) {
      return;
    }
    _redirected = true;
    // 目標名稱經 parseReturnRoute 的同一份白名單檢查：閘自己帶的參數
    // 也不走信任捷徑，清單外名稱到了登入頁那端同樣會被當成沒有。
    Navigator.of(context).pushReplacementNamed(
      kLoginRoute,
      arguments: AppRouter.parseReturnRoute(widget.targetRoute),
    );
  }

  void _requestRestore(SessionController session) {
    if (_restoreRequested) {
      return;
    }
    _restoreRequested = true;
    session.restore();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SessionController session = SessionScope.of(context);

    switch (session.status) {
      case SessionStatus.signedIn:
        final ActiveSession? active = session.activeSession;
        // 放行與否交給路由表那份唯一判定（AppRouter.identityAllows）：
        // 閘與登入成功後的跳轉共用同一規則，不會出現兩套「算不算 Root」。
        final bool allowed = AppRouter.identityAllows(
          widget.targetRoute,
          active,
        );
        if (allowed) {
          return widget.child;
        }
        return _BlockedNotice(
          onBackHome: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          message: widget.requireRoot
              ? l10n.sessionGateRootRequiredHint
              : l10n.sessionGateBlockedHint,
        );
      case SessionStatus.signedOut:
      case SessionStatus.expired:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _redirectToLogin(session);
          }
        });
        return _CheckingNotice(text: l10n.sessionGateCheckingHint);
      case SessionStatus.verifying:
        return _CheckingNotice(text: l10n.sessionGateCheckingHint);
      case SessionStatus.unknown:
        // 還沒問過伺服器：先自動恢復一次（啟動恢復的同一條路，不另造判定）。
        // 問過了仍然未知（連不上、儲存讀不到）：如實說查不了，給再驗證與回入口。
        if (!_restoreRequested) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _requestRestore(session);
            }
          });
          return _CheckingNotice(text: l10n.sessionGateCheckingHint);
        }
        return _BlockedNotice(
          onBackHome: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          message: l10n.sessionUnknownHint,
          revalidate: () => session.restore(),
        );
    }
  }
}

/// 中性等待畫面：只有一句「先確認身分」，不帶任何受保護內容。
class _CheckingNotice extends StatelessWidget {
  /// 以提示文字建立。
  const _CheckingNotice({required this.text});

  /// 提示文字。
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              key: SessionGate.checkingKey,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// 擋回畫面：說清楚「以伺服器的答案為準，這個身分開不了這頁」，並給唯一出口。
class _BlockedNotice extends StatelessWidget {
  /// 以回入口動作與說明文字建立。
  const _BlockedNotice({
    required this.onBackHome,
    required this.message,
    this.revalidate,
  });

  /// 返回入口頁的動作。
  final VoidCallback onBackHome;

  /// 為什麼開不了的說明。
  final String message;

  /// 可選的「再驗證一次」動作（狀態未知時才給）。
  final VoidCallback? revalidate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.sessionGateBlockedTitle,
            key: SessionGate.blockedKey,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(message, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: SessionGate.backHomeKey,
                onPressed: onBackHome,
                child: Text(l10n.sessionBackHomeAction),
              ),
              if (revalidate != null)
                FilledButton(
                  onPressed: revalidate,
                  child: Text(l10n.sessionRevalidateAction),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
