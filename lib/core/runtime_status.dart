/// 狀態條顯示用的一組執行期事實。
///
/// 本檔只保存事實與判定，不產出介面文字：狀態對應的顯示字串由元件層
/// 依目前語言向 AppLocalizations 取得，因此這裡不硬編碼任何語言。
///
/// 連線狀態與伺服器位址**不**在此處：它們的唯一來源分別是
/// `ConnectionTracker`（探測結果）與 `ServerApiConfig`（組態），
/// 複述一份只會出現兩個版本，不會出現正確的那個。
library;

import 'package:flutter/foundation.dart';

import 'app_information.dart';

/// 應用殼狀態條所需的一組執行期事實。
///
/// 這裡只放「取得到、且如實可顯示」的資訊；未取得的能力不在此處佔位，
/// 由元件層直接呈現「未設定」「尚未探測」等事實。
@immutable
class RuntimeStatus {
  /// 以建置資訊建立狀態。
  const RuntimeStatus({required this.information});

  /// 僅有建置資訊的狀態：不含任何業務資料。
  const RuntimeStatus.informationOnly() : information = const AppInformation();

  /// 應用建置資訊。
  final AppInformation information;
}
