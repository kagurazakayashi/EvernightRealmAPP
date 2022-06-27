import 'package:flutter/widgets.dart';

import 'app/app_dependencies.dart';
import 'app/bootstrap.dart';
import 'app/evernight_app.dart';
import 'core/api/connection_tracker.dart';
import 'core/api/server_address_settings.dart';
import 'core/diagnostics/diagnostics_hub.dart';
import 'core/language_settings.dart';
import 'platform/shared_preferences_language_store.dart';
import 'platform/shared_preferences_server_store.dart';

/// 應用進入點：先架好錯誤護欄，再組裝依賴與語言／位址設定並啟動應用殼。
///
/// 版號等建置資訊由編譯期參數帶入，這裡不做任何推測；
/// 語言選擇與伺服器位址都先從本地讀取再啟動，避免啟動後先閃一下另一種語言
/// 或先顯示「位址未設定」；位址來源以本機保存值為準（debug 建置例外），
/// 因此組裝端點介面時把設定物件當成唯一來源，而不是再抄一份位址文字。
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

      final ServerAddressSettings addresses = ServerAddressSettings(
        const SharedPreferencesServerAddressStore(),
      );
      await addresses.restore();

      final AppDependencies dependencies = AppDependencies.assembled(
        addresses: addresses,
      );
      final ConnectionTracker connection = ConnectionTracker(
        dependencies.api,
        addresses: addresses,
      );

      runApp(
        EvernightApp(
          dependencies: dependencies,
          language: language,
          addresses: addresses,
          connection: connection,
          diagnostics: diagnostics,
        ),
      );
    },
  );
}
