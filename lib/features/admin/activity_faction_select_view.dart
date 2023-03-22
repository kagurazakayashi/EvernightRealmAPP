/// 「玩家自選陣營」那一欄活動配置的卡：讀現值、選一個模式、經確認後存下去。
///
/// 這張卡的邊界與它接的後端通路一一對應，寫在這裡是因為界面藏不住它們：
///
/// * 底稿只能來自服務端讀回的那一欄現值：本卡預填的是父層按標識讀回的
///   `faction_select_mode`，compare-and-set 的唯一依據值（`expected_mode`）也是它。
///   目錄裡的印象與本地推測都不夠格當底稿——把依據值湊一份出來，2013 那道併發把關就形同虛設。
/// * 這一欄只約束「往後玩家能不能自己選」，不改寫任何人的既有歸屬：界面把這句話寫在
///   確認框與模式說明裡，而不是讓管理人以為關掉開關就會把人清出陣營。
/// * 出廠值是 disabled：新活動與既有活動都不未經批準就開放自選。這一格在回應裡缺席時
///   判合同違例（讀成「沒開放」的預設會把開關畫錯，而庫裡可能正開著）。
/// * 按鈕只由服務端讀回的活動狀態決定：草稿、開放、停止都還能準備這欄配置
///   （它屬活動自己的資料，與名稱描述同側；玩家在停止與草稿態本來就寫不進來，
///   那是自選通路自己問的問題，不在這裡重複一套門禁）；歸檔收起控件並說「這件事已結束」
///   （2029）；表外狀態一律當不可寫。
/// * 表外的模式取值不長出保存控件：那種情況下連「依據值」都只能是猜的，
///   而猜一份送出去就是拿一次寫入去探資料庫。
/// * 現值過期（2013）時收起寫入控件，只留「重新讀取這場活動」一個出口；
///   結果不明（連不上、逾時）絕不自動補發，由人重讀再決定。
/// * 成功句只在寫入回應回來之後出現，內容取回應回讀的現值：保存成功前不顯示「已完成」。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 活動的「玩家自選陣營」配置卡。
class FactionSelectConfigCard extends StatefulWidget {
  /// 以端點介面、活動標識、服務端讀回的狀態與模式現值建立本卡。
  const FactionSelectConfigCard({
    super.key,
    required this.api,
    required this.activityId,
    required this.activityStatus,
    required this.currentMode,
    required this.onReload,
    this.onSaved,
  });

  /// 統一端點存取介面。
  final ServerApi api;

  /// 歸屬活動的標識（路徑引數；請求本體沒有這一格）。
  final String activityId;

  /// 服務端讀回的活動狀態：本卡的寫入控件只由它決定，不由本地推測。
  final String activityStatus;

  /// 服務端讀回的自選模式現值，同時是本卡提交時的 compare-and-set 依據值。
  final String currentMode;

  /// 「重新讀取這場活動」的動作：2013 與載入失敗都只有這一個出口。
  final VoidCallback onReload;

  /// 任意一次保存成功的回呼，帶著回應回讀的活動現值：父層據此更新自己那份底稿，
  /// 也讓名冊與陣營卡看到的「此刻能不能選」跟同一個現值（不做本地拼裝）。
  final ValueSetter<ActivitySaveResult>? onSaved;

  /// 載入中說明識別鍵。
  static const Key loadingKey = ValueKey<String>('faction-select-loading');

  /// 現值列識別鍵。
  static const Key currentKey = ValueKey<String>('faction-select-current');

  /// 模式選項識別鍵（整項容器）。
  static Key optionKey(String mode) =>
      ValueKey<String>('faction-select-option-$mode');

  /// 某一項的「選取」按鈕識別鍵：點一下只改本地選中的那一項，仍要經確認才送出。
  static Key pickKey(String mode) =>
      ValueKey<String>('faction-select-pick-$mode');

  /// 保存按鈕識別鍵。
  static const Key saveKey = ValueKey<String>('faction-select-save');

  /// 取消識別鍵。
  static const Key cancelKey = ValueKey<String>('faction-select-cancel');

  /// 重新讀取識別鍵（2013 與載入失敗共用那個出口）。
  static const Key reloadKey = ValueKey<String>('faction-select-reload');

  /// 確認對話框肯定按鈕識別鍵。
  static const Key confirmKey = ValueKey<String>('faction-select-confirm');

  /// 歸檔只讀列識別鍵。
  static const Key archivedKey = ValueKey<String>('faction-select-archived');

  /// 表外取值交代列識別鍵。
  static const Key unknownKey = ValueKey<String>('faction-select-unknown');

  /// 提示列識別鍵（本地校驗與失敗轉述共用）。
  static const Key noticeKey = ValueKey<String>('faction-select-notice');

  /// 保存成功列識別鍵。
  static const Key savedKey = ValueKey<String>('faction-select-saved');

  @override
  State<FactionSelectConfigCard> createState() =>
      _FactionSelectConfigCardState();
}

/// 一次配置保存讀回的事實（本卡只需要模式與時刻兩格，因此不要求整份活動）。
class ActivitySaveResult {
  /// 以已驗證的現值建立一份結果。
  const ActivitySaveResult({required this.factionSelectMode});

  /// 寫入後服務端回讀的模式現值。
  final String factionSelectMode;
}

class _FactionSelectConfigCardState extends State<FactionSelectConfigCard> {
  /// 本卡選定的模式；null 表示還沒選（底稿就是目前的現值，不預先假裝有人改過）。
  String? _selected;

  /// 目前介面語言對應的 Accept-Language 標記。
  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  bool _writing = false;
  bool _stale = false;
  String? _notice;
  String? _saved;

  /// 已批準可寫的模式集合（界面只列這三個，取值語意由後端那一欄的封閉集合定義）。
  static const List<String> _modes = <String>['disabled', 'first_only', 'free'];

  /// 現值是不是已批準的三個取值之一：表外值不長出寫入控件（理由見檔頭）。
  bool get _knownMode => _modes.contains(widget.currentMode);

  /// 本卡此刻準不準寫：只採信服務端讀回的活動狀態——歸檔是終態一律收起控件，
  /// 其餘三態都能準備這一欄配置；表外狀態一律當不可寫（與名冊卡、陣營卡同一取向）。
  bool get _canWrite => _knownMode && !_isArchived && !_stale;

  /// 是否已歸檔（界面要如實說那一句，而不是靜默收起控件讓人以為載入壞了）。
  bool get _isArchived => widget.activityStatus == 'archived';

  /// 模式取值的人話名稱；表外值照實顯示原值，不靜默歸類成某一態。
  String _modeLabel(AppLocalizations l10n, String mode) {
    return switch (mode) {
      'disabled' => l10n.factionSelectModeDisabled,
      'first_only' => l10n.factionSelectModeFirstOnly,
      'free' => l10n.factionSelectModeFree,
      _ => l10n.factionSelectModeUnknown(mode),
    };
  }

  /// 每一態的語意說明（表外值沒有說明可給：那一格只把原值唸出來）。
  String? _modeHint(AppLocalizations l10n, String mode) {
    return switch (mode) {
      'disabled' => l10n.factionSelectModeHintDisabled,
      'first_only' => l10n.factionSelectModeHintFirstOnly,
      'free' => l10n.factionSelectModeHintFree,
      _ => null,
    };
  }

  /// 走一次配置寫入：本體恰好兩格（新模式與它所依據的現值）。
  ///
  /// 成功後以父層的重讀收尾而不是本地蓋值：回應裡那一欄才是寫進去的事實，
  /// 而「此刻玩家能不能選」還要多問活動狀態，那屬服務端的派生值。
  Future<void> _save() async {
    // 保存按鈕只在「選了、且與現值不同、且不在寫入中」時才亮；這裡的擋是雙保險，
    // 不是第二套規則（本地擋的條件與本體白名單一樣只有兩格）。
    final String? picked = _selected;
    if (picked == null || picked == widget.currentMode || _writing) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _writing = true;
      _notice = null;
      _saved = null;
    });
    try {
      final ActivityDetailReport report = await widget.api
          .updateFactionSelectMode(
            activityId: widget.activityId,
            mode: picked,
            expectedMode: widget.currentMode,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _selected = null;
        _saved = l10n.factionSelectSavedNotice;
        _stale = false;
      });
      widget.onSaved?.call(
        ActivitySaveResult(
          factionSelectMode: report.activity.factionSelectMode,
        ),
      );
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _notice = apiErrorText(l10n, error);
        // 2013 的處置只有重讀；2029 是終態、1004 是寫法不對，由統一對映轉述。
        _stale = error.knownCode == ApiMachineCode.profileConflict;
      });
    }
  }

  /// 最小確認清單：一次講完「只動這一欄」與兩件不會發生的事。
  Future<bool> _confirm(AppLocalizations l10n, String picked) async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.factionSelectConfirmTitle),
        content: Text(l10n.factionSelectConfirmBody(_modeLabel(l10n, picked))),
        actions: <Widget>[
          TextButton(
            key: FactionSelectConfigCard.cancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.activityConfirmCancelAction),
          ),
          FilledButton(
            key: FactionSelectConfigCard.confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.activityConfirmOkAction),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.factionSelectCardTitle,
              style: theme.textTheme.titleSmall,
            ),
            if (_writing)
              Text(
                l10n.activityLoadingNotice,
                key: FactionSelectConfigCard.loadingKey,
                style: theme.textTheme.bodySmall,
              ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  l10n.factionSelectCurrentModeLabel,
                  key: FactionSelectConfigCard.currentKey,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(_modeLabel(l10n, widget.currentMode)),
              ],
            ),
            if (!_knownMode) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                l10n.factionSelectUnknownBlocksNotice,
                key: FactionSelectConfigCard.unknownKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_isArchived) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                l10n.factionSelectArchivedNotice,
                key: FactionSelectConfigCard.archivedKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_knownMode && !_isArchived) ...<Widget>[
              const SizedBox(height: 8),
              // 三個取值各自成項，並且每一項把自己那句語意直接攤開顯示：
              // 「僅首次選錯今日無人能改」這句話必須在選之前就讀得到，
              // 而不是收在選單深處、等 2039 回來才讓人知道規則。
              for (final String mode in _modes)
                Padding(
                  key: FactionSelectConfigCard.optionKey(mode),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        mode == (_selected ?? widget.currentMode)
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(_modeLabel(l10n, mode)),
                            if (_modeHint(l10n, mode) != null)
                              Text(
                                _modeHint(l10n, mode)!,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      // 「點一下即選取」而不自動送出：改配置要經過確認框那一步。
                      if (_canWrite && !_writing)
                        TextButton(
                          key: FactionSelectConfigCard.pickKey(mode),
                          onPressed: () => setState(() => _selected = mode),
                          child: Text(l10n.factionSelectPickAction),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton(
                    key: FactionSelectConfigCard.saveKey,
                    onPressed:
                        _canWrite &&
                            _selected != null &&
                            _selected != widget.currentMode &&
                            !_writing
                        ? () async {
                            if (await _confirm(l10n, _selected!)) {
                              await _save();
                            }
                          }
                        : null,
                    child: Text(l10n.factionSelectSaveAction),
                  ),
                  if (_stale || _notice != null)
                    OutlinedButton(
                      key: FactionSelectConfigCard.reloadKey,
                      onPressed: widget.onReload,
                      child: Text(l10n.activityReloadAction),
                    ),
                ],
              ),
            ],
            if (_saved != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _saved!,
                key: FactionSelectConfigCard.savedKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_notice != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _notice!,
                key: FactionSelectConfigCard.noticeKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
