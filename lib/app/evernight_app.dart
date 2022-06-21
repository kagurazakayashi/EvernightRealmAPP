/// 應用根節點：把裝配好的依賴暴露給整棵元件樹，並交出原生 Navigator 路由表。
///
/// 主題在此只取 Material 的淺色與深色預設，品牌色與字型屬後續設計步驟；
/// 語言解析亦維持現狀，四語言資源機制建立後在此接入。
library;

import 'package:flutter/material.dart';

import '../core/app_copy.dart';
import 'app_dependencies.dart';
import 'app_router.dart';

/// 長夜幻境使用者端的應用根節點。
class EvernightApp extends StatelessWidget {
  /// 以裝配好的依賴建立根節點。
  const EvernightApp({super.key, required this.dependencies});

  /// 啟動時裝配的依賴集合。
  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        title: AppCopy.appDisplayName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        themeMode: ThemeMode.system,
        initialRoute: AppRouter.initialRoute,
        routes: AppRouter.routes,
        onUnknownRoute: AppRouter.onUnknownRoute,
      ),
    );
  }
}
