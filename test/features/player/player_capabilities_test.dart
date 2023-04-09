/// 玩家端「有效能力」區的介面測試：狀態來源、逐能力獨立與規則版本。
///
/// 這一檔問的是：
///   1. 六枚手動限制全是 false 時，有效能力仍可以因為業務狀態而拒絕 login——
///      兩份讀法不是同一件事，界面不把「手動未限制」念成「已解凍」；
///   2. 被拒絕的能力逐項列出「拒絕」與來源標籤；允許的能力唸「允許」；
///   3. 進場被拒時有明確那句「其餘能力規則上仍可能允許，但實際不可達」；
///   4. 規則版本與常駐邊界句在場；未上線業務不冒充可用。
library;

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/player/player_restrictions_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');
const String _activityId = '01b40000-0000-7000-8000-0000000000a1';
const String _memberId = '01b40000-0000-7000-8000-0000000000m1';

String _activityRow() {
  return '{"activity_id":"$_activityId","name":"狀態受限的場",'
      '"status":"active","faction_select_mode":"free",'
      '"access_restricted":true,"member_id":"$_memberId",'
      '"nickname":"夜行者","faction_id":"",'
      '"joined_at":"2026-10-10T03:00:00.000Z"}';
}

/// 六枚手動限制全 false：這一讀不是「有效能力」的答案。
String _restrictionsBody() {
  return '{"activity_id":"$_activityId","member_id":"$_memberId",'
      '"restrict_login":false,"restrict_chat":false,'
      '"restrict_private_chat":false,"restrict_trade":false,'
      '"restrict_transfer":false,"restrict_item_use":false,'
      '"request_id":"r-own-restrictions"}';
}

String _capabilitiesBody() {
  String item(String key, bool allowed, List<String> sources) =>
      '{"capability":"$key","allowed":$allowed,'
      '"sources":[${sources.map((String s) => '"$s"').join(',')}]}';
  return '{"activity_id":"$_activityId","member_id":"$_memberId",'
      '"rules_revision":3,"access_allowed":false,'
      '"capabilities":['
      '${item('login', false, const <String>['status'])},'
      '${item('chat', true, const <String>[])},'
      '${item('private_chat', true, const <String>[])},'
      '${item('trade', true, const <String>[])},'
      '${item('transfer', true, const <String>[])},'
      '${item('item_use', true, const <String>[])}'
      '],"request_id":"r-own-capabilities"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

class _Fixture {
  int capabilityReads = 0;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        if (request.method == 'GET' && path == '/player/activities') {
          return _json(
            '{"activities":[${_activityRow()}],"request_id":"r-list"}',
            200,
          );
        }
        if (path == '/player/activities/$_activityId/restrictions') {
          return _json(_restrictionsBody(), 200);
        }
        if (path == '/player/activities/$_activityId/capabilities') {
          capabilityReads++;
          return _json(_capabilitiesBody(), 200);
        }
        return _json(
          '{"code":1001,"message":"not found","request_id":"r-nope"}',
          404,
        );
      }),
    );
  }
}

Future<AppLocalizations> _pump(WidgetTester tester, _Fixture fixture) async {
  final ServerAddressSettings settings = await buildAddressSettings(
    storedUrl: reachableUrl,
    reachable: <String>[reachableUrl],
  );
  final ServerApi api = fixture.api(settings);
  final Size previousSize = tester.view.physicalSize;
  final double previousRatio = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(720, 3000);
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
              body: SafeArea(
                child: SingleChildScrollView(
                  child: PlayerRestrictionsCard(key: UniqueKey()),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

void main() {
  testWidgets('手動全未限制但狀態拒絕 login：有效能力仍然說拒絕與來源', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(
      find.byKey(PlayerRestrictionsCard.openActionKey(_activityId)),
    );
    await tester.pumpAndSettle();

    expect(fixture.capabilityReads, 1);
    expect(
      find.byKey(PlayerRestrictionsCard.capabilitiesSectionKey),
      findsOneWidget,
    );
    // 手動六欄全 false：不會出現「進場資格已被限制」那句手動邊界。
    expect(
      find.byKey(PlayerRestrictionsCard.accessLineKey),
      findsNothing,
    );
    expect(
      find.byKey(PlayerRestrictionsCard.noneActiveKey),
      findsOneWidget,
    );
    // 但有效能力仍說 login 被拒，來源是業務狀態。
    expect(
      find.byKey(PlayerRestrictionsCard.capabilitiesAccessLineKey),
      findsOneWidget,
    );
    expect(
      find.text(l10n.playerCapabilitiesAccessDeniedNote),
      findsOneWidget,
    );
    expect(
      find.text(
        l10n.labelValuePair(
          l10n.capabilityKeyLoginLabel,
          l10n.capabilityDeniedValue,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        l10n.capabilitySourcesLine(l10n.capabilitySourceStatusLabel),
      ),
      findsOneWidget,
    );
    // 其餘能力在規則上允許：逐能力獨立，不因 login 被拒而全部改寫。
    expect(
      find.text(
        l10n.labelValuePair(
          l10n.capabilityKeyChatLabel,
          l10n.capabilityAllowedValue,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.capabilityRulesRevisionLine(3)), findsOneWidget);
    expect(
      find.byKey(PlayerRestrictionsCard.capabilitiesBoundaryKey),
      findsOneWidget,
    );
    expect(find.text(l10n.playerCapabilitiesNotWiredNote), findsOneWidget);
  });
}
