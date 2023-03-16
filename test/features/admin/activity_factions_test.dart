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
///   7. 停用與恢復那顆按鈕：確認框先把成員影響摘要與「當前狀態／此刻可否收新成員」念完，
///      取消零請求，確認後只翻可用性那一欄，結果句讀回應回讀的現值；
///   8. 派生值與旗標分得開：活動停止時可用行照實多講一句「此刻不接收新分配」，
///      界面不拿 available 自己猜；
///   9. 圖標封閉集合每一鍵都有本地可繪圖標，未知鍵落佔位而不是空白；
///  10. 360 px 窄屏下不出現佈局溢出（垂直滾動由殼承擔，這裡只放內容）。
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
///
/// [acceptsNewMembers] 是服務端派生值（陣營可用**且**活動接受業務寫入才為真）：
/// 這裡刻意不與 available 綁死，才能演出「旗標還在、此刻收不到新成員」那一格。
String _factionJson({
  required String id,
  String name = '黎明軍',
  String description = '開場的一組',
  String icon = 'sun',
  String color = '#f0a020',
  int sortOrder = 0,
  bool available = true,
  bool? acceptsNewMembers,
}) {
  return '{"faction_id":"$id","activity_id":"$_activityId","name":"$name",'
      '"description":"$description","icon":"$icon","color":"$color",'
      '"sort_order":$sortOrder,"available":$available,'
      '"accepts_new_members":${acceptsNewMembers ?? available},'
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

  /// 第一次列表回兩行；寫入成功後換第二份，
  /// 證明界面重讀服務端結果而不是本地拼一行。
  bool _written = false;

  /// 活動是否處於不收業務寫入的狀態（停止與歸檔）：派生值據它而不是據旗標翻假。
  bool get _frozen =>
      activityStatus == 'closed' || activityStatus == 'archived';

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
                _factionJson(
                  id: _factionId,
                  name: '建立後的名字',
                  acceptsNewMembers: !_frozen,
                ),
                _factionJson(
                  id: _otherFactionId,
                  name: '黎明軍',
                  sortOrder: 1,
                  available: false,
                  acceptsNewMembers: false,
                ),
              ]),
              200,
            );
          }
          return _json(
            _listBody(<String>[
              _factionJson(id: _factionId, acceptsNewMembers: !_frozen),
              _factionJson(
                id: _otherFactionId,
                name: '長夜軍',
                icon: 'moon',
                color: '#102040',
                sortOrder: 1,
                available: false,
                acceptsNewMembers: false,
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
            _writeBody(
              _factionJson(
                id: _factionId,
                name: '建立後的名字',
                acceptsNewMembers: !_frozen,
              ),
            ),
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
          // 回應回讀的是資料庫現值：這裡按提交的本體組出「存下來之後的那一行」，
          // 於是界面的結果句只能讀回應、讀不到請求裡的意圖。
          final Map<String, Object?> sent =
              jsonDecode(request.body) as Map<String, Object?>;
          _written = true;
          final bool available = sent['available']! as bool;
          return _json(
            _writeBody(
              _factionJson(
                id: _factionId,
                name: sent['name']! as String,
                description: sent['description']! as String,
                icon: sent['icon']! as String,
                color: sent['color']! as String,
                sortOrder: sent['sort_order']! as int,
                available: available,
                acceptsNewMembers: available && !_frozen,
              ),
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
    // 活動可寫時不講那句門禁話：派生值與旗標同真，沒有需要分開說的事情。
    expect(
      find.text(l10n.factionNotAcceptingWhileActivityFrozen),
      findsNothing,
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

  testWidgets('停用確認框先把影響摘要念完；取消一個請求都不發', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityFactionsCard.toggleActionKey(_factionId)),
    );
    await tester.pumpAndSettle();

    // 標題點名是哪一個陣營；兩行「當前狀態」與「此刻可否接收新成員」取列表讀回的現值。
    expect(find.text(l10n.factionDisableConfirmTitle('黎明軍')), findsOneWidget);
    expect(
      find.text(
        l10n.labelValuePair(
          l10n.factionConfirmCurrentStatusLabel,
          l10n.factionAvailableLabel,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        l10n.labelValuePair(
          l10n.factionConfirmAcceptanceLabel,
          l10n.factionAcceptanceYesLabel,
        ),
      ),
      findsOneWidget,
    );
    // 影響摘要一段話講完禁新分配、保留歸屬與互見、不踢出不凍結不刪行、可恢復；
    // 這一句的全文由 ARB 承擔，這裡只钉「確認框裡唸的是它」而不是本地另寫一份。
    expect(find.text(l10n.factionDisableConfirmBody('黎明軍')), findsOneWidget);
    // 成員歸屬尚未接入這件事如實寫在摘要裡：這一檔沒有成員名單，也不拿空清單冒充。
    expect(find.text(l10n.factionMemberImpactPendingNotice), findsOneWidget);

    await tester.tap(find.byKey(ActivityFactionsCard.confirmCancelKey));
    await tester.pumpAndSettle();
    expect(fixture.editWrites, isEmpty);
    expect(find.byKey(ActivityFactionsCard.confirmSummaryKey), findsNothing);
    expect(find.byKey(ActivityFactionsCard.savedKey), findsNothing);
  });

  testWidgets('確認停用：只翻可用性那一欄，其餘依據值原樣带回，結果句唸「已停用」', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityFactionsCard.toggleActionKey(_factionId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityFactionsCard.confirmActionKey));
    await tester.pumpAndSettle();

    expect(fixture.editWrites, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.editWrites.single.body) as Map<String, Object?>;
    // 這一次 PUT 動的就是那一格：新值 false、依據值 true，其餘五欄新值與依據值同現值。
    expect(body['available'], isFalse);
    expect(body['expected_available'], isTrue);
    expect(body['name'], '黎明軍');
    expect(body['expected_name'], '黎明軍');
    expect(body['description'], body['expected_description']);
    expect(body['icon'], body['expected_icon']);
    expect(body['color'], body['expected_color']);
    expect(body['sort_order'], body['expected_sort_order']);
    // 派生值不是可寫欄位：本體裡沒有這一格，界面要宣稱「還收新成員」也無處可填。
    expect(body.containsKey('accepts_new_members'), isFalse);
    // 結果句來自回應回讀的現值，而不是「保存成功」那一句通用話。
    expect(find.text(l10n.factionDisabledNotice('黎明軍')), findsOneWidget);
    expect(find.text(l10n.factionSavedNotice), findsNothing);
  });

  testWidgets('已停用的那一行長的是「重新啟用」，確認後帶回 true 與停用依據值且不改寫名字', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    // 按鈕文案讀服務端現值：available 為假的那一行給的是恢復，不是再一次停用。
    expect(
      find.widgetWithText(TextButton, l10n.factionDisableAction),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextButton, l10n.factionEnableAction),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ActivityFactionsCard.toggleActionKey(_otherFactionId)),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.factionEnableConfirmTitle('長夜軍')), findsOneWidget);
    await tester.tap(find.byKey(ActivityFactionsCard.confirmActionKey));
    await tester.pumpAndSettle();

    final Map<String, Object?> body =
        jsonDecode(fixture.editWrites.single.body) as Map<String, Object?>;
    expect(body['available'], isTrue);
    expect(body['expected_available'], isFalse);
    // 恢復不順手改寫任何東西：名稱與排序帶著它現值原樣回来。
    expect(body['name'], '長夜軍');
    expect(body['sort_order'], 1);
    expect(find.text(l10n.factionEnabledNotice('長夜軍')), findsOneWidget);
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
    expect(
      find.byKey(ActivityFactionsCard.toggleActionKey(_factionId)),
      findsNothing,
    );
    expect(find.byKey(ActivityFactionsCard.rowKey(_factionId)), findsOneWidget);
    // 停止態的派生值是假（活動不收業務寫入），可用那一行因此多講一句：
    // 這句说的是活動門禁，不是把那個陣營停用。
    expect(
      find.text(closedL10n.factionNotAcceptingWhileActivityFrozen),
      findsOneWidget,
    );

    final AppLocalizations archivedL10n = await _pump(
      tester,
      _Fixture(activityStatus: 'archived'),
    );
    expect(find.byKey(ActivityFactionsCard.archivedKey), findsOneWidget);
    expect(find.text(archivedL10n.factionArchivedNotice), findsOneWidget);
    expect(find.byKey(ActivityFactionsCard.createSubmitKey), findsNothing);
    expect(
      find.byKey(ActivityFactionsCard.toggleActionKey(_factionId)),
      findsNothing,
    );
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
