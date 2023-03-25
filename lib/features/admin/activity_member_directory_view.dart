/// 「玩家目錄可見性」那一欄活動配置的卡：讀現值、選一個模式、經確認後存下去。
///
/// 這張卡的邊界與它接的後端通路一一對應，寫在這裡是因為界面藏不住它們：
///
/// * 底稿只能來自服務端讀回的那一欄現值：本卡預填的是父層按標識讀回的
///   `member_directory_mode`，compare-and-set 的唯一依據值（`expected_mode`）也是它。
///   湊一份依據值等於把 2013 那道併發把關做成擺設。
/// * 這一欄只約束「往後誰能在目錄裡看見誰」，不改寫任何人的既有事實：
///   界面把這句話寫在確認框與模式說明裡，而不是讓管理人以為收成 hidden
///   就會把人已分好的陣營清掉、或把他自己那一格覆蓋一起抹平。
/// * 出廠值是 hidden：新活動與既有活動都不未經批準就有了可見面。這一格在回應裡缺席時
///   判合同違例（讀成「沒開放」的預設會把開關畫錯，而庫裡可能正開著）。
/// * 四態的語意直接攤在選項上，尤其 `same_faction_only` 要寫清楚「尚未分組的人彼此
///   看不見，只看得見自己」——這句話若留到使用者對著空目錄回報 bug 時才說明，
///   代價是整場活動的信任。
/// * `all_players_except_admin` 收起來的是「此刻持有 server_admin 授予的那幾行」，
///   判據是後端現讀的授予，不是暱稱、顯示名或任何前端標籤；界面把這件事講成一句人話，
///   免得有人拿「把他改名成平民」當成把人放回的辦法（那名冊卡的 `admin_identity` 才是依據）。
/// * 按鈕只由服務端讀回的活動狀態決定：草稿、開放、停止都還能準備這欄配置
///   （它屬活動自己的資料，與名稱描述同側；玩家讀不讀得到東西是模式自己回答的問題）；
///   歸檔收起控件並說「這件事已結束」（2029）；表外狀態一律當不可寫。
/// * 表外的模式取值不長出保存控件：那種情況下連「依據值」都只能是猜的，
///   而猜一份送出去就是拿一次寫入去探資料庫。
/// * 現值過期（2013）時收起寫入控件，只留「重新讀取這場活動」一個出口；
///   結果不明（連不上、逾時）絕不自動補發，由人重讀再決定。
/// * 成功句只在寫入回應回來之後出現，內容取回應回讀的現值：保存成功前不顯示「已完成」。
/// * 保存成功後本頁重讀詳情與名冊、頁面重讀目錄：倉庫裡沒有別處快取「目錄開到多大」，
///   今日也沒實時推送層可宣稱——失效的就是「下一次請求按新規則判定」這一句。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 活動的「玩家目錄可見性」配置卡。
class MemberDirectoryConfigCard extends StatefulWidget {
  /// 以端點介面、活動標識、服務端讀回的狀態與模式現值建立本卡。
  const MemberDirectoryConfigCard({
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

  /// 服務端讀回的目錄模式現值，同時是本卡提交時的 compare-and-set 依據值。
  final String currentMode;

  /// 「重新讀取這場活動」的動作：2013 與載入失敗都只有這一個出口。
  final VoidCallback onReload;

  /// 任意一次保存成功的回呼，帶著回應回讀的現值：父層據此更新自己那份底稿，
  /// 也讓名冊卡看到的「這一行現在被誰看見」跟同一個現值（不做本地拼裝）。
  final ValueSetter<DirectorySaveResult>? onSaved;

  /// 載入中說明識別鍵。
  static const Key loadingKey = ValueKey<String>('member-directory-loading');

  /// 現值列識別鍵。
  static const Key currentKey = ValueKey<String>('member-directory-current');

  /// 模式選項識別鍵（整項容器）。
  static Key optionKey(String mode) =>
      ValueKey<String>('member-directory-option-$mode');

  /// 某一項的「選取」按鈕識別鍵：點一下只改本地選中的那一項，仍要經確認才送出。
  static Key pickKey(String mode) =>
      ValueKey<String>('member-directory-pick-$mode');

  /// 保存按鈕識別鍵。
  static const Key saveKey = ValueKey<String>('member-directory-save');

  /// 取消識別鍵。
  static const Key cancelKey = ValueKey<String>('member-directory-cancel');

  /// 重新讀取識別鍵（2013 與載入失敗共用那個出口）。
  static const Key reloadKey = ValueKey<String>('member-directory-reload');

  /// 確認對話框肯定按鈕識別鍵。
  static const Key confirmKey = ValueKey<String>('member-directory-confirm');

  /// 歸檔只讀列識別鍵。
  static const Key archivedKey = ValueKey<String>('member-directory-archived');

  /// 表外取值交代列識別鍵。
  static const Key unknownKey = ValueKey<String>('member-directory-unknown');

  /// 提示列識別鍵（本地校驗與失敗轉述共用）。
  static const Key noticeKey = ValueKey<String>('member-directory-notice');

  /// 保存成功列識別鍵。
  static const Key savedKey = ValueKey<String>('member-directory-saved');

  @override
  State<MemberDirectoryConfigCard> createState() =>
      _MemberDirectoryConfigCardState();
}

/// 一次配置保存讀回的事實（本卡只需要模式一格，因此不要求整份活動）。
class DirectorySaveResult {
  /// 以已驗證的現值建立一份結果。
  const DirectorySaveResult({required this.memberDirectoryMode});

  /// 寫入後服務端回讀的模式現值。
  final String memberDirectoryMode;
}

class _MemberDirectoryConfigCardState extends State<MemberDirectoryConfigCard> {
  /// 本卡選定的模式；null 表示還沒選（底稿就是目前的現值，不預先假裝有人改過）。
  String? _selected;

  /// 目前介面語言對應的 Accept-Language 標記。
  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  bool _writing = false;
  bool _stale = false;
  String? _notice;
  String? _saved;

  /// 已批準可寫的目錄模式集合（界面只列這四個，取值語意由後端那一欄的封閉集合定義）。
  static const List<String> _modes = <String>[
    'hidden',
    'same_faction_only',
    'all_players_except_admin',
    'all_members',
  ];

  /// 現值是不是已批準的四個取值之一：表外值不長出寫入控件（理由見檔頭）。
  bool get _knownMode => _modes.contains(widget.currentMode);

  /// 本卡此刻準不準寫：只採信服務端讀回的活動狀態——歸檔是終態一律收起控件，
  /// 其餘三態都能準備這一欄配置（與自選配置卡、名冊卡同一取向）。
  bool get _canWrite => _knownMode && !_isArchived && !_stale;

  /// 是否已歸檔（界面要如實說那一句，而不是靜默收起控件讓人以為載入壞了）。
  bool get _isArchived => widget.activityStatus == 'archived';

  /// 模式取值的人話名稱；表外值照實顯示原值，不靜默歸類成某一態。
  String _modeLabel(AppLocalizations l10n, String mode) {
    return switch (mode) {
      'hidden' => l10n.memberDirectoryModeHidden,
      'same_faction_only' => l10n.memberDirectoryModeSameFaction,
      'all_players_except_admin' => l10n.memberDirectoryModeExceptAdmin,
      'all_members' => l10n.memberDirectoryModeAllMembers,
      _ => l10n.memberDirectoryModeUnknown(mode),
    };
  }

  /// 每一態的語意說明（表外值沒有說明可給：那一格只把原值唸出來）。
  String? _modeHint(AppLocalizations l10n, String mode) {
    return switch (mode) {
      'hidden' => l10n.memberDirectoryModeHintHidden,
      'same_faction_only' => l10n.memberDirectoryModeHintSameFaction,
      'all_players_except_admin' => l10n.memberDirectoryModeHintExceptAdmin,
      'all_members' => l10n.memberDirectoryModeHintAllMembers,
      _ => null,
    };
  }

  /// 走一次配置寫入：本體恰好兩格（新模式與它所依據的現值）。
  ///
  /// 成功後以父層的重讀收尾而不是本地蓋值：回應裡那一欄才是寫進去的事實，
  /// 而「這一行現在被誰看見」還要問每一行自己的覆蓋，那屬服務端的派生值。
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
          .updateMemberDirectoryMode(
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
        _saved = l10n.memberDirectorySavedNotice;
        _stale = false;
      });
      widget.onSaved?.call(
        DirectorySaveResult(
          memberDirectoryMode: report.activity.memberDirectoryMode,
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
        title: Text(l10n.memberDirectoryConfirmTitle),
        content: Text(
          l10n.memberDirectoryConfirmBody(_modeLabel(l10n, picked)),
        ),
        actions: <Widget>[
          TextButton(
            key: MemberDirectoryConfigCard.cancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.activityConfirmCancelAction),
          ),
          FilledButton(
            key: MemberDirectoryConfigCard.confirmKey,
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
              l10n.memberDirectoryCardTitle,
              style: theme.textTheme.titleSmall,
            ),
            if (_writing)
              Text(
                l10n.activityLoadingNotice,
                key: MemberDirectoryConfigCard.loadingKey,
                style: theme.textTheme.bodySmall,
              ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  l10n.memberDirectoryCurrentModeLabel,
                  key: MemberDirectoryConfigCard.currentKey,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(_modeLabel(l10n, widget.currentMode)),
              ],
            ),
            if (!_knownMode) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                l10n.memberDirectoryUnknownBlocksNotice,
                key: MemberDirectoryConfigCard.unknownKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_isArchived) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                l10n.memberDirectoryArchivedNotice,
                key: MemberDirectoryConfigCard.archivedKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_knownMode && !_isArchived) ...<Widget>[
              const SizedBox(height: 8),
              // 四個取值各自成項，並且每一項把自己那句語意直接攤開顯示：
              // 「尚未分組的人彼此看不見」與「持有授予者被收起來」這兩句必須在選之前
              // 就讀得到，而不是等有人對著空目錄回報 bug 時才解釋。
              for (final String mode in _modes)
                Padding(
                  key: MemberDirectoryConfigCard.optionKey(mode),
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
                          key: MemberDirectoryConfigCard.pickKey(mode),
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
                    key: MemberDirectoryConfigCard.saveKey,
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
                    child: Text(l10n.memberDirectorySaveAction),
                  ),
                  if (_stale || _notice != null)
                    OutlinedButton(
                      key: MemberDirectoryConfigCard.reloadKey,
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
                key: MemberDirectoryConfigCard.savedKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_notice != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _notice!,
                key: MemberDirectoryConfigCard.noticeKey,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
