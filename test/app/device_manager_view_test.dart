/// 「我的裝置」面板的介面測試：入口在已登入態出現、面板標記當前裝置、
/// 撤自己這臺會走確認並把後方會話卡帶入退出態。
///
/// 狀態機本身由 [SessionController] 的測試釘死；這裡補的是「按鈕接得上、清單画得對、
/// 撤當前裝置真的落到退出態」這條 UI 走線。全部走假傳輸，不碰網路也不落任何真實憑據。
library;

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/app/widgets/device_manager_view.dart';
import 'package:evernightrealm/app/widgets/session_summary_view.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
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
const String _deviceSelf = '019e0000-0000-7000-8000-0000000000aa';
const String _deviceOther = '019e0000-0000-7000-8000-0000000000bb';

String get _listBody =>
    '{"devices":['
    '{"device_id":"$_deviceSelf","created_at":"2026-09-30T03:04:05.000Z",'
    '"last_active_at":"2026-09-30T03:05:05.000Z",'
    '"expires_at":"2026-10-02T03:04:05.000Z","status":"active","current":true},'
    '{"device_id":"$_deviceOther","created_at":"2026-09-30T02:04:05.000Z",'
    '"last_active_at":"2026-09-30T02:40:05.000Z",'
    '"expires_at":"2026-10-02T02:04:05.000Z","status":"active","current":false}'
    '],"request_id":"r-list"}';

http.Response _revoke({required bool current}) => http.Response(
  '{"device_id":"${current ? _deviceSelf : _deviceOther}","revoked":true,'
  '"current":$current,"request_id":"r-rev"}',
  200,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

ServerApi _api(
  ServerAddressSettings settings, {
  http.Response Function()? onRevoke,
}) {
  return ServerApi(
    config: ServerApiConfig(source: settings),
    client: MockClient((http.Request request) async {
      switch (request.url.path) {
        case kAuthDevicesPath:
          return jsonOk(_listBody);
        case kAuthDeviceRevokePath:
          return onRevoke!.call();
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

  Future<SessionController> signIn(ServerApi api) => signedInSession(
    api: api,
    addresses: settings,
    persistence: store,
    exchange: rootExchange(),
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

  testWidgets('已登入態出現「我的裝置」入口', (WidgetTester tester) async {
    final ServerApi api = _api(settings);
    await mount(tester, api, await signIn(api));
    expect(find.byKey(SessionSummaryView.deviceManagerKey), findsOneWidget);
    expect(find.text(l10n.sessionDevicesAction), findsOneWidget);
  });

  testWidgets('開啟面板：兩臺裝置在列，當前那一臺帶徽章', (WidgetTester tester) async {
    final ServerApi api = _api(settings);
    await mount(tester, api, await signIn(api));

    await tester.ensureVisible(find.byKey(SessionSummaryView.deviceManagerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SessionSummaryView.deviceManagerKey));
    await tester.pumpAndSettle();

    expect(find.byKey(MyDevicesDialog.revokeKey(_deviceSelf)), findsOneWidget);
    expect(find.byKey(MyDevicesDialog.revokeKey(_deviceOther)), findsOneWidget);
    expect(find.text(l10n.devicesCurrentBadge), findsOneWidget);
    expect(find.text(l10n.devicesRevokeCurrentAction), findsOneWidget);
  });

  testWidgets('撤當前裝置：走確認、面板關閉、後方卡進入退出態', (WidgetTester tester) async {
    final ServerApi api = _api(
      settings,
      onRevoke: () => _revoke(current: true),
    );
    final SessionController session = await signIn(api);
    await mount(tester, api, session);

    await tester.ensureVisible(find.byKey(SessionSummaryView.deviceManagerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SessionSummaryView.deviceManagerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MyDevicesDialog.revokeKey(_deviceSelf)));
    await tester.pumpAndSettle();
    // 確認框。
    expect(find.text(l10n.devicesRevokeConfirmTitle), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('devices-revoke-confirm')),
    );
    await tester.pumpAndSettle();

    expect(session.status, SessionStatus.signedOut);
    expect(find.byKey(MyDevicesDialog.revokeKey(_deviceSelf)), findsNothing);
    // 後方會話卡改口：出現「前往登入」，身分卡不再在列。
    expect(find.byKey(SessionSummaryView.goLoginKey), findsOneWidget);
    expect(find.byKey(SessionSummaryView.identityKey), findsNothing);
  });

  testWidgets('撤別臺：面板留在原地、清單刷新、仍為已登入', (WidgetTester tester) async {
    final ServerApi api = _api(
      settings,
      onRevoke: () => _revoke(current: false),
    );
    final SessionController session = await signIn(api);
    await mount(tester, api, session);

    await tester.ensureVisible(find.byKey(SessionSummaryView.deviceManagerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SessionSummaryView.deviceManagerKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MyDevicesDialog.revokeKey(_deviceOther)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('devices-revoke-confirm')),
    );
    await tester.pumpAndSettle();

    expect(session.status, SessionStatus.signedIn);
    // 撤銷別臺後重新載入清單：面板仍在、兩臺仍列（假傳輸恆回同一份清單）。
    expect(find.byKey(MyDevicesDialog.revokeKey(_deviceSelf)), findsOneWidget);
    expect(find.text(l10n.devicesRevokeSuccessNotice), findsOneWidget);
  });
}
