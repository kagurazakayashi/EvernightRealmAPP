/// 「變更密碼」面板與強制改密態的介面測試：入口在已登入態出現、本地校驗擋在
/// 發請求之前、成功把後方會話卡帶入退出態；欠改密時只留改密與登出兩個入口。
///
/// 狀態機由 [SessionController] 的測試釘死；這裡補的是 UI 走線：按鈕接得上、
/// 提示落得對、強制態不呈現注定被 2010 擋下的入口。全部走假傳輸，不落任何真實憑據。
library;

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/widgets/password_change_view.dart';
import 'package:evernightrealm/app/widgets/session_summary_view.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/core/session/session_status.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_address.dart';
import '../support/test_language.dart';
import '../support/test_server.dart';
import '../support/test_session.dart';

const Locale _locale = Locale('zh', 'TW');

/// 測試專屬假口令：只活在本測試進程，不是任何環境的憑據。
const String _current = 'ui-current-pass';
const String _newer = 'ui-newer-pass';

http.Response jsonError(
  int status,
  int code,
  String requestId, {
  String? details,
}) {
  final String tail = details == null ? '' : ',"details":$details';
  return http.Response(
    '{"code":$code,"message":"server text","request_id":"$requestId"$tail}',
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

/// `/auth/session` 的帳戶回應，可指定 must_change_password 旗標。
String sessionAccountBody({bool mustChange = false}) =>
    '{"subject_kind":"account","account_id":"acct-ui-1","device_id":"device-ui",'
    '"rotation_seq":0,'
    '"created_at":"2026-09-30T03:04:05.000Z",'
    '"last_active_at":"2026-09-30T03:05:05.000Z",'
    '"expires_at":"2026-10-02T03:04:05.000Z",'
    '${mustChange ? '"must_change_password":true,' : ''}"request_id":"r-sess"}';

/// 帶旗標的帳戶登入成果（強制改密態的起點）。
LoginExchange flaggedAccountExchange() {
  return LoginExchange(
    report: LoginReport(
      subjectKind: AuthSubjectKind.account,
      accountId: 'acct-ui-1',
      deviceId: 'device-ui',
      expiresAt: DateTime.utc(2026, 10, 2, 3, 4, 5),
      requestId: 'r-login',
      mustChangePassword: true,
    ),
    sessionSecret: 'tok-ui-1',
  );
}

ServerApi _api(
  ServerAddressSettings settings, {
  bool mustChange = false,
  http.Response Function()? onChange,
  void Function(http.Request)? onAny,
}) {
  return ServerApi(
    config: ServerApiConfig(source: settings),
    client: MockClient((http.Request request) async {
      onAny?.call(request);
      switch (request.url.path) {
        case kAuthSessionPath:
          return jsonOk(sessionAccountBody(mustChange: mustChange));
        case kAuthPasswordChangePath:
          return onChange == null
              ? jsonOk('{"revoked_sessions":2,"request_id":"r-pw"}')
              : onChange();
        default:
          return jsonOk('{}');
      }
    }),
  );
}

void main() {
  late AppLocalizations l10n;
  late ServerAddressSettings settings;
  late InMemorySessionPersistence store;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  setUp(() async {
    settings = await buildAddressSettings(
      storedUrl: reachableUrl,
      reachable: <String>[reachableUrl],
    );
    store = InMemorySessionPersistence();
  });

  Future<SessionController> signIn(ServerApi api, {LoginExchange? exchange}) =>
      signedInSession(
        api: api,
        addresses: settings,
        persistence: store,
        exchange: exchange ?? rootExchange(),
      );

  Future<void> mount(
    WidgetTester tester,
    ServerApi api,
    SessionController session,
  ) async {
    await tester.pumpWidget(
      await buildTestApp(
        storedTag: _locale.toLanguageTag(),
        addresses: settings,
        dependencies: AppDependencies(api: api),
        session: session,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 打開改密面板並填滿三個口令欄（默認兩次新口令一致）。
  Future<void> openAndFill(
    WidgetTester tester, {
    String current = _current,
    String newer = _newer,
    String? confirm,
  }) async {
    await tester.ensureVisible(
      find.byKey(SessionSummaryView.passwordChangeKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SessionSummaryView.passwordChangeKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PasswordChangeDialog.currentFieldKey),
      current,
    );
    await tester.enterText(find.byKey(PasswordChangeDialog.newFieldKey), newer);
    await tester.enterText(
      find.byKey(PasswordChangeDialog.confirmFieldKey),
      confirm ?? newer,
    );
  }

  testWidgets('已登入態出現「變更密碼」入口', (WidgetTester tester) async {
    final ServerApi api = _api(settings);
    await mount(tester, api, await signIn(api));
    expect(find.byKey(SessionSummaryView.passwordChangeKey), findsOneWidget);
  });

  testWidgets('本地校驗：兩次新口令不一致時不發任何請求', (WidgetTester tester) async {
    int asks = 0;
    final ServerApi counted = _api(
      settings,
      onChange: () => jsonOk('{"revoked_sessions":1,"request_id":"r"}'),
      onAny: (_) => asks++,
    );
    await mount(tester, counted, await signIn(counted));
    asks = 0;

    await openAndFill(tester, confirm: '不一致的另一串');
    await tester.tap(find.byKey(PasswordChangeDialog.submitKey));
    await tester.pumpAndSettle();

    expect(find.text(l10n.passwordChangeMismatchNotice), findsOneWidget);
    expect(asks, 0, reason: '本地就該擋下，不值得發請求');
  });

  testWidgets('現行口令不對（2001）：提示落對、仍停在已登入且面板不關', (WidgetTester tester) async {
    final ServerApi api = _api(
      settings,
      onChange: () => jsonError(401, 2001, 'r'),
    );
    final SessionController session = await signIn(api);
    await mount(tester, api, session);

    await openAndFill(tester, current: '打錯的口令');
    await tester.tap(find.byKey(PasswordChangeDialog.submitKey));
    await tester.pumpAndSettle();

    expect(find.text(l10n.passwordChangeInvalidCurrentNotice), findsOneWidget);
    expect(find.byType(PasswordChangeDialog), findsOneWidget);
    expect(session.status, SessionStatus.signedIn);
  });

  testWidgets('同口令（1004＋reason）：落「新口令等於現行」那一句', (WidgetTester tester) async {
    final ServerApi sameApi = _api(
      settings,
      onChange: () =>
          jsonError(400, 1004, 'r', details: '{"reason":"same_as_current"}'),
    );
    await mount(tester, sameApi, await signIn(sameApi));
    await openAndFill(tester);
    await tester.tap(find.byKey(PasswordChangeDialog.submitKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.passwordChangeSameNotice), findsOneWidget);
  });

  testWidgets('形狀不合格（1004）：落「新口令不合形狀」那一句', (WidgetTester tester) async {
    final ServerApi shapeApi = _api(
      settings,
      onChange: () => jsonError(400, 1004, 'r'),
    );
    await mount(tester, shapeApi, await signIn(shapeApi));
    await openAndFill(tester);
    await tester.tap(find.byKey(PasswordChangeDialog.submitKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.passwordChangeInvalidNewNotice), findsOneWidget);
  });

  testWidgets('改密成功：面板關閉、後方卡進入退出態', (WidgetTester tester) async {
    final ServerApi api = _api(settings);
    final SessionController session = await signIn(api);
    await mount(tester, api, session);

    await openAndFill(tester);
    await tester.tap(find.byKey(PasswordChangeDialog.submitKey));
    await tester.pumpAndSettle();

    expect(find.byType(PasswordChangeDialog), findsNothing);
    expect(session.status, SessionStatus.signedOut);
    expect(store.credentials, isEmpty);
  });

  testWidgets('強制改密態：只留改密與登出入口，受保護入口不呈現', (WidgetTester tester) async {
    final ServerApi api = _api(settings, mustChange: true);
    final SessionController session = await signIn(
      api,
      exchange: flaggedAccountExchange(),
    );
    expect(session.mustChangePassword, isTrue);
    await mount(tester, api, session);

    expect(find.byKey(SessionSummaryView.passwordRequiredKey), findsOneWidget);
    expect(find.text(l10n.passwordChangeRequiredNotice), findsOneWidget);
    expect(find.byKey(SessionSummaryView.passwordChangeKey), findsOneWidget);
    expect(find.byKey(SessionSummaryView.logoutKey), findsOneWidget);
    expect(find.byKey(SessionSummaryView.deviceManagerKey), findsNothing);
    expect(find.byKey(SessionSummaryView.rotateKey), findsNothing);
  });

  testWidgets('還清義務後再登入：受保護入口回到卡面', (WidgetTester tester) async {
    final ServerApi api = _api(settings);
    final SessionController session = await signIn(
      api,
      exchange: flaggedAccountExchange(),
    );
    await mount(tester, api, session);
    // 面板改密成功 → 退出態；再以「不帶旗標的登入回應」走一次 completeLogin，
    // 演練「還清義務後重新登入」的下一幀：入口回來、提示消失。
    await tester.ensureVisible(
      find.byKey(SessionSummaryView.passwordChangeKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SessionSummaryView.passwordChangeKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PasswordChangeDialog.currentFieldKey),
      _current,
    );
    await tester.enterText(
      find.byKey(PasswordChangeDialog.newFieldKey),
      _newer,
    );
    await tester.enterText(
      find.byKey(PasswordChangeDialog.confirmFieldKey),
      _newer,
    );
    await tester.tap(find.byKey(PasswordChangeDialog.submitKey));
    await tester.pumpAndSettle();
    expect(session.status, SessionStatus.signedOut);

    await session.completeLogin(
      ServerAddress.tryParse(reachableUrl)!,
      accountExchange('acct-ui-1', secret: 'tok-ui-2'),
    );
    await tester.pumpAndSettle();
    expect(session.status, SessionStatus.signedIn);
    expect(session.mustChangePassword, isFalse);
    expect(find.byKey(SessionSummaryView.deviceManagerKey), findsOneWidget);
    expect(find.byKey(SessionSummaryView.rotateKey), findsOneWidget);
    expect(find.byKey(SessionSummaryView.passwordRequiredKey), findsNothing);
  });
}
