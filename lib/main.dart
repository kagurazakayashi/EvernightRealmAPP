import 'package:flutter/widgets.dart';

import 'app/app_dependencies.dart';
import 'app/evernight_app.dart';
import 'core/api/connection_tracker.dart';
import 'core/language_settings.dart';
import 'platform/shared_preferences_language_store.dart';

/// 應用進入點：組裝依賴與語言設定後啟動應用殼。
///
/// 版號等建置資訊由編譯期參數帶入，這裡不做任何推測；
/// 語言選擇先從本地讀取再啟動，避免啟動後先閃一下另一種語言；
/// 連線追蹤器的生命週期與應用同長，因此由本處建立並交給根節點暴露；
/// 啟動階段不填入示範資料——頁面出現的每個值都必須有真實來源。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final LanguageSettings language = LanguageSettings(
    const SharedPreferencesLanguageStore(),
    systemLocale: WidgetsBinding.instance.platformDispatcher.locale,
  );
  await language.restore();

  final AppDependencies dependencies = AppDependencies.assembled();
  final ConnectionTracker connection = ConnectionTracker(dependencies.api);

  runApp(
    EvernightApp(
      dependencies: dependencies,
      language: language,
      connection: connection,
    ),
  );
}
