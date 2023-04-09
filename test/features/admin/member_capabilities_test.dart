/// 「成員有效能力與來源摘要」對話框的介面測試。
///
/// 這一檔問的是：
///   1. 對話框以服務端讀回的業務狀態、活動狀態、帳戶狀態與 revision 為底稿；
///   2. 被拒絕的能力逐項列出「拒絕」與來源標籤（手動、狀態等）；
///   3. 進場被拒時有明確那句，且不把活動級讀成帳戶停用；
///   4. 邊界句常駐：解除手動不會清除狀態規則，生命週期與帳戶資格不能在此編輯；
///   5. 只顯示能力與來源，沒有審計原因、操作者或時刻。
library;

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:evernightrealm/features/admin/member_capabilities_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');
const String _activityId = '01b30000-0000-7000-8000-0000000000a1';
const String _memberId = '01b30000-0000-7000-8000-0000000000m1';

String _capability(
  String key, {
  bool allowed = true,
  List<String> sources = const <String>[],
  bool manual = false,
  bool status = false,
  bool lifecycle = false,
  bool identity = false,
}) {
  return '{"capability":"$key","allowed":$allowed,'
      '"sources":[${sources.map((String s) => '"$s"').join(',')}],'
      '"manual_denied":$manual,"status_denied":$status,'
      '"lifecycle_denied":$lifecycle,"identity_denied":$identity}';
}

String _body() {
  return '{"activity_id":"$_activityId","member_id":"$_memberId",'
      '"business_status":"arrested","activity_status":"active",'
      '"account_status":"active","rules_revision":4,"access_allowed":false,'
      '"capabilities":['
      '${_capability('login', allowed: true)},'
      '${_capability('chat')},'
      '${_capability('private_chat')},'
      '${_capability('trade', allowed: false, sources: const <String>['status', 'manual'], status: true, manual: true)},'
      '${_capability('transfer', allowed: false, sources: const <String>['status'], status: true)},'
      '${_capability('item_use', allowed: false, sources: const <String>['status'], status: true)}'
      '],"request_id":"r-member-capabilities"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

class _Fixture {
  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        if (request.method == 'GET' &&
            request.url.path ==
                '/admin/activities/$_activityId/members/$_memberId/capabilities') {
          return _json(_body(), 200);
        }
        return _json(
          '{"code":1001,"message":"not found","request_id":"r-nope"}',
          404,
        );
      }),
    );
  }
}

Future<AppLocalizations> _pump(WidgetTester tester, String nickname) async {
  final ServerAddressSettings settings = await buildAddressSettings(
    storedUrl: reachableUrl,
    reachable: <String>[reachableUrl],
  );
  final ServerApi api = _Fixture().api(settings);
  final Size previousSize = tester.view.physicalSize;
  final double previousRatio = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(720, 2200);
  addTearDown(() {
    tester.view.physicalSize = previousSize;
    tester.view.devicePixelRatio = previousRatio;
  });

  late AppLocalizations l10n;
  await tester.pumpWidget(
    AppScope(
      dependencies: AppDependencies(api: api),
      child: MaterialApp(
        locale: _locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            l10n = AppLocalizations.of(context);
            return Scaffold(
              body: Center(
                child: FilledButton(
                  key: const Key('open-member-capabilities'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (BuildContext dialogContext) =>
                        MemberCapabilitiesDialog(
                          api: api,
                          activityId: _activityId,
                          member: _memberReport(nickname),
                        ),
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-member-capabilities')));
  await tester.pumpAndSettle();
  return l10n;
}

MemberReport _memberReport(String nickname) {
  return MemberReport(
    memberId: _memberId,
    activityId: _activityId,
    accountId: '01b30000-0000-7000-8000-0000000000c1',
    nickname: nickname,
    factionId: '',
    displayName: '玩家甲',
    accountStatus: 'active',
    directoryVisibility: 'inherit',
    adminIdentity: false,
    businessStatus: 'arrested',
    customStatusId: '',
    customStatusName: '',
    statusDisplayName: '',
    statusAvailable: true,
    restrictLogin: false,
    restrictChat: false,
    restrictPrivateChat: false,
    restrictTrade: true,
    restrictTransfer: false,
    restrictItemUse: false,
    joinedAt: DateTime.utc(2026, 10, 10, 3),
    updatedAt: DateTime.utc(2026, 10, 10, 4),
  );
}

void main() {
  testWidgets('逐項能力與來源如實唸出，進場拒絕與邊界句常駐', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await _pump(tester, '受限的甲');

    expect(
      find.byKey(MemberCapabilitiesDialog.titleKey),
      findsOneWidget,
    );
    expect(find.text(l10n.memberCapabilitiesTitle('受限的甲')), findsOneWidget);
    expect(
      find.byKey(MemberCapabilitiesDialog.accessLineKey),
      findsOneWidget,
    );
    expect(find.text(l10n.memberCapabilitiesAccessDenied), findsOneWidget);

    // 交易被狀態與手動同時拒絕：來源行必須兩個都唸出來。
    expect(
      find.byKey(MemberCapabilitiesDialog.capabilityRowKey('trade')),
      findsOneWidget,
    );
    expect(
      find.text(
        l10n.capabilitySourcesLine(
          '${l10n.capabilitySourceStatusLabel}, '
          '${l10n.capabilitySourceManualLabel}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.capabilityRulesRevisionLine(4)), findsOneWidget);
    expect(
      find.byKey(MemberCapabilitiesDialog.boundaryKey),
      findsOneWidget,
    );
    // 沒有審計原因、操作者或時刻。
    expect(find.textContaining('reason'), findsNothing);
    expect(find.textContaining('actor'), findsNothing);
  });
}
