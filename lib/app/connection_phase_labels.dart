/// 連線探測階段的介面文字對照。
///
/// 狀態條與探測區讀同一份對應，避免兩個地方對同一個階段寫出不同的話。
library;

import '../core/api/connection_tracker.dart';
import '../l10n/app_localizations.dart';

/// 取得探測階段的顯示文字。
String connectionPhaseLabel(
  AppLocalizations l10n,
  ServerConnectionPhase phase,
) {
  return switch (phase) {
    ServerConnectionPhase.notConfigured => l10n.connectionNotConfigured,
    ServerConnectionPhase.notProbed => l10n.connectionNotProbed,
    ServerConnectionPhase.probing => l10n.connectionProbing,
    ServerConnectionPhase.probeSucceeded => l10n.connectionProbeOk,
    ServerConnectionPhase.probeFailed => l10n.connectionProbeFailed,
  };
}
