/// 引導卡的介面測試：畫面說的每一句話都必須是伺服器真的回了的那一句。
///
/// 這裡一律走注入的假傳輸（MockClient），測試期間不碰網路、也不碰任何真實資料目錄。
/// 重點不在「有沒有畫出元件」，而在三個容易出事的形態：把查不到講成一個狀態、
/// 把口令收進畫面，以及重複查詢時多做了一次「寫」的動作。
library;

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/widgets/root_init_guide_view.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_address.dart';
import '../support/test_language.dart';
import '../support/test_server.dart';

/// 測試固定以繁體中文呈現；斷言用的期望文字取自同一份資源。
const Locale _locale = Locale('zh', 'TW');

/// 「有組態檔、還沒有 Root」的正常回應。
String uninitializedBody({bool envOverride = false}) =>
    '{"config_exists":true,"root_initialized":false,'
    '"env_override":$envOverride,"request_id":"r-init-1"}';

/// 「已有 Root 憑據」的正常回應。
const String initializedBody =
    '{"config_exists":true,"root_initialized":true,"env_override":false,'
    '"request_id":"r-init-2"}';

/// 中性入口能力回應（自註冊入口預設關閉）。
///
/// 同一頁上另有會自動查准入的自註冊入口卡；本卡只關心自己的狀態端點，故給那條通路
/// 一份合法且關閉的回應，使其不影響本卡的請求計數、也不在外層拋解碼例外。
const String neutralCapsBody =
    '{"sign_up_open":false,"invite_code_required":false,"guest_open":false,'
    '"request_id":"r-caps-neutral"}';

/// 一台隨測試擺佈的假伺服器，加上它被問過的每一次請求。
class _Fixture {
  /// 以回應決定方式建立。
  _Fixture({
    required this.bodyFor,
    this.status = 200,
    this.storedUrl = reachableUrl,
  });

  /// 依路徑決定回應內容；要製造傳輸級失敗時直接在裡面對外拋例外。
  final String Function(String path) bodyFor;

  /// 回應的 HTTP 狀態碼。
  final int status;

  /// 本機保存的位址；空字串代表「還沒有設定」。
  final String storedUrl;

  /// 被問過的次數。
  int hits = 0;

  /// 每趟請求的方法。
  final List<String> methods = <String>[];

  /// 每趟請求的本體。
  final List<String> bodies = <String>[];

  /// 依本卡片的合同決定回應；其餘路徑一律回中立內容，讓同頁其他卡不干擾本卡計數。
  String respond(String path) {
    if (path == kRootInitStatusPath) {
      return bodyFor(path);
    }
    if (path == kAuthCapabilitiesPath) {
      return neutralCapsBody;
    }
    return healthBody;
  }

  /// 組裝成一份可掛進應用樹的測試應用。
  Future<Widget> mount(ServerAddressSettings settings) async {
    final ServerApi api = ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        // 只計本卡的狀態端點：入口能力等同頁其他卡的自動查詢不計入本卡的hits／methods。
        if (request.url.path == kRootInitStatusPath) {
          hits++;
          methods.add(request.method);
          bodies.add(request.body);
        }
        return http.Response(
          respond(request.url.path),
          status,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );
    return buildTestApp(
      storedTag: _locale.toLanguageTag(),
      addresses: settings,
      dependencies: AppDependencies(api: api),
    );
  }
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  /// 掛上應用並完成首幀，回傳那台假伺服器。
  Future<_Fixture> pump(WidgetTester tester, _Fixture fixture) async {
    final ServerAddressSettings settings = await buildAddressSettings(
      storedUrl: fixture.storedUrl.isEmpty ? null : fixture.storedUrl,
    );
    await tester.pumpWidget(await fixture.mount(settings));
    await tester.pumpAndSettle();
    return fixture;
  }

  /// 狀態結論那一行的文字。
  String statusLine(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(RootInitGuideView.statusKey)).data ?? '';

  /// 按一次引導卡的查詢按鈕。
  Future<void> tapCheck(WidgetTester tester) async {
    await tester.tap(find.byKey(RootInitGuideView.actionKey));
    await tester.pumpAndSettle();
  }

  /// 任何階段都不准出現口令欄位：這張卡沒有提交通路。
  void expectNoSecretField(WidgetTester tester) {
    expect(
      find.descendant(
        of: find.byType(RootInitGuideView),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(RootInitGuideView),
        matching: find.byType(TextFormField),
      ),
      findsNothing,
    );
  }

  /// 只在狀態端點上決定回應，其他路徑保持正常。
  _Fixture statusOnly(
    String Function() body, {
    int status = 200,
    String storedUrl = reachableUrl,
  }) => _Fixture(bodyFor: (_) => body(), status: status, storedUrl: storedUrl);

  group('尚未初始化', () {
    testWidgets('列出本機步驟與狀態結論，卡內沒有任何輸入欄', (WidgetTester tester) async {
      final _Fixture fixture = await pump(
        tester,
        statusOnly(uninitializedBody),
      );

      expect(statusLine(tester), l10n.rootInitUninitializedTitle);
      expect(find.byKey(RootInitGuideView.guidanceKey), findsOneWidget);
      expect(find.text(l10n.rootInitStepInitialize), findsOneWidget);
      expectNoSecretField(tester);
      // 查狀態這一步本身只有 GET，而且不帶任何請求內容。
      expect(fixture.methods, <String>['GET']);
      expect(fixture.bodies, <String>['']);
    });

    testWidgets('組態檔還不存在時多講一句，與「有檔案沒填」分開', (WidgetTester tester) async {
      await pump(
        tester,
        statusOnly(
          () =>
              '{"config_exists":false,"root_initialized":false,'
              '"env_override":false,"request_id":"r-0"}',
        ),
      );

      expect(find.text(l10n.rootInitConfigMissingHint), findsOneWidget);
    });

    testWidgets('環境變數蓋著時警告，不勸人跑一次會被拒的初始化', (WidgetTester tester) async {
      await pump(
        tester,
        statusOnly(() => uninitializedBody(envOverride: true)),
      );

      expect(find.text(l10n.rootInitEnvOverrideHint), findsOneWidget);
    });
  });

  group('已完成初始化', () {
    testWidgets('不再列出步驟，也不提供任何能再建一個 Root 的操作', (WidgetTester tester) async {
      await pump(tester, statusOnly(() => initializedBody));

      expect(statusLine(tester), l10n.rootInitInitializedTitle);
      expect(find.text(l10n.rootInitInitializedNote), findsOneWidget);
      expect(find.byKey(RootInitGuideView.guidanceKey), findsNothing);
      expect(find.text(l10n.rootInitUninitializedTitle), findsNothing);
      expectNoSecretField(tester);
    });
  });

  group('查不到狀態', () {
    testWidgets('連不上時如實說無從得知，不假充任何初始化狀態', (WidgetTester tester) async {
      await pump(
        tester,
        _Fixture(
          storedUrl: reachableUrl,
          bodyFor: (_) => throw http.ClientException('no route'),
        ),
      );

      expect(statusLine(tester), l10n.rootInitUnreachableTitle);
      expect(find.byKey(RootInitGuideView.guidanceKey), findsNothing);
      expect(find.text(l10n.rootInitUninitializedTitle), findsNothing);
      expect(find.text(l10n.rootInitInitializedTitle), findsNothing);
    });

    testWidgets('伺服器拒絕回答時說的是拒絕，不是「還沒有 Root」', (WidgetTester tester) async {
      await pump(
        tester,
        statusOnly(
          () => '{"code":2005,"message":"no","request_id":"r-403"}',
          status: 403,
        ),
      );

      expect(statusLine(tester), l10n.rootInitForbiddenTitle);
      expect(find.text(l10n.rootInitUninitializedTitle), findsNothing);
    });

    testWidgets('內容對不上合同時只說結果不明確，並給出再問一次', (WidgetTester tester) async {
      await pump(tester, statusOnly(() => '{"status":"ok"}'));

      expect(statusLine(tester), l10n.rootInitUnknownTitle);
      expect(find.text(l10n.rootInitUnknownHint), findsOneWidget);
      expect(find.byKey(RootInitGuideView.guidanceKey), findsNothing);
    });
  });

  group('重新檢查與重複打開', () {
    testWidgets('結果不明確後按重新檢查，狀態跟著伺服器的新答案刷新', (WidgetTester tester) async {
      int asks = 0;
      final _Fixture fixture = _Fixture(
        bodyFor: (_) {
          asks++;
          // 第一趟回的是對不上合同的內容，第二趟才給出可信答案。
          return asks == 1 ? '{"status":"ok"}' : initializedBody;
        },
      );
      await pump(tester, fixture);

      expect(statusLine(tester), l10n.rootInitUnknownTitle);
      expect(fixture.hits, 1);

      await tapCheck(tester);

      expect(statusLine(tester), l10n.rootInitInitializedTitle);
      expect(find.byKey(RootInitGuideView.guidanceKey), findsNothing);
      // 重新檢查只是再多問一次：全是 GET、全無請求內容，沒有任何「提交」存在，
      // 因此它不可能把一個已存在的 Root 再建立或覆蓋一次。
      expect(fixture.methods, <String>['GET', 'GET']);
      expect(fixture.bodies, <String>['', '']);
    });

    testWidgets('按按鈕再問一次時同樣只有 GET，狀態維持在同一個結論', (WidgetTester tester) async {
      final _Fixture fixture = await pump(
        tester,
        statusOnly(uninitializedBody),
      );
      expect(fixture.hits, 1);

      await tapCheck(tester);

      expect(fixture.hits, 2);
      expect(fixture.methods, <String>['GET', 'GET']);
      expect(statusLine(tester), l10n.rootInitUninitializedTitle);
    });

    testWidgets('重複打開本頁各查一次，之後不自已變成輪詢', (WidgetTester tester) async {
      final _Fixture fixture = statusOnly(uninitializedBody);

      await pump(tester, fixture);
      expect(fixture.hits, 1);

      // 真的關掉畫面再重新打開（舊的組件樹不復用）：新的那次打開再問一次。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pump(tester, fixture);
      expect(fixture.hits, 2);

      // 之後沒有再操作就不該再發請求：自動查詢只發生在每次打開的那一瞬間。
      await tester.pump(const Duration(seconds: 30));
      expect(fixture.hits, 2);
    });

    testWidgets('沒有位址時不發任何請求，按鈕停用並說明原因', (WidgetTester tester) async {
      final _Fixture fixture = await pump(
        tester,
        _Fixture(bodyFor: (_) => uninitializedBody(), storedUrl: ''),
      );

      expect(fixture.hits, 0);
      expect(find.text(l10n.rootInitNotConfiguredHint), findsOneWidget);
      // 沒查過就沒有結論：這張卡不允許在沒有依據時顯示任何狀態。
      expect(find.byKey(RootInitGuideView.statusKey), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(RootInitGuideView.actionKey))
            .onPressed,
        isNull,
      );
    });
  });
}
