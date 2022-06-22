/// 應用根節點：把裝配好的依賴暴露給整棵元件樹，並交出原生 Navigator 路由表。
///
/// 語言解析在此完成：介面語言從本地化資源支援的四個 locale 中選出，
/// 未指定語言時跟隨系統語言。主題只取 Material 的淺色與深色預設，
/// 品牌色與字型屬後續設計步驟。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_localizations.dart';
import 'app_dependencies.dart';
import 'app_router.dart';

/// 長夜幻境使用者端的應用根節點。
class EvernightApp extends StatelessWidget {
  /// 以裝配好的依賴建立根節點。
  const EvernightApp({
    super.key,
    required this.dependencies,
    this.forcedLocale,
  });

  /// 啟動時裝配的依賴集合。
  final AppDependencies dependencies;

  /// 指定介面語言；為 `null` 時跟隨系統語言。
  ///
  /// 語言切換與測試由此進入，切換結果的持久化由語言設定負責。
  final Locale? forcedLocale;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        // 視窗與瀏覽器分頁的品牌名由各平台元資料與原生標題承擔，
        // 這裡不重複保存一份介面文字。
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        themeMode: ThemeMode.system,
        locale: forcedLocale,
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
    );
  }
}
