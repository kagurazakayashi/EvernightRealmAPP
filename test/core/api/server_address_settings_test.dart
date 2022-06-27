/// 伺服器位址設定的測試：來源優先序、必達才保存、寫入失敗不改狀態。
///
/// 這裡守住的三條結論：格式不合格時一個請求都不發；連不通時本機與狀態都不動；
/// 生效位址與已保存位址是分開的兩件事（debug 建置下注入值會壓過本機值）。
library;

import 'package:evernight_realm/core/api/server_address.dart';
import 'package:evernight_realm/core/api/server_address_settings.dart';
import 'package:evernight_realm/platform/shared_preferences_server_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_address.dart';
import '../../support/test_server.dart';

void main() {
  group('來源優先序', () {
    test('未注入也不保存時判定為未設定', () async {
      final ServerAddressSettings settings = await buildAddressSettings();

      expect(settings.currentUrl(), isNull);
      expect(settings.hasAddress, isFalse);
      expect(settings.origin, ServerAddressOrigin.unset);
      expect(settings.addressDisplay, isNull);
    });

    test('一般建置以本機保存值為準', () async {
      final ServerAddressSettings settings = await buildAddressSettings(
        storedUrl: reachableUrl,
        injectedUrl: 'http://build-parameter.invalid:5206',
        preferInjected: false,
      );

      expect(settings.currentUrl(), reachableUrl);
      expect(settings.origin, ServerAddressOrigin.saved);
    });

    test('debug 建置下編譯期注入值壓過本機保存值', () async {
      final ServerAddressSettings settings = await buildAddressSettings(
        storedUrl: reachableUrl,
        injectedUrl: 'http://build-parameter.invalid:5206',
        preferInjected: true,
      );

      expect(settings.currentUrl(), 'http://build-parameter.invalid:5206');
      expect(settings.origin, ServerAddressOrigin.injected);
      // 本機值仍留在那裡：切換回一般建置時它會重新生效，不因注入而消失。
      expect(settings.savedUrl, reachableUrl);
    });

    test('未注入時一般建置退回注入來源的判定不成立', () async {
      final ServerAddressSettings settings = await buildAddressSettings(
        injectedUrl: 'http://build-parameter.invalid:5206',
        preferInjected: true,
      );

      expect(settings.currentUrl(), 'http://build-parameter.invalid:5206');
      expect(settings.origin, ServerAddressOrigin.injected);
    });

    test('無法辨識的已存值視為未設定，不保留壞值', () async {
      final ServerAddressSettings settings = await buildAddressSettings(
        storedUrl: '不是位址',
      );

      expect(settings.savedUrl, isNull);
      expect(settings.origin, ServerAddressOrigin.unset);
    });

    test('已存值的首尾空白與結尾斜線在載入時正規化', () async {
      final ServerAddressSettings settings = await buildAddressSettings(
        storedUrl: '  http://10.0.0.5:5206/  ',
      );

      expect(settings.savedUrl, reachableUrl);
      expect(settings.addressDisplay, reachableUrl);
    });
  });

  group('保存前必經可達性驗證', () {
    test('格式不合格時不發請求也不寫入', () async {
      final InMemoryServerAddressPersistence store =
          InMemoryServerAddressPersistence();
      final StubAddressVerifier verifier = StubAddressVerifier(
        reachable: <String>[reachableUrl],
      );
      final ServerAddressSettings settings = await buildAddressSettings(
        persistence: store,
        verifier: verifier.call,
      );

      final ServerAddressSaveResult result = await settings.save(
        '192.168.1.20:5206',
      );

      expect(result.status, ServerAddressSaveStatus.rejectedByFormat);
      expect(result.issue, ServerAddressIssue.missingScheme);
      expect(verifier.callCount, 0, reason: '格式不合格不該發出任何請求');
      expect(store.writeCount, 0);
      expect(settings.savedUrl, isNull);
    });

    test('格式合格但連不通時不保存，並帶回失敗原因', () async {
      final InMemoryServerAddressPersistence store =
          InMemoryServerAddressPersistence();
      final StubAddressVerifier verifier = StubAddressVerifier();
      final ServerAddressSettings settings = await buildAddressSettings(
        persistence: store,
        verifier: verifier.call,
      );

      final ServerAddressSaveResult result = await settings.save(
        'http://192.168.1.99:5206',
      );

      expect(result.status, ServerAddressSaveStatus.rejectedByConnectivity);
      expect(result.isSaved, isFalse);
      expect(result.error, isNotNull);
      expect(result.error!.kind.name, 'unreachable');
      expect(verifier.callCount, 1);
      expect(store.writeCount, 0);
      expect(settings.hasAddress, isFalse);
    });

    test('驗證通過才寫入，並把探測結果帶回給呼叫端沿用', () async {
      final InMemoryServerAddressPersistence store =
          InMemoryServerAddressPersistence();
      final StubAddressVerifier verifier = StubAddressVerifier(
        reachable: <String>[reachableUrl],
      );
      final ServerAddressSettings settings = await buildAddressSettings(
        persistence: store,
        verifier: verifier.call,
      );

      final ServerAddressSaveResult result = await settings.save(
        ' $reachableUrl/ ',
      );

      expect(result.status, ServerAddressSaveStatus.saved);
      expect(result.isActive, isTrue);
      expect(result.probe?.isSuccessful, isTrue);
      // 保存的是正規化後的文字，之後重開也讀到同一個值。
      expect(store.url, reachableUrl);
      expect(settings.savedUrl, reachableUrl);
      expect(settings.currentUrl(), reachableUrl);
    });

    test('寫入失敗時狀態保持原樣，不出現未落盤的新位址', () async {
      final InMemoryServerAddressPersistence store =
          InMemoryServerAddressPersistence(reachableUrl)
            ..failWith = StateError('本機儲存寫不進去');
      final StubAddressVerifier verifier = StubAddressVerifier(
        reachable: <String>['http://10.0.0.9:5206'],
      );
      final ServerAddressSettings settings = await buildAddressSettings(
        persistence: store,
        verifier: verifier.call,
      );

      final ServerAddressSaveResult result = await settings.save(
        'http://10.0.0.9:5206',
      );

      expect(result.status, ServerAddressSaveStatus.persistenceFailed);
      expect(result.isSaved, isFalse);
      expect(settings.savedUrl, reachableUrl, reason: '舊位址必須還在');
      expect(store.url, reachableUrl);
    });

    test('debug 建置下保存成功但未生效，結果如實標示', () async {
      final InMemoryServerAddressPersistence store =
          InMemoryServerAddressPersistence();
      final StubAddressVerifier verifier = StubAddressVerifier(
        reachable: <String>[reachableUrl],
      );
      final ServerAddressSettings settings = await buildAddressSettings(
        persistence: store,
        injectedUrl: 'http://build-parameter.invalid:5206',
        preferInjected: true,
        verifier: verifier.call,
      );

      final ServerAddressSaveResult result = await settings.save(reachableUrl);

      expect(result.isSaved, isTrue);
      expect(result.isActive, isFalse);
      expect(result.status, ServerAddressSaveStatus.savedInactive);
      expect(settings.currentUrl(), 'http://build-parameter.invalid:5206');
      expect(settings.savedUrl, reachableUrl);
    });

    test('保存成功與失敗都通知訂閱者（失敗也不留在探測中）', () async {
      final StubAddressVerifier verifier = StubAddressVerifier(
        reachable: <String>[reachableUrl],
      );
      final ServerAddressSettings settings = await buildAddressSettings(
        verifier: verifier.call,
      );
      int notifications = 0;
      settings.addListener(() => notifications++);

      await settings.save('http://10.0.0.9:5206');
      expect(notifications, 0, reason: '未改變狀態就不該通知');

      await settings.save(reachableUrl);
      expect(notifications, 1);
    });
  });

  group('清除', () {
    test('清除後退回未設定，並真的移除本機值', () async {
      final InMemoryServerAddressPersistence store =
          InMemoryServerAddressPersistence(reachableUrl);
      final ServerAddressSettings settings = await buildAddressSettings(
        persistence: store,
      );
      expect(settings.hasAddress, isTrue);

      await settings.clear();

      expect(store.url, isNull);
      expect(store.clearCount, 1);
      expect(settings.savedUrl, isNull);
      expect(settings.origin, ServerAddressOrigin.unset);
    });

    test('清除失敗時擲例外且保留原值', () async {
      final InMemoryServerAddressPersistence store =
          InMemoryServerAddressPersistence(reachableUrl)
            ..failWith = StateError('清除失敗');
      final ServerAddressSettings settings = await buildAddressSettings(
        persistence: store,
      );

      await expectLater(settings.clear(), throwsStateError);
      expect(store.url, reachableUrl);
      expect(settings.savedUrl, reachableUrl);
    });
  });

  group('共用偏好實作', () {
    test('以 shared_preferences 往返寫讀與清除', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const SharedPreferencesServerAddressStore store =
          SharedPreferencesServerAddressStore();
      expect(await store.readUrl(), isNull);

      await store.writeUrl(reachableUrl);
      expect(await store.readUrl(), reachableUrl);

      await store.clearUrl();
      expect(await store.readUrl(), isNull);
    });

    test('真實實作接上設定物件後可完整還原', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const SharedPreferencesServerAddressStore store =
          SharedPreferencesServerAddressStore();
      final StubAddressVerifier verifier = StubAddressVerifier(
        reachable: <String>[testBaseUrl],
      );

      final ServerAddressSettings first = ServerAddressSettings(
        store,
        preferInjected: false,
        verifier: verifier.call,
      );
      await first.restore();
      await first.save(testBaseUrl);

      // 在同一個儲存上重建設定，等價於重開應用：位址必須還在且仍然生效。
      final ServerAddressSettings second = ServerAddressSettings(
        store,
        preferInjected: false,
      );
      await second.restore();
      expect(second.savedUrl, testBaseUrl);
      expect(second.currentUrl(), testBaseUrl);
    });

    test('儲存鍵名固定，避免後續改名造成既有位址失蹤', () {
      expect(
        SharedPreferencesServerAddressStore.storageKey,
        'evernight_realm.server_base_url',
      );
    });
  });
}
