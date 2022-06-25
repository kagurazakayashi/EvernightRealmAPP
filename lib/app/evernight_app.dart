/// 應用根節點：把裝配好的依賴與語言設定暴露給整棵元件樹，並交出原生 Navigator 路由表。
///
/// 介面語言由 [LanguageSettings] 決定（未手工選擇時跟隨系統語言），語言變更時
/// 重建子樹以換取新文字；解析規則集中在 `resolveAppLocale`，未支援的語言一律回退 en-US。
///
/// 字體策略：Web 的 CanvasKit 取不到系統字體，缺字時會向線上服務取字，違反完全離線。
/// 因此 Web 首次啟動先載入目前語言需要的本地 CJK 字體，載入完成前只顯示載入指示、
/// 不渲染任何文字；之後換語言時再補載對應家族（此時已有字體可暫代，不必再擋）。
/// 桌面與行動端由 Skia 直接使用系統字體，不做任何載入。
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/api/connection_tracker.dart';
import '../core/app_fonts.dart';
import '../core/app_locale.dart';
import '../core/language_settings.dart';
import '../l10n/app_localizations.dart';
import 'app_dependencies.dart';
import 'app_router.dart';
import 'app_theme.dart';
import 'connection_scope.dart';
import 'language_scope.dart';

/// 長夜幻境使用者端的應用根節點。
class EvernightApp extends StatefulWidget {
  /// 以裝配好的依賴、語言設定與連線追蹤建立根節點。
  const EvernightApp({
    super.key,
    required this.dependencies,
    required this.language,
    required this.connection,
  });

  /// 啟動時裝配的依賴集合。
  final AppDependencies dependencies;

  /// 介面語言設定（含持久化的手工選擇）。
  final LanguageSettings language;

  /// 連線探測狀態；由組裝點建立並負責其生命週期。
  final ConnectionTracker connection;

  @override
  State<EvernightApp> createState() => _EvernightAppState();
}

class _EvernightAppState extends State<EvernightApp> {
  /// 已載入並套用的本地字體家族；非 Web 平台維持 `null`（改用系統字體）。
  String? _fontFamily;

  /// Web 首次字體載入完成前不渲染文字，避免向線上服務取字。
  bool _waitingForFont = kIsWeb;

  /// 避免同一字體被並發載入。
  bool _loadingFont = false;

  @override
  void initState() {
    super.initState();
    widget.language.addListener(_onLanguageChanged);
    _loadFontForCurrentLanguage();
  }

  @override
  void didUpdateWidget(EvernightApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      oldWidget.language.removeListener(_onLanguageChanged);
      widget.language.addListener(_onLanguageChanged);
      _loadFontForCurrentLanguage();
    }
  }

  @override
  void dispose() {
    widget.language.removeListener(_onLanguageChanged);
    super.dispose();
  }

  /// 語言變更：立即重建換文，並視需要補載該語言的字體。
  void _onLanguageChanged() {
    setState(() {});
    _loadFontForCurrentLanguage();
  }

  /// 載入目前介面語言對應的本地字體（僅 Web 需要）。
  Future<void> _loadFontForCurrentLanguage() async {
    if (!kIsWeb || _loadingFont) {
      return;
    }
    _loadingFont = true;
    try {
      final String family = AppFonts.familyFor(widget.language.effective);
      await AppFonts.loadFamily(family);
      if (!mounted) {
        return;
      }
      setState(() {
        _fontFamily = family;
        _waitingForFont = false;
      });
    } catch (error, stack) {
      // 載入失敗時停在載入畫面並回報錯誤：寧可不出現文字，
      // 也不能讓 CanvasKit 轉向線上字體服務取字（完全離線是硬性要求）。
      if (!mounted) {
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'evernight_realm',
          context: ErrorDescription('載入本地 CJK 字體失敗'),
        ),
      );
    } finally {
      _loadingFont = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: widget.dependencies,
      child: ConnectionScope(
        tracker: widget.connection,
        child: LanguageScope(
          settings: widget.language,
          child: MaterialApp(
            // 視窗與瀏覽器分頁的品牌名由各平台元資料與原生標題承擔，
            // 這裡不重複保存一份介面文字。
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(fontFamily: _fontFamily),
            darkTheme: AppTheme.dark(fontFamily: _fontFamily),
            themeMode: ThemeMode.system,
            locale: widget.language.effectiveLocale,
            localeResolutionCallback:
                (Locale? locale, Iterable<Locale> supported) {
                  return resolveAppLocale(
                    locale ?? widget.language.effectiveLocale,
                  ).locale;
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
            builder: (BuildContext context, Widget? child) {
              if (!_waitingForFont) {
                return child ?? const SizedBox.shrink();
              }
              // 字體就緒前只有指示器：沒有任何文字，因此不會觸發線上取字。
              return const Directionality(
                textDirection: TextDirection.ltr,
                child: Material(
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
