/// 首次啟動的 Root 初始化引導卡：讀伺服器真實的初始化狀態，並按狀態決定說什麼。
///
/// 這個畫面存在的理由只有一個：全新部署的伺服器還沒有 Root，而瀏覽器這端的人
/// 需要知道「接下來該去伺服器那台機器上做什麼」。它因此守著三條界線：
///
///  1. **只讀不寫**：這張卡只 GET 一個狀態端點，沒有任何表單、沒有任何提交路徑。
///     Root 的初始化只有伺服器本機的 `evernight-server init-root` 一條路，
///     那是批准過的邊界（授權依據是「能在主機上執行命令」，不是「誰先連上線」），
///     把口令收進來送出去才是越界。
///  2. **狀態必須是真的**：連不上就講連不上，查不出來就講查不出來。
///     只有在伺服器明確回報「還沒有 Root」時才列出初始化步驟——
///     那時候列出的步驟也是從本機命令的行為逐條對出來的，不是通用的安慰話。
///  3. **已初始化就把門關上**：伺服器說有了，這裡不再顯示任何可以「再建一個 Root」
///     的東西；剩下的只有如實說明登入畫面尚未開發。
///
/// 位址在這次會話中被換掉時，舊狀態立刻作廢並重新查一次：掛著另一台伺服器的
/// 初始化狀態來講眼前這台，比「尚未查詢」更容易害人做錯事。
///
/// 所有顯示文字取自本地化資源；本檔不出現任何語言的硬編碼字串。
library;

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/connection_tracker.dart';
import '../../core/api/root_init_status.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';
import '../app_dependencies.dart';
import '../connection_scope.dart';

/// Root 初始化引導卡。
class RootInitGuideView extends StatefulWidget {
  /// 建立引導卡。
  const RootInitGuideView({super.key});

  /// 查詢按鈕的測試識別鍵。
  static const Key actionKey = ValueKey<String>('root-init-action');

  /// 初始化步驟區塊的測試識別鍵。
  static const Key guidanceKey = ValueKey<String>('root-init-guidance');

  /// 狀態結論行的測試識別鍵。
  static const Key statusKey = ValueKey<String>('root-init-status');

  @override
  State<RootInitGuideView> createState() => _RootInitGuideViewState();
}

class _RootInitGuideViewState extends State<RootInitGuideView> {
  /// 目前階段；起點取決於有位址沒有（沒位址時連「查過但失敗」都谈不上）。
  RootInitPhase _phase = RootInitPhase.notConfigured;

  /// 成功查到的狀態；只在 [initialized]、[uninitialized] 兩個階段有意義。
  InitStatusReport? _report;

  /// 這份狀態是對哪個基準位址查出來的（位址一變即作廢）。
  String? _checkedAddress;

  /// 進行中的查詢；同一時間只准有一趟，避免連點按鈕交出交錯的結果。
  Future<void>? _inFlight;

  /// 這個組件存續期間有沒有自動查過（自動查詢只發生一次，不變成輪詢）。
  bool _didAutoCheck = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String? address = AppScope.of(context).api.addressDisplay;
    if (address != _checkedAddress) {
      // 位址換了（或第一次拿到位址）：舊狀態不再描述眼前這台伺服器，一律重來。
      _checkedAddress = address;
      _report = null;
      _didAutoCheck = false;
      _phase = address == null
          ? RootInitPhase.notConfigured
          : RootInitPhase.checking;
    }
    if (!_didAutoCheck && address != null) {
      // 首次啟動的節奏是「裝好服務、打開網頁」，那個人不該先學會按哪個按鈕；
      // 因此有位址就自動查一次，而且只在這個組件存續期間查這一次。
      _didAutoCheck = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _check();
        }
      });
    }
  }

  /// 查一次狀態：同一時間只准有一趟在跑，重複點擊沿用同一個結果。
  ///
  /// 本方法不拋例外——失敗收斂成階段呈現。這裡刻意不做輪詢：狀態的變更只發生在
  /// 「有人在本機跑了一次 init-root」這種人工動作之後，由人回來按「重新檢查」
  /// 才是對的節奏；畫面自己縮輪會讓「連不上」被讀成「還在查」。
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
      setState(() {
        _phase = RootInitPhase.notConfigured;
        _report = null;
      });
      return;
    }
    // 送出的 Accept-Language 採目前介面語言，讓伺服器的診斷訊息與介面同語言；
    // 介面文字本身仍一律取自本地化資源。
    final AppLocale locale = resolveAppLocale(Localizations.localeOf(context));
    setState(() {
      _phase = RootInitPhase.checking;
    });

    InitStatusReport report;
    try {
      report = await api.initStatus(acceptLanguage: locale.tag);
    } on ApiError catch (error) {
      if (!mounted || api.addressDisplay != askedAddress) {
        return;
      }
      setState(() {
        _report = null;
        _phase = classifyInitStatusFailure(error);
      });
      return;
    }
    if (!mounted) {
      return;
    }
    if (api.addressDisplay != askedAddress) {
      // 位址已換：didChangeDependencies 已重置狀態並排了新的查詢，
      // 這裡再寫一筆就等於拿舊伺服器的答案去講新伺服器。
      return;
    }
    setState(() {
      _report = report;
      _phase = classifyInitStatus(report);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ConnectionTracker tracker = ConnectionScope.of(context);
    final bool busy = _phase == RootInitPhase.checking;

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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.rootInitTitle, style: theme.textTheme.titleSmall),
              SizedBox(
                // 固定高度，避免窄屏下按鈕隨文字長度撐出不同高度。
                height: 36,
                child: FilledButton(
                  key: RootInitGuideView.actionKey,
                  onPressed: tracker.isConfigured && !busy
                      ? () {
                          _check();
                        }
                      : null,
                  child: Text(l10n.rootInitAction),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(l10n.rootInitSummary, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          ...switch (_phase) {
            RootInitPhase.notConfigured => <Widget>[
              _Note(text: l10n.rootInitNotConfiguredHint),
            ],
            RootInitPhase.checking => <Widget>[
              _RunningNote(text: l10n.rootInitRunning),
            ],
            RootInitPhase.uninitialized => _uninitializedBody(l10n),
            RootInitPhase.initialized => <Widget>[
              _Status(title: l10n.rootInitInitializedTitle),
              _Note(text: l10n.rootInitInitializedNote),
            ],
            // 三個失敗階段這裡只給自己那一句結論，不再抄一遍錯誤碼與關聯 ID：
            // 同一屏的連通性探測區才是「這個位址到底怎麼了」的診斷出口，兩處逐字
            // 相同的診斷行沒有帶來第二份資訊，只會讓畫面變成兩倍長。
            RootInitPhase.unreachable => <Widget>[
              _Status(title: l10n.rootInitUnreachableTitle),
            ],
            RootInitPhase.forbidden => <Widget>[
              _Status(title: l10n.rootInitForbiddenTitle),
            ],
            RootInitPhase.unknown => <Widget>[
              _Status(title: l10n.rootInitUnknownTitle),
              _Note(text: l10n.rootInitUnknownHint),
            ],
          },
        ],
      ),
    );
  }

  /// 「尚未初始化」的內容：狀態一句、本機步驟一組、口令界線一句。
  ///
  /// 步驟只在這個階段出現——伺服器還沒有 Root 時列步驟才是指引，
  /// 其他階段列步驟會變成教人去做一件會被拒絕（更糟是沒必要）的事。
  List<Widget> _uninitializedBody(AppLocalizations l10n) {
    final InitStatusReport? report = _report;
    return <Widget>[
      _Status(title: l10n.rootInitUninitializedTitle),
      if (report != null && !report.configExists)
        _Note(text: l10n.rootInitConfigMissingHint),
      if (report != null && report.envOverride)
        _Note(text: l10n.rootInitEnvOverrideHint),
      _StepList(
        steps: <String>[
          l10n.rootInitStepStop,
          l10n.rootInitStepMigrate,
          l10n.rootInitStepInitialize,
          l10n.rootInitStepRestart,
          l10n.rootInitStepRecheck,
        ],
      ),
      _Note(text: l10n.rootInitSecretBoundary),
    ];
  }
}

/// 一行補充說明。
class _Note extends StatelessWidget {
  /// 以文字建立說明。
  const _Note({required this.text});

  /// 說明文字。
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

/// 查詢進行中的提示。
class _RunningNote extends StatelessWidget {
  /// 以提示文字建立。
  const _RunningNote({required this.text});

  /// 進行中顯示的文字。
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// 狀態結論那一句。
///
/// 它是這張卡片唯一被允許宣稱「伺服器現在是什麼狀態」的地方，因此帶上測試識別鍵，
/// 讓「查不到卻顯示某個狀態」這種事在測試裡一定被抓得到。
class _Status extends StatelessWidget {
  /// 以結論文字建立。
  const _Status({required this.title});

  /// 結論文字。
  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        title,
        key: RootInitGuideView.statusKey,
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

/// 本機初始化步驟的有序清單。
class _StepList extends StatelessWidget {
  /// 以步驟清單建立。
  const _StepList({required this.steps});

  /// 每一步的文字（依順序）。
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        key: RootInitGuideView.guidanceKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int index = 0; index < steps.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 序號是呈現用的，不進本地化資源：換語言時序號不該跟著翻。
                  Text('${index + 1}. ', style: theme.textTheme.bodySmall),
                  Expanded(
                    child: Text(steps[index], style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
