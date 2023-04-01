/// 玩家業務狀態在介面上的那句顯示名稱（管理名冊、玩家目錄與本人資料共用同一份換算）。
///
/// 規則只有一條來源，写在這裡是因為三處讀法都拿到同一份後端投影，而界面各自猜一次
/// 就會出現「列表唸預設、點進去唸覆蓋」這種兩個答案來源：
///
/// * `status_display_name` 非空就用它：那是服務端現讀的展示值（內建狀態的活動層級覆蓋，
///   或自訂定義的名稱）。它是純文字，只能當文字渲染，不得交給任何 HTML／富文本通路。
/// * 內建狀態沒有覆蓋時這一格是空字串，介面因此走四語言預設文案（`builtinStatus*` 七句）。
/// * 集合外的內部值（後端日後放寬集合時的多餘取值）照實唸出原值而不猜一個名字：
///   界面不替自己發明第二套狀態語意。
/// * custom 而定義讀不到時回 `null`：呼叫端改念「讀不到那個定義」那句通用話，
///   不編一個名稱，也不把整行判死。
library;

import '../l10n/app_localizations.dart';

/// 七個內建穩定值（順序與後端目錄一致；界面不以此排序，只以此判「是不是內建值」）。
const List<String> builtinBusinessStatuses = <String>[
  'normal',
  'suspended',
  'eliminated',
  'dead',
  'arrested',
  'offline',
  'custom',
];

/// 內建狀態的四語言預設顯示名（沒有活動層級覆蓋時走這裡）。
String? builtinBusinessStatusLabel(AppLocalizations l10n, String statusKey) {
  return switch (statusKey) {
    'normal' => l10n.builtinStatusNormal,
    'suspended' => l10n.builtinStatusSuspended,
    'eliminated' => l10n.builtinStatusEliminated,
    'dead' => l10n.builtinStatusDead,
    'arrested' => l10n.builtinStatusArrested,
    'offline' => l10n.builtinStatusOffline,
    'custom' => l10n.builtinStatusCustom,
    _ => null,
  };
}

/// 把一份狀態投影換成界面要念的那一句；回 `null` 表示「唸不出來」，呼叫端換成通用句。
///
/// [businessStatus] 是內部值、[statusDisplayName] 是服務端算好的展示值、
/// [customStatusName] 是自訂定義此刻的名稱——三者都取自同一次回應，介面不另拼。
String? businessStatusLabel({
  required AppLocalizations l10n,
  required String businessStatus,
  required String statusDisplayName,
  required String customStatusName,
}) {
  if (statusDisplayName.isNotEmpty) {
    return statusDisplayName;
  }
  if (businessStatus == 'custom') {
    // custom 而兩個名稱都讀不到：那個定義此刻不可讀，交給呼叫端念通用話。
    return customStatusName.isEmpty ? null : customStatusName;
  }
  final String? builtin = builtinBusinessStatusLabel(l10n, businessStatus);
  if (builtin != null) {
    return builtin;
  }
  // 集合外的取值：如實唸出服務端的原始值，不靜默歸類成某一態。
  return businessStatus;
}
