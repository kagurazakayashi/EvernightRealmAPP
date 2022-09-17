/// 會話相關介面測試的共用助手：記憶體安全儲存假件與「已登入」控制器的快速組裝。
///
/// 刻意沿用 [SessionPersistence] 協定做假件——測試演練的是真實控制器的狀態機，
/// 假件只取代「平台安全儲存」這一端；不把控制器替換成假物件，才不会出現
/// 「測試通過但真實控制器的分支沒被走過」的空白。
library;

import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/core/session/session_persistence.dart';

import 'test_server.dart';

/// 以記憶體欄位模擬「按伺服器身份保存秘密」的安全儲存，可安排讀寫刪失敗。
class InMemorySessionPersistence implements SessionPersistence {
  /// 以既有內容建立假件。
  InMemorySessionPersistence([Map<String, String>? seeded])
    : secrets = <String, String>{...?seeded};

  /// 各伺服器身份已保存的秘密。
  final Map<String, String> secrets;

  /// 不為 `null` 時，讀取一律拋出該物件。
  Object? failReadWith;

  /// 不為 `null` 時，寫入一律拋出該物件。
  Object? failWriteWith;

  /// 不為 `null` 時，刪除一律拋出該物件。
  Object? failClearWith;

  /// 依身份記錄的讀取次數。
  final Map<String, int> readCounts = <String, int>{};

  @override
  Future<String?> readSecret(String serverIdentity) {
    final Object? failure = failReadWith;
    if (failure != null) {
      throw failure;
    }
    readCounts.update(serverIdentity, (int n) => n + 1, ifAbsent: () => 1);
    return Future<String?>.value(secrets[serverIdentity]);
  }

  @override
  Future<void> writeSecret(String serverIdentity, String secret) {
    final Object? failure = failWriteWith;
    if (failure != null) {
      throw failure;
    }
    secrets[serverIdentity] = secret;
    return Future<void>.value();
  }

  @override
  Future<void> clearSecret(String serverIdentity) {
    final Object? failure = failClearWith;
    if (failure != null) {
      throw failure;
    }
    secrets.remove(serverIdentity);
    return Future<void>.value();
  }
}

/// 一份合同內的 Root 登入成果（秘密可指定，便於斷言保存與注入）。
LoginExchange rootExchange({String secret = 'tok-root-1'}) {
  return LoginExchange(
    report: LoginReport(
      subjectKind: AuthSubjectKind.root,
      accountId: null,
      deviceId: 'device-77',
      expiresAt: DateTime.utc(2026, 10, 2, 3, 4, 5),
      requestId: 'r-login-root',
    ),
    sessionSecret: secret,
  );
}

/// 一份合同內的普通帳戶登入成果。
LoginExchange accountExchange(
  String accountId, {
  String secret = 'tok-acct-1',
}) {
  return LoginExchange(
    report: LoginReport(
      subjectKind: AuthSubjectKind.account,
      accountId: accountId,
      deviceId: 'device-88',
      expiresAt: DateTime.utc(2026, 10, 2, 3, 4, 5),
      requestId: 'r-login-acct',
    ),
    sessionSecret: secret,
  );
}

/// 建立原生形态的會話控制器（測試直接掌控持久化假件）。
SessionController nativeSession({
  required ServerApi api,
  required ServerAddressSettings addresses,
  required InMemorySessionPersistence persistence,
}) {
  return SessionController(
    api: api,
    addresses: addresses,
    mode: SessionTransportMode.native,
    persistence: persistence,
  );
}

/// 以一份既成登入成果把控制器推到已登入，供「先登入再操作」的介面測試使用。
///
/// 綁定位址取 [addresses] 的生效位址：與真實流程一樣，登入結果描述的就是那台
/// 伺服器；測試要在別台位址上演練時，先改位址再呼叫。
Future<SessionController> signedInSession({
  required ServerApi api,
  required ServerAddressSettings addresses,
  required InMemorySessionPersistence persistence,
  required LoginExchange exchange,
}) async {
  final ServerAddress server = ServerAddress.tryParse(
    addresses.currentUrl() ?? testBaseUrl,
  )!;
  final SessionController session = nativeSession(
    api: api,
    addresses: addresses,
    persistence: persistence,
  );
  await session.completeLogin(server, exchange);
  return session;
}
