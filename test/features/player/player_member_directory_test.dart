/// 玩家端「活動玩家目錄」介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是界面能不能把
/// 後端那幾句分開講，而不是問好看與不好看：
///   1. 四態目錄模式各成一句：`hidden` 是「這一態本來就不列任何人」，不是錯誤、
///      也不是「沒人加入」；另外三態列的是後端給的行，界面不自己筛；
///   2. 目錄收起時本人那一段仍有內容：兩段各讀各的，誰失敗都不抹掉對方；
///   3. 詳情走受權的單筆路徑，不拿列表那一行本地展開，返回後清單還在原處；
///   4. 遲到的舊回應不覆蓋新頁面：換頁時先發的那一筆回來，畫面仍取後到的那一份；
///      換活動時舊卡已離樹，它的回應連觸發 setState 的資格都沒有；
///   5. 失權後的下一筆權威請求把不可見的內容清掉（不留一份「離線緩存」在畫面上）；
///   6. 真正空目錄、篩後無匹配、載入失敗、1001 不可分辨——四句話不混用；
///   7. 停用旗標只在讀到展示值時才講「已停用」，簡介那一格只有佔位，
///      在線狀態與人數一個字都不猜；
///   8. 360 px 窄屏下不出現佈局溢出（垂直滾動由殼承擔，這裡只放內容）。
library;

import 'dart:async';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/player/player_member_directory_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _firstActivity = '01a1e000-0000-7000-8000-0000000000a1';
const String _secondActivity = '01a1e000-0000-7000-8000-0000000000a2';
const String _selfMember = '01a1e000-0000-7000-8000-0000000000m0';
const String _targetMember = '01a1e000-0000-7000-8000-0000000000m9';
const String _redFaction = '01a1e000-0000-7000-8000-0000000000f1';
const String _blueFaction = '01a1e000-0000-7000-8000-0000000000f2';

/// 一行目錄投影（`factionId` 空字串＝尚未分組；`factionName` 空字串＝讀不到展示值）。
String _row({
  required String memberId,
  required String nickname,
  String factionId = _redFaction,
  String factionName = '紅隊',
  bool factionAvailable = true,
  String businessStatus = 'normal',
  String customStatusId = '',
  String customStatusName = '',
  String statusDisplayName = '',
  bool statusAvailable = true,
}) {
  final List<String> parts = <String>[
    '"member_id":"$memberId"',
    '"nickname":"$nickname"',
    '"faction_id":"$factionId"',
    '"faction_name":"$factionName"',
    '"faction_icon":"star"',
    '"faction_color":"#12abcd"',
    '"faction_available":$factionAvailable',
    '"business_status":"$businessStatus"',
    '"custom_status_id":"$customStatusId"',
    '"custom_status_name":"$customStatusName"',
    '"status_display_name":"$statusDisplayName"',
    '"status_available":$statusAvailable',
    '"joined_at":"2026-10-10T03:00:00.000Z"',
  ];
  return '{${parts.join(',')}}';
}

/// 本檔的預設三行：紅隊一人、藍隊一個停用陣營的長暱稱者、一人尚未分組。
List<String> _defaultRows() => <String>[
  _row(memberId: _selfMember, nickname: '夜行者'),
  _row(
    memberId: _targetMember,
    nickname: '一個非常長的活動內暱稱需要換行才讀得完的那一位',
    factionId: _blueFaction,
    factionName: '藍隊',
    factionAvailable: false,
  ),
  _row(
    memberId: '01a1e000-0000-7000-8000-0000000000m3',
    nickname: '還沒進組的那一位',
    factionId: '',
    factionName: '',
    factionAvailable: false,
  ),
];

String _facet({
  String factionId = _redFaction,
  String name = '紅隊',
  int count = 2,
}) {
  return '{"faction_id":"$factionId","name":"$name","icon":"star",'
      '"color":"#12abcd","count":$count}';
}

String _directoryBody({
  String mode = 'all_members',
  List<String> rows = const <String>[],
  List<String> facets = const <String>[],
  int page = 1,
  int total = 0,
  String selfMemberId = _selfMember,
}) {
  final List<String> parts = <String>[
    '"members":[${rows.join(',')}]',
    '"facets":[${facets.join(',')}]',
    '"member_directory_mode":"$mode"',
    '"self_member_id":"$selfMemberId"',
    '"page":$page',
    '"page_size":20',
    '"total":$total',
    '"request_id":"r-dir"',
  ];
  return '{${parts.join(',')}}';
}

String _profileBody({
  String mode = 'all_members',
  String visibility = 'inherit',
  String status = 'active',
}) {
  final List<String> parts = <String>[
    '"activity_id":"$_firstActivity"',
    '"name":"秋夜長談"',
    '"status":"$status"',
    '"member_directory_mode":"$mode"',
    '"member_id":"$_selfMember"',
    '"nickname":"夜行者"',
    '"faction_id":"$_redFaction"',
    '"faction_name":"紅隊"',
    '"faction_icon":"star"',
    '"faction_color":"#12abcd"',
    '"faction_available":true',
    '"directory_visibility":"$visibility"',
    '"business_status":"normal"',
    '"custom_status_id":""',
    '"custom_status_name":""',
    '"status_display_name":""',
    '"status_available":true',
    '"joined_at":"2026-10-10T03:00:00.000Z"',
    '"request_id":"r-profile"',
  ];
  return '{${parts.join(',')}}';
}

String _detailBody({String nickname = '被點名那一行'}) {
  return '{"member":${_row(memberId: _targetMember, nickname: nickname)},'
      '"request_id":"r-one"}';
}

String _activityRow(String activityId, String name) {
  return '{"activity_id":"$activityId","name":"$name","status":"active",'
      '"faction_select_mode":"free","member_id":"$_selfMember",'
      '"nickname":"夜行者","faction_id":"$_redFaction",'
      '"joined_at":"2026-10-10T03:00:00.000Z"}';
}

/// 本人的活動清單：換場景取證時要真的有两行，否則「進另一場活動」無從按下去。
String _myActivitiesBody({required List<String> ids}) {
  return '{"activities":[${ids.map((String id) => _activityRow(id, '秋夜長談')).join(',')}]'
      ',"request_id":"r-list"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 依路徑與方法分流的假後端。
///
/// 它刻意把「第幾次目錄請求回什麼」留給測試自己安排：遲到響應那組斷言需要的正是
/// 「先發的那一筆晚到、後發的那一筆先到」這種在真實網路裡會發生、卻不能用 sleep 去賭的形狀。
class _Fixture {
  _Fixture({
    this.mode = 'all_members',
    this.rows,
    this.profileVisibility = 'inherit',
  });

  /// 本人活動清單是否為空（那一句與故障分開）。
  bool emptyActivities = false;

  /// 清單是否帶第二場活動（換場後的遲到回應取證用）。
  bool twoActivities = false;

  /// 目錄回應裡那一欄模式現值（界面據它分岔，絕不在請求裡）。
  String mode;
  List<String>? rows;
  List<String>? facets;

  /// 覆寫總筆數：分頁控件只由後端回顯的 page／total 決定，取證時要能做出「還有下頁」。
  int? total;
  String activityId = _firstActivity;
  int directoryStatus = 200;
  int directoryCode = 0;
  int profileStatus = 200;
  int detailStatus = 200;
  int detailCode = 0;
  String profileVisibility;

  /// 本人投影裡那個活動的狀態現值（停止與歸檔態要多念一句說明）。
  String profileActivityStatus = 'active';

  int listCalls = 0;
  int directoryCalls = 0;
  int profileCalls = 0;
  int detailCalls = 0;
  final List<String> directoryQueries = <String>[];
  final List<String> detailPaths = <String>[];

  /// 指定第幾次目錄請求要等到 [gate] 放行（遲到響應取證用）。
  Set<int> holdCalls = <int>{};
  Completer<void>? gate;

  /// 換場活動時測試用它改本人清單（舊卡的回應必須因為離樹而被丟棄）。
  String myActivitiesBody() => emptyActivities
      ? '{"activities":[],"request_id":"r-list"}'
      : _myActivitiesBody(
          ids: twoActivities
              ? <String>[activityId, _secondActivity]
              : <String>[activityId],
        );

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final String method = request.method;
        if (method == 'GET' && path == playerActivitiesPath()) {
          listCalls++;
          return _json(myActivitiesBody(), 200);
        }
        if (method == 'GET' && path.endsWith('/profile')) {
          profileCalls++;
          if (profileStatus != 200) {
            return _json(
              '{"code":1001,"message":"x","request_id":"r-p"}',
              profileStatus,
            );
          }
          return _json(
            _profileBody(
              mode: mode,
              visibility: profileVisibility,
              status: profileActivityStatus,
            ),
            200,
          );
        }
        if (method == 'GET' && path.endsWith('/members')) {
          directoryCalls++;
          directoryQueries.add(request.url.query);
          if (holdCalls.contains(directoryCalls)) {
            await gate!.future;
          }
          if (directoryStatus != 200) {
            return _json(
              '{"code":$directoryCode,"message":"x","request_id":"r-d"}',
              directoryStatus,
            );
          }
          return _json(
            _directoryBody(
              mode: mode,
              rows: rows ?? _defaultRows(),
              facets: facets ?? <String>[_facet()],
              page: int.parse(request.url.queryParameters['page'] ?? '1'),
              total: total ?? (rows ?? _defaultRows()).length,
            ),
            200,
          );
        }
        if (method == 'GET' && path.contains('/members/')) {
          detailCalls++;
          detailPaths.add(path);
          if (detailStatus != 200) {
            return _json(
              '{"code":$detailCode,"message":"x","request_id":"r-one"}',
              detailStatus,
            );
          }
          return _json(_detailBody(), 200);
        }
        return _json('{"code":1001,"request_id":"r-nope"}', 404);
      }),
    );
  }
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 720,
  String surfaceTag = 'default',
}) async {
  final ServerAddressSettings settings = await buildAddressSettings(
    storedUrl: reachableUrl,
    reachable: <String>[reachableUrl],
  );
  final ServerApi api = fixture.api(settings);
  final Size previousSize = tester.view.physicalSize;
  final double previousRatio = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 2800);
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
              body: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 每一次掛樹帶自己的 tag：同一個 runtimeType 在 pumpWidget 之間會
                    // 共用 State，不區分就會帶著上一趟的「已進入某一場活動」狀態。
                    PlayerDirectorySurface(
                      key: ValueKey<String>('directory-surface-$surfaceTag'),
                    ),
                  ],
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

/// 從本人清單進入某一場活動的目錄。
Future<void> _openDirectory(WidgetTester tester, String activityId) async {
  await tester.tap(find.byKey(PlayerDirectorySurface.openKey(activityId)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('四態模式各自的一句話：hidden 不是錯誤也不是沒人加入', (WidgetTester tester) async {
    for (final String mode in <String>[
      'hidden',
      'same_faction_only',
      'all_players_except_admin',
      'all_members',
    ]) {
      final _Fixture fixture = _Fixture(mode: mode);
      final AppLocalizations l10n = await _pump(
        tester,
        fixture,
        surfaceTag: 'mode-$mode',
      );
      await _openDirectory(tester, _firstActivity);

      if (mode == 'hidden') {
        expect(
          find.byKey(ActivityMemberDirectoryCard.hiddenKey),
          findsOneWidget,
          reason: 'hidden 態要講出「這一態本來就不列任何人」那一句',
        );
        expect(find.text(l10n.playerDirectoryHiddenNotice), findsOneWidget);
        expect(
          find.byKey(ActivityMemberDirectoryCard.emptyKey),
          findsNothing,
          reason: '策略隱藏與真正沒人加入是兩句話，不能都落到空目錄那一句',
        );
        expect(find.byKey(ActivityMemberDirectoryCard.listKey), findsNothing);
      } else {
        expect(find.byKey(ActivityMemberDirectoryCard.listKey), findsOneWidget);
        expect(find.text('夜行者'), findsOneWidget);
        expect(find.byKey(ActivityMemberDirectoryCard.hiddenKey), findsNothing);
        // 模式列取後端回顯的那一格，界面只負責把它講成人話。
        expect(find.byKey(ActivityMemberDirectoryCard.modeKey), findsOneWidget);
      }
      // 每一態都讀得到本人那一段：目錄收不收起都不動它。
      expect(
        find.byKey(ActivityMemberDirectoryCard.profileKey),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey<String>('player-directory-back')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('目錄收起時本人的資料仍在，且不把「我的資料」清空', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(mode: 'hidden');
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openDirectory(tester, _firstActivity);

    expect(fixture.directoryCalls, 1);
    expect(fixture.profileCalls, 1);
    expect(find.text(l10n.playerDirectoryHiddenNotice), findsOneWidget);
    // 本人那一段用的是獨立通路：列表空掉的時候它仍帶著我的暱稱與歸屬。
    expect(find.textContaining('夜行者'), findsWidgets);
    expect(find.text(l10n.playerProfileSectionTitle), findsOneWidget);
    expect(
      find.text(
        l10n.labelValuePair(l10n.playerDirectoryMemberIdLabel, _selfMember),
      ),
      findsWidgets,
    );
  });

  testWidgets('真正空目錄、篩後無匹配、載入失敗與 1001 四句不混用', (WidgetTester tester) async {
    // 一、空而並非隱藏：後端回 total=0 而模式不是 hidden。
    final _Fixture emptyFixture = _Fixture(
      mode: 'all_members',
      rows: <String>[],
    );
    final AppLocalizations l10n = await _pump(tester, emptyFixture);
    await _openDirectory(tester, _firstActivity);
    expect(find.byKey(ActivityMemberDirectoryCard.emptyKey), findsOneWidget);
    expect(find.text(l10n.playerDirectoryEmptyNotice), findsOneWidget);
    expect(find.text(l10n.playerDirectoryHiddenNotice), findsNothing);

    // 二、帶關鍵字後無匹配：那句要換成「篩掉了」而不是「沒人加入」。
    await tester.enterText(
      find.byKey(ActivityMemberDirectoryCard.searchKey),
      '查無此人',
    );
    await tester.tap(find.byKey(ActivityMemberDirectoryCard.searchActionKey));
    await tester.pumpAndSettle();
    expect(emptyFixture.directoryCalls, 2);
    expect(emptyFixture.directoryQueries.last, contains('q='));
    emptyFixture.rows = <String>[];
    expect(find.byKey(ActivityMemberDirectoryCard.noMatchKey), findsOneWidget);
    expect(find.text(l10n.playerDirectoryNoMatchNotice), findsOneWidget);

    // 三、傳輸級失敗：那不是「沒有」，也不宣稱讀到了任何人。
    final _Fixture offline = _Fixture(mode: 'all_members')
      ..directoryStatus = 500
      ..directoryCode = 1000;
    final AppLocalizations l2 = await _pump(tester, offline, surfaceTag: 'off');
    await _openDirectory(tester, _firstActivity);
    expect(find.byKey(ActivityMemberDirectoryCard.failedKey), findsOneWidget);
    expect(
      find.byKey(ActivityMemberDirectoryCard.unavailableKey),
      findsNothing,
    );
    expect(find.byKey(ActivityMemberDirectoryCard.listKey), findsNothing);
    expect(find.text(l2.activityReloadAction), findsWidgets);

    // 四、1001：查無活動、非成員、跨活動、此刻不可見，四句在外是同一句，
    // 而那句裡不出現「還有別人看不見的人」這種存在性訊號。
    final _Fixture gone = _Fixture(mode: 'all_members')
      ..directoryStatus = 404
      ..directoryCode = 1001;
    final AppLocalizations l3 = await _pump(tester, gone, surfaceTag: 'gone');
    await _openDirectory(tester, _firstActivity);
    expect(
      find.byKey(ActivityMemberDirectoryCard.unavailableKey),
      findsOneWidget,
    );
    expect(find.text(l3.playerDirectoryUnavailableNotice), findsOneWidget);
    expect(find.text('夜行者'), findsNothing);
  });

  testWidgets('詳情走受權的單筆路徑，返回後清單還在原處', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openDirectory(tester, _firstActivity);

    await tester.tap(
      find.byKey(ActivityMemberDirectoryCard.detailKey(_targetMember)),
    );
    await tester.pumpAndSettle();

    expect(fixture.detailCalls, 1);
    expect(
      fixture.detailPaths.single,
      playerActivityMemberItemPath(_firstActivity, _targetMember),
      reason: '進入詳情必須重新問那條受權路徑，而不是把列表那一行本地展開',
    );
    expect(find.byKey(PlayerMemberDetailCard.cardKey), findsOneWidget);
    expect(find.text(l10n.playerDetailTitle), findsOneWidget);
    expect(find.text('被點名那一行'), findsOneWidget);
    expect(find.textContaining(_targetMember), findsWidgets);
    // 簡介那一格只有佔位與一句「合同裡還沒有這一欄」。
    expect(
      find.byKey(ValueKey<String>('player-bio-placeholder')),
      findsOneWidget,
    );
    expect(find.text(l10n.playerBioNotWiredNotice), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey<String>('member-directory-detail-back')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ActivityMemberDirectoryCard.listKey), findsOneWidget);
    expect(find.text('夜行者'), findsOneWidget);
  });

  testWidgets('失權後下一筆權威請求清掉詳情內容，不留一份可讀的舊資料', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openDirectory(tester, _firstActivity);
    await tester.tap(
      find.byKey(ActivityMemberDirectoryCard.detailKey(_targetMember)),
    );
    await tester.pumpAndSettle();
    expect(find.text('被點名那一行'), findsOneWidget);

    // 把這張卡改成此刻讀不到：下一次重讀就該把內容換成那一句，而不是繼續顯示上一份。
    fixture.detailStatus = 404;
    fixture.detailCode = 1001;
    await tester.tap(
      find.byKey(ValueKey<String>('member-detail-reload-again')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PlayerMemberDetailCard.unavailableKey), findsOneWidget);
    expect(find.text(l10n.playerDirectoryUnavailableNotice), findsOneWidget);
    expect(find.text('被點名那一行'), findsNothing);
    expect(find.byKey(PlayerMemberDetailCard.cardKey), findsNothing);
  });

  testWidgets('權限改變後重查目錄：行清掉，不拿上一批冒充現值', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openDirectory(tester, _firstActivity);
    expect(find.byKey(ActivityMemberDirectoryCard.listKey), findsOneWidget);

    fixture.directoryStatus = 404;
    fixture.directoryCode = 1001;
    await tester.tap(find.byKey(ActivityMemberDirectoryCard.reloadKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ActivityMemberDirectoryCard.listKey), findsNothing);
    expect(find.text('夜行者'), findsNothing);
    expect(
      find.byKey(ActivityMemberDirectoryCard.unavailableKey),
      findsOneWidget,
    );
    // 本人那一段是另一條讀法：它沒失敗，就不該被目錄那一段的失敗抹掉。
    expect(find.byKey(ActivityMemberDirectoryCard.profileKey), findsOneWidget);
    expect(find.text(l10n.playerProfileSectionTitle), findsOneWidget);
  });

  testWidgets('遲到的篩選回應不覆蓋後到的那一份', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture()..total = 45;
    await _pump(tester, fixture, surfaceTag: 'late');
    await _openDirectory(tester, _firstActivity);
    expect(find.text('夜行者'), findsOneWidget);

    // 第 2 次目錄請求（點陣營候選）被擋住，讓它能「遲到」；第 3 次（清掉篩選）先到。
    // 這裡刻意不用換頁做對照：下一頁在最後一份權威回應裡仍是第 1 頁，
    // 那顆按鈕按後端回顯收起才是對的，界面不拿本地猜的頁碼去放開它。
    fixture.holdCalls = <int>{2};
    fixture.gate = Completer<void>();
    fixture.rows = <String>[
      _row(
        memberId: '01a1e000-0000-7000-8000-0000000000zz',
        nickname: '遲到的那一份',
      ),
    ];
    await tester.tap(
      find.byKey(ActivityMemberDirectoryCard.facetKey(_redFaction)),
    );
    await tester.pump();
    expect(fixture.directoryCalls, 2);
    expect(
      Uri.splitQueryString(fixture.directoryQueries.last)['faction'],
      _redFaction,
    );

    fixture.rows = <String>[_row(memberId: _selfMember, nickname: '後到的那一份')];
    await tester.tap(find.byKey(ActivityMemberDirectoryCard.filterAllKey));
    await tester.pumpAndSettle();
    expect(find.text('後到的那一份'), findsOneWidget);

    // 放行遲到的那一筆：它屬於上一個篩選，畫面此刻問的是另一份結果集，必須被丟棄。
    fixture.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('遲到的那一份'), findsNothing);
    expect(find.text('後到的那一份'), findsOneWidget);
    expect(find.byKey(ActivityMemberDirectoryCard.listKey), findsOneWidget);
  });

  testWidgets('換一場活動後舊卡的遲到回應不觸碰新頁面', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture()..twoActivities = true;
    await _pump(tester, fixture, surfaceTag: 'switch');
    fixture.holdCalls = <int>{1};
    fixture.gate = Completer<void>();
    await _openDirectory(tester, _firstActivity);
    expect(find.byKey(ActivityMemberDirectoryCard.loadingKey), findsOneWidget);

    // 回到清單並進另一場活動：舊卡離樹，它那筆還壓著的回應不能再寫任何狀態。
    fixture.holdCalls = <int>{};
    fixture.rows = <String>[
      _row(memberId: '01a1e000-0000-7000-8000-0000000000b2', nickname: '第二場的行'),
    ];
    await tester.tap(find.byKey(ValueKey<String>('player-directory-back')));
    await tester.pumpAndSettle();
    await _openDirectory(tester, _secondActivity);
    await tester.pumpAndSettle();
    expect(find.text('第二場的行'), findsOneWidget);

    fixture.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('第二場的行'), findsOneWidget);
  });

  testWidgets('活動已結束與目錄沒有可列的人，是兩句分得開的話', (WidgetTester tester) async {
    // 停止態：後端的讀取通路不受生命週期門禁約束（那道閘只管寫入），
    // 所以目錄照舊列得出來，而界面必須同時把「這場已經結束」講出來——
    // 不讓玩家把「活動結束了」誤讀成「這份目錄讀不到東西」。
    for (final String status in <String>['closed', 'archived']) {
      final _Fixture fixture = _Fixture()..profileActivityStatus = status;
      final AppLocalizations l10n = await _pump(
        tester,
        fixture,
        surfaceTag: 'status-$status',
      );
      await _openDirectory(tester, _firstActivity);
      expect(find.byKey(ActivityMemberDirectoryCard.statusKey), findsOneWidget);
      expect(
        find.byKey(ActivityMemberDirectoryCard.frozenKey),
        findsOneWidget,
        reason: '$status 態要多加那一句「讀取不因停止或歸檔而失效」',
      );
      expect(find.text(l10n.playerDirectoryFrozenReadNotice), findsOneWidget);
      expect(find.byKey(ActivityMemberDirectoryCard.listKey), findsOneWidget);
      expect(find.text('夜行者'), findsOneWidget);
      // 空目錄那句不該被誤唸成活動失效，反之也然：兩句同時在場時各自有自己的鍵。
      expect(find.byKey(ActivityMemberDirectoryCard.emptyKey), findsNothing);
    }

    // 對照組：active 態不多念那一句。
    final _Fixture openFixture = _Fixture();
    await _pump(tester, openFixture, surfaceTag: 'status-active');
    await _openDirectory(tester, _firstActivity);
    expect(find.byKey(ActivityMemberDirectoryCard.frozenKey), findsNothing);
    expect(find.byKey(ActivityMemberDirectoryCard.statusKey), findsOneWidget);
  });

  testWidgets('搜尋與陣營篩選都回到第一頁，並把引數交給後端', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pump(tester, fixture);
    await _openDirectory(tester, _firstActivity);
    expect(fixture.directoryQueries.single, 'page=1&page_size=20');

    await tester.enterText(
      find.byKey(ActivityMemberDirectoryCard.searchKey),
      '夜行者',
    );
    await tester.tap(find.byKey(ActivityMemberDirectoryCard.searchActionKey));
    await tester.pumpAndSettle();
    expect(fixture.directoryQueries.last, contains('page=1'));
    expect(Uri.splitQueryString(fixture.directoryQueries.last)['q'], '夜行者');

    await tester.tap(
      find.byKey(ActivityMemberDirectoryCard.facetKey(_redFaction)),
    );
    await tester.pumpAndSettle();
    expect(
      Uri.splitQueryString(fixture.directoryQueries.last)['faction'],
      _redFaction,
    );
    expect(fixture.directoryQueries.last, contains('page=1'));

    await tester.tap(find.byKey(ActivityMemberDirectoryCard.filterAllKey));
    await tester.pumpAndSettle();
    expect(fixture.directoryQueries.last, isNot(contains('faction=')));
  });

  testWidgets('停用旗標只在讀到展示值時才講；無歸屬與讀不到各有各的句子', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openDirectory(tester, _firstActivity);

    // 藍隊那一行所屬陣營已停用：句子講的是「不再接收新成員＋既有歸屬保留」。
    expect(
      find.text(l10n.playerDirectoryFactionDisabledSuffix),
      findsOneWidget,
    );
    // 尚未分組那行講「尚未分組」，不跟著唸一遍已停用。
    expect(find.textContaining(l10n.playerCurrentFactionNone), findsOneWidget);
    // 讀不到展示值（名稱空而標識非空）那句不該被當成停用。
    fixture.rows = <String>[
      _row(
        memberId: '01a1e000-0000-7000-8000-0000000000m4',
        nickname: '歸屬讀不到的人',
        factionId: _blueFaction,
        factionName: '',
        factionAvailable: false,
      ),
    ];
    await tester.tap(find.byKey(ActivityMemberDirectoryCard.reloadKey));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(l10n.playerDirectoryFactionUnreadableNotice),
      findsOneWidget,
    );
    expect(find.text(l10n.playerDirectoryFactionDisabledSuffix), findsNothing);
  });

  testWidgets('在線狀態一個字都不猜，簡介只有佔位', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openDirectory(tester, _firstActivity);

    expect(find.byKey(ActivityMemberDirectoryCard.presenceKey), findsOneWidget);
    expect(find.text(l10n.playerDirectoryPresenceNotice), findsOneWidget);
    // 不出現任何一枚「在線／離線」狀態字樣，也不報在線人數（倉庫裡今日沒有那一層）：
    // 界面不拿「沒顯示」冒充「他離線」，也不拿行數冒充在線數。
    for (final String guess in <String>[
      '在線',
      '离線',
      '離線',
      'Offline',
      'Online',
    ]) {
      expect(find.text(guess), findsNothing);
    }
    // 本人那一段的簡介同樣只有佔位那一句。
    expect(
      find.descendant(
        of: find.byKey(ActivityMemberDirectoryCard.profileKey),
        matching: find.byKey(ValueKey<String>('player-bio-placeholder')),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.playerBioNotWiredNotice), findsWidgets);
  });

  testWidgets('被覆蓋收起來時本人仍讀得到自己，兩句各說各的', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(
      mode: 'all_members',
      profileVisibility: 'hidden',
    );
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openDirectory(tester, _firstActivity);

    expect(find.text(l10n.playerProfileHiddenByOverrideNotice), findsOneWidget);
    expect(
      find.text(l10n.playerProfileFollowsModeNotice),
      findsNothing,
      reason: '覆蓋態與服從活動設定是兩句話，不能同時唸出來',
    );
    expect(find.text('夜行者'), findsOneWidget);
  });

  testWidgets('360 窄屏：清單與詳情都不出現佈局溢出', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pump(tester, fixture, width: 360, surfaceTag: 'narrow');
    await _openDirectory(tester, _firstActivity);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(ActivityMemberDirectoryCard.detailKey(_targetMember)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(PlayerMemberDetailCard.cardKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本人讀法失敗只抹掉自己那一段，不動目錄', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture()..profileStatus = 404;
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openDirectory(tester, _firstActivity);

    expect(
      find.byKey(ActivityMemberDirectoryCard.profileFailedKey),
      findsOneWidget,
    );
    expect(find.byKey(ActivityMemberDirectoryCard.listKey), findsOneWidget);
    expect(find.text('夜行者'), findsOneWidget);
    expect(fixture.directoryCalls, 1);
    expect(fixture.profileCalls, 1);
    expect(find.text(l10n.playerDirectoryUnavailableNotice), findsOneWidget);
  });

  testWidgets('空活動清單那句是「我還沒參加任何活動」，不是故障', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture()..emptyActivities = true;
    final AppLocalizations l10n = await _pump(tester, fixture);
    expect(fixture.listCalls, 1);
    expect(
      find.byKey(PlayerDirectorySurface.emptyKey),
      findsOneWidget,
      reason: '空清單是一句事實，不能落成載入失敗那一句',
    );
    expect(find.text(l10n.playerActivitiesEmptyNotice), findsOneWidget);
    expect(find.byKey(PlayerDirectorySurface.failedKey), findsNothing);
    expect(
      find.byKey(PlayerDirectorySurface.openKey(_firstActivity)),
      findsNothing,
    );
  });

  testWidgets('業務狀態那一列只念服務端回讀的展示值，並與在線狀態分開講', (WidgetTester tester) async {
    const String customId = '01a1e000-0000-7000-8000-0000000000s1';
    final _Fixture fixture = _Fixture(
      mode: 'all_members',
      rows: <String>[
        // 內建值帶著活動層級的覆蓋：界面念覆蓋那一份，不念內部鍵。
        _row(
          memberId: _selfMember,
          nickname: '夜行者',
          businessStatus: 'offline',
          statusDisplayName: '暫離現場',
        ),
        // 自訂定義此刻已停用：既有歸屬保留，只有可用性這一格改口。
        _row(
          memberId: _targetMember,
          nickname: '自訂那位',
          businessStatus: 'custom',
          customStatusId: customId,
          customStatusName: '失蹤中',
          statusDisplayName: '失蹤中',
          statusAvailable: false,
        ),
      ],
    );
    final AppLocalizations l10n = await _pump(
      tester,
      fixture,
      surfaceTag: 'status',
    );
    await _openDirectory(tester, _firstActivity);

    expect(find.textContaining('暫離現場'), findsWidgets);
    expect(find.textContaining('失蹤中'), findsWidgets);
    expect(
      find.byKey(ActivityMemberDirectoryCard.statusRowKey(_targetMember)),
      findsOneWidget,
    );
    expect(find.textContaining(l10n.playerStatusDisabledNotice), findsWidgets);
    // 「不是在線指示」那一句寫在本人那一段；這一頁也一個「在線／Offline」字樣都不長。
    expect(
      find.byKey(ActivityMemberDirectoryCard.statusScopeKey),
      findsOneWidget,
    );
    for (final String guess in <String>['在線', '線上', 'Online']) {
      expect(find.text(guess), findsNothing);
    }
    // 狀態名稱是純文字：承擔它的是 Text（其內部 RichText 是 Flutter 的實作細節，
    // 不是把這段文字交給 HTML 渲染）。界面今日也沒有任何一條富文本／HTML 通路。
    expect(find.byType(Text), findsWidgets);
  });
}
