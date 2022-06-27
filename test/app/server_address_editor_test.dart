/// 伺服器位址輸入卡的界面測試：可切換、格式錯誤有提示、連不通時不保存。
///
/// 界面層能真實驅動輸入的地方就是這裡（`tester.enterText` 走真實的 TextField
/// 管線），因此「輸入 → 驗證 → 保存 → 狀態條與探測區跟著換」這條鏈在測試層
/// 完整覆蓋。成功與失敗一律由注入的驗證器決定，測試不對外發起請求。
library;

import 'dart:async';

import 'package:evernight_realm/app/app_dependencies.dart';
import 'package:evernight_realm/app/server_address_labels.dart';
import 'package:evernight_realm/app/widgets/server_address_editor.dart';
import 'package:evernight_realm/app/widgets/server_probe_view.dart';
import 'package:evernight_realm/app/widgets/status_bar.dart';
import 'package:evernight_realm/core/api/api_client.dart';
import 'package:evernight_realm/core/api/server_address.dart';
import 'package:evernight_realm/core/api/server_address_settings.dart';
import 'package:evernight_realm/core/api/server_api.dart';
import 'package:evernight_realm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_address.dart';
import '../support/test_language.dart';
import '../support/test_server.dart';

/// 測試固定以簡體中文呈現；斷言用的期望文字取自同一份資源。
const Locale _locale = Locale('zh', 'CN');

/// 兩台「測試伺服器」：可切換是本步的核心場景，因此位址一律成對出現。
const String _urlA = 'http://10.0.0.5:5206';
const String _urlB = 'http://10.0.0.9:5206';

/// 一組組裝好的測試材料。
class _Harness {
  const _Harness(this.settings, this.store, this.verifier);

  final ServerAddressSettings settings;
  final InMemoryServerAddressPersistence store;
  final StubAddressVerifier verifier;
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  /// 組裝入口頁並完成首幀渲染，回傳可供斷言的材料。
  Future<_Harness> pump(
    WidgetTester tester, {
    String? storedUrl,
    String? injectedUrl,
    bool preferInjected = false,
    List<String> reachable = const <String>[_urlA, _urlB],
    bool failWrites = false,
    String? storedTag,
    VerifyServerAddress? verifier,
  }) async {
    final InMemoryServerAddressPersistence store =
        InMemoryServerAddressPersistence(storedUrl)
          ..failWith = failWrites ? StateError('本機儲存不可寫') : null;
    final StubAddressVerifier stub = StubAddressVerifier(reachable: reachable);
    final ServerAddressSettings settings = ServerAddressSettings(
      store,
      injectedUrl: injectedUrl,
      preferInjected: preferInjected,
      verifier: verifier ?? stub.call,
    );
    await settings.restore();

    // 端點介面以同一個設定物件為來源，並一律走假傳輸：探測區即便被點也不會碰網路。
    final ServerApi api = ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        return jsonOk(request.url.path == kTimePath ? timeBody : healthBody);
      }),
    );
    await tester.pumpWidget(
      await buildTestApp(
        storedTag: storedTag ?? _locale.toLanguageTag(),
        addresses: settings,
        dependencies: AppDependencies(api: api),
      ),
    );
    await tester.pumpAndSettle();
    return _Harness(settings, store, stub);
  }

  /// 在輸入框裡打一段文字。
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(ServerAddressEditor.inputKey), text);
    await tester.pump();
  }

  /// 點下「檢查並保存」。
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byKey(ServerAddressEditor.saveKey));
    await tester.pumpAndSettle();
  }

  /// 讀狀態條某個欄位的文字。
  String statusOf(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data ?? '';

  /// 取輸入框當前內容。
  String fieldText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(ServerAddressEditor.inputKey))
      .controller!
      .text;

  /// 位址卡片內某個「標籤：數值」列的文字。
  String effectiveLine(String value) =>
      l10n.labelValuePair(l10n.serverAddressEffectiveLabel, value);

  group('尚未設定位址', () {
    testWidgets('生效與本機兩行都顯示未設定，清除按鈕停用', (WidgetTester tester) async {
      await pump(tester);

      expect(find.byType(ServerAddressEditor), findsOneWidget);
      expect(
        find.text(effectiveLine(l10n.serverAddressNotSet)),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.labelValuePair(
            l10n.serverAddressSavedLabel,
            l10n.serverAddressNotSet,
          ),
        ),
        findsOneWidget,
      );
      expect(
        statusOf(tester, ConnectionStatusBar.serverKey),
        l10n.labelValuePair(l10n.statusServerLabel, l10n.serverAddressNotSet),
      );
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(ServerAddressEditor.clearKey))
            .onPressed,
        isNull,
        reason: '沒有可清除的值時不該給一個會失敗的按鈕',
      );
    });

    testWidgets('已保存的位址預填進輸入框並列為生效', (WidgetTester tester) async {
      await pump(tester, storedUrl: _urlA);

      expect(fieldText(tester), _urlA);
      expect(find.text(effectiveLine(_urlA)), findsOneWidget);
      expect(
        find.text(l10n.labelValuePair(l10n.serverAddressSavedLabel, _urlA)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(ServerAddressEditor.clearKey))
            .onPressed,
        isNotNull,
      );
    });
  });

  group('格式錯誤', () {
    // 每條輸入都必須落到一個具體原因上：一句「格式不正確」不足以為使用者指路。
    const Map<String, ServerAddressIssue> cases = <String, ServerAddressIssue>{
      '': ServerAddressIssue.empty,
      '192.168.1.20:5206': ServerAddressIssue.missingScheme,
      'localhost:5206': ServerAddressIssue.missingScheme,
      'ftp://10.0.0.5:5206': ServerAddressIssue.unsupportedScheme,
      'javascript:alert(1)': ServerAddressIssue.unsupportedScheme,
      'http://127.0.0.1:520 6': ServerAddressIssue.embeddedWhitespace,
      'http://root:secret@10.0.0.5': ServerAddressIssue.credentials,
      'http://10.0.0.5:5206?debug=1': ServerAddressIssue.queryOrFragment,
      'http://': ServerAddressIssue.hostMissing,
    };

    for (final MapEntry<String, ServerAddressIssue> entry in cases.entries) {
      testWidgets('輸入「${entry.key}」得到具體原因且不發請求', (WidgetTester tester) async {
        final _Harness h = await pump(tester, reachable: <String>[]);

        await type(tester, entry.key);
        await tapSave(tester);

        expect(
          find.descendant(
            of: find.byKey(ServerAddressEditor.issueKey),
            matching: find.text(addressIssueLabel(l10n, entry.value)!),
          ),
          findsOneWidget,
          reason: '${entry.key} 應提示 ${entry.value.name}',
        );
        // 三件硬性事實：沒發請求、沒寫本機、也沒有任何看起來像成功的文字。
        expect(h.verifier.callCount, 0, reason: '格式不合格不該發出請求');
        expect(h.store.writeCount, 0);
        expect(find.text(l10n.serverAddressSavedNote), findsNothing);
        expect(h.settings.hasAddress, isFalse);
      });
    }

    testWidgets('提示句本身不把憑證抄一遍', (WidgetTester tester) async {
      await pump(tester, reachable: <String>[]);

      await type(tester, 'http://root:secret@10.0.0.5');
      await tapSave(tester);

      final String hint = addressIssueLabel(
        l10n,
        ServerAddressIssue.credentials,
      )!;
      expect(hint, isNot(contains('secret')));
      expect(find.byKey(ServerAddressEditor.issueKey), findsOneWidget);
    });

    testWidgets('改動輸入後先前的提示立即收回', (WidgetTester tester) async {
      await pump(tester, reachable: <String>[]);

      await type(tester, 'no-scheme-here');
      await tapSave(tester);
      expect(find.byKey(ServerAddressEditor.issueKey), findsOneWidget);

      await type(tester, _urlA);
      expect(find.byKey(ServerAddressEditor.issueKey), findsNothing);
    });
  });

  group('連不通', () {
    testWidgets('不保存、保留輸入並說明原因', (WidgetTester tester) async {
      final _Harness h = await pump(tester, reachable: <String>[]);

      await type(tester, _urlA);
      await tapSave(tester);

      expect(h.verifier.callCount, 1, reason: '格式合格才輪到發請求');
      expect(h.store.writeCount, 0, reason: '連不通不得落盤');
      expect(h.settings.savedUrl, isNull);
      expect(
        find.descendant(
          of: find.byKey(ServerAddressEditor.resultKey),
          matching: find.text(l10n.serverAddressVerifyFailed),
        ),
        findsOneWidget,
      );
      // 失敗原因沿用統一存取層的類別文字，卡片不自造一套說法。
      expect(find.text(l10n.errorKindUnreachable), findsOneWidget);
      // 輸入內容留在框裡，使用者改正後可直接再試。
      expect(fieldText(tester), _urlA);
      expect(
        statusOf(tester, ConnectionStatusBar.serverKey),
        contains(l10n.serverAddressNotSet),
      );
      expect(find.text(l10n.serverAddressSavedNote), findsNothing);
    });

    testWidgets('本機寫入失敗時不留下未落盤的地址', (WidgetTester tester) async {
      final _Harness h = await pump(tester, failWrites: true);

      await type(tester, _urlA);
      await tapSave(tester);

      expect(
        find.descendant(
          of: find.byKey(ServerAddressEditor.resultKey),
          matching: find.text(l10n.serverAddressStorageFailed),
        ),
        findsOneWidget,
      );
      expect(h.settings.currentUrl(), isNull);
      expect(find.text(l10n.serverAddressSavedNote), findsNothing);
      expect(fieldText(tester), _urlA);
    });

    testWidgets('驗證進行中按鈕與輸入框都停用', (WidgetTester tester) async {
      final Completer<ServerProbeOutcome> gate =
          Completer<ServerProbeOutcome>();
      await pump(
        tester,
        verifier: (ServerAddress address, {String? acceptLanguage}) =>
            gate.future,
      );

      await type(tester, _urlA);
      await tester.tap(find.byKey(ServerAddressEditor.saveKey));
      await tester.pump();

      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(ServerAddressEditor.saveKey))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(ServerAddressEditor.inputKey))
            .enabled,
        isFalse,
      );
      expect(find.text(l10n.serverAddressSaving), findsOneWidget);

      gate.complete(
        await StubAddressVerifier(reachable: <String>[_urlA])
            .call(ServerAddress.tryParse(_urlA)!),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.serverAddressSaving), findsNothing);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(ServerAddressEditor.saveKey))
            .onPressed,
        isNotNull,
      );
    });
  });

  group('可切換測試伺服器', () {
    testWidgets('保存新位址後狀態條與探測區一起換到那台', (WidgetTester tester) async {
      final _Harness h = await pump(tester, storedUrl: _urlA);
      expect(statusOf(tester, ConnectionStatusBar.serverKey), contains(_urlA));

      await type(tester, _urlB);
      await tapSave(tester);

      expect(h.store.url, _urlB);
      expect(h.settings.currentUrl(), _urlB);
      expect(h.settings.origin, ServerAddressOrigin.saved);
      expect(
        find.descendant(
          of: find.byKey(ServerAddressEditor.resultKey),
          matching: find.text(l10n.serverAddressSavedNote),
        ),
        findsOneWidget,
      );
      expect(
        statusOf(tester, ConnectionStatusBar.serverKey),
        l10n.labelValuePair(l10n.statusServerLabel, _urlB),
      );
      // 保存前那趟驗證打的就是新位址：探測區直接沿用結果，不出現「尚未探測」。
      expect(find.byKey(ServerProbeView.successKey), findsOneWidget);
      expect(
        statusOf(tester, ConnectionStatusBar.connectionKey),
        contains(l10n.connectionProbeOk),
      );
    });

    testWidgets('候選連不通時舊位址仍然可用', (WidgetTester tester) async {
      final _Harness h = await pump(
        tester,
        storedUrl: _urlA,
        reachable: <String>[_urlA],
      );

      await type(tester, _urlB);
      await tapSave(tester);

      expect(h.verifier.callCount, 1);
      expect(h.store.url, _urlA, reason: '連不通的候選不得覆蓋已在用的位址');
      expect(h.settings.currentUrl(), _urlA);
      expect(statusOf(tester, ConnectionStatusBar.serverKey), contains(_urlA));
    });

    testWidgets('清除後回到未設定', (WidgetTester tester) async {
      final _Harness h = await pump(tester, storedUrl: _urlA);

      await tester.tap(find.byKey(ServerAddressEditor.clearKey));
      await tester.pumpAndSettle();

      expect(h.store.url, isNull);
      expect(h.store.clearCount, 1);
      expect(fieldText(tester), isEmpty);
      expect(
        find.descendant(
          of: find.byKey(ServerAddressEditor.resultKey),
          matching: find.text(l10n.serverAddressCleared),
        ),
        findsOneWidget,
      );
      expect(
        statusOf(tester, ConnectionStatusBar.serverKey),
        contains(l10n.serverAddressNotSet),
      );
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(ServerAddressEditor.clearKey))
            .onPressed,
        isNull,
      );
    });
  });

  group('生效來源說明', () {
    testWidgets('debug 建置注入值優先，並說明剛保存的值尚未生效', (WidgetTester tester) async {
      const String injected = 'http://build-parameter.invalid:5206';
      final _Harness h = await pump(
        tester,
        injectedUrl: injected,
        preferInjected: true,
      );

      expect(find.text(l10n.serverAddressFromBuildNote), findsOneWidget);
      expect(find.text(effectiveLine(injected)), findsOneWidget);
      expect(
        statusOf(tester, ConnectionStatusBar.serverKey),
        contains(injected),
      );

      await type(tester, _urlA);
      await tapSave(tester);

      expect(h.store.url, _urlA, reason: '仍然保存，供一般建置使用');
      expect(h.settings.currentUrl(), injected, reason: '注入值仍舊優先');
      expect(find.text(l10n.serverAddressInactiveNote), findsOneWidget);
      // 未生效時不得讓狀態條顯示成本機那個位址。
      expect(
        statusOf(tester, ConnectionStatusBar.serverKey),
        contains(injected),
      );
    });

    testWidgets('一般建置下保存即生效，不出現來源提示', (WidgetTester tester) async {
      const String injected = 'http://build-parameter.invalid:5206';
      final _Harness h = await pump(
        tester,
        injectedUrl: injected,
        preferInjected: false,
      );

      // 尚未保存任何位址時，生效值確實來自建置參數，提示必須出現。
      expect(find.text(l10n.serverAddressFromBuildNote), findsOneWidget);
      expect(find.text(effectiveLine(injected)), findsOneWidget);

      await type(tester, _urlA);
      await tapSave(tester);

      // 存了本機位址之後就以它為準，來源提示隨之消失（不留過期的說明）。
      expect(h.settings.currentUrl(), _urlA);
      expect(h.settings.origin, ServerAddressOrigin.saved);
      expect(find.text(l10n.serverAddressInactiveNote), findsNothing);
      expect(find.text(l10n.serverAddressFromBuildNote), findsNothing);
      expect(statusOf(tester, ConnectionStatusBar.serverKey), contains(_urlA));
    });
  });

  group('四語言', () {
    testWidgets('同一條格式提示隨介面語言切換，不混用另一種語言', (WidgetTester tester) async {
      for (final String tag in <String>['zh-CN', 'zh-TW', 'en-US', 'ja-JP']) {
        await pump(tester, reachable: <String>[], storedTag: tag);
        // 先取該語言的文案：介面語言若沒切換，下面的比對就沒有意義。
        final AppLocalizations local = await AppLocalizations.delegate.load(
          Localizations.localeOf(
            tester.element(find.byType(ServerAddressEditor)),
          ),
        );

        await type(tester, '192.168.1.20:5206');
        await tapSave(tester);

        expect(
          find.descendant(
            of: find.byKey(ServerAddressEditor.issueKey),
            matching: find.text(local.addressIssueMissingScheme),
          ),
          findsOneWidget,
          reason: '$tag 介面應顯示該語言的提示',
        );
        expect(
          find.text(l10n.addressIssueMissingScheme),
          tag == 'zh-CN' ? findsOneWidget : findsNothing,
          reason: '$tag 不該同時出現簡體那份文字',
        );
      }
    });
  });
}
