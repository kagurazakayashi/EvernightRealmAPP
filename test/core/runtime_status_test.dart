/// 建置資訊與執行期狀態的測試：缺資料時必須如實回報，不得填補假值。
///
/// 這裡只驗資料與判定；顯示文字的正誤由本地化資源的測試負責。
library;

import 'package:evernight_realm/core/app_information.dart';
import 'package:evernight_realm/core/runtime_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppInformation', () {
    test('未取得注入版號時判定為沒有版號', () {
      const AppInformation information = AppInformation(buildVersion: '');

      expect(information.hasBuildVersion, isFalse);
    });

    test('取得注入版號時原樣保留該值', () {
      const AppInformation information = AppInformation(buildVersion: '1.0.0');

      expect(information.hasBuildVersion, isTrue);
      expect(information.buildVersion, '1.0.0');
    });

    test('版號的編譯期參數名稱固定', () {
      expect(AppInformation.buildVersionKey, 'ER_BUILD_VERSION');
    });
  });

  group('RuntimeStatus', () {
    test('預設狀態為伺服器位址未設定、網路層未接上', () {
      const RuntimeStatus status = RuntimeStatus.informationOnly();

      expect(status.serverAddress, isNull);
      expect(status.hasServerAddress, isFalse);
      expect(status.connection, ServerConnectionState.notWired);
    });

    test('給定伺服器位址後如實保留該位址', () {
      const RuntimeStatus status = RuntimeStatus(
        information: AppInformation(buildVersion: '1.0.0'),
        serverAddress: 'http://192.168.1.20:5206',
      );

      expect(status.hasServerAddress, isTrue);
      expect(status.serverAddress, 'http://192.168.1.20:5206');
    });
  });
}
