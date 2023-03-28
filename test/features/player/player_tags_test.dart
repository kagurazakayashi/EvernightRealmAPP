/// 玩家端「公開標籤定義」介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是界面有沒有把後端那幾句
/// 分開講，而不是問好不好看：
///   1. 清單只列服務端回來的公開定義（名稱以文字在場，圖標與顏色只是展示）；
///   2. 玩家讀到的是白名單投影：可用性、公開旗標本身、時刻與任何計數都不在回應裡，
///      界面也就無處渲染——假後端刻意多發那幾個格子，畫面仍一個都不許出現；
///   3. 「誰帶著哪個標籤」尚未落地：這一頁不擺任何貼標控件，也不拿空清單或 0 冒充；
///   4. 一枚標籤公開與否不改變目錄裡谁能被看见，這句話必須在場；
///   5. 四種「看不到東西」各有各的句子：沒有參加任何活動、這場沒公開任何一枚、
///      1001 不可分辨、以及這一次沒讀成功——四句不混用；
///   6. 遲到的舊回應不覆蓋新頁面：換了活動之後才回來的上一筆必須被丟棄；
///   7. 沒有快取層也沒有實時層：界面只宣稱「下一筆請求重讀」，不假造推送；
///   8. 360 px 窄屏下不出現佈局溢出（垂直滾動由殼承擔，這裡只放內容）。
library;

import 'dart:async';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/player/player_tags_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _firstActivity = '01a1f000-0000-7000-8000-0000000000a1';
const String _secondActivity = '01a1f000-0000-7000-8000-0000000000a2';
const String _firstTag = '01a1f000-0000-7000-8000-0000000000t1';
const String _secondTag = '01a1f000-0000-7000-8000-0000000000t2';

/// 玩家投影的一行：合同就只有標識加展示四值與排序。
///
/// [leakyFields] 是刻意多塞的格子（可用性、公開旗標本身、一個計數）：後端今日不發，
/// 而前端也必須容忍未知欄位——容忍的形態是「讀得過去而不渲染」，不是「顯示出來」。
String _publicTagRow({
  required String tagId,
  required String name,
  String description = '發給得名者的標記',
  String icon = 'trophy',
  String color = '#f0a020',
  int sortOrder = 0,
  bool leakyFields = false,
}) {
  final List<String> parts = <String>[
    '"tag_id":"$tagId"',
    '"name":"$name"',
    '"description":"$description"',
    '"icon":"$icon"',
    '"color":"$color"',
    '"sort_order":$sortOrder',
    if (leakyFields) '"member_count":81425',
    if (leakyFields) '"created_at":"2026-10-10T03:00:00.000Z"',
  ];
  return '{${parts.join(',')}}';
}

String _publicListBody(List<String> rows) =>
    '{"tags":[${rows.join(',')}],"request_id":"r-pub-list"}';

String _activityRow(String activityId, String name) {
  final List<String> parts = <String>[
    '"activity_id":"$activityId"',
    '"name":"$name"',
    '"status":"active"',
    '"faction_select_mode":"free"',
    '"member_id":"01a1f000-0000-7000-8000-0000000000m1"',
    '"nickname":"夜行者"',
    // 空字串＝尚未分組，是合法現值（缺席才判合同違例）。
    '"faction_id":""',
    '"joined_at":"2026-10-10T03:00:00.000Z"',
  ];
  return '{${parts.join(',')}}';
}

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
/// 「第幾次標籤請求要等到 gate 放行」留給測試自己安排：遲到響應那組斷言需要的正是
/// 「先發的那一筆晚到、後發的那一筆先到」這種不能用 sleep 去賭的形狀。
class _Fixture {
  _Fixture({this.twoActivities = false});

  /// 本人清單是否帶第二場活動（換場後的遲到回應取證用）。
  bool twoActivities;

  /// 本人清單是否為空（那一句與故障分開）。
  bool emptyActivities = false;

  /// 標籤那一讀的狀態與機器碼：404/1001 演的是「四種原因同一句話」那一態。
  int tagsStatus = 200;
  int tagsCode = 0;

  /// 公開定義清單是否回空清單（那一句與「讀不到」「沒有活動」三者各成一句）。
  bool emptyTags = false;

  /// 本人清單那一讀的狀態與機器碼（2002 匿名由此演）。
  int activitiesStatus = 200;
  int activitiesCode = 0;

  /// 指定第幾次標籤請求要等到 [gate] 放行。
  Set<int> holdCalls = <int>{};
  Completer<void>? gate;

  int listCalls = 0;
  int tagsCalls = 0;

  /// 每一次標籤讀求走過的路徑：用來證明這一頁只敲玩家那一族（各趟取證各自一份）。
  final List<String> tagsPaths = <String>[];

  /// 各場活動回哪些行：換場之後的取證要能看出「畫面上這一份屬於哪一場」。
  /// 引數是請求路徑（活動標識在路徑裡），比對用它而不另猜。
  List<String> rowsFor(String path) => path.contains(_firstActivity)
      ? <String>[
          _publicTagRow(tagId: _firstTag, name: '第一場的公開標籤'),
          _publicTagRow(
            tagId: _secondTag,
            name: '一個非常長的標籤名稱需要換行才讀得完的那一枚',
            description: '',
            icon: '',
            color: '',
            sortOrder: 1,
            leakyFields: true,
          ),
        ]
      : <String>[_publicTagRow(tagId: _firstTag, name: '第二場的公開標籤')];

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final String method = request.method;
        if (method == 'GET' && path == playerActivitiesPath()) {
          listCalls++;
          if (activitiesStatus != 200) {
            return _json(
              '{"code":$activitiesCode,"message":"x","request_id":"r-list-fail"}',
              activitiesStatus,
            );
          }
          return _json(
            _myActivitiesBody(
              ids: emptyActivities
                  ? <String>[]
                  : twoActivities
                  ? <String>[_firstActivity, _secondActivity]
                  : <String>[_firstActivity],
            ),
            200,
          );
        }
        if (method == 'GET' && path.endsWith('/tags')) {
          tagsCalls++;
          tagsPaths.add(path);
          if (holdCalls.contains(tagsCalls)) {
            await gate!.future;
          }
          if (tagsStatus != 200) {
            return _json(
              '{"code":$tagsCode,"message":"x","request_id":"r-tag-fail"}',
              tagsStatus,
            );
          }
          return _json(
            _publicListBody(emptyTags ? <String>[] : rowsFor(path)),
            200,
          );
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
  tester.view.physicalSize = Size(width, 3000);
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
                      child: PlayerTagsCard(
                        // 每一趟掛樹帶自己的 tag：同一個 runtimeType 在 pumpWidget 之間
                        // 會共用 State，不區分就帶著上一趟「已進入某一場活動」的狀態。
                        key: ValueKey<String>('player-tags-card-$surfaceTag'),
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

/// 從本人清單進入某一場活動的公開標籤清單。
Future<void> _openTags(WidgetTester tester, String activityId) async {
  await tester.tap(find.byKey(PlayerTagsCard.openKey(activityId)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('清單只列服務端回來的公開定義，名稱以文字在場且順序取回顯', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openTags(tester, _firstActivity);

    expect(find.byKey(PlayerTagsCard.listKey), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.rowKey(_firstTag)), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.rowKey(_secondTag)), findsOneWidget);
    expect(find.text('第一場的公開標籤'), findsOneWidget);
    // 長名稱在那一行裡換行讀完，而不是被截斷成看不見的尾巴。
    expect(find.text('一個非常長的標籤名稱需要換行才讀得完的那一枚'), findsOneWidget);
    // 描述為空字串是合法現值：界面念「沒有寫描述」，不念成讀取失敗。
    expect(find.text(l10n.playerTagsNoDescriptionLabel), findsOneWidget);
    // 標識在場：將來的引用指向它，而不是名稱。
    expect(
      find.text(l10n.labelValuePair(l10n.playerTagsIdLabel, _firstTag)),
      findsOneWidget,
    );
    // 這一次讀的是玩家那一族的路徑，不是管理那一族（兩道閘不同，讀法也不同）。
    expect(fixture.tagsPaths.last, playerActivityTagsPath(_firstActivity));
    expect(fixture.tagsPaths.last.startsWith('/admin'), isFalse);
  });

  testWidgets('回應裡多塞的內部格子一概不渲染：沒有可用性、公開旗標與計數', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(),
      surfaceTag: 'leaky',
    );
    await _openTags(tester, _firstActivity);

    // 假後端在第二行多發了 member_count 與 created_at（今日合同裡沒有那些格子）。
    // 容忍的形態是「讀得過去而不顯示」：那一行照樣渲染，而多出來的格子一個字都不出現。
    expect(find.byKey(PlayerTagsCard.rowKey(_secondTag)), findsOneWidget);
    expect(find.textContaining('81425'), findsNothing);
    expect(find.textContaining('2026-10-10'), findsNothing);
    // 管理側那幾句狀態話術一字不該出現在玩家頁：它們對應的格子不在玩家投影裡。
    expect(find.textContaining(l10n.tagAcceptanceLabel), findsNothing);
    expect(
      find.textContaining(
        l10n.labelValuePair(l10n.tagStatusLabel, l10n.tagAvailableLabel),
      ),
      findsNothing,
    );
    expect(
      find.textContaining(
        l10n.labelValuePair(l10n.tagStatusLabel, l10n.tagDisabledLabel),
      ),
      findsNothing,
    );
  });

  testWidgets('四句交代都在場：只有定義、貼標未落地、可見性不由標籤決定、沒有快取', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture());
    await _openTags(tester, _firstActivity);

    expect(find.byKey(PlayerTagsCard.definitionsOnlyKey), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.assignmentPendingKey), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.directoryScopeKey), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.noCacheKey), findsOneWidget);
    expect(find.text(l10n.playerTagsDefinitionsOnlyNotice), findsOneWidget);
    expect(find.text(l10n.playerTagsAssignmentPendingNotice), findsOneWidget);
    expect(find.text(l10n.playerTagsDirectoryScopeNotice), findsOneWidget);
    expect(find.text(l10n.playerTagsNoCacheNotice), findsOneWidget);
    // 「下一筆請求重讀」是今日唯一可宣稱的失效形態：這裡不寫任何推送或即時失效的字。
    expect(l10n.playerTagsNoCacheNotice, contains('下一次'));
    // 這一頁不擺任何貼標控件：沒有那條通路，就沒有那顆按鈕。
    // 這是一張唯讀卡：沒有開關也沒有輸入框，任何一格都不能被本地改動後「以為保存了」。
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('空清單那句是「還沒公開任何一枚」，不是讀取失敗也不是「沒有活動」', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture()..emptyTags = true;
    final AppLocalizations l10n = await _pump(
      tester,
      fixture,
      surfaceTag: 'empty',
    );
    await _openTags(tester, _firstActivity);
    expect(find.byKey(PlayerTagsCard.emptyKey), findsOneWidget);
    expect(find.text(l10n.playerTagsEmptyNotice), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.listKey), findsNothing);
    expect(find.byKey(PlayerTagsCard.failedKey), findsNothing);
    expect(find.byKey(PlayerTagsCard.unavailableKey), findsNothing);
    expect(fixture.listCalls, 1);
  });

  testWidgets('1001 那一態一句話不可分辨：不說有隱藏的標籤，也不說沒有', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture()
      ..tagsStatus = 404
      ..tagsCode = 1001;
    final AppLocalizations l10n = await _pump(
      tester,
      fixture,
      surfaceTag: 'gone',
    );
    await _openTags(tester, _firstActivity);

    expect(find.byKey(PlayerTagsCard.unavailableKey), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.failedKey), findsNothing);
    expect(find.text(l10n.playerTagsUnavailableNotice), findsOneWidget);
    expect(find.text('第一場的公開標籤'), findsNothing);
    expect(find.byKey(PlayerTagsCard.listKey), findsNothing);
    // 重讀是這一態唯一的出口（換目標不會變成另一句話）。
    await tester.tap(find.byKey(PlayerTagsCard.reloadKey));
    await tester.pumpAndSettle();
    expect(fixture.tagsCalls, 2);
  });

  testWidgets('2002 匿名與 1001 各成一句：這一頁不拿「你沒有標籤」騙人', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture()
      ..tagsStatus = 401
      ..tagsCode = 2002;
    final AppLocalizations l10n = await _pump(
      tester,
      fixture,
      surfaceTag: 'anon',
    );
    await _openTags(tester, _firstActivity);

    expect(find.byKey(PlayerTagsCard.failedKey), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.unavailableKey), findsNothing);
    expect(find.text(l10n.errorCodeNotAuthenticated), findsOneWidget);
    expect(find.text(l10n.playerTagsUnavailableNotice), findsNothing);
  });

  testWidgets('本人清單為空那句與「這場沒公開任何一枚」分得開', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture()..emptyActivities = true;
    final AppLocalizations l10n = await _pump(
      tester,
      fixture,
      surfaceTag: 'no-activity',
    );
    expect(find.byKey(PlayerTagsCard.activitiesEmptyKey), findsOneWidget);
    expect(find.text(l10n.playerActivitiesEmptyNotice), findsOneWidget);
    // 還沒進入任何一場活動，就不該有任何一條標籤那一段的句子。
    expect(find.byKey(PlayerTagsCard.emptyKey), findsNothing);
    expect(find.byKey(PlayerTagsCard.openKey(_firstActivity)), findsNothing);
    expect(fixture.tagsCalls, 0);
  });

  testWidgets('本人清單讀失敗：轉述那一句並只給重讀出口', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture()
      ..activitiesStatus = 500
      ..activitiesCode = 1000;
    await _pump(tester, fixture, surfaceTag: 'activities-fail');
    expect(find.byKey(PlayerTagsCard.activitiesFailedKey), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.activitiesReloadKey), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.activitiesListKey), findsNothing);
  });

  testWidgets('遲到的上一場回應不覆蓋新頁面：換場後畫面只取後到的那一份', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(twoActivities: true);
    await _pump(tester, fixture, surfaceTag: 'late');

    // 第 1 次標籤請求（第一場）被擋住讓它「遲到」，換場後第 2 次（第二場）先到。
    fixture.holdCalls = <int>{1};
    fixture.gate = Completer<void>();
    await _openTags(tester, _firstActivity);
    await tester.pump();
    expect(fixture.tagsCalls, 1);
    expect(find.byKey(PlayerTagsCard.loadingKey), findsOneWidget);

    await tester.tap(find.byKey(PlayerTagsCard.backKey));
    await tester.pumpAndSettle();
    await _openTags(tester, _secondActivity);
    expect(find.text('第二場的公開標籤'), findsOneWidget);

    // 放行遲到的那一筆：它屬於上一場，畫面此刻問的是另一場活動，必須被丟棄。
    fixture.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('第一場的公開標籤'), findsNothing);
    expect(find.text('第二場的公開標籤'), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.rowKey(_secondTag)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('回到清單讓壓著的回應失效：它不再寫任何狀態也不報錯', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pump(tester, fixture, surfaceTag: 'back');
    fixture.holdCalls = <int>{1};
    fixture.gate = Completer<void>();
    await _openTags(tester, _firstActivity);
    await tester.pump();
    expect(find.byKey(PlayerTagsCard.loadingKey), findsOneWidget);

    await tester.tap(find.byKey(PlayerTagsCard.backKey));
    await tester.pumpAndSettle();
    fixture.gate!.complete();
    await tester.pumpAndSettle();

    // 回到清單後，標籤那一段與那一筆遲到回應都不在場；清單仍可用。
    expect(find.byKey(PlayerTagsCard.loadingKey), findsNothing);
    expect(find.text('第一場的公開標籤'), findsNothing);
    expect(find.byKey(PlayerTagsCard.activitiesListKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('每次重讀都重新問一次：界面不持有一份第二答案來源', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pump(tester, fixture, surfaceTag: 'reload');
    await _openTags(tester, _firstActivity);
    final int before = fixture.tagsCalls;

    await tester.tap(find.byKey(PlayerTagsCard.reloadKey));
    await tester.pumpAndSettle();
    expect(fixture.tagsCalls, greaterThan(before));
    // 重讀的仍是那一場活動的玩家路徑，不是管理路徑。
    expect(fixture.tagsPaths.last, playerActivityTagsPath(_firstActivity));
  });

  testWidgets('360 px 窄屏渲染無異常，交代句仍完整', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(),
      width: 360,
      surfaceTag: 'narrow',
    );
    await _openTags(tester, _firstActivity);
    expect(tester.takeException(), isNull);
    expect(find.text(l10n.playerTagsCardTitle), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.rowKey(_firstTag)), findsOneWidget);
    expect(find.byKey(PlayerTagsCard.noCacheKey), findsOneWidget);
  });
}
