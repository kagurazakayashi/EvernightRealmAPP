import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'app/app_dependencies.dart';
import 'app/bootstrap.dart';
import 'app/evernight_app.dart';
import 'core/api/api_client.dart';
import 'core/api/connection_tracker.dart';
import 'core/api/server_address_settings.dart';
import 'core/api/server_api.dart';
import 'core/diagnostics/diagnostics_hub.dart';
import 'core/language_settings.dart';
import 'core/runtime_status.dart';
import 'core/session/session_controller.dart';
import 'core/session/session_persistence.dart';
import 'platform/flutter_secure_key_value_store.dart';
import 'platform/keyed_session_persistence.dart';
import 'platform/shared_preferences_language_store.dart';
import 'platform/shared_preferences_server_store.dart';

/// 應用進入點：先架好錯誤護欄，再組裝依賴與語言／位址／會話設定並啟動應用殼。
///
/// 版號等建置資訊由編譯期參數帶入，這裡不做任何推測；
/// 語言選擇與伺服器位址都先從本地讀取再啟動，避免啟動後先閃一下另一種語言
/// 或先顯示「位址未設定」；位址來源以本機保存值為準（debug 建置例外），
/// 因此組裝端點介面時把設定物件當成唯一來源，而不是再抄一份位址文字。
///
/// 會話层的组装是这一步的重点，也是「平台适配」唯一该发生的地方：
/// * 傳輸形态由 [kIsWeb] 一次定死——浏览器端會話由 HttpOnly Cookie 代管，
///   不建立任何安全儲存、不注入 Bearer；原生端才用系统级安全儲存保存秘密并注入。
/// * 端点介面在建立时就绑定「按请求身份取凭据」的闭包，闭包读取稍后才建好的控制器，
///   因此凭据注入集中在存取层，页面无从各自拼装 authorization 标头。
/// 連線追蹤器、會話控制器與失敗收集器的生命週期與應用同長，因此由本處建立；
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

      // 傳輸形态在此一次决定，之后各处只消费它，不再各自判断平台。
      final SessionTransportMode transportMode = kIsWeb
          ? SessionTransportMode.web
          : SessionTransportMode.native;
      // 只有原生端需要安全儲存；浏览器端永不落盘任何令牌（连内存中的秘密都不保留）。
      final SessionPersistence? persistence =
          transportMode == SessionTransportMode.native
          ? const KeyedSessionPersistence(FlutterSecureKeyValueStore())
          : null;

      // 先声明控制器槽位，让端点闭包能在请求时回读它（闭包延后取值，建立顺序不成环）。
      SessionController? controller;
      final ServerApi api = ServerApi(
        config: ServerApiConfig(
          source: addresses,
          transportMode: transportMode,
          credentials: (String serverIdentity) =>
              controller?.bearerFor(serverIdentity),
        ),
      );
      controller = SessionController(
        api: api,
        addresses: addresses,
        mode: transportMode,
        persistence: persistence,
      );

      final AppDependencies dependencies = AppDependencies(
        runtimeStatus: const RuntimeStatus.informationOnly(),
        api: api,
      );
      final ConnectionTracker connection = ConnectionTracker(
        api,
        addresses: addresses,
      );

      runApp(
        EvernightApp(
          dependencies: dependencies,
          language: language,
          addresses: addresses,
          connection: connection,
          session: controller,
          diagnostics: diagnostics,
        ),
      );
    },
  );
}
