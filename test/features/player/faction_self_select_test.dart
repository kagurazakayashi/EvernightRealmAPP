/// 玩家端「我的陣營」介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是幾件事：
///   1. 清單與現況一律取服務端回顯；空清單那一句是「我還沒參加任何活動」而不是故障；
///   2. 「此刻能不能選」讀的是後端派生值：can_select_now 為假時四種原因各說各的一句，
///      界面不把它們併成一句「現在不行」，也不因為藏了按鈕就以為擋住了；
///   3. 停用的陣營照樣列在候選裡並標成不可選（保留歸屬是已批準的語意，顯示出來比消失好解釋）；
///   4. 自選提交恰好兩欄，依據值同取自上一次讀回的那一格；結果句只讀回應，
///      成功後以一次重讀收尾，把本地那份現值換成服務端回來的；
///   5. 確認框取消時一請求都不發；2013 之後只給「重新讀取我的現值」的出口，不自動補發；
///   6. 「自選不能清空」那句限制常在，且沒有一顆把歸屬改回空白的按鈕；
///   7. 360 px 窄屏下不出現佈局溢出（垂直滾動由殼承擔，這裡只放內容）。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/player/faction_self_select_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _activityId = '01a1d000-0000-7000-8000-0000000000e1';
const String _memberId = '01a1d000-0000-7000-8000-0000000000m1';
const String _openFactionId = '01a1d000-0000-7000-8000-0000000000f1';
const String _stoppedFactionId = '01a1d000-0000-7000-8000-0000000000f2';

/// 一個候選項的回顯本體。
String _optionJson({
  String factionId = _openFactionId,
  String name = '黎明軍',
  bool available = true,
  bool selectable = true,
}) {
  return '{"faction_id":"$factionId","name":"$name","description":"",'
      '"icon":"star","color":"#12abcd","sort_order":0,'
      '"available":$available,"selectable":$selectable}';
}

/// 本人現況一讀的本體（`factionId` 空字串＝尚未分組）。
String _viewBody({
  String status = 'active',
  String mode = 'free',
  bool canSelectNow = true,
  String factionId = '',
  List<String> options = const <String>[],
}) {
  return '{"activity_id":"$_activityId","name":"秋夜長談","status":"$status",'
      '"faction_select_mode":"$mode","can_select_now":$canSelectNow,'
      '"member_id":"$_memberId","nickname":"夜行者","faction_id":"$factionId",'
      '"factions":[${options.join(',')}],"request_id":"r-view"}';
}

String _listBody(List<String> rows) =>
    '{"activities":[${rows.join(',')}],"request_id":"r-list"}';

String _listRow({String factionId = '', String mode = 'free'}) {
  return '{"activity_id":"$_activityId","name":"秋夜長談","status":"active",'
      '"faction_select_mode":"$mode","member_id":"$_memberId",'
      '"nickname":"夜行者","faction_id":"$factionId",'
      '"joined_at":"2026-10-10T03:00:00.000Z"}';
}

String _writeBody({required String factionId}) {
  return '{"member_id":"$_memberId","activity_id":"$_activityId",'
      '"nickname":"夜行者","faction_id":"$factionId",'
      '"updated_at":"2026-10-10T05:00:00.000Z","request_id":"r-w"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 依路徑與方法分流的假後端：寫入成功後現況換成新的歸屬，證明界面重讀服務端結果。
class _Fixture {
  _Fixture({
    this.status = 'active',
    this.mode = 'free',
    this.canSelectNow = true,
    this.factionId = '',
    this.factionMissing = false,
    this.emptyActivities = false,
    this.writeStatus = 200,
    this.writeCode = 0,
  });

  final String status;
  final String mode;
  final bool canSelectNow;
  final String factionId;

  /// 演「歸屬指向一個清單裡沒有的標識」：界面要說得出「這一格我讀不懂」。
  final bool factionMissing;
  final bool emptyActivities;
  final int writeStatus;
  final int writeCode;

  int listCalls = 0;
  int viewCalls = 0;
  final List<http.Request> writes = <http.Request>[];

  String _savedFactionId = '';

  List<String> get _options => <String>[
    _optionJson(),
    _optionJson(
      factionId: _stoppedFactionId,
      name: '停用的軍',
      available: false,
      selectable: false,
    ),
  ];

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final String method = request.method;
        if (method == 'GET' && path == playerActivitiesPath()) {
          listCalls++;
          return _json(
            _listBody(
              emptyActivities
                  ? <String>[]
                  : <String>[
                      _listRow(
                        factionId: viewCalls == 0 ? factionId : _savedFactionId,
                        mode: mode,
                      ),
                    ],
            ),
            200,
          );
        }
        if (method == 'GET' && path.endsWith('/faction')) {
          viewCalls++;
          return _json(
            _viewBody(
              status: status,
              mode: mode,
              canSelectNow: canSelectNow,
              factionId: viewCalls <= 1 ? factionId : _savedFactionId,
              options: factionMissing && viewCalls <= 1 ? <String>[] : _options,
            ),
            200,
          );
        }
        if (method == 'PUT' && path.endsWith('/faction')) {
          writes.add(request);
          if (writeStatus != 200) {
            return _json(
              '{"code":$writeCode,"message":"rejected","request_id":"r-fail"}',
              writeStatus,
            );
          }
          final Map<String, Object?> body =
              jsonDecode(request.body) as Map<String, Object?>;
          _savedFactionId = body['faction_id']! as String;
          return _json(_writeBody(factionId: _savedFactionId), 200);
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
                    // 每次掛樹都帶著自己的 tag：同一個 runtimeType 在 pumpWidget 之間會
                    // 共用 State，若不做區隔，第二次進入時還留著上一趟的「已展開現況卡」，
                    // 於是在清單層找進入按鈕會找不到。
                    PlayerFactionSurface(
                      key: ValueKey<String>('surface-$surfaceTag'),
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

/// 從清單進入某一場活動的現況卡。
Future<void> _openDetail(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byKey(PlayerFactionSurface.openKey(_activityId)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空清單如實說「還沒有參加任何活動」，不拿佔位冒充內容', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(emptyActivities: true),
    );

    expect(find.byKey(PlayerFactionSurface.emptyKey), findsOneWidget);
    expect(find.text(l10n.playerActivitiesEmptyNotice), findsOneWidget);
    expect(find.text(l10n.playerFactionRemainingNotice), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('清單列我的活動與那場活動的模式現值，進入後讀到現況', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    expect(
      find.byKey(PlayerFactionSurface.rowKey(_activityId)),
      findsOneWidget,
    );
    // 暱稱與模式同列在「標籤：數值」那一格裡，斷言用包含比對而非逐字比對。
    expect(find.textContaining('夜行者'), findsOneWidget);
    expect(
      find.byKey(PlayerFactionSurface.openKey(_activityId)),
      findsOneWidget,
    );

    await _openDetail(tester, l10n);

    expect(fixture.viewCalls, 1);
    expect(find.byKey(FactionSelfSelectCard.currentKey), findsOneWidget);
    expect(find.textContaining(l10n.playerCurrentFactionNone), findsOneWidget);
    // 兩個候選項都列出來：停用的那一項不是被藏起來，而是標成不可選。
    expect(
      find.byKey(FactionSelfSelectCard.optionKey(_stoppedFactionId)),
      findsOneWidget,
    );
    expect(find.text(l10n.playerFactionOptionUnavailable), findsOneWidget);
    // 「自選不能清空」那句限制常在。
    expect(find.byKey(FactionSelfSelectCard.noClearKey), findsOneWidget);
  });

  testWidgets('可選時按下目標、經確認後 PUT 恰好兩欄且依據值是上一次讀到的現值', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openDetail(tester, l10n);

    await tester.tap(
      find.byKey(FactionSelfSelectCard.chooseKey(_openFactionId)),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.playerSelectConfirmTitle), findsOneWidget);
    await tester.tap(find.byKey(FactionSelfSelectCard.cancelKey));
    await tester.pumpAndSettle();
    expect(fixture.writes, isEmpty);

    await tester.tap(
      find.byKey(FactionSelfSelectCard.chooseKey(_openFactionId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FactionSelfSelectCard.confirmKey));
    await tester.pumpAndSettle();

    expect(fixture.writes, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.writes.single.body) as Map<String, Object?>;
    expect(body.keys.toSet(), <String>{'faction_id', 'expected_faction_id'});
    expect(body['faction_id'], _openFactionId);
    expect(body['expected_faction_id'], '');
    // 成功句與現值都讀回應與重讀，不是本地拼裝：歸屬換成「黎明軍」。
    expect(find.byKey(FactionSelfSelectCard.savedKey), findsOneWidget);
    expect(fixture.viewCalls, 2);
    expect(find.text('黎明軍'), findsWidgets);
  });

  testWidgets('can_select_now 為假時所有選擇控件都停著，並按原因說那一句', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(mode: 'disabled', canSelectNow: false),
    );
    await _openDetail(tester, l10n);

    expect(find.text(l10n.playerSelectBlockedDisabled), findsOneWidget);
    for (final String id in <String>[_openFactionId, _stoppedFactionId]) {
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(FactionSelfSelectCard.chooseKey(id)),
            )
            .onPressed,
        isNull,
      );
    }
  });

  testWidgets('草稿、停止與歸檔各有各的一句，不併成同一句「現在不行」', (WidgetTester tester) async {
    for (final (String status, String Function(AppLocalizations) pick)
        in <(String, String Function(AppLocalizations))>[
          ('draft', (AppLocalizations l10n) => l10n.playerSelectBlockedNotOpen),
          ('closed', (AppLocalizations l10n) => l10n.playerSelectBlockedClosed),
          (
            'archived',
            (AppLocalizations l10n) => l10n.playerSelectBlockedArchived,
          ),
        ]) {
      await _pump(
        tester,
        _Fixture(status: status, canSelectNow: false),
        surfaceTag: status,
      );
      // 每次 _pump 都重新掛一棵樹，直接斷言清單層再進入現況。
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(PlayerFactionSurface)),
      );
      await _openDetail(tester, l10n);
      expect(
        find.text(pick(l10n)),
        findsOneWidget,
        reason: '狀態 $status 該有它自己那句處置',
      );
      expect(find.byKey(FactionSelfSelectCard.blockedKey), findsOneWidget);
    }
  });

  testWidgets('僅首次已選過時，那句「自助不再可改」單獨說得出來', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(
        mode: 'first_only',
        canSelectNow: false,
        factionId: _openFactionId,
      ),
    );
    await _openDetail(tester, l10n);

    expect(find.text(l10n.playerSelectLockedInNotice), findsOneWidget);
    expect(find.text('黎明軍'), findsWidgets);
  });

  testWidgets('2013 只留重讀出口：不給成功句也不自動補發', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(writeStatus: 409, writeCode: 2013);
    final AppLocalizations l10n = await _pump(tester, fixture);
    await _openDetail(tester, l10n);

    await tester.tap(
      find.byKey(FactionSelfSelectCard.chooseKey(_openFactionId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FactionSelfSelectCard.confirmKey));
    await tester.pumpAndSettle();

    expect(find.byKey(FactionSelfSelectCard.savedKey), findsNothing);
    expect(find.byKey(FactionSelfSelectCard.noticeKey), findsOneWidget);
    expect(fixture.writes, hasLength(1));

    await tester.tap(find.byKey(FactionSelfSelectCard.reloadKey));
    await tester.pumpAndSettle();
    expect(fixture.viewCalls, greaterThan(1));
  });

  testWidgets('歸屬指向讀不懂的標識時如實唸出來，不編一個名字', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(factionMissing: true, factionId: _openFactionId),
    );
    await _openDetail(tester, l10n);

    // 這一句由 currentKey 那一列承擔：它帶的是回應裡的原值，不是猜的名稱。
    expect(find.byKey(FactionSelfSelectCard.currentKey), findsOneWidget);
    expect(find.textContaining(_openFactionId), findsWidgets);
  });

  testWidgets('360 窄屏下整頁照樣渲染，不拋佈局異常', (WidgetTester tester) async {
    await _pump(tester, _Fixture(), width: 360);
    expect(tester.takeException(), isNull);
    expect(find.byKey(PlayerFactionSurface.listKey), findsOneWidget);
  });
}
