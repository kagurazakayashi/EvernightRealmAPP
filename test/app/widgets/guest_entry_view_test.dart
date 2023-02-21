/// 入口層「訪客進入」卡的介面測試（R2-016）。
///
/// 這張卡與註冊入口卡最大的不同是：它那颗按鈕是**全應用唯一一處會寫入匿名建號的訪客入口**，
/// 因此這裡釘的是「什麼時候不寫」多於「寫了會怎樣」：
///
/// * 掛上頁面只發一條唯讀的入口能力 GET，一條 POST 都不發——載入、刷新、重連、
///   查完改口都不寫庫（那是孤兒帳戶的來源）。
/// * 只有 `guest_open` 為真才露出按鈕；查不到、連不上、回了關閉——降級方向一律是「收」。
/// * 連點只發一趟；進行中按鈕停用。
/// * 成功後的身分只准來自伺服器回應：摘要卡把這個人唸成「訪客（臨時身分）」，
///   並如實說明為什麼沒有改密入口；Root 與管理員那幾顆按鈕不在這裡出現。
/// * 失敗文案取自機器碼映射（2017 是「此刻不開放」、1004 是「暱稱不合規」），
///   不轉述伺服器原文，也不把被拒說成已進入。
///
/// 全程走注入的假傳輸（MockClient）：測試期間不碰網路、不落任何真實憑據。
library;

import 'dart:async';
import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/widgets/guest_entry_view.dart';
import 'package:evernightrealm/app/widgets/session_summary_view.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/features/player/player_surface_page.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';
import '../../support/test_language.dart';
import '../../support/test_server.dart';

/// 測試固定以繁體中文呈現；斷言用的期望文字取自同一份資源。
const Locale _locale = Locale('zh', 'TW');

/// 一則入口能力回應：只把 `guest_open` 交給測試決定，其餘兩格恆為關以保持中立。
String capsBody({required bool guestOpen}) =>
    '{"sign_up_open":false,"invite_code_required":false,'
    '"guest_open":$guestOpen,"request_id":"r-caps"}';

/// 訪客進入成功回應本體（合同欄位，不含任何憑據材料）。
const String guestEnterBody =
    '{"subject_kind":"account","account_id":"01a0e000-0000-7000-8000-0000000000f0",'
    '"account_type":"guest","display_name":"夜訪的旅人",'
    '"device_id":"01a0e000-0000-7000-8000-0000000000f1",'
    '"expires_at":"2026-10-08T10:00:00.000Z","request_id":"r-guest"}';

/// 統一錯誤信封。
String envelope(int code, String requestId) =>
    '{"code":$code,"message":"server text","request_id":"$requestId"}';

/// 一則由路徑決定的回應設定。
typedef StubResponse = ({int status, String body, Map<String, String> headers});

/// 一台隨測試擺佈的假伺服器：入口能力與訪客進入兩條路徑各自可安排。
class _Fixture {
  /// 建立測試現場。[guestOpen] 決定入口答案，[guestReply] 決定進入那趟的回應。
  _Fixture({
    this.guestOpen = true,
    this.guestReply,
    this.storedUrl = reachableUrl,
    this.failCaps = false,
  });

  /// 入口能力裡訪客那一格的現值。
  final bool guestOpen;

  /// 自訂訪客進入的回應；未給時回一份成功回應。
  final Future<http.Response> Function(http.Request request)? guestReply;

  /// 是否讓入口能力查詢直接失敗（製造「查不了」那一格降級方向）。
  final bool failCaps;

  /// 本機保存的位址。
  final String storedUrl;

  /// 被問過的請求。
  final List<http.Request> requests = <http.Request>[];

  /// 掛進應用樹之後的會話控制器（斷言狀態用）。
  late SessionController session;

  /// 被問到的指定路徑請求。
  List<http.Request> to(String path) =>
      requests.where((http.Request r) => r.url.path == path).toList();

  /// 依路徑決定回應：探測兩條路徑保持正常，讓畫面中立。
  Future<http.Response> _reply(http.Request request) async {
    requests.add(request);
    switch (request.url.path) {
      case kHealthPath:
        return jsonOk(healthBody);
      case kTimePath:
        return jsonOk(timeBody);
      case kAuthCapabilitiesPath:
        if (failCaps) {
          throw http.ClientException('offline');
        }
        return jsonOk(capsBody(guestOpen: guestOpen));
      case kAuthGuestPath:
        final Future<http.Response> Function(http.Request)? custom = guestReply;
        if (custom != null) {
          return custom(request);
        }
        return jsonOk(guestEnterBody);
      default:
        return http.Response(
          envelope(1001, 'r-404'),
          404,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
    }
  }

  /// 組裝成一份可掛進應用樹的測試應用（瀏覽器形態：會話由 Cookie 代管）。
  Future<Widget> mount() async {
    final ServerAddressSettings settings = await buildAddressSettings(
      storedUrl: storedUrl.isEmpty ? null : storedUrl,
      reachable: <String>[storedUrl],
    );
    final ServerApi api = ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient(_reply),
    );
    session = SessionController(
      api: api,
      addresses: settings,
      mode: SessionTransportMode.web,
    );
    return buildTestApp(
      storedTag: _locale.toLanguageTag(),
      addresses: settings,
      dependencies: AppDependencies(api: api),
      session: session,
    );
  }
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  /// 回到入口層（彈掉最上層路由）。
  ///
  /// 不用 `pageBack`：應用殼的標題列不一定畫出系統樣式的返回鈕，而這裡要的只是
  /// 「把最上層那頁關掉」，直接對導航器下指令與真實導航同形。
  Future<void> backToEntry(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
  }

  /// 掛上應用並完成首幀。
  Future<void> pump(WidgetTester tester, _Fixture fixture) async {
    await tester.pumpWidget(await fixture.mount());
    await tester.pumpAndSettle();
  }

  /// 狀態結論行的文字。
  String statusLine(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(GuestEntryView.statusKey)).data ?? '';

  /// 失敗或補充說明行的文字。
  String noteLine(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(GuestEntryView.noteKey)).data ?? '';

  /// 按一次「以訪客進入」（不等一下結果，供連點測試先按再 pump）。
  Future<void> tapEnter(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(GuestEntryView.actionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GuestEntryView.actionKey));
    await tester.pump();
  }

  group('掛上頁面只讀不寫', () {
    testWidgets('入口開放時也只發一條入口能力 GET，一條 POST 都不發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      // 入口頁現掛兩張入口卡（自註冊與訪客），每張各自查一次唯讀的入口能力；
      // 這裡要釘的不是「全頁面只有一條 GET」，而是「訪客卡自己只查一次、而且絕不順手寫入」。
      expect(fixture.to(kAuthCapabilitiesPath), hasLength(2));
      // 這條界線釘的是「載入不寫庫」：自動查詢只讀，寫入只由人主動按下觸發。
      expect(fixture.to(kAuthGuestPath), isEmpty);
      expect(statusLine(tester), l10n.guestEntryOpenHint);
      expect(find.byKey(GuestEntryView.limitsKey), findsOneWidget);
      expect(find.byKey(GuestEntryView.nicknameKey), findsOneWidget);
      expect(find.byKey(GuestEntryView.actionKey), findsOneWidget);
    });

    testWidgets('多幾幀仍不會自己縮成輪詢，也不會偷偷進入', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // 停在兩張卡各查一次的那個數目上：任何輪詢都會把它推過去。
      expect(fixture.to(kAuthCapabilitiesPath), hasLength(2));
      expect(fixture.to(kAuthGuestPath), isEmpty);
    });

    testWidgets('未設位址時整張卡收起，一個查詢都不發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(storedUrl: '');
      await pump(tester, fixture);

      expect(find.byKey(GuestEntryView.recheckKey), findsNothing);
      expect(find.byKey(GuestEntryView.statusKey), findsNothing);
      expect(fixture.to(kAuthCapabilitiesPath), isEmpty);
      expect(fixture.to(kAuthGuestPath), isEmpty);
    });
  });

  group('只因伺服器回了「開」才露出口', () {
    testWidgets('guest_open 為假：說此刻不允許，不給按鈕，也不給寫入入口', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(guestOpen: false);
      await pump(tester, fixture);

      expect(statusLine(tester), l10n.guestEntryClosedHint);
      expect(find.byKey(GuestEntryView.actionKey), findsNothing);
      expect(find.byKey(GuestEntryView.nicknameKey), findsNothing);
      expect(find.byKey(GuestEntryView.limitsKey), findsNothing);
      expect(fixture.to(kAuthGuestPath), isEmpty);
    });

    testWidgets('入口查不了：說「這一刻查不到」，不冒充開放也不冒充關閉', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(failCaps: true);
      await pump(tester, fixture);

      expect(statusLine(tester), l10n.guestEntryCheckFailedHint);
      expect(statusLine(tester), isNot(l10n.guestEntryOpenHint));
      expect(statusLine(tester), isNot(l10n.guestEntryClosedHint));
      // 查不到就不給出口：那一顆按鈕會寫庫，不能建立在一份沒查到的答案上。
      expect(find.byKey(GuestEntryView.actionKey), findsNothing);
      expect(fixture.to(kAuthGuestPath), isEmpty);
    });
  });

  group('主動按下才寫入', () {
    testWidgets('按一次發一趟 POST，本體只帶暱稱；成功後帶進玩家面', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      await tester.enterText(find.byKey(GuestEntryView.nicknameKey), '夜訪的旅人');
      await tapEnter(tester);
      await tester.pumpAndSettle();

      final List<http.Request> posts = fixture.to(kAuthGuestPath);
      expect(posts, hasLength(1));
      expect(posts.single.method, 'POST');
      expect(
        json.decode(posts.single.body) as Map<String, Object?>,
        <String, Object?>{'nickname': '夜訪的旅人'},
      );

      // 進入後的去處：玩家面如實呈現「尚未屬於任何活動」，不是假的活动清單。
      expect(find.byType(PlayerSurfacePage), findsOneWidget);
      expect(fixture.session.isSignedIn, isTrue);
      expect(fixture.session.activeSession?.isGuest, isTrue);
    });

    testWidgets('留空暱稱時本體不帶那一格（由伺服器產生臨時編號）', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      await tapEnter(tester);
      await tester.pumpAndSettle();

      expect(fixture.to(kAuthGuestPath), hasLength(1));
      expect(fixture.to(kAuthGuestPath).single.body, '{}');
    });

    testWidgets('連點只發一趟：進行中按鈕停用，不會多換出一筆訪客帳戶', (WidgetTester tester) async {
      // 把回應握在手上：這樣「還沒落定就再按」才是真的在進行中按，而不是事後補點。
      final Completer<http.Response> pending = Completer<http.Response>();
      final _Fixture fixture = _Fixture(guestReply: (_) => pending.future);
      await pump(tester, fixture);

      await tester.ensureVisible(find.byKey(GuestEntryView.actionKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GuestEntryView.actionKey));
      await tester.pump();

      final FilledButton inFlight = tester.widget<FilledButton>(
        find.byKey(GuestEntryView.actionKey),
      );
      expect(inFlight.onPressed, isNull);
      await tester.tap(find.byKey(GuestEntryView.actionKey));
      await tester.tap(find.byKey(GuestEntryView.actionKey));
      await tester.pump();

      expect(fixture.to(kAuthGuestPath), hasLength(1));

      pending.complete(jsonOk(guestEnterBody));
      await tester.pumpAndSettle();
      expect(fixture.to(kAuthGuestPath), hasLength(1));
      expect(fixture.session.isSignedIn, isTrue);
    });

    testWidgets('2017（策略關著）：一句「此刻不開放」，身份一個字都沒變', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        guestReply: (http.Request request) async => http.Response(
          envelope(2017, 'r-2017'),
          403,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      await pump(tester, fixture);

      await tapEnter(tester);
      await tester.pumpAndSettle();

      expect(noteLine(tester), l10n.errorCodeAccountCreationDisabled);
      expect(fixture.session.isSignedIn, isFalse);
      // 被拒的這一趟不留下任何「已進入」的痕跡，也不重發。
      expect(fixture.to(kAuthGuestPath), hasLength(1));
    });

    testWidgets('2006（來源被限流）說的是等一會兒，不是重新登入也不是權限不足', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(
        guestReply: (http.Request request) async => http.Response(
          envelope(2006, 'r-2006'),
          429,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      await pump(tester, fixture);

      await tapEnter(tester);
      await tester.pumpAndSettle();

      expect(noteLine(tester), l10n.errorCodeLoginThrottled);
      expect(noteLine(tester), isNot(l10n.errorCodeAccountCreationDisabled));
    });

    testWidgets('1004 點名暱稱時說的是写法問題，不混成策略結論', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        guestReply: (http.Request request) async => http.Response(
          '{"code":1004,"message":"server text",'
          '"details":{"invalid_field":"nickname"},"request_id":"r-1004"}',
          400,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      await pump(tester, fixture);

      await tapEnter(tester);
      await tester.pumpAndSettle();

      expect(noteLine(tester), l10n.errorCodeInvalidBody);
      expect(fixture.session.isSignedIn, isFalse);
    });
  });

  group('進入後的臨時身分如實呈現', () {
    testWidgets('摘要卡唸成訪客、說明沒有口令可改，且不給改密入口', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await tapEnter(tester);
      await tester.pumpAndSettle();

      // 回到入口層看自己那張卡：身份行取自伺服器的 account_type，不是本地推測。
      await backToEntry(tester);

      expect(find.byKey(SessionSummaryView.identityKey), findsOneWidget);
      // 身分列是「標籤：值」那一格合成的，所以要問的是这一行裡出現了訪客那一句，
      // 而不是有一枚獨立 Text 恰等於它。
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((Text t) => t.data ?? '')
            .any((String text) => text.contains(l10n.sessionSubjectGuest)),
        isTrue,
      );
      // 同一張卡不能還唸成普通帳戶：那句話對這個人是不準確的。
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((Text t) => t.data ?? '')
            .any(
              (String text) =>
                  text.contains(l10n.sessionSubjectLabel) &&
                  text.endsWith(l10n.sessionSubjectAccount),
            ),
        isFalse,
      );
      expect(find.byKey(SessionSummaryView.guestNoticeKey), findsOneWidget);
      // 訪客沒有口令可改：那一顆按鈕不在這裡出現（後端對他也只會回 2001）。
      expect(find.byKey(SessionSummaryView.passwordChangeKey), findsNothing);
      // 登出入口照舊在：這一趟隨時可以主動結束。
      expect(find.byKey(SessionSummaryView.logoutKey), findsOneWidget);
      // 訪客不是管理員，Root 控制台入口也不出現（放行判定本來就在服務端與閘裡）。
      expect(find.byKey(SessionSummaryView.rootConsoleKey), findsNothing);
    });

    testWidgets('已登入者整張訪客卡收起，不再給第二個臨時身分的入口', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await tapEnter(tester);
      await tester.pumpAndSettle();
      await backToEntry(tester);

      expect(find.byKey(GuestEntryView.recheckKey), findsNothing);
      expect(find.byKey(GuestEntryView.statusKey), findsNothing);
      expect(find.byKey(GuestEntryView.actionKey), findsNothing);
      // 收起之後也就不可能再發第二趟寫入。
      expect(fixture.to(kAuthGuestPath), hasLength(1));
    });
  });

  group('重新檢查', () {
    testWidgets('按「重新檢查」才再問一次入口能力，而且仍不寫入', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      // 掛上後的基數（兩張入口卡各查一次）之後不再成長，按一顆按鈕才多問一次。
      final int afterMount = fixture.to(kAuthCapabilitiesPath).length;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(fixture.to(kAuthCapabilitiesPath), hasLength(afterMount));

      await tester.ensureVisible(find.byKey(GuestEntryView.recheckKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GuestEntryView.recheckKey));
      await tester.pumpAndSettle();

      expect(fixture.to(kAuthCapabilitiesPath), hasLength(afterMount + 1));
      expect(fixture.to(kAuthGuestPath), isEmpty);
    });
  });
}
