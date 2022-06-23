/// 介面語言設定的測試：跟隨系統、手工選擇、持久化往返與寫入失敗時不改變狀態。
library;

import 'dart:ui' show Locale;

import 'package:evernight_realm/core/app_locale.dart';
import 'package:evernight_realm/core/language_settings.dart';
import 'package:evernight_realm/l10n/app_localizations.dart';
import 'package:evernight_realm/platform/shared_preferences_language_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_language.dart';

/// 寫入失敗的持久化假實作，用來確認不會留下未落盤的狀態。
class _FailingPersistence implements LanguagePersistence {
  @override
  Future<String?> readTag() async => null;

  @override
  Future<void> writeTag(String? tag) async {
    throw StateError('儲存寫入失敗');
  }
}

void main() {
  group('跟隨系統語言', () {
    test('未設定時依系統語言解析，且標記為跟隨系統', () {
      final LanguageSettings settings = LanguageSettings(
        InMemoryLanguagePersistence(),
        systemLocale: const Locale('ja', 'JP'),
      );

      expect(settings.followsSystem, isTrue);
      expect(settings.effective, AppLocale.jaJP);
      expect(settings.effectiveLocale, const Locale('ja', 'JP'));
    });

    test('系統語言變更時跟隨者跟著改變，已手工選擇者不受影響', () async {
      final LanguageSettings following = LanguageSettings(
        InMemoryLanguagePersistence(),
        systemLocale: const Locale('en'),
      );
      final LanguageSettings pinned = LanguageSettings(
        InMemoryLanguagePersistence('ja-JP'),
        systemLocale: const Locale('en'),
      );
      await pinned.restore();

      following.updateSystemLocale(const Locale('zh', 'HK'));
      pinned.updateSystemLocale(const Locale('zh', 'HK'));

      expect(following.effective, AppLocale.zhTW);
      expect(pinned.effective, AppLocale.jaJP);
    });
  });

  group('手工選擇與持久化', () {
    test('載入後還原先前選擇', () async {
      final LanguageSettings settings = await _build(storedTag: 'zh-CN');

      expect(settings.followsSystem, isFalse);
      expect(settings.effective, AppLocale.zhCN);
    });

    test('無法辨識的標識視為未設定，回到跟隨系統', () async {
      final LanguageSettings settings = await _build(
        storedTag: 'ko-KR',
        systemLocale: const Locale('ja'),
      );

      expect(settings.followsSystem, isTrue);
      expect(settings.effective, AppLocale.jaJP);
    });

    test('選擇寫入成功後才更新狀態', () async {
      final InMemoryLanguagePersistence store = InMemoryLanguagePersistence();
      final LanguageSettings settings = LanguageSettings(
        store,
        systemLocale: const Locale('en'),
      );
      await settings.restore();

      await settings.select(AppLocale.zhTW);

      expect(store.tag, 'zh-TW');
      expect(store.writeCount, 1);
      expect(settings.effective, AppLocale.zhTW);
    });

    test('選回跟隨系統會清除已存標識', () async {
      final InMemoryLanguagePersistence store = InMemoryLanguagePersistence(
        'ja-JP',
      );
      final LanguageSettings settings = LanguageSettings(
        store,
        systemLocale: const Locale('en'),
      );
      await settings.restore();
      expect(settings.effective, AppLocale.jaJP);

      await settings.select(null);

      expect(store.tag, isNull);
      expect(settings.followsSystem, isTrue);
      expect(settings.effective, AppLocale.enUS);
    });

    test('寫入失敗時介面語言不變，不留下未落盤的選擇', () async {
      final LanguageSettings settings = LanguageSettings(
        _FailingPersistence(),
        systemLocale: const Locale('en'),
      );

      await expectLater(settings.select(AppLocale.jaJP), throwsStateError);
      expect(settings.effective, AppLocale.enUS);
    });
  });

  group('共用偏好實作', () {
    test('以 shared_preferences 往返寫讀，並清理空值', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const SharedPreferencesLanguageStore store =
          SharedPreferencesLanguageStore();
      expect(await store.readTag(), isNull);

      await store.writeTag(AppLocale.zhTW.tag);
      expect(await store.readTag(), 'zh-TW');

      final LanguageSettings settings = LanguageSettings(store);
      await settings.restore();
      expect(settings.effective, AppLocale.zhTW);

      await settings.select(null);
      expect(await store.readTag(), isNull);
    });

    test('儲存鍵名固定，避免後續改名造成既有選擇失蹤', () {
      expect(
        SharedPreferencesLanguageStore.storageKey,
        'evernight_realm.interface_locale',
      );
    });
  });

  group('生效語言與資源一致', () {
    test('四個 AppLocale 都能載到對應的本地化資源', () async {
      for (final AppLocale locale in AppLocale.values) {
        final AppLocalizations loaded = await AppLocalizations.delegate.load(
          locale.locale,
        );
        expect(loaded.statusVersionLabel, isNotEmpty);
      }
    });
  });
}

/// 以已存標識與系統語言建立並載入設定。
Future<LanguageSettings> _build({
  String? storedTag,
  Locale systemLocale = const Locale('en'),
}) async {
  final LanguageSettings settings = LanguageSettings(
    InMemoryLanguagePersistence(storedTag),
    systemLocale: systemLocale,
  );
  await settings.restore();
  return settings;
}
