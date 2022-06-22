import 'package:flutter/widgets.dart';

import 'app/app_dependencies.dart';
import 'app/evernight_app.dart';

/// 應用進入點：組裝依賴後啟動應用殼。
///
/// 版號等建置資訊由編譯期參數帶入，這裡不做任何推測；
/// 也不在啟動階段填入示範資料——頁面出現的每個值都必須有真實來源。
void main() {
  runApp(EvernightApp(dependencies: AppDependencies.assembled()));
}
