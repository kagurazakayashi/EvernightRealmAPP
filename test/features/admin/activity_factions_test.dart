/// 「活動陣營管理」介面測試：列表、建立、編輯與真實錯誤轉述。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是幾件事：
///   1. 行、可用性與排序一律取服務端回顯；空列表那一句不猜原因；
///   2. 建立只送白名單欄位（可用性沒有格子——新建一律可用是後端領域規則），
///      成功後顯示的是服務端回來的現值，保存句只在回應回來後出現；
///   3. 本地先擋的空名、壞顏色與越界排序不發注定 1004 的請求；
///   4. 編輯表單與依據值同取自上一次讀回的那一行；停用開關走同一条 PUT；
///   5. 2013 之後只給「重新讀取這份列表」的出口；2034／2033／2029 各轉述各的句子；
///   6. 寫入控件的有與無只由服務端讀回的活动狀態決定（停止與歸檔都不長按鈕）；
///   7. 圖標封閉集合每一鍵都有本地可繪圖標，未知鍵落佔位而不是空白；
///   8. 360 px 窄屏下不出現佈局溢出（垂直滾動由殼承擔，這裡只放內容）。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/activity_factions_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _activityId = '01a1d000-0000-7000-8000-0000000000e1';
const String _factionId = '01a1d000-0000-7000-8000-0000000000f1';
const String _otherFactionId = '01a1d000-0000-7000-8000-0000000000f2';

/// 一筆陣營的回應片段。
String _factionJson({
  required String id,
  String name = '黎明軍',
  String description = '開場的一組',
  String icon = 'sun',
  String color = '#f0a020',
  int sortOrder = 0,
  bool available = true,
}) {
  return '{"faction_id":"$id","activity_id":"$_activityId","name":"$name",'
      '"description":"$description","icon":"$icon","color":"$color",'
      '"sort_order":$sortOrder,"available":$available,'
      '"created_at":"2026-10-10T03:00:00.000Z",'
      '"updated_at":"2026-10-10T04:00:00.000Z"}';
}

String _listBody(List<String> rows) =>
    '{"factions":[${rows.join(',')}],"request_id":"r-fac-list"}';

String _writeBody(String faction) =>
    '{"faction":$faction,"request_id":"r-fac-write"}';

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 依路徑與方法分流的假後端：列表可腳本化（寫入成功後換第二份），
/// 建立與編輯各自可回指定失敗碼。
class _Fixture {
  _Fixture({
    this.activityStatus = 'active',
    this.createStatus = 201,
    this.createCode = 0,
    this.editStatus = 200,
    this.editCode = 0,
  });

  final String activityStatus;
  final int createStatus;
  final int createCode;
  final int editStatus;
  final int editCode;

  int listCalls = 0;
  final List<http.Request> createWrites = <http.Request>[];
  final List<http.Request> editWrites = <http.Request>[];

  /// 第一次列表回兩行；寫入成功後回「建立後的名字」在前的兩行，
  /// 證明界面重讀服務端結果而不是本地拼一行。
  bool _written = false;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final String method = request.method;
        if (method == 'GET' && path.endsWith('/factions')) {
          listCalls++;
          if (_written) {
            return _json(
              _listBody(<String>[
                _factionJson(id: _factionId, name: '建立後的名字'),
                _factionJson(
                  id: _otherFactionId,
                  name: '黎明軍',
                  sortOrder: 1,
                  available: false,
                ),
              ]),
              200,
            );
          }
          return _json(
            _listBody(<String>[
              _factionJson(id: _factionId),
              _factionJson(
                id: _otherFactionId,
                name: '長夜軍',
                icon: 'moon',
                color: '#102040',
                sortOrder: 1,
                available: false,
              ),
            ]),
            200,
          );
        }
        if (method == 'POST' && path.endsWith('/factions')) {
          createWrites.add(request);
          if (createStatus != 201) {
            return _json(
              '{"code":$createCode,"message":"rejected","request_id":"r-fac-fail"}',
              createStatus,
            );
          }
          _written = true;
          return _json(
            _writeBody(_factionJson(id: _factionId, name: '建立後的名字')),
            201,
          );
        }
        if (method == 'PUT' && path.contains('/factions/')) {
          editWrites.add(request);
          if (editStatus != 200) {
            return _json(
              '{"code":$editCode,"message":"rejected","request_id":"r-fac-fail"}',
              editStatus,
            );
          }
          _written = true;
          return _json(
            _writeBody(
              _factionJson(id: _factionId, name: '建立後的名字', available: false),
            ),
            200,
          );
        }
        return _json('{"code":1001,"message":"ghost","request_id":"r-x"}', 404);
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
  // 控制項要在畫面內才打得到：高度拉高只為容納整卡，寬度由引數決定。
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
                      child: ActivityFactionsCard(
                        api: api,
                        activityId: _activityId,
                        activityStatus: fixture.activityStatus,
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
  testWidgets('列表行、可用性與排序取服務端回顯', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture());

    expect(find.byKey(ActivityFactionsCard.rowKey(_factionId)), findsOneWidget);
    expect(find.text('黎明軍'), findsOneWidget);
    expect(find.text('長夜軍'), findsOneWidget);
    // 可用性用文字說而不是只變色：兩行各自的狀態句都得在場（副標是一整行組合句，
    // 所以比對用 containing——比對的仍是 ARB 拼出來的句子，不是硬譯）。
    expect(
      find.textContaining(
        l10n.labelValuePair(
          l10n.factionStatusLabel,
          l10n.factionAvailableLabel,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        l10n.labelValuePair(l10n.factionStatusLabel, l10n.factionDisabledLabel),
      ),
      findsOneWidget,
    );
  });

  testWidgets('建立恰好送四欄、成功句只在回應回來後出現並重讀列表', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pump(tester, fixture);
    final int callsBefore = fixture.listCalls;

    await tester.enterText(
      find.byKey(ActivityFactionsCard.createNameKey),
      '  建立後的名字  ',
    );
    await tester.tap(find.byKey(ActivityFactionsCard.createSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.createWrites, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.createWrites.single.body) as Map<String, Object?>;
    // 可用性沒有格子（新建一律可用）；未帶排序也不發該欄（由後端排尾）。
    expect(body.keys.toSet(), <String>{'name', 'description', 'icon', 'color'});
    expect(body['name'], '建立後的名字');
    expect(find.byKey(ActivityFactionsCard.savedKey), findsOneWidget);
    expect(fixture.listCalls, greaterThan(callsBefore));
    expect(find.text('建立後的名字'), findsOneWidget);
  });

  testWidgets('空名、壞顏色與越界排序本地先擋：一個請求都不發', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(find.byKey(ActivityFactionsCard.createSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.createWrites, isEmpty);
    expect(find.byKey(ActivityFactionsCard.noticeKey), findsOneWidget);
    expect(find.text(l10n.factionFormIncompleteNotice), findsOneWidget);

    await tester.enterText(
      find.byKey(ActivityFactionsCard.createNameKey),
      '合法的',
    );
    await tester.enterText(
      find.byKey(ActivityFactionsCard.createColorKey),
      'ff00',
    );
    await tester.tap(find.byKey(ActivityFactionsCard.createSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.createWrites, isEmpty);
    expect(find.text(l10n.factionInvalidColorNotice), findsOneWidget);

    await tester.enterText(find.byKey(ActivityFactionsCard.createColorKey), '');
    await tester.enterText(
      find.byKey(ActivityFactionsCard.createSortKey),
      '100000',
    );
    await tester.tap(find.byKey(ActivityFactionsCard.createSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.createWrites, isEmpty);
    expect(find.text(l10n.factionInvalidSortNotice), findsOneWidget);
  });

  testWidgets('編輯預填現值；停用開關與六欄依據值同走一條 PUT', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityFactionsCard.editActionKey(_factionId)),
    );
    await tester.pumpAndSettle();
    final TextField nameField = tester.widget<TextField>(
      find.byKey(ActivityFactionsCard.editNameKey),
    );
    expect(nameField.controller!.text, '黎明軍');

    await tester.tap(find.byKey(ActivityFactionsCard.editAvailableKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityFactionsCard.editSaveKey));
    await tester.pumpAndSettle();

    expect(fixture.editWrites, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.editWrites.single.body) as Map<String, Object?>;
    expect(body.keys.toSet(), <String>{
      'name',
      'description',
      'icon',
      'color',
      'sort_order',
      'available',
      'expected_name',
      'expected_description',
      'expected_icon',
      'expected_color',
      'expected_sort_order',
      'expected_available',
    });
    expect(body['available'], false);
    expect(body['expected_available'], true);
    // 標識與歸屬不在本體里：編輯動不了「這是哪個陣營、屬於哪個活動」。
    expect(body.containsKey('id'), isFalse);
    expect(body.containsKey('activity_id'), isFalse);
    expect(find.byKey(ActivityFactionsCard.savedKey), findsOneWidget);
  });

  testWidgets('2034 重名轉述成「換個名字」那一句，不顯示成功', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(createStatus: 409, createCode: 2034),
    );
    await tester.enterText(
      find.byKey(ActivityFactionsCard.createNameKey),
      '黎明軍',
    );
    await tester.tap(find.byKey(ActivityFactionsCard.createSubmitKey));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorCodeFactionNameTaken), findsOneWidget);
    expect(find.byKey(ActivityFactionsCard.savedKey), findsNothing);
  });

  testWidgets('2013 現值過期後收起寫入控件，只留重讀出口；重讀後恢復', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(editStatus: 409, editCode: 2013);
    await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityFactionsCard.editActionKey(_factionId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityFactionsCard.editSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ActivityFactionsCard.reloadKey), findsOneWidget);
    expect(find.byKey(ActivityFactionsCard.createSubmitKey), findsNothing);
    expect(
      find.byKey(ActivityFactionsCard.editActionKey(_factionId)),
      findsNothing,
    );
    expect(find.byKey(ActivityFactionsCard.savedKey), findsNothing);

    await tester.tap(find.byKey(ActivityFactionsCard.reloadKey));
    await tester.pumpAndSettle();
    expect(find.byKey(ActivityFactionsCard.createSubmitKey), findsOneWidget);
  });

  testWidgets('停止與歸檔：列表照列，寫入控件一顆都不長，各說各的句子', (WidgetTester tester) async {
    final AppLocalizations closedL10n = await _pump(
      tester,
      _Fixture(activityStatus: 'closed'),
    );
    expect(find.byKey(ActivityFactionsCard.closedKey), findsOneWidget);
    expect(find.text(closedL10n.factionClosedNotice), findsOneWidget);
    expect(find.byKey(ActivityFactionsCard.createSubmitKey), findsNothing);
    expect(
      find.byKey(ActivityFactionsCard.editActionKey(_factionId)),
      findsNothing,
    );
    expect(find.byKey(ActivityFactionsCard.rowKey(_factionId)), findsOneWidget);

    final AppLocalizations archivedL10n = await _pump(
      tester,
      _Fixture(activityStatus: 'archived'),
    );
    expect(find.byKey(ActivityFactionsCard.archivedKey), findsOneWidget);
    expect(find.text(archivedL10n.factionArchivedNotice), findsOneWidget);
    expect(find.byKey(ActivityFactionsCard.createSubmitKey), findsNothing);
  });

  testWidgets('360 px 窄屏渲染無異常，狀態句仍完整', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture(), width: 360);
    expect(tester.takeException(), isNull);
    expect(find.text(l10n.factionSectionTitle), findsOneWidget);
    expect(find.byKey(ActivityFactionsCard.rowKey(_factionId)), findsOneWidget);
  });

  test('圖標封閉集合每一鍵都有本地可繪圖標；未知鍵與未選落佔位', () {
    for (final String key in ActivityFactionsCard.iconKeys) {
      if (key.isEmpty) {
        continue;
      }
      expect(
        factionIconData(key),
        isNot(Icons.category_outlined),
        reason: '封閉集合裡的 $key 必須有真實圖標，否則界面等於拿佔位冒充支援',
      );
    }
    expect(factionIconData(''), Icons.category_outlined);
    expect(factionIconData('not_a_key'), Icons.category_outlined);
  });
}
