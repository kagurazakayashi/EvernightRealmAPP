/// 讀取建置期注入的應用資訊。
///
/// 版號一律由建置指令注入（`--dart-define=ER_BUILD_VERSION=x.y.z`），
/// 不在執行期推測、也不在本檔寫死，避免與 `pubspec.yaml` 的版本口徑分岔。
library;

import 'package:flutter/foundation.dart';

import 'app_copy.dart';

/// 應用的建置資訊。
///
/// 注入缺席時如實回報「未指定」，不以假版號冒充正式構建。
@immutable
class AppInformation {
  /// 建立建置資訊，預設讀取編譯期參數。
  const AppInformation({this.buildVersion = injectedBuildVersion});

  /// 版號的編譯期參數名稱。
  static const String buildVersionKey = 'ER_BUILD_VERSION';

  /// 編譯期注入的版號，未取得時為空字串。
  static const String injectedBuildVersion = String.fromEnvironment(
    buildVersionKey,
  );

  /// 版號字串，空字串代表建置時未注入。
  final String buildVersion;

  /// 是否已取得注入版號。
  bool get hasBuildVersion => buildVersion.isNotEmpty;

  /// 給介面顯示的版號文字。
  ///
  /// 未注入時回傳〔未指定〕，讓狀態條呈現真實情況。
  String get displayVersion =>
      hasBuildVersion ? buildVersion : AppCopy.valueNotProvided;
}
