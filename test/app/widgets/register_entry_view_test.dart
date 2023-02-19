/// 入口層「建立帳戶」卡的介面測試（R2-011）：只准照伺服器的入口回話決定露不露這扇門。
///
/// 四種入口結論各說各句，且降級方向一律是「收」：查不到、連不上、回了關閉——都不給
/// 註冊出口。「入口能力不是准入保證」也釘在這裡：卡只讀 `sign_up_open`，自動查詢只一次
/// （不縮成輪詢），要再問得由人按「重新檢查」。已登入者已有身分，整張卡收起。
/// 全程走注入的假傳輸（MockClient），不碰網路、不發會話、不落任何真實憑據。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/widgets/register_entry_view.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/features/auth/register_page.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';
import '../../support/test_language.dart';
import '../../support/test_server.dart';
import '../../support/test_session.dart';

/// 測試固定以繁體中文呈現；斷言用的期望文字取自同一份資源。
const Locale _locale = Locale('zh', 'TW');

/// 一則入口能力回應：只問 `sign_up_open`，其餘格子恆為關以保持中立。
String capsBody({required bool signUpOpen, bool inviteCodeRequired = false}) =>
    '{"sign_up_open":$signUpOpen,'
    '"invite_code_required":$inviteCodeRequired,"guest_open":false,'
    '"request_id":"r-caps"}';

/// 統一錯誤信封。
String envelope(int code, String requestId) =>
    '{"code":$code,"message":"server text","request_id":"$requestId"}';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  /// 一臺只對 `/auth/capabilities` 擺佈、其餘保持中立的假伺服器；記錄入口查詢次數。
  ServerApi apiFor(
    ServerAddressSettings settings, {
    required Future<http.Response> Function(http.Request request) onCaps,
    void Function(http.Request request)? onAny,
  }) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        onAny?.call(request);
        switch (request.url.path) {
          case kHealthPath:
            return jsonOk(healthBody);
          case kTimePath:
            return jsonOk(timeBody);
          case kAuthCapabilitiesPath:
            return onCaps(request);
          default:
            return http.Response(
              envelope(1001, 'r-404'),
              404,
              headers: <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
        }
      }),
    );
  }

  Future<ServerAddressSettings> addressesFor({String? storedUrl}) async {
    final String url = storedUrl ?? reachableUrl;
    return buildAddressSettings(storedUrl: url, reachable: <String>[url]);
  }

  /// 以給定會話（預設瀏覽器形態未登入）掛上應用；入口卡就擺在起始的伺服器入口頁。
  Future<void> mount(
    WidgetTester tester, {
    required ServerAddressSettings settings,
    required ServerApi api,
    SessionController? session,
  }) async {
    await tester.pumpWidget(
      await buildTestApp(
        storedTag: _locale.toLanguageTag(),
        addresses: settings,
        dependencies: AppDependencies(api: api),
        session:
            session ??
            SessionController(
              api: api,
              addresses: settings,
              mode: SessionTransportMode.web,
            ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 狀態結論行的文字。
  String statusLine(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(RegisterEntryView.statusKey)).data ?? '';

  group('沒有位址：談不上准入', () {
    testWidgets('未設位址時整張卡收起，一個入口查詢都不發', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor(storedUrl: '');
      int asks = 0;
      await mount(
        tester,
        settings: settings,
        api: apiFor(
          settings,
          onCaps: (http.Request request) async {
            asks++;
            return jsonOk(capsBody(signUpOpen: true));
          },
        ),
      );

      expect(find.byKey(RegisterEntryView.recheckKey), findsNothing);
      expect(find.byKey(RegisterEntryView.statusKey), findsNothing);
      expect(asks, 0, reason: '沒有位址就不該假裝查過准入');
    });
  });

  group('開放：只因伺服器回了「開」才露出口', () {
    testWidgets('sign_up_open 為真：開放提示與「建立帳戶」出口都在', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      await mount(
        tester,
        settings: settings,
        api: apiFor(
          settings,
          onCaps: (http.Request request) async =>
              jsonOk(capsBody(signUpOpen: true)),
        ),
      );

      expect(find.text(l10n.registerEntryTitle), findsOneWidget);
      expect(statusLine(tester), l10n.registerEntryOpenHint);
      expect(find.byKey(RegisterEntryView.actionKey), findsOneWidget);
    });

    testWidgets('按「建立帳戶」導向註冊頁', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      await mount(
        tester,
        settings: settings,
        api: apiFor(
          settings,
          onCaps: (http.Request request) async =>
              jsonOk(capsBody(signUpOpen: true)),
        ),
      );

      await tester.ensureVisible(find.byKey(RegisterEntryView.actionKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RegisterEntryView.actionKey));
      await tester.pumpAndSettle();

      expect(find.byType(RegisterPage), findsOneWidget);
    });
  });

  group('關閉與查不了：降級方向是收', () {
    testWidgets('sign_up_open 為假：說Root關掉了，不給出口', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      await mount(
        tester,
        settings: settings,
        api: apiFor(
          settings,
          onCaps: (http.Request request) async =>
              jsonOk(capsBody(signUpOpen: false)),
        ),
      );

      expect(statusLine(tester), l10n.registerEntryClosedHint);
      expect(find.byKey(RegisterEntryView.actionKey), findsNothing);
    });

    testWidgets('入口查不了：說「這一刻查不到」，不冒充開放也不冒充關閉', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      await mount(
        tester,
        settings: settings,
        api: apiFor(
          settings,
          onCaps: (http.Request request) async =>
              throw http.ClientException('offline'),
        ),
      );

      expect(statusLine(tester), l10n.registerEntryCheckFailedHint);
      expect(statusLine(tester), isNot(l10n.registerEntryOpenHint));
      expect(statusLine(tester), isNot(l10n.registerEntryClosedHint));
      expect(find.byKey(RegisterEntryView.actionKey), findsNothing);
    });
  });

  group('查詢節奏：自動只一次、可重查、不輪詢', () {
    testWidgets('掛上後自動查一次並停住，不自己縮成輪詢', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      int asks = 0;
      await mount(
        tester,
        settings: settings,
        api: apiFor(
          settings,
          onCaps: (http.Request request) async {
            asks++;
            return jsonOk(capsBody(signUpOpen: true));
          },
        ),
      );

      // 多幾幀仍只一次：准入的變更靠人回來重查，不是畫面自己縮輪詢。
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(asks, 1);
    });

    testWidgets('按「重新檢查」才再問一次', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      int asks = 0;
      await mount(
        tester,
        settings: settings,
        api: apiFor(
          settings,
          onCaps: (http.Request request) async {
            asks++;
            return jsonOk(capsBody(signUpOpen: true));
          },
        ),
      );
      expect(asks, 1);

      await tester.ensureVisible(find.byKey(RegisterEntryView.recheckKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RegisterEntryView.recheckKey));
      await tester.pumpAndSettle();

      expect(asks, 2);
    });

    testWidgets('先查不了再重查成功：由失敗句改口為開放並放出出口', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      int asks = 0;
      await mount(
        tester,
        settings: settings,
        api: apiFor(
          settings,
          onCaps: (http.Request request) async {
            asks++;
            if (asks == 1) {
              throw http.ClientException('offline');
            }
            return jsonOk(capsBody(signUpOpen: true));
          },
        ),
      );
      expect(statusLine(tester), l10n.registerEntryCheckFailedHint);
      expect(find.byKey(RegisterEntryView.actionKey), findsNothing);

      await tester.ensureVisible(find.byKey(RegisterEntryView.recheckKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RegisterEntryView.recheckKey));
      await tester.pumpAndSettle();

      expect(asks, 2);
      expect(statusLine(tester), l10n.registerEntryOpenHint);
      expect(find.byKey(RegisterEntryView.actionKey), findsOneWidget);
    });
  });

  group('只對門外的人呈現', () {
    testWidgets('已登入者整張卡收起，不再露出建立帳戶的通路', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final ServerApi api = apiFor(
        settings,
        onCaps: (http.Request request) async =>
            jsonOk(capsBody(signUpOpen: true)),
      );
      // 先登入再掛上：判定取自會話層那份「伺服器確認過的身分」，不看本地印象。
      final SessionController session = await signedInSession(
        api: api,
        addresses: settings,
        persistence: InMemorySessionPersistence(),
        exchange: rootExchange(),
      );
      await mount(tester, settings: settings, api: api, session: session);

      expect(find.byKey(RegisterEntryView.recheckKey), findsNothing);
      expect(find.byKey(RegisterEntryView.statusKey), findsNothing);
      expect(find.byKey(RegisterEntryView.actionKey), findsNothing);
    });
  });

  group('請求形態', () {
    testWidgets('入口查詢是無請求本的 GET，本體不含任何身分欄', (WidgetTester tester) async {
      final ServerAddressSettings settings = await addressesFor();
      final List<http.Request> caps = <http.Request>[];
      await mount(
        tester,
        settings: settings,
        api: apiFor(
          settings,
          onCaps: (http.Request request) async {
            caps.add(request);
            return jsonOk(capsBody(signUpOpen: true));
          },
        ),
      );

      expect(caps.single.method, 'GET');
      expect(caps.single.url.path, kAuthCapabilitiesPath);
      // GET 沒有本體，因此也無處夾帶任何自報身分；這恰是入口合同「只進不出」的一面。
      expect(caps.single.body, isEmpty);
      // 回話僅三個布林：卡片不讀也不顯示任何模式名字、閾值或帳戶清單。
      expect(jsonDecode(capsBody(signUpOpen: true)).keys.toSet(), <String>{
        'sign_up_open',
        'invite_code_required',
        'guest_open',
        'request_id',
      });
    });
  });
}
