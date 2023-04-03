/// 「玩家分項限制」管理側介面測試：名冊標示、逐欄編輯與本地把關。
///
/// 這一檔問的是幾件事：
///   1. 名冊行如實唸出服務端讀回的限制現值（有任何一枚生效就擺標示，
///      restrict_login 亮著時再點名「進場已被限制」）；
///   2. 對話框六個開關的底稿只有那一行的現值；送出去的本體只包含被改動的欄，
///      每一欄帶著它所依據的現值（compare-and-set）；
///   3. 一個都沒改時完全不發請求（不發注定 1004 的往返）；
///   4. 成功後界面唸的是重讀回來的現值：解除 login 之後標示消失，
///      而沒有被點名的欄位原樣留在名冊裡；
///   5. 三句邊界（只作用這一場／業務未上線／逐欄獨立＋請求級生效）常駐在對話框裡，
///      不藏在按鈕之後；
///   6. 2013 之後只給重讀出口（沿用名冊那一檔的既有形態，這裡釘「編輯限制」
///      也走在同一條路上）。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/activity_members_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _activityId = '01a1f000-0000-7000-8000-0000000000e1';
const String _memberId = '01a1f000-0000-7000-8000-0000000000m1';

/// 一行成員的回應片段：六欄取值都能指定，其餘走穩定佔位。
String _memberJson({
  bool restrictLogin = false,
  bool restrictPrivateChat = false,
}) {
  return '{"member_id":"$_memberId","activity_id":"$_activityId",'
      '"account_id":"01a1f000-0000-7000-8000-0000000000c1",'
      '"nickname":"被凍結的甲","faction_id":"",'
      '"display_name":"玩家甲","account_status":"active",'
      '"directory_visibility":"inherit","admin_identity":false,'
      '"business_status":"normal","custom_status_id":"",'
      '"custom_status_name":"","status_display_name":"",'
      '"status_available":true,'
      '"restrict_login":$restrictLogin,'
      '"restrict_chat":false,'
      '"restrict_private_chat":$restrictPrivateChat,'
      '"restrict_trade":false,"restrict_transfer":false,'
      '"restrict_item_use":false,'
      '"joined_at":"2026-10-10T03:00:00.000Z",'
      '"updated_at":"2026-10-10T04:00:00.000Z"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 假後端：名冊可換版本；PUT restrictions 記下每一筆本體，
/// 成功時回「把送來的欄蓋到現值上」的讀回行（不是請求意圖的迴音）。
class _Fixture {
  _Fixture({this.editStatus = 200, this.editCode = 2013});

  /// 名冊兩行的出廠現值：login 與私聊都是真，聊天等其餘為假。
  static const bool _rosterRestrictLogin = true;
  static const bool _rosterRestrictPrivateChat = true;

  final int editStatus;
  final int editCode;

  /// 每一次 PUT restrictions 送來的本體（依送交順序）。
  final List<Map<String, Object?>> editWrites = <Map<String, Object?>>[];

  /// 名冊讀取次數：成功寫入後界面要重讀一次（不做本地拼裝）。
  int rosterReads = 0;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final String method = request.method;
        if (path == '/admin/activities/$_activityId/members' &&
            method == 'GET') {
          rosterReads++;
          // 寫入成功後名冊換第二份：被點名的欄以本體送來的新值為準，其餘保留原樣。
          final bool restricted = editWrites.isEmpty
              ? _rosterRestrictLogin
              : (editWrites.last['restrict_login'] as bool?) ??
                    _rosterRestrictLogin;
          final bool privateChat = editWrites.isEmpty
              ? _rosterRestrictPrivateChat
              : (editWrites.last['restrict_private_chat'] as bool?) ??
                    _rosterRestrictPrivateChat;
          return _json(
            '{"members":[${_memberJson(restrictLogin: restricted, restrictPrivateChat: privateChat)}],"request_id":"r-mem-list"}',
            200,
          );
        }
        if (method == 'PUT' &&
            path ==
                '/admin/activities/$_activityId/members/$_memberId/restrictions') {
          editWrites.add(jsonDecode(request.body) as Map<String, Object?>);
          if (editStatus != 200) {
            return _json(
              '{"code":$editCode,"message":"rejected","request_id":"r-mem-edit"}',
              editStatus,
            );
          }
          final Map<String, Object?> body = editWrites.last;
          final bool sentLogin =
              (body['restrict_login'] as bool?) ?? _rosterRestrictLogin;
          final bool sentPrivate =
              (body['restrict_private_chat'] as bool?) ??
              _rosterRestrictPrivateChat;
          return _json(
            '{"member":${_memberJson(restrictLogin: sentLogin, restrictPrivateChat: sentPrivate)},"request_id":"r-mem-edit"}',
            200,
          );
        }
        return _json(
          '{"code":1001,"message":"not found","request_id":"r-mem-nope"}',
          404,
        );
      }),
    );
  }
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 720,
}) async {
  final ServerAddressSettings settings = await buildAddressSettings(
    storedUrl: reachableUrl,
    reachable: <String>[reachableUrl],
  );
  final ServerApi api = fixture.api(settings);
  final Size previousSize = tester.view.physicalSize;
  final double previousRatio = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 2600);
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width),
                    child: SingleChildScrollView(
                      child: ActivityMembersCard(
                        key: UniqueKey(),
                        api: api,
                        activityId: _activityId,
                        activityStatus: 'active',
                      ),
                    ),
                  ),
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
  testWidgets('名冊行唸出服務端的限制現值與進場標示', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture());

    expect(
      find.byKey(ActivityMembersCard.restrictionsLabelKey(_memberId)),
      findsOneWidget,
    );
    // 有任何一枚生效就擺「有限制生效」；login 亮著時同一列再點名「進場已被限制」。
    expect(find.textContaining(l10n.memberRestrictionBadge), findsOneWidget);
    expect(
      find.textContaining(l10n.playerActivityAccessRestricted),
      findsOneWidget,
    );
    // 編輯按鈕只由可寫狀態決定（active 時出現）。
    expect(
      find.byKey(ActivityMembersCard.restrictionsActionKey(_memberId)),
      findsOneWidget,
    );
  });

  testWidgets('對話框六個開關的底稿取自那一行現值，邊界句常駐', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture());

    await tester.tap(
      find.byKey(ActivityMembersCard.restrictionsActionKey(_memberId)),
    );
    await tester.pumpAndSettle();

    for (final String field in memberRestrictionFields) {
      expect(
        find.byKey(ActivityMembersCard.restrictionsSwitchKey(field)),
        findsOneWidget,
      );
    }
    final SwitchListTile loginSwitch = tester.widget<SwitchListTile>(
      find.byKey(ActivityMembersCard.restrictionsSwitchKey('restrict_login')),
    );
    final SwitchListTile tradeSwitch = tester.widget<SwitchListTile>(
      find.byKey(ActivityMembersCard.restrictionsSwitchKey('restrict_trade')),
    );
    expect(loginSwitch.value, isTrue); // 那一行此刻為真
    expect(tradeSwitch.value, isFalse); // 出廠不限制

    for (final String boundaryNotice in <String>[
      l10n.memberRestrictionActivityOnlyNote,
      l10n.memberRestrictionNotWiredNote,
      l10n.memberRestrictionIndependentNote,
      l10n.memberRestrictionRequestLevelNote,
    ]) {
      expect(find.text(boundaryNotice), findsOneWidget);
    }
  });

  testWidgets('一個都沒改時完全不發請求，本地先擋那一句', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityMembersCard.restrictionsActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.restrictionsSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.editWrites, isEmpty);
    expect(
      find.text(l10n.memberRestrictionEmptySubmitHint),
      findsOneWidget,
      reason: '沒有選中任何一欄時那顆保存不該製造一次註定失敗的往返',
    );
  });

  testWidgets('送出的本體只含被改動的欄，每一欄帶著依據值', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityMembersCard.restrictionsActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    // 只動兩欄：取消 login（現值為真）、把私聊也一併取消（現值為真）；
    // 聊天與其余三欄沒碰——本體裡就不該出現它們。
    await tester.tap(
      find.byKey(ActivityMembersCard.restrictionsSwitchKey('restrict_login')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        ActivityMembersCard.restrictionsSwitchKey('restrict_private_chat'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(ActivityMembersCard.restrictionsSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.editWrites, hasLength(1));
    final Map<String, Object?> body = fixture.editWrites.single;
    expect(body.keys.toSet(), <String>{
      'restrict_login',
      'expected_restrict_login',
      'restrict_private_chat',
      'expected_restrict_private_chat',
    });
    expect(body['restrict_login'], isFalse);
    expect(body['expected_restrict_login'], isTrue);
    expect(body['restrict_private_chat'], isFalse);
    expect(body['expected_restrict_private_chat'], isTrue);

    // 成功後界面以一次重讀收尾（不做本地拼裝）：對話框收起，
    // 進場標示消失而「有限制生效」留下——被取消的只有選中的那兩欄，
    // 沒被點名的私聊在第二份名冊裡仍以服務端回讀為準。
    expect(
      find.byKey(ActivityMembersCard.restrictionsSwitchKey('restrict_login')),
      findsNothing,
    );
    expect(
      find.textContaining(l10n.playerActivityAccessRestricted),
      findsNothing,
    );
    // 寫入之後名冊至少重讀過一次（成功句與標示都只能讀回應，不能讀請求意圖）。
    expect(fixture.rosterReads, greaterThan(1));
  });

  testWidgets('2013 之後收起寫入控件，只留重讀出口', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(editStatus: 409, editCode: 2013);
    await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityMembersCard.restrictionsActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ActivityMembersCard.restrictionsSwitchKey('restrict_trade')),
    );
    await tester.pump();
    await tester.tap(find.byKey(ActivityMembersCard.restrictionsSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.editWrites, hasLength(1));
    // 過期之後名冊卡收起所有寫入控件（口徑同改名與狀態那兩條通路）：
    // 界面不再讓人在舊依據值上第二次按下去。
    expect(
      find.byKey(ActivityMembersCard.restrictionsActionKey(_memberId)),
      findsNothing,
    );
    expect(find.byKey(ActivityMembersCard.reloadKey), findsOneWidget);
  });
}
