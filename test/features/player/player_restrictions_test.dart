/// 玩家端「我的限制狀態」卡介面測試：清單小標、六欄現值與邊界句。
///
/// 這一檔釘的是：
///   1. 清單行帶著服務端的 access_restricted 小標，被限制的活動仍列出不被藏起來；
///   2. 進入某一場後六欄逐欄唸「已被限制／未限制」，取值只讀回應、不本地推測；
///   3. restrict_login 為真時念出「只針對這一場、不停全域登入」那一句；
///      六欄全假時念「沒有任何限制生效」，兩句不會同時出現；
///   4. 邊界句常駐，不藏在按鈕或錯誤之後；
///   5. 倉庫沒有實時層：卡上那句說的是「每一次請求重新判定」，
///      不出現任何「即時推送／馬上收到通知」的字樣。
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

const String _activityId = '01a20000-0000-7000-8000-0000000000a1';
const String _otherActivityId = '01a20000-0000-7000-8000-0000000000a2';
const String _memberId = '01a20000-0000-7000-8000-0000000000m1';

String _activityRow(String activityId, String name, {bool restricted = false}) {
  return '{"activity_id":"$activityId","name":"$name","status":"active",'
      '"faction_select_mode":"free","access_restricted":$restricted,'
      '"member_id":"$_memberId","nickname":"夜行者","faction_id":"",'
      '"joined_at":"2026-10-10T03:00:00.000Z"}';
}

String _ownBody({bool login = false, bool chat = false}) {
  return '{"activity_id":"$_activityId","member_id":"$_memberId",'
      '"restrict_login":$login,"restrict_chat":$chat,'
      '"restrict_private_chat":false,"restrict_trade":false,'
      '"restrict_transfer":false,"restrict_item_use":false,'
      '"request_id":"r-own-restriction"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

class _Fixture {
  _Fixture({this.login = false, this.chat = false});

  final bool login;
  final bool chat;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        if (request.method == 'GET' && request.url.path == '/player/activities') {
          return _json(
            '{"activities":[${_activityRow(_activityId, '被限制的場',
                    restricted: login)},'
            '${_activityRow(_otherActivityId, '照常的場')}],'
            '"request_id":"r-list"}',
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path ==
                '/player/activities/$_activityId/restrictions') {
          return _json(_ownBody(login: login, chat: chat), 200);
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
  tester.view.physicalSize = Size(720, 2600);
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
                top: false,
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
  testWidgets('被限制的活動仍列出，小標說在敲壁之前', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture(login: true));

    expect(
      find.byKey(PlayerRestrictionsCard.activityRowKey(_activityId)),
      findsOneWidget,
    );
    expect(
      find.byKey(PlayerRestrictionsCard.restrictedBadgeKey(_activityId)),
      findsOneWidget,
    );
    expect(find.text(l10n.playerActivityAccessRestricted), findsOneWidget);
    // 另一場不受牽連：小標只出现在被限制的那一列。
    expect(
      find.byKey(PlayerRestrictionsCard.restrictedBadgeKey(_otherActivityId)),
      findsNothing,
    );
  });

  testWidgets('六欄逐欄唸現值；限制生效時唸進場那一句，與全假那句不會同時出現', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture(login: true));

    await tester.tap(
      find.byKey(PlayerRestrictionsCard.openActionKey(_activityId)),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(l10n.playerRestrictionActiveValue),
      findsNWidgets(2),
    );
    expect(
      find.byKey(PlayerRestrictionsCard.fieldRowKey('restrict_login')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.playerRestrictionsAccessLine),
      findsOneWidget,
    );
    expect(
      find.text(l10n.playerRestrictionsNoneActive),
      findsNothing,
    );
    // 邊界句常駐。
    expect(find.text(l10n.playerRestrictionsBoundaryNote), findsOneWidget);
  });

  testWidgets('六欄全假時唸「沒有任何限制生效」，不出現進場那一句', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture());

    await tester.tap(
      find.byKey(PlayerRestrictionsCard.openActionKey(_activityId)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.playerRestrictionsNoneActive),
      findsOneWidget,
    );
    expect(
      find.text(l10n.playerRestrictionsAccessLine),
      findsNothing,
    );
    expect(
      find.textContaining(l10n.playerRestrictionInactiveValue),
      findsNWidgets(6),
    );
  });

  testWidgets('界面不宣稱推送：只說每一次請求重新判定', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture(chat: true));

    await tester.tap(
      find.byKey(PlayerRestrictionsCard.openActionKey(_activityId)),
    );
    await tester.pumpAndSettle();

    expect(l10n.playerRestrictionsBoundaryNote, contains('重新判定'));
    // 卡上沒有一句「即時／推送／馬上通知」：倉庫今日沒有實時層。
    expect(find.textContaining('推送'), findsNothing);
    expect(find.textContaining('即時'), findsNothing);
  });
}
