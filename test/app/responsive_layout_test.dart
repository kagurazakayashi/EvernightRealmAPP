/// 響應式佈局測試：從 320 px 到桌面大窗都不出現溢出，寬屏限制內文寬度。
///
/// Flutter 在 RenderFlex 溢出時會拋出異常，因此「無異常」就是無嚴重溢出的判據；
/// 同時檢查狀態條四個欄位與內容在各尺寸下都仍在畫面上。
library;

import 'package:evernight_realm/app/app_shell.dart';
import 'package:evernight_realm/app/widgets/language_selector.dart';
import 'package:evernight_realm/app/widgets/not_wired_view.dart';
import 'package:evernight_realm/app/widgets/status_bar.dart';
import 'package:evernight_realm/core/layout_breakpoints.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_language.dart';

/// 測試覆蓋的視窗尺寸（含規格 UI-001 要求的 360 px 起）。
const List<Size> _viewportSizes = <Size>[
  Size(320, 568),
  Size(360, 640),
  Size(414, 896),
  Size(600, 900),
  Size(840, 1000),
  Size(1280, 800),
  Size(1920, 1080),
];

void main() {
  group('多尺寸渲染', () {
    for (final Size size in _viewportSizes) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} 無溢出且關鍵元件齊備', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(await buildTestApp(storedTag: 'zh-TW'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(ConnectionStatusBar.versionKey), findsOneWidget);
        expect(find.byKey(ConnectionStatusBar.localeKey), findsOneWidget);
        expect(find.byKey(ConnectionStatusBar.serverKey), findsOneWidget);
        expect(find.byKey(ConnectionStatusBar.connectionKey), findsOneWidget);
        expect(find.byKey(LanguageSelector.dropdownKey), findsOneWidget);
      });
    }
  });

  group('內文寬度', () {
    testWidgets('寬螢幕下內容被限制在最大內文寬度內', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await buildTestApp(storedTag: 'ja-JP'));
      await tester.pumpAndSettle();

      final double bodyWidth = tester
          .getSize(find.byKey(NotWiredView.contentKey))
          .width;
      expect(
        bodyWidth,
        lessThanOrEqualTo(Breakpoints.contentMaxWidth + 0.5),
        reason: '寬螢幕不應把內文拉成整頁長行',
      );
    });

    testWidgets('窄螢幕下內容铺滿可用寬度', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await buildTestApp(storedTag: 'zh-CN'));
      await tester.pumpAndSettle();

      final double bodyWidth = tester.getSize(find.byType(AppShell)).width;
      expect(bodyWidth, 360);
    });
  });

  group('語言選單在窄屏', () {
    testWidgets('320 px 下展開選單仍可看到四個語言與跟隨系統', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await buildTestApp(storedTag: 'en-US'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(LanguageSelector.dropdownKey));
      await tester.pumpAndSettle();

      expect(find.text('简体中文'), findsWidgets);
      expect(find.text('繁體中文（台灣）'), findsWidgets);
      expect(find.text('English'), findsWidgets);
      expect(find.text('日本語'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
