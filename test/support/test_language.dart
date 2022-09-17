/// 語言與應用組裝測試的共用助手：記憶體持久化假實作與根節點組裝。
library;

import 'package:flutter/widgets.dart';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/evernight_app.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/connection_tracker.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/diagnostics/diagnostics_hub.dart';
import 'package:evernightrealm/core/language_settings.dart';
import 'package:evernightrealm/core/session/session_controller.dart';

import 'test_address.dart';

/// 以記憶體欄位模擬持久化，便於直接斷言寫入的值與次數。
class InMemoryLanguagePersistence implements LanguagePersistence {
  /// 以初始已存標識建立假實作。
  InMemoryLanguagePersistence([this.tag]);

  /// 目前儲存的語言標識，`null` 代表未設定。
  String? tag;

  /// 寫入次數，用於確認「跟隨系統」確實清除了選擇。
  int writeCount = 0;

  @override
  Future<String?> readTag() async => tag;

  @override
  Future<void> writeTag(String? value) async {
    tag = value;
    writeCount++;
  }
}

/// 建立已完成載入的語言設定（測試直接用它組裝應用）。
Future<LanguageSettings> buildLanguageSettings({
  Locale systemLocale = const Locale('en'),
  String? storedTag,
}) async {
  final LanguageSettings settings = LanguageSettings(
    InMemoryLanguagePersistence(storedTag),
    systemLocale: systemLocale,
  );
  await settings.restore();
  return settings;
}

/// 以系統語言／已存標識（或直接給定設定）與依賴組裝應用根節點。
///
/// 未給 [connection] 時，依依賴裡的端點介面自動建立一個追蹤器：大多數測試
/// 只關心文字與佈局，不需要真假設探測。未給 [diagnostics] 時同樣給一組全新的
/// 收集器，避免測試之間共用狀態。[addresses] 未給定時一律以「本機未保存位址」
/// 起算，讓位址輸入卡在多數測試裡保持中立狀態。
///
/// [session] 未給定时使用瀏覽器形态的空會話控制器（不讀寫任何本地秘密）。
/// [restoreOnLaunch] 刻意預設為偽：正式啟動會自動恢復會話，但大多數元件測試
/// 不該平白多發一個 `/auth/session` 請求而干擾「恰好問了 N 次」的斷言；
/// 需要演練啟動恢復的測試自己傳真，或直接調控制器的 `restore()`。
Future<Widget> buildTestApp({
  AppDependencies? dependencies,
  Locale systemLocale = const Locale('en'),
  String? storedTag,
  LanguageSettings? language,
  ServerAddressSettings? addresses,
  ConnectionTracker? connection,
  DiagnosticsHub? diagnostics,
  SessionController? session,
  bool restoreOnLaunch = false,
}) async {
  final LanguageSettings settings =
      language ??
      await buildLanguageSettings(
        systemLocale: systemLocale,
        storedTag: storedTag,
      );
  final ServerAddressSettings addressSettings =
      addresses ?? await buildAddressSettings();
  final AppDependencies deps =
      dependencies ?? AppDependencies.assembled(addresses: addressSettings);
  return EvernightApp(
    dependencies: deps,
    language: settings,
    addresses: addressSettings,
    connection:
        connection ?? ConnectionTracker(deps.api, addresses: addressSettings),
    // 元件測試預設走瀏覽器形态的會話控制器：不建立安全儲存、不注入憑據，
    // 讓「會話适配」的存在不干扰這些只关心文字／佈局的測試。
    session:
        session ??
        SessionController(
          api: deps.api,
          addresses: addressSettings,
          mode: SessionTransportMode.web,
        ),
    diagnostics: diagnostics ?? DiagnosticsHub(sink: (String _) {}),
    restoreOnLaunch: restoreOnLaunch,
  );
}
