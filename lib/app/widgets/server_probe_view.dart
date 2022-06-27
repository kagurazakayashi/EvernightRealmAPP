/// 伺服器連通性探測區：讀取存活與校時端點，把結果如實呈現。
///
/// 設計前提（完成判斷要求「網路錯誤不顯示為成功」）：
/// 1. 數值一律來自 [ConnectionTracker]，本元件不自行發請求也不自行判定；
/// 2. 失敗時只顯示失敗類別文字與診斷資訊，**不保留任何看起來像成功的數值**；
/// 3. 位址未設定時按鈕停用並說明原因，不拿預設位址去試。
///
/// 所有顯示文字取自本地化資源；本檔不出現任何語言的硬編碼字串。
library;

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/connection_tracker.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';
import '../api_error_labels.dart';
import '../connection_scope.dart';

/// 伺服器連通性探測區。
class ServerProbeView extends StatelessWidget {
  /// 建立探測區。
  const ServerProbeView({super.key});

  /// 探測按鈕的測試識別鍵。
  static const Key actionKey = ValueKey<String>('server-probe-action');

  /// 失敗說明的測試識別鍵。
  static const Key failureKey = ValueKey<String>('server-probe-failure');

  /// 成功數值清單的測試識別鍵。
  static const Key successKey = ValueKey<String>('server-probe-success');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ConnectionTracker tracker = ConnectionScope.of(context);
    final ServerConnectionPhase phase = tracker.phase;

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
              Text(l10n.serverProbeTitle, style: theme.textTheme.titleSmall),
              _ProbeButton(tracker: tracker),
            ],
          ),
          const SizedBox(height: 6),
          Text(l10n.serverProbeSummary, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            l10n.labelValuePair(
              l10n.serverProbeAddressLabel,
              tracker.addressDisplay ?? l10n.serverAddressNotSet,
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          // 階段的文字由殼的狀態條承擔（它在所有頁面持續可見），
          // 此處只放該階段才有的說明、進行中提示或結果，避免同屏重複。
          ...switch (phase) {
            ServerConnectionPhase.notConfigured => <Widget>[
              _Note(text: l10n.serverProbeNotConfiguredHint),
            ],
            ServerConnectionPhase.notProbed => <Widget>[
              _Note(text: l10n.serverProbeNever),
            ],
            ServerConnectionPhase.probing => <Widget>[_RunningNote()],
            ServerConnectionPhase.probeSucceeded => <Widget>[
              if (tracker.result case final ServerProbeResult result)
                _SuccessBlock(result: result),
            ],
            ServerConnectionPhase.probeFailed => <Widget>[
              if (tracker.error case final ApiError error)
                _FailureBlock(error: error),
            ],
          },
        ],
      ),
    );
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

/// 探測進行中的提示。
class _RunningNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
          Flexible(
            child: Text(
              l10n.serverProbeRunning,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 探測按鈕：位址不可用或正在探測時停用。
class _ProbeButton extends StatelessWidget {
  /// 以追蹤器建立按鈕。
  const _ProbeButton({required this.tracker});

  /// 連線探測狀態。
  final ConnectionTracker tracker;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SizedBox(
      // 固定高度，避免窄屏下按鈕隨文字長度撐出不同高度。
      height: 36,
      child: FilledButton(
        key: ServerProbeView.actionKey,
        onPressed: tracker.isConfigured && !tracker.isProbing
            ? () {
                // 送出的 Accept-Language 採目前介面語言的標識，讓伺服器的
                // 診斷訊息與介面同語言；介面文字本身仍一律取自本地化資源。
                final AppLocale locale = resolveAppLocale(
                  Localizations.localeOf(context),
                );
                tracker.probe(acceptLanguage: locale.tag);
              }
            : null,
        child: Text(switch (tracker.phase) {
          ServerConnectionPhase.probeSucceeded ||
          ServerConnectionPhase.probeFailed => l10n.serverProbeRetryAction,
          _ => l10n.serverProbeAction,
        }),
      ),
    );
  }
}

/// 探測成功的數值區塊。
class _SuccessBlock extends StatelessWidget {
  /// 以探測結果建立區塊。
  const _SuccessBlock({required this.result});

  /// 成功的探測結果。
  final ServerProbeResult result;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final HealthReport health = result.health;
    final ServerTimeReport time = result.time;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        key: ServerProbeView.successKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.serverProbeSucceeded, style: theme.textTheme.bodyMedium),
          Text(
            l10n.labelValuePair(l10n.serverProbeStatusLabel, health.status),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.labelValuePair(
              l10n.serverProbeServiceLabel,
              '${health.service} ${health.version}',
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.labelValuePair(l10n.serverProbeTimeLabel, time.timeText),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.labelValuePair(
              l10n.serverProbeClockLabel,
              '${time.displayClock} (${time.timezone} ${time.utcOffsetText})',
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.labelValuePair(l10n.diagnosticRequestId, time.requestId),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 探測失敗的說明區塊：只顯示失敗類別文字與語言無關的診斷資訊。
class _FailureBlock extends StatelessWidget {
  /// 以失敗原因建立區塊。
  const _FailureBlock({required this.error});

  /// 上次探測失敗的原因。
  final ApiError error;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String? requestId = error.requestId;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        key: ServerProbeView.failureKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.serverProbeFailed, style: theme.textTheme.bodyMedium),
          Text(
            apiErrorText(l10n, error),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          if (error.machineCode != null)
            Text(
              l10n.labelValuePair(
                l10n.diagnosticErrorCode,
                '${error.machineCode}',
              ),
              style: theme.textTheme.bodySmall,
            ),
          if (requestId != null && requestId.isNotEmpty)
            Text(
              l10n.labelValuePair(l10n.diagnosticRequestId, requestId),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
