/// 伺服器入口頁探測區的測試：四種狀態如實呈現，失敗絕不長得像成功。
library;

import 'dart:async';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/widgets/server_probe_view.dart';
import 'package:evernightrealm/app/widgets/status_bar.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/connection_tracker.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/app_locale.dart';
import 'package:evernightrealm/core/language_settings.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_language.dart';
import '../support/test_server.dart';

/// 測試固定以簡體中文呈現；斷言用的期望文字取自同一份資源。
const Locale _locale = Locale('zh', 'CN');

/// 依階段組裝入口頁。
Future<Widget> _harness({required ServerApi api, String? storedTag}) async {
  return buildTestApp(
    storedTag: storedTag ?? _locale.toLanguageTag(),
    dependencies: AppDependencies(api: api),
    connection: ConnectionTracker(api),
  );
}

/// 讀取狀態條某個欄位的文字。
String _statusOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data ?? '';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  group('位址未設定', () {
    testWidgets('按鈕停用並說明原因，不拿預設位址去試', (WidgetTester tester) async {
      await tester.pumpWidget(await _harness(api: const ServerApi()));
      await tester.pumpAndSettle();

      expect(find.byType(ServerProbeView), findsOneWidget);
      final ButtonStyleButton button = tester.widget<ButtonStyleButton>(
        find.byKey(ServerProbeView.actionKey),
      );
      expect(button.onPressed, isNull, reason: '沒有位址就不該可點');
      expect(find.text(l10n.serverProbeNotConfiguredHint), findsOneWidget);
      expect(
        _statusOf(tester, ConnectionStatusBar.connectionKey),
        l10n.labelValuePair(
          l10n.statusConnectionLabel,
          l10n.connectionNotConfigured,
        ),
      );
      expect(find.text(l10n.serverProbeSucceeded), findsNothing);
    });
  });

  group('有位址但尚未探測', () {
    testWidgets('按鈕可用並如實標明尚未探測', (WidgetTester tester) async {
      await tester.pumpWidget(await _harness(api: stubApi()));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(ServerProbeView.actionKey))
            .onPressed,
        isNotNull,
      );
      expect(find.text(l10n.serverProbeNever), findsOneWidget);
      expect(
        _statusOf(tester, ConnectionStatusBar.connectionKey),
        contains(l10n.connectionNotProbed),
      );
    });
  });

  group('探測成功', () {
    testWidgets('按下後顯示伺服器回傳的存活與時間數值', (WidgetTester tester) async {
      await tester.pumpWidget(await _harness(api: stubApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ServerProbeView.actionKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.serverProbeSucceeded), findsOneWidget);
      expect(
        find.text(
          l10n.labelValuePair(
            l10n.serverProbeTimeLabel,
            '2026-09-25T09:33:32.614Z',
          ),
        ),
        findsOneWidget,
        reason: '時間原樣取自伺服器回應，不由本機推算',
      );
      expect(
        find.textContaining('17:33:32 (Asia/Shanghai +08:00)'),
        findsOneWidget,
      );
      expect(find.textContaining('evernight-server 0.1.0-dev'), findsOneWidget);
      expect(
        find.textContaining('01a0d7e9-b446-72b2-a1e8-87a33231cd7a'),
        findsOneWidget,
        reason: '成功也要帶關聯 ID，才對得上伺服器日誌',
      );
      expect(
        _statusOf(tester, ConnectionStatusBar.connectionKey),
        contains(l10n.connectionProbeOk),
      );
      expect(find.byKey(ServerProbeView.failureKey), findsNothing);
    });

    testWidgets('按鈕文字從首次探測轉為再次探測', (WidgetTester tester) async {
      await tester.pumpWidget(await _harness(api: stubApi()));
      await tester.pumpAndSettle();
      expect(find.text(l10n.serverProbeAction), findsOneWidget);

      await tester.tap(find.byKey(ServerProbeView.actionKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.serverProbeRetryAction), findsOneWidget);
    });
  });

  group('探測失敗', () {
    testWidgets('連不上時只顯示失敗說明，不出現任何成功數值', (WidgetTester tester) async {
      final ServerApi api = apiWithHandler(
        (_) async => throw http.ClientException('no route'),
      );
      await tester.pumpWidget(await _harness(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ServerProbeView.actionKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ServerProbeView.failureKey), findsOneWidget);
      expect(find.text(l10n.serverProbeFailed), findsOneWidget);
      expect(find.text(l10n.errorKindUnreachable), findsOneWidget);
      // 「不顯示為成功」的具體判據：成功的標題與數值一律不得出現。
      expect(find.text(l10n.serverProbeSucceeded), findsNothing);
      expect(find.byKey(ServerProbeView.successKey), findsNothing);
      expect(find.textContaining('2026-09-25T09:33:32.614Z'), findsNothing);
      expect(
        _statusOf(tester, ConnectionStatusBar.connectionKey),
        contains(l10n.connectionProbeFailed),
      );
    });

    testWidgets('未就緒時按機器碼取 ARB 文案，不顯示伺服器原文', (WidgetTester tester) async {
      const String serverMessage = 'The service is not ready yet.';
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed(testBaseUrl),
        client: MockClient((http.Request request) async {
          return http.Response(
            '{"code":1007,"message":"$serverMessage","request_id":"r-777"}',
            503,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      await tester.pumpWidget(await _harness(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ServerProbeView.actionKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.errorCodeNotReady), findsOneWidget);
      expect(
        find.textContaining(serverMessage),
        findsNothing,
        reason: '介面文字唯一來源是本地化資源，伺服器原文只供診斷',
      );
      expect(
        find.text(l10n.labelValuePair(l10n.diagnosticErrorCode, '1007')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.labelValuePair(l10n.diagnosticRequestId, 'r-777')),
        findsOneWidget,
      );
    });

    testWidgets('200 但內容不合合同時判為失敗而不是成功', (WidgetTester tester) async {
      final ServerApi api = stubApi(
        overrides: <String, String>{kHealthPath: '{"status":"ok"}'},
      );
      await tester.pumpWidget(await _harness(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ServerProbeView.actionKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.errorKindInvalidResponse), findsOneWidget);
      expect(find.text(l10n.serverProbeSucceeded), findsNothing);
    });

    testWidgets('伺服器原文帶憑證時不會出現在介面', (WidgetTester tester) async {
      final ServerApi api = ServerApi(
        config: ServerApiConfig.fixed(testBaseUrl),
        client: MockClient(
          (_) async => http.Response(
            '{"code":1000,"message":"token=abc123secret",'
            '"request_id":"r-1"}',
            500,
            headers: <String, String>{'content-type': 'application/json'},
          ),
        ),
      );
      await tester.pumpWidget(await _harness(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ServerProbeView.actionKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('abc123secret'), findsNothing);
      expect(find.text(l10n.errorCodeInternal), findsOneWidget);
    });
  });

  group('探測中', () {
    testWidgets('請求未回來時顯示進行中提示', (WidgetTester tester) async {
      final CompletableGate gate = CompletableGate();
      await tester.pumpWidget(await _harness(api: gate.api()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ServerProbeView.actionKey));
      await tester.pump();

      expect(find.text(l10n.serverProbeRunning), findsOneWidget);
      expect(
        _statusOf(tester, ConnectionStatusBar.connectionKey),
        contains(l10n.connectionProbing),
      );

      gate.release();
      await tester.pumpAndSettle();
      expect(find.text(l10n.serverProbeRunning), findsNothing);
    });
  });

  group('語言切換', () {
    testWidgets('換語言後保留數值、改用新語言文字', (WidgetTester tester) async {
      await tester.pumpWidget(await _harness(api: stubApi()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ServerProbeView.actionKey));
      await tester.pumpAndSettle();

      final LanguageSettings language = await buildLanguageSettings(
        storedTag: 'zh-CN',
      );
      final ServerApi api = stubApi();
      final ConnectionTracker tracker = ConnectionTracker(api);
      await tester.pumpWidget(
        await buildTestApp(
          dependencies: AppDependencies(api: api),
          connection: tracker,
          language: language,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ServerProbeView.actionKey));
      await tester.pumpAndSettle();

      final AppLocalizations english = await AppLocalizations.delegate.load(
        const Locale('en', 'US'),
      );
      await language.select(AppLocale.enUS);
      await tester.pumpAndSettle();

      expect(find.text(english.serverProbeSucceeded), findsOneWidget);
      expect(find.text(l10n.serverProbeSucceeded), findsNothing);
      expect(
        find.textContaining('2026-09-25T09:33:32.614Z'),
        findsOneWidget,
        reason: '數值與語言無關，換語言不該丟失已讀到的伺服器時間',
      );
    });
  });
}

/// 讓回應停在門口的假端點，用於觀察「探測中」狀態。
class CompletableGate {
  final List<Completer<http.Response>> _pending = <Completer<http.Response>>[];
  bool _released = false;

  /// 未放行前讓每個請求停在門口，放行後直接回正常回應。
  ServerApi api() {
    return ServerApi(
      config: ServerApiConfig.fixed(testBaseUrl),
      client: MockClient((http.Request request) async {
        if (!_released) {
          final Completer<http.Response> completer = Completer<http.Response>();
          _pending.add(completer);
          return completer.future;
        }
        return jsonOk(request.url.path == kTimePath ? timeBody : healthBody);
      }),
    );
  }

  /// 放行：完成所有停在門口的請求，之後的請求直接返回。
  void release() {
    _released = true;
    for (final Completer<http.Response> completer in _pending) {
      if (!completer.isCompleted) {
        completer.complete(jsonOk(healthBody));
      }
    }
  }
}
