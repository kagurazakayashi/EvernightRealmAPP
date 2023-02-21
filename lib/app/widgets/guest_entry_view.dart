/// 入口層的「以訪客進入」卡：讀伺服器對外入口能力，只在訪客通路真的開放時給出口，
/// 並且只在人主動按下的那一刻才向伺服器要一筆臨時身分。
///
/// 這張卡守著的界線比註冊入口卡更多一條，因為它按下去會**在伺服器上留下一筆帳戶**：
///
/// * **只在主動按的時候寫入**：卡片載入、刷新、重新檢查、連線恢復都不發進入請求。
///   入口能力那次查詢是唯讀的（GET /auth/capabilities），它決定要不要露這扇門；
///   真正會寫庫的那一趟只由一顆按鈕觸發。這條界線存在的理由是孤兒帳戶：
///   「每次重連就自動多出一個訪客」會讓目錄被没人認領的行填滿，而那是清理不回來的一团真相。
/// * **進行中只准一趟**：連點沿用同一個結果，於是一次猶豫不會換出兩筆帳戶。
/// * **入口能力不是准入保證**：`guest_open` 只講「這一刻要不要顯示這扇門」，
///   准不准放由後端在寫入那一刻現讀策略重判（見 internal/guestacct）。Root 隨時可能把開關
///   轉回去，界面因此不承諾按下必然成功。
/// * **降級方向是收不是開**：查不到、連不上、回的是關閉——一律不顯示出口，只講自己
///   那一句。把「查不了」說成「開放」會把人送去撞一個未知結果；說成「Root 關掉了」則是
///   替伺服器編一個它沒做過的決定。
/// * **限制先講、不靠灰按鈕假裝執行**：這張卡負責在按下去之前講完「這是臨時身分、
///   沒有口令、不屬於任何活動、也做不了管理動作」；真正的把關全在服務端（訪客不帶任何授予，
///   管理端與 Root 端對他一律 2011），界面只是不撒謊。
/// * **不承諾事後找回**：暱稱是展示用的，不是憑據、也不承擔唯一性，這裡沒有任何
///   「記著暱稱就能回來」的意思。會話到期、主動退出、換裝置或清掉本機憑據之後，
///   這一趟就結束了；要處置得由管理員核實身分後另行決定。
///
/// 已登入者已有身分，這一頁不再需要另一個臨時身分，卡片整張收起（判定取自會話層那份
/// 「伺服器確認過的身分」，不看本地印象）。位址在本次存續中被換掉時，舊答案立刻作廢並重查一次：
/// 拿另一臺伺服器的入口狀態來講眼前這臺，比「尚未查詢」更容易害人做錯事。
///
/// 內容為不滾動的 Column：垂直滾動由應用殼統一承擔。
/// 所有顯示文字取自本地化資源；本檔不出現任何語言的硬編碼字串。
library;

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/server_address.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../api_error_labels.dart';
import '../app_dependencies.dart';
import '../app_router.dart';
import '../nav_context.dart';
import '../session_scope.dart';

/// 進入卡的階段：起點取決於有位址沒有，其後取決於查到的入口能力。
enum _EntryPhase { notConfigured, checking, open, closed, failed }

/// 入口層的「以訪客進入」卡。
class GuestEntryView extends StatefulWidget {
  /// 建立卡片。
  const GuestEntryView({super.key});

  /// 「重新檢查」按鈕的測試識別鍵。
  static const Key recheckKey = ValueKey<String>('guest-entry-recheck');

  /// 「以訪客身分進入」按鈕的測試識別鍵。
  static const Key actionKey = ValueKey<String>('guest-entry-action');

  /// 狀態結論行的測試識別鍵。
  static const Key statusKey = ValueKey<String>('guest-entry-status');

  /// 限制說明行的測試識別鍵。
  static const Key limitsKey = ValueKey<String>('guest-entry-limits');

  /// 暱稱輸入框的測試識別鍵。
  static const Key nicknameKey = ValueKey<String>('guest-entry-nickname');

  /// 失敗或補充說明的測試識別鍵。
  static const Key noteKey = ValueKey<String>('guest-entry-note');

  @override
  State<GuestEntryView> createState() => _GuestEntryViewState();
}

class _GuestEntryViewState extends State<GuestEntryView> {
  _EntryPhase _phase = _EntryPhase.notConfigured;

  final TextEditingController _nickname = TextEditingController();

  /// 這份入口答案是對哪個基準位址查出來的（位址一變即作廢）。
  String? _checkedAddress;

  /// 進行中的入口能力查詢；同一時間只准有一趟。
  Future<void>? _checkInFlight;

  /// 進行中的進入請求。**這張卡唯一會寫庫的行動**，因此单独一座在來：
  /// 連點沿用同一個結果，不會多換出一筆帳戶。
  Future<void>? _enterInFlight;

  /// 最近一次進入失敗的結構化原因（來自端點判定，按機器碼給四語言句子）。
  ApiError? _lastError;

  /// 補充說明的另一個來源：飛行中位址被換掉、或本端取不到可回傳的憑據。
  String? _localNote;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String? address = AppScope.of(context).api.addressDisplay;
    if (address != _checkedAddress) {
      // 位址換了（或第一次拿到位址）：舊答案不再描述眼前這臺伺服器，一律重來。
      _checkedAddress = address;
      _didAutoCheck = false;
      _phase = address == null
          ? _EntryPhase.notConfigured
          : _EntryPhase.checking;
    }
    if (!_didAutoCheck && address != null) {
      _didAutoCheck = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _check();
        }
      });
    }
  }

  /// 這個組件存續期間對目前位址有沒有自動查過入口能力（唯讀查詢，自動只一次、不輪詢）。
  bool _didAutoCheck = false;

  /// 查一次入口能力：同一時間只准有一趟，重複點擊沿用同一個結果。
  Future<void> _check() {
    final Future<void>? running = _checkInFlight;
    if (running != null) {
      return running;
    }
    late final Future<void> task;
    task = _runCheck().whenComplete(() {
      if (identical(_checkInFlight, task)) {
        _checkInFlight = null;
      }
    });
    _checkInFlight = task;
    return task;
  }

  /// 實際執行入口能力查詢；位址在請求期間被換掉時，這筆結果直接丟棄。
  Future<void> _runCheck() async {
    final ServerApi api = AppScope.of(context).api;
    final String? askedAddress = api.addressDisplay;
    if (askedAddress == null) {
      setState(() => _phase = _EntryPhase.notConfigured);
      return;
    }
    // 送出的 Accept-Language 採目前介面語言；介面文字本身仍一律取自本地化資源。
    final AppLocale locale = resolveAppLocale(Localizations.localeOf(context));
    setState(() => _phase = _EntryPhase.checking);

    final EntryCapabilitiesReport report;
    try {
      report = await api.entryCapabilities(acceptLanguage: locale.tag);
    } on ApiError {
      if (!mounted || api.addressDisplay != askedAddress) {
        return;
      }
      // 查不到就收：不顯示出口，只給「這一刻查不到准入狀態」那一句。
      setState(() => _phase = _EntryPhase.failed);
      return;
    }
    if (!mounted || api.addressDisplay != askedAddress) {
      // 位址已換：didChangeDependencies 已重置並排了新的查詢，這裡再寫就等於
      // 拿另一臺伺服器的答案去講眼前這臺。
      return;
    }
    setState(
      () => _phase = report.entry.guestOpen
          ? _EntryPhase.open
          : _EntryPhase.closed,
    );
  }

  /// 按一次「進入」：整趟走真實端點與會話層，失敗一律收斂成提示。
  ///
  /// 這裡沒有任何「顺帶重查入口能力」的寫法：那一格是唯讀的，而這一格會在伺服器上
  /// 留下一筆帳戶，兩者不該共用同一個觸發點。
  Future<void> _enter() {
    final Future<void>? running = _enterInFlight;
    if (running != null) {
      return running;
    }
    late final Future<void> task;
    task = _runEnter().whenComplete(() {
      if (identical(_enterInFlight, task)) {
        _enterInFlight = null;
      }
    });
    _enterInFlight = task;
    return task;
  }

  Future<void> _runEnter() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ServerApi api = AppScope.of(context).api;
    final SessionController session = SessionScope.of(context);

    // 問的是哪台伺服器，事後就要用哪台來綁定：以本趟實際打去的位址為準。
    final ServerAddress? asked = api.config.address;
    if (asked == null) {
      setState(() {
        _lastError = ApiError(
          kind: ApiErrorKind.notConfigured,
          path: kAuthGuestPath,
        );
        _localNote = null;
      });
      return;
    }

    final AppLocale locale = resolveAppLocale(Localizations.localeOf(context));
    final String nickname = _nickname.text.trim();
    setState(() {
      _lastError = null;
      _localNote = null;
    });

    final LoginExchange exchange;
    try {
      exchange = await api.guestEnter(
        nickname: nickname,
        acceptLanguage: locale.tag,
      );
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
      // 位址在請求飛行中被換掉：這筆回應描述的是另一臺伺服器，如實丟棄，
      // 不拿甲伺服器的臨時身分去綁乙伺服器。
      setState(() {
        _localNote = l10n.guestEntryAddressChangedHint;
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
        // persistenceFailed 照常進入：記憶體中的本機會話有效，重開才需重新進入；
        // 「保存不住」那一句由同一頁的會話摘要卡據 lastStorageFailure 如實呈現。
        _goAfterEntry(session);
      case SessionLoginOutcome.missingCredential:
        // 原生端取不到可回傳的憑據：狀態如實停在「無法確定」，不謊報已進入。
        setState(() {
          _localNote = l10n.guestEntryMissingCredentialNote;
        });
    }
  }

  /// 進入成功後的去處：只認「伺服器確認過的身分真的能開啟」的那一個受保護上下文。
  ///
  /// 訪客開得了玩家面（那裡如實呈現「尚未屬於任何活動」），開不了 Root 與管理端——
  /// 這條判定經 [AppRouter.identityAllows] 走，與會話閘同一份規則，界面不自創第二套。
  void _goAfterEntry(SessionController session) {
    final NavigatorState navigator = Navigator.of(context);
    final String target = NavContext.playerSurface.routeName;
    if (AppRouter.identityAllows(target, session.activeSession)) {
      navigator.pushNamed(target);
      return;
    }
    navigator.popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    // 已登入者已有身分：訪客是門外的通路，整張卡收起（判定取自會話層，不看本地印象）。
    if (SessionScope.of(context).isSignedIn) {
      return const SizedBox.shrink();
    }
    // 沒有位址就談不上准入：既不顯示出口，也不假裝查過。
    if (_phase == _EntryPhase.notConfigured) {
      return const SizedBox.shrink();
    }
    final bool checking =
        _phase == _EntryPhase.checking || _checkInFlight != null;
    final bool entering = _enterInFlight != null;
    final bool busy = checking || entering;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(l10n.guestEntryTitle, style: theme.textTheme.titleSmall),
              SizedBox(
                // 固定高度，避免窄屏下按鈕隨文字長度撐出不同高度。
                height: 36,
                child: OutlinedButton(
                  key: GuestEntryView.recheckKey,
                  onPressed: busy ? null : _check,
                  child: Text(l10n.guestEntryRecheckAction),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...switch (_phase) {
            _EntryPhase.checking => <Widget>[
              _Hint(
                text: l10n.guestEntryCheckingHint,
                valueKey: GuestEntryView.statusKey,
                busy: true,
              ),
            ],
            _EntryPhase.closed => <Widget>[
              _Hint(
                text: l10n.guestEntryClosedHint,
                valueKey: GuestEntryView.statusKey,
              ),
            ],
            _EntryPhase.failed => <Widget>[
              _Hint(
                text: l10n.guestEntryCheckFailedHint,
                valueKey: GuestEntryView.statusKey,
              ),
            ],
            _EntryPhase.open => _openBody(l10n, theme, entering),
            _EntryPhase.notConfigured => const <Widget>[],
          },
        ],
      ),
    );
  }

  /// 開放態的內文：限制說明、可選暱稱、那颗與眾不同的「會寫庫」的按鈕與失敗那一句。
  List<Widget> _openBody(
    AppLocalizations l10n,
    ThemeData theme,
    bool entering,
  ) {
    return <Widget>[
      _Hint(text: l10n.guestEntryOpenHint, valueKey: GuestEntryView.statusKey),
      const SizedBox(height: 6),
      Text(
        l10n.guestEntryLimitsNote,
        key: GuestEntryView.limitsKey,
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 10),
      TextField(
        key: GuestEntryView.nicknameKey,
        controller: _nickname,
        enabled: !entering,
        maxLines: 1,
        maxLength: 64,
        decoration: InputDecoration(
          labelText: l10n.guestEntryNicknameLabel,
          hintText: l10n.guestEntryNicknameHint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
      if (_lastError != null || _localNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _localNote ?? apiErrorText(l10n, _lastError!),
            key: GuestEntryView.noteKey,
            style: theme.textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: 8),
      SizedBox(
        height: 40,
        child: FilledButton(
          key: GuestEntryView.actionKey,
          // 進行中一律停用：防連點產生第二筆訪客帳戶，也防把限流計數無故推向冷卻。
          onPressed: entering ? null : _enter,
          child: entering
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: Text(l10n.guestEntrySubmitting)),
                  ],
                )
              : Text(l10n.guestEntryAction),
        ),
      ),
    ];
  }
}

/// 一行入口狀態提示；查問進行中時自帶一顆小 spinner。
class _Hint extends StatelessWidget {
  /// 以文字、測試識別鍵與是否進行中建立。
  const _Hint({required this.text, required this.valueKey, this.busy = false});

  /// 提示文字。
  final String text;

  /// 掛在提示文字上的測試識別鍵。
  final Key valueKey;

  /// 是否顯示進行中的轉圈。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (!busy) {
      return Text(text, key: valueKey, style: theme.textTheme.bodySmall);
    }
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text, key: valueKey, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}
