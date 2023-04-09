/// 「狀態能力規則」卡：管理員按活動維護七個內建狀態 × 六項能力的封鎖矩陣。
///
/// 這張卡只碰「狀態來源」：它不會覆蓋手動限制、活動生命週期或身份資格，
/// 也沒有任何一格能把手動限制或歸檔狀態改寫成別的語意。每一次判定都由服務端現讀，
/// 本卡保存後以回應的 revision 為準，不把本地那份當成下一份底稿。
///
/// 自訂狀態不參與矩陣：它的名稱由管理員自由填寫，讓名稱參與能力判定等於從名字
/// 推測行為。卡上因此只有一句說明，沒有自訂狀態的勾選格。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';
import '../business_status_labels.dart';
import '../capability_labels.dart';

/// 活動層級的狀態能力規則卡。
class ActivityCapabilityRulesCard extends StatefulWidget {
  /// 以端點介面、活動標識與活動現狀建立本卡。
  const ActivityCapabilityRulesCard({
    super.key,
    required this.api,
    required this.activityId,
    required this.activityStatus,
  });

  /// 統一端點存取介面。
  final ServerApi api;

  /// 歸屬活動的標識。
  final String activityId;

  /// 服務端讀回的活動狀態：歸檔時收起寫入控件，停止態仍可準備規則。
  final String activityStatus;

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>(
    'capability-rules-loading',
  );

  /// 載入或保存失敗那句的識別鍵。
  static const Key noticeKey = ValueKey<String>('capability-rules-notice');

  /// 保存成功句識別鍵。
  static const Key savedKey = ValueKey<String>('capability-rules-saved');

  /// revision 那一行識別鍵。
  static const Key revisionKey = ValueKey<String>('capability-rules-revision');

  /// 保存按鈕識別鍵。
  static const Key saveKey = ValueKey<String>('capability-rules-save');

  /// 重新讀取按鈕識別鍵。
  static const Key reloadKey = ValueKey<String>('capability-rules-reload');

  /// 載入或保存失敗後那顆重試按鈕的識別鍵（與底部的重讀分開，避免同一畫面兩個同鍵）。
  static const Key retryKey = ValueKey<String>('capability-rules-retry');

  /// 自訂狀態不參與矩陣那句的識別鍵。
  static const Key customNoteKey = ValueKey<String>(
    'capability-rules-custom-note',
  );

  /// 常駐邊界句識別鍵。
  static const Key boundaryKey = ValueKey<String>('capability-rules-boundary');

  /// 歸檔說明識別鍵。
  static const Key archivedKey = ValueKey<String>('capability-rules-archived');

  /// 某個狀態那一列的識別鍵。
  static Key statusRowKey(String statusKey) =>
      ValueKey<String>('capability-rules-status-$statusKey');

  /// 某一格的勾選識別鍵。
  static Key cellKey(String statusKey, String capabilityKey) =>
      ValueKey<String>('capability-rules-cell-$statusKey-$capabilityKey');

  @override
  State<ActivityCapabilityRulesCard> createState() =>
      _ActivityCapabilityRulesCardState();
}

class _ActivityCapabilityRulesCardState
    extends State<ActivityCapabilityRulesCard> {
  CapabilityRulesReport? _report;
  Map<String, Set<String>> _edits = <String, Set<String>>{};
  bool _loading = true;
  bool _writing = false;
  String? _notice;
  String? _saved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  bool get _canWrite => widget.activityStatus != 'archived';

  Map<String, Set<String>> _editsFrom(CapabilityRulesReport report) {
    return <String, Set<String>>{
      for (final String status in kCapabilityStatusKeys)
        status: report.deniedFor(status),
    };
  }

  bool get _dirty {
    final CapabilityRulesReport? report = _report;
    if (report == null) {
      return false;
    }
    for (final String status in kCapabilityStatusKeys) {
      final Set<String> current = report.deniedFor(status);
      final Set<String> edited = _edits[status] ?? const <String>{};
      if (current.length != edited.length ||
          !current.containsAll(edited)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _load() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _notice = null;
      _saved = null;
    });
    try {
      final CapabilityRulesReport report = await widget.api.capabilityRules(
        activityId: widget.activityId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _report = report;
        _edits = _editsFrom(report);
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _report = null;
        _edits = <String, Set<String>>{};
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  void _toggle(String status, String capability, bool selected) {
    final Set<String> next = <String>{
      ...(_edits[status] ?? const <String>{}),
    };
    if (selected) {
      next.add(capability);
    } else {
      next.remove(capability);
    }
    setState(() {
      _edits = <String, Set<String>>{..._edits, status: next};
      _saved = null;
      _notice = null;
    });
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final CapabilityRulesReport? report = _report;
    if (report == null || _writing || !_canWrite) {
      return;
    }
    if (!_dirty) {
      setState(() {
        _saved = l10n.capabilityRulesNothingChanged;
        _notice = null;
      });
      return;
    }
    setState(() {
      _writing = true;
      _notice = null;
      _saved = null;
    });
    try {
      final CapabilityRulesReport updated = await widget.api
          .updateCapabilityRules(
            activityId: widget.activityId,
            expectedRevision: report.revision,
            deniedByStatus: _edits,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        _report = updated;
        _edits = _editsFrom(updated);
        _saved = l10n.capabilityRulesSaved(updated.revision);
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _writing = false;
        // 衝突與其他失敗都不本地改寫底稿：要嘛重讀，要嘛關掉重開。
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final CapabilityRulesReport? report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.capabilityRulesCardTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(l10n.capabilityRulesIntro, style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        if (_loading)
          Text(l10n.activityLoadingNotice, key: ActivityCapabilityRulesCard.loadingKey),
        if (_notice != null) ...<Widget>[
          Text(
            _notice!,
            key: ActivityCapabilityRulesCard.noticeKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: ActivityCapabilityRulesCard.retryKey,
              onPressed: _writing ? null : _load,
              child: Text(l10n.capabilityRulesReloadAction),
            ),
          ),
        ],
        if (report != null) ...<Widget>[
          Text(
            report.configured
                ? l10n.capabilityRulesRevisionValue(report.revision)
                : l10n.capabilityRulesRevisionUnconfigured,
            key: ActivityCapabilityRulesCard.revisionKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          for (final String status in kCapabilityStatusKeys)
            Padding(
              key: ActivityCapabilityRulesCard.statusRowKey(status),
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    builtinBusinessStatusLabel(l10n, status) ?? status,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (status == 'custom')
                    Text(
                      l10n.capabilityRulesCustomNote,
                      key: ActivityCapabilityRulesCard.customNoteKey,
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final String capability in kCapabilityKeys)
                          FilterChip(
                            key: ActivityCapabilityRulesCard.cellKey(
                              status,
                              capability,
                            ),
                            label: Text(capabilityLabel(l10n, capability)),
                            selected:
                                (_edits[status] ?? const <String>{})
                                    .contains(capability),
                            onSelected: _canWrite && !_writing
                                ? (bool selected) =>
                                      _toggle(status, capability, selected)
                                : null,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            l10n.capabilityRulesBoundaryNote,
            key: ActivityCapabilityRulesCard.boundaryKey,
            style: theme.textTheme.bodySmall,
          ),
          if (!_canWrite) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              l10n.capabilityRulesArchivedNote,
              key: ActivityCapabilityRulesCard.archivedKey,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton(
                key: ActivityCapabilityRulesCard.saveKey,
                onPressed: _canWrite && !_writing ? _save : null,
                child: Text(l10n.capabilityRulesSaveAction),
              ),
              TextButton(
                key: ActivityCapabilityRulesCard.reloadKey,
                onPressed: _writing ? null : _load,
                child: Text(l10n.capabilityRulesReloadAction),
              ),
            ],
          ),
          if (_saved != null)
            Text(
              _saved!,
              key: ActivityCapabilityRulesCard.savedKey,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ],
    );
  }
}
