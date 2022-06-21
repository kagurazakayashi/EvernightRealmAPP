/// 應用壳狀態條的測試：驗證四個欄位都顯示有真實來源的值。
library;

import 'package:evernight_realm/app/app_dependencies.dart';
import 'package:evernight_realm/app/app_shell.dart';
import 'package:evernight_realm/app/widgets/status_bar.dart';
import 'package:evernight_realm/core/app_copy.dart';
import 'package:evernight_realm/core/app_information.dart';
import 'package:evernight_realm/core/runtime_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 以指定依賴套一層壳，狀態條由壳負責掛載。
Widget _harness(AppDependencies dependencies) {
  return AppScope(
    dependencies: dependencies,
    child: const MaterialApp(
      home: AppShell(title: '測試頁面', child: SizedBox.shrink()),
    ),
  );
}

void main() {
  group('連線狀態條', () {
    testWidgets('四個欄位齊全且數值取自裝配的依賴', (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(
          const AppDependencies(
            runtimeStatus: RuntimeStatus(
              information: AppInformation(buildVersion: '9.9.9-test'),
            ),
          ),
        ),
      );

      expect(find.byKey(ConnectionStatusBar.versionKey), findsOneWidget);
      expect(find.byKey(ConnectionStatusBar.localeKey), findsOneWidget);
      expect(find.byKey(ConnectionStatusBar.serverKey), findsOneWidget);
      expect(find.byKey(ConnectionStatusBar.connectionKey), findsOneWidget);
      expect(find.text('9.9.9-test'), findsOneWidget);
    });

    testWidgets('尚未具備的能力如實顯示未設定與未接上', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(const AppDependencies()));

      expect(find.text(AppCopy.serverAddressNotSet), findsOneWidget);
      expect(find.text(AppCopy.connectionNotWired), findsOneWidget);
      expect(find.text(AppCopy.valueNotProvided), findsOneWidget);
    });

    testWidgets('系統語系取自平台設定，不是介面語言', (WidgetTester tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('ja', 'JP');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);

      await tester.pumpWidget(_harness(const AppDependencies()));

      expect(find.text('ja-JP'), findsOneWidget);
    });
  });
}
