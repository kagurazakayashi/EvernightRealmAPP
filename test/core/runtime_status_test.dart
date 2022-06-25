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
    test('預設狀態只帶建置資訊，不含任何業務資料', () {
      const RuntimeStatus status = RuntimeStatus.informationOnly();

      expect(status.information.hasBuildVersion, isFalse);
    });

    test('建置資訊原樣保留給定的版號', () {
      const RuntimeStatus status = RuntimeStatus(
        information: AppInformation(buildVersion: '1.0.0'),
      );

      expect(status.information.buildVersion, '1.0.0');
    });
  });
}
