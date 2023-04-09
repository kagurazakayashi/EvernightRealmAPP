/// 能力鍵與拒絕來源在介面上的那一句（管理規則卡、成員來源摘要與玩家有效能力共用）。
///
/// 對照只有這一份：後端新增一個能力鍵或來源類別時，三處界面會一起落到「認不得」的
/// 通用句，而不是各自猜一個名字。鍵本身是穩定內部值，顯示名永遠來自 ARB。
library;

import '../l10n/app_localizations.dart';

/// 六項能力鍵的界面名；集合外的鍵照實唸原值，不猜一個名字。
String capabilityLabel(AppLocalizations l10n, String capability) {
  return switch (capability) {
    'login' => l10n.capabilityKeyLoginLabel,
    'chat' => l10n.capabilityKeyChatLabel,
    'private_chat' => l10n.capabilityKeyPrivateChatLabel,
    'trade' => l10n.capabilityKeyTradeLabel,
    'transfer' => l10n.capabilityKeyTransferLabel,
    'item_use' => l10n.capabilityKeyItemUseLabel,
    _ => capability,
  };
}

/// 四個拒絕來源類別的界面名；集合外的來源照實唸原值。
String capabilitySourceLabel(AppLocalizations l10n, String source) {
  return switch (source) {
    'identity' => l10n.capabilitySourceIdentityLabel,
    'lifecycle' => l10n.capabilitySourceLifecycleLabel,
    'status' => l10n.capabilitySourceStatusLabel,
    'manual' => l10n.capabilitySourceManualLabel,
    _ => source,
  };
}

/// 把來源清單換成「被誰拒絕」那一句；空清單回空字串（允許的能力不長這一行）。
String capabilitySourcesLine(
  AppLocalizations l10n,
  List<String> sources,
) {
  if (sources.isEmpty) {
    return '';
  }
  final String joined = sources
      .map((String source) => capabilitySourceLabel(l10n, source))
      .join(', ');
  return l10n.capabilitySourcesLine(joined);
}
