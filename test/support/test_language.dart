/// 語言相關測試的共用助手：記憶體持久化假實作與應用組裝。
library;

import 'package:flutter/widgets.dart';

import 'package:evernight_realm/app/app_dependencies.dart';
import 'package:evernight_realm/app/evernight_app.dart';
import 'package:evernight_realm/core/language_settings.dart';

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
Future<Widget> buildTestApp({
  AppDependencies dependencies = const AppDependencies(),
  Locale systemLocale = const Locale('en'),
  String? storedTag,
  LanguageSettings? language,
}) async {
  final LanguageSettings settings =
      language ??
      await buildLanguageSettings(
        systemLocale: systemLocale,
        storedTag: storedTag,
      );
  return EvernightApp(dependencies: dependencies, language: settings);
}
