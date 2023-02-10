/// 入口層的「建立帳戶」入口卡：讀伺服器對外入口能力，只在自註冊真的開放時給出口。
///
/// 這張卡存在的唯一理由，是把「這臺伺服器此刻准不准自註冊」如實呈現在登入前界面，
/// 並只在答案為真時露出一個導航捷徑。它守著幾條界線：
///
/// * **入口能力不是准入保證**：`sign_up_open` 只回答「要不要顯示這扇門」，真正准不准建
///   由後端在提交那一刻現讀策略並校驗模式決定（見 RegisterPage）。Root 隨時可能把開關
///   轉回去，界面因此不承諾按下必然成功，也不因為這裡讀到「開」就繞過提交端的二次判定。
/// * **降級方向是收不是開**：查不到、連不上、回的是關閉——一律不顯示註冊出口，只講自己
///   那一句。把「查不了」說成「開放」會把人送去撞一個未知結果；說成「Root 關掉了」則是
///   替伺服器編一個它沒做過的決定。
/// * **只對門外的人呈現**：已登入者已有身分，這一頁不再需要建立另一個帳戶，卡片整張收起
///   （判定取自會話層那份「伺服器確認過的身分」，不看本地印象）。
/// * **不輪詢、但可重查**：准入的變更發生在 Root 手動改策略之後，由人回來按「重新檢查」
///   才是對的節奏；畫面自己縮輪會讓「連不上」被讀成「還在查」。
///
/// 位址在本次存續中被換掉時，舊答案立刻作廢並重查一次：拿另一臺伺服器的入口狀態來講
/// 眼前這臺，比「尚未查詢」更容易害人做錯事。
///
/// 所有顯示文字取自本地化資源；本檔不出現任何語言的硬編碼字串。
library;

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';
import '../app_dependencies.dart';
import '../app_router.dart';
import '../session_scope.dart';

/// 入口卡的階段：起點取決於有位址沒有，其後取決於查到的入口能力。
enum _EntryPhase { notConfigured, checking, open, closed, failed }

/// 入口層的「建立帳戶」入口卡。
class RegisterEntryView extends StatefulWidget {
  /// 建立卡片。
  const RegisterEntryView({super.key});

  /// 「重新檢查」按鈕的測試識別鍵。
  static const Key recheckKey = ValueKey<String>('register-entry-recheck');

  /// 「建立帳戶」入口按鈕的測試識別鍵。
  static const Key actionKey = ValueKey<String>('register-entry-action');

  /// 狀態結論行的測試識別鍵。
  static const Key statusKey = ValueKey<String>('register-entry-status');

  @override
  State<RegisterEntryView> createState() => _RegisterEntryViewState();
}

class _RegisterEntryViewState extends State<RegisterEntryView> {
  _EntryPhase _phase = _EntryPhase.notConfigured;

  /// 這份入口答案是對哪個基準位址查出來的（位址一變即作廢）。
  String? _checkedAddress;

  /// 進行中的查詢；同一時間只准有一趟，避免連點交出交錯的結果。
  Future<void>? _inFlight;

  /// 這個組件存續期間對目前位址有沒有自動查過（自動查詢只一次，不變成輪詢）。
  bool _didAutoCheck = false;

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

  /// 查一次入口能力：同一時間只准有一趟在跑，重複點擊沿用同一個結果。
  Future<void> _check() {
    final Future<void>? running = _inFlight;
    if (running != null) {
      return running;
    }
    late final Future<void> task;
    task = _runCheck().whenComplete(() {
      if (identical(_inFlight, task)) {
        _inFlight = null;
      }
    });
    _inFlight = task;
    return task;
  }

  /// 實際執行查詢；位址在請求期間被換掉時，這筆結果直接丟棄。
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
      () => _phase = report.entry.signUpOpen
          ? _EntryPhase.open
          : _EntryPhase.closed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    // 已登入者已有身分：註冊是門外的通路，整張卡收起（判定取自會話層，不看本地印象）。
    if (SessionScope.of(context).isSignedIn) {
      return const SizedBox.shrink();
    }
    // 沒有位址就談不上准入：既不顯示出口，也不假裝查過。
    if (_phase == _EntryPhase.notConfigured) {
      return const SizedBox.shrink();
    }
    final bool busy = _phase == _EntryPhase.checking || _inFlight != null;

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
              Text(l10n.registerEntryTitle, style: theme.textTheme.titleSmall),
              SizedBox(
                // 固定高度，避免窄屏下按鈕隨文字長度撐出不同高度。
                height: 36,
                child: OutlinedButton(
                  key: RegisterEntryView.recheckKey,
                  onPressed: busy ? null : _check,
                  child: Text(l10n.registerEntryRecheckAction),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...switch (_phase) {
            _EntryPhase.checking => <Widget>[
              _Hint(
                text: l10n.registerEntryCheckingHint,
                valueKey: RegisterEntryView.statusKey,
                busy: true,
              ),
            ],
            _EntryPhase.closed => <Widget>[
              _Hint(
                text: l10n.registerEntryClosedHint,
                valueKey: RegisterEntryView.statusKey,
              ),
            ],
            _EntryPhase.failed => <Widget>[
              _Hint(
                text: l10n.registerEntryCheckFailedHint,
                valueKey: RegisterEntryView.statusKey,
              ),
            ],
            _EntryPhase.open => <Widget>[
              _Hint(
                text: l10n.registerEntryOpenHint,
                valueKey: RegisterEntryView.statusKey,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: FilledButton(
                  key: RegisterEntryView.actionKey,
                  onPressed: () =>
                      Navigator.of(context).pushNamed(kRegisterRoute),
                  child: Text(l10n.registerEntryAction),
                ),
              ),
            ],
            _EntryPhase.notConfigured => const <Widget>[],
          },
        ],
      ),
    );
  }
}

/// 一行入口狀態提示；查問進行中時自帶一顆小spinner。
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
