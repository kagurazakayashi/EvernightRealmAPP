/// 管理側的「有效能力與來源摘要」對話框。
///
/// 它是派生讀法：成員行、狀態能力矩陣、活動生命週期與帳戶狀態各自現讀一次，
/// 再按同一套組合規則合成。對話框刻意把逐來源布林翻成四句來源標籤：
/// 管理人解除手動項之後，如果狀態仍拒絕，這裡會如實顯示「仍被狀態限制」，
/// 不會因為手動那一欄翻回 false 就念「已解凍」。
///
/// 它不顯示審計原因、操作者、時刻、內部備註或任何帳戶隱私；查無成員、跨活動與
/// 幽靈活動都由統一錯誤對映收斂成 1001。
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

/// 管理側成員有效能力對話框。
class MemberCapabilitiesDialog extends StatefulWidget {
  /// 以端點介面、活動與成員建立對話框。
  const MemberCapabilitiesDialog({
    super.key,
    required this.api,
    required this.activityId,
    required this.member,
  });

  /// 統一端點存取介面。
  final ServerApi api;

  /// 歸屬活動的標識。
  final String activityId;

  /// 那一行的服務端現值（暱稱只用於標題，不作為任何判定依據）。
  final MemberReport member;

  /// 對話框標題識別鍵。
  static const Key titleKey = ValueKey<String>('member-capabilities-title');

  /// 載入中識別鍵。
  static const Key loadingKey = ValueKey<String>(
    'member-capabilities-loading',
  );

  /// 失敗提示識別鍵。
  static const Key noticeKey = ValueKey<String>('member-capabilities-notice');

  /// 摘要容器識別鍵。
  static const Key reportKey = ValueKey<String>('member-capabilities-report');

  /// 進入資格那一行識別鍵。
  static const Key accessLineKey = ValueKey<String>(
    'member-capabilities-access-line',
  );

  /// 某項能力那一行識別鍵。
  static Key capabilityRowKey(String capability) =>
      ValueKey<String>('member-capabilities-row-$capability');

  /// 常駐邊界句識別鍵。
  static const Key boundaryKey = ValueKey<String>(
    'member-capabilities-boundary',
  );

  /// 重讀按鈕識別鍵。
  static const Key reloadKey = ValueKey<String>('member-capabilities-reload');

  /// 失敗後那顆重試按鈕的識別鍵（與底部的重讀分開）。
  static const Key retryKey = ValueKey<String>('member-capabilities-retry');

  /// 關閉按鈕識別鍵。
  static const Key closeKey = ValueKey<String>('member-capabilities-close');

  @override
  State<MemberCapabilitiesDialog> createState() =>
      _MemberCapabilitiesDialogState();
}

class _MemberCapabilitiesDialogState extends State<MemberCapabilitiesDialog> {
  MemberCapabilitiesReport? _report;
  bool _loading = true;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  Future<void> _load() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _notice = null;
    });
    try {
      final MemberCapabilitiesReport report = await widget.api
          .memberCapabilities(
            activityId: widget.activityId,
            memberId: widget.member.memberId,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _report = report;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _report = null;
        _notice = apiErrorText(l10n, error);
      });
    }
  }

  String _activityStatusLabel(AppLocalizations l10n, String status) {
    return switch (status) {
      'draft' => l10n.activityStatusDraftLabel,
      'active' => l10n.activityStatusActiveLabel,
      'closed' => l10n.activityStatusClosedLabel,
      'archived' => l10n.activityStatusArchivedLabel,
      _ => status,
    };
  }

  String _accountStatusLabel(AppLocalizations l10n, String status) {
    return switch (status) {
      'active' => l10n.memberStatusActiveLabel,
      'disabled' => l10n.memberStatusDisabledLabel,
      '' => l10n.memberAccountUnreadableNotice,
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final MemberCapabilitiesReport? report = _report;
    return AlertDialog(
      title: Text(
        l10n.memberCapabilitiesTitle(widget.member.nickname),
        key: MemberCapabilitiesDialog.titleKey,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_loading)
                Text(
                  l10n.activityLoadingNotice,
                  key: MemberCapabilitiesDialog.loadingKey,
                ),
              if (_notice != null) ...<Widget>[
                Text(
                  _notice!,
                  key: MemberCapabilitiesDialog.noticeKey,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    key: MemberCapabilitiesDialog.retryKey,
                    onPressed: _load,
                    child: Text(l10n.activityReloadAction),
                  ),
                ),
              ],
              if (report != null) ...<Widget>[
                Text(
                  report.accessAllowed
                      ? l10n.memberCapabilitiesAccessAllowed
                      : l10n.memberCapabilitiesAccessDenied,
                  key: MemberCapabilitiesDialog.accessLineKey,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.labelValuePair(
                    l10n.memberCapabilitiesBusinessStatusLabel,
                    builtinBusinessStatusLabel(l10n, report.businessStatus) ??
                        report.businessStatus,
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  l10n.labelValuePair(
                    l10n.memberCapabilitiesActivityStatusLabel,
                    _activityStatusLabel(l10n, report.activityStatus),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  l10n.labelValuePair(
                    l10n.memberCapabilitiesAccountStatusLabel,
                    _accountStatusLabel(l10n, report.accountStatus),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  l10n.capabilityRulesRevisionLine(report.rulesRevision),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Column(
                  key: MemberCapabilitiesDialog.reportKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final MemberCapabilityDecision item
                        in report.capabilities)
                      Padding(
                        key: MemberCapabilitiesDialog.capabilityRowKey(
                          item.capability,
                        ),
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              l10n.labelValuePair(
                                capabilityLabel(l10n, item.capability),
                                item.allowed
                                    ? l10n.capabilityAllowedValue
                                    : l10n.capabilityDeniedValue,
                              ),
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (item.sources.isNotEmpty)
                              Text(
                                capabilitySourcesLine(l10n, item.sources),
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.memberCapabilitiesBoundaryNote,
                  key: MemberCapabilitiesDialog.boundaryKey,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: MemberCapabilitiesDialog.reloadKey,
          onPressed: _loading ? null : _load,
          child: Text(l10n.activityReloadAction),
        ),
        FilledButton(
          key: MemberCapabilitiesDialog.closeKey,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.activityConfirmOkAction),
        ),
      ],
    );
  }
}
