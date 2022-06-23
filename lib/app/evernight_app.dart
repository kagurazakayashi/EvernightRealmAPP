/// 應用根節點：把裝配好的依賴與語言設定暴露給整棵元件樹，並交出原生 Navigator 路由表。
///
/// 介面語言由 [LanguageSettings] 決定（未手工選擇時跟隨系統語言），語言變更時
/// 重建整棵樹以換取新的顯示文字；解析規則集中在 `resolveAppLocale`，
/// 未支援的語言一律回退 en-US。主題只取 Material 的淺色與深色預設，
/// 品牌色與字型屬後續設計步驟。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/app_locale.dart';
import '../core/language_settings.dart';
import '../l10n/app_localizations.dart';
import 'app_dependencies.dart';
import 'app_router.dart';
import 'language_scope.dart';

/// 長夜幻境使用者端的應用根節點。
class EvernightApp extends StatelessWidget {
  /// 以裝配好的依賴與語言設定建立根節點。
  const EvernightApp({
    super.key,
    required this.dependencies,
    required this.language,
  });

  /// 啟動時裝配的依賴集合。
  final AppDependencies dependencies;

  /// 介面語言設定（含持久化的手工選擇）。
  final LanguageSettings language;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: language,
      builder: (BuildContext context, Widget? child) {
        return AppScope(
          dependencies: dependencies,
          child: LanguageScope(
            settings: language,
            child: MaterialApp(
              // 視窗與瀏覽器分頁的品牌名由各平台元資料與原生標題承擔，
              // 這裡不重複保存一份介面文字。
              debugShowCheckedModeBanner: false,
              theme: ThemeData(useMaterial3: true),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
              ),
              themeMode: ThemeMode.system,
              locale: language.effectiveLocale,
              localeResolutionCallback:
                  (Locale? locale, Iterable<Locale> supported) {
                    return resolveAppLocale(locale ?? language.effectiveLocale)
                        .locale;
                  },
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              initialRoute: AppRouter.initialRoute,
              routes: AppRouter.routes,
              onUnknownRoute: AppRouter.onUnknownRoute,
            ),
          ),
        );
      },
    );
  }
}
