/// 使用者端與伺服器的連線狀態，以及狀態條顯示用的一組執行期事實。
library;

import 'package:flutter/foundation.dart';

import 'app_copy.dart';
import 'app_information.dart';

/// 與伺服器的連線狀態。
///
/// 目前只有一個真實存在的狀態：網路層尚未接上。刻意不預先列舉「已連線」「斷線」
/// 等尚無來源的狀態，避免介面出現無依據的判斷。
enum ServerConnectionState {
  /// 尚未建立任何與伺服器的連線（網路層未實作）。
  notWired;

  /// 給狀態條顯示的連線狀態文字。
  String get displayLabel {
    return switch (this) {
      ServerConnectionState.notWired => AppCopy.connectionNotWired,
    };
  }
}

/// 應用殼狀態條所需的一組執行期事實。
///
/// 這裡只放「取得到、且如實可顯示」的資訊；伺服器位址與連線狀態在對應能力
/// 實作前保持未設定與未接上，讓狀態條呈現事實而非佔位假值。
@immutable
class RuntimeStatus {
  /// 以建置資訊與（可選的）伺服器位址建立狀態。
  const RuntimeStatus({
    required this.information,
    this.serverAddress,
    this.connection = ServerConnectionState.notWired,
  });

  /// 僅有建置資訊的狀態：伺服器位址未設定、網路層未接上。
  const RuntimeStatus.informationOnly()
    : information = const AppInformation(),
      serverAddress = null,
      connection = ServerConnectionState.notWired;

  /// 應用建置資訊。
  final AppInformation information;

  /// 伺服器位址；`null` 代表尚未設定（位址輸入尚未實作）。
  final String? serverAddress;

  /// 目前連線狀態。
  final ServerConnectionState connection;

  /// 狀態條顯示的伺服器位址文字。
  String get serverAddressLabel => serverAddress ?? AppCopy.serverAddressNotSet;

  /// 狀態條顯示的連線狀態文字。
  String get connectionLabel => connection.displayLabel;
}
