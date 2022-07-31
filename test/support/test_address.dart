/// 位址設定測試的共用助手：記憶體持久化、可預期成敗的驗證器與組裝捷徑。
///
/// 成功路徑刻意沿用 `stubApi()` 的假傳輸，讓「驗證通過」這件事仍走真實的
/// 解碼與合同判定程式碼，而不是直接塞一個構造好的成功值。
library;

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_address.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';

import 'test_server.dart';

/// 測試統一使用的「驗證得通」位址（比對正規化後的顯示文字）。
const String reachableUrl = 'http://10.0.0.5:5206';

/// 以記憶體欄位模擬位址持久化，可指定寫入失敗以驗證「落盤成功才改狀態」。
class InMemoryServerAddressPersistence implements ServerAddressPersistence {
  /// 以初始已存位址建立假實作。
  InMemoryServerAddressPersistence([this.url]);

  /// 目前保存的位址文字，`null` 代表未設定。
  String? url;

  /// 不為 `null` 時，寫入與清除一律拋出該物件。
  Object? failWith;

  /// 寫入次數。
  int writeCount = 0;

  /// 清除次數。
  int clearCount = 0;

  @override
  Future<String?> readUrl() async => url;

  @override
  Future<void> writeUrl(String value) async {
    final Object? failure = failWith;
    if (failure != null) {
      throw failure;
    }
    url = value;
    writeCount++;
  }

  @override
  Future<void> clearUrl() async {
    final Object? failure = failWith;
    if (failure != null) {
      throw failure;
    }
    url = null;
    clearCount++;
  }
}

/// 僅對列在其中的位址回傳「連得通」，並記錄每一趟被驗證的位址。
class StubAddressVerifier {
  /// 以可達位址清單建立驗證器。
  StubAddressVerifier({this.reachable = const <String>[]});

  /// 視為可達的位址（比對正規化後的顯示文字）。
  final List<String> reachable;

  /// 依序記錄被驗證過的位址；用於斷言「格式錯誤時一個請求都沒發」。
  final List<String> checked = <String>[];

  /// 被驗證過的次數。
  int get callCount => checked.length;

  /// 當成 `VerifyServerAddress` 使用。
  Future<ServerProbeOutcome> call(
    ServerAddress address, {
    String? acceptLanguage,
  }) async {
    checked.add(address.displayText);
    if (!reachable.contains(address.displayText)) {
      return ServerProbeOutcome.failure(
        ApiError(
          kind: ApiErrorKind.unreachable,
          path: kHealthPath,
          cause: 'fake: 位址不在可達清單內',
        ),
      );
    }
    return probeServerConnectivity(stubApi());
  }
}

/// 建立已完成載入的位址設定（測試直接用它組裝應用）。
Future<ServerAddressSettings> buildAddressSettings({
  String? storedUrl,
  String? injectedUrl,
  bool? preferInjected,
  List<String> reachable = const <String>[],
  ServerAddressPersistence? persistence,
  VerifyServerAddress? verifier,
}) async {
  final ServerAddressSettings settings = ServerAddressSettings(
    persistence ?? InMemoryServerAddressPersistence(storedUrl),
    injectedUrl: injectedUrl,
    preferInjected: preferInjected ?? false,
    verifier: verifier ?? StubAddressVerifier(reachable: reachable).call,
  );
  await settings.restore();
  return settings;
}
