import 'package:flutter/widgets.dart';

import 'app/app_dependencies.dart';
import 'app/bootstrap.dart';
import 'app/evernight_app.dart';
import 'core/api/connection_tracker.dart';
import 'core/diagnostics/diagnostics_hub.dart';
import 'core/language_settings.dart';
import 'platform/shared_preferences_language_store.dart';

/// 應用進入點：先架好錯誤護欄，再組裝依賴與語言設定並啟動應用殼。
///
/// 版號等建置資訊由編譯期參數帶入，這裡不做任何推測；
/// 語言選擇先從本地讀取再啟動，避免啟動後先閃一下另一種語言；
/// 連線追蹤器與失敗收集器的生命週期與應用同長，因此由本處建立；
/// 啟動流程整個包在護欄裡——綁定或讀設定階段就失敗時，仍會留下一筆已脫敏的
/// 記錄（此時畫面可能還是空的，因為應用殼尚未建起來，無處可蓋安全畫面）。
void main() {
  final DiagnosticsHub diagnostics = DiagnosticsHub();

  bootstrapApp(
    diagnostics: diagnostics,
    body: () async {
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
          diagnostics: diagnostics,
        ),
      );
    },
  );
}
