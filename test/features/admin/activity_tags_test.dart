/// 「活動標籤定義管理」介面測試：列表、建立、編輯、兩個開關與真實錯誤轉述。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是幾件事：
///   1. 行、可用性、公開範圍與排序一律取服務端回顯；狀態用文字說而不是只變色；
///   2. 建立表單沒有一格能宣稱公開（連一顆開關都不長），本體恰好四欄，
///      而成功後重讀回來的那一行讀成「內部」——出生即內部是合同，不是界面預設；
///   3. 本地先擋的空名、壞顏色與越界排序不發注定 1004 的請求；
///   4. 編輯表單與七個依據值同取自上一次讀回的那一行；翻動公開那一欄必經確認框，
///      確認框點名標籤並把「會發生的那一件」與「四件不會發生的事」唸完；取消零請求；
///   5. 行內「停用／重新啟用」與「公開／收回公開」四顆捷徑發的都是同一條 PUT 白名單，
///      只翻對應那一格，其餘帶著現值原樣送回；結果句讀回應回讀的現值；
///   6. 2013 之後只給「重新讀取這份列表」的出口；2040 轉述成「換個名字」那一句；
///      1004 點名到哪一欄就念哪一欄；
///   7. 寫入控件的有與無只由服務端讀回的活動狀態決定（停止與歸檔都不長按鈕），
///      而派生值「此刻貼不貼得出去」仍如實列出——它講的是門禁，不是這一枚被停用了；
///   8. 「誰帶著哪個標籤」尚未落地：這一卡不列名單也不報人無；
///   9. 圖標封閉集合與陣營同源，每一鍵都有本地可繪圖標，未知鍵落佔位而不是空白；
///  10. 360 px 窄屏下不出現佈局溢出（垂直滾動由殼承擔，這裡只放內容）。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/activity_factions_view.dart'
    show ActivityFactionsCard, factionIconData;
import 'package:evernightrealm/features/admin/activity_tags_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _activityId = '01a1d000-0000-7000-8000-0000000000e1';
const String _tagId = '01a1d000-0000-7000-8000-0000000000t1';
const String _otherTagId = '01a1d000-0000-7000-8000-0000000000t2';

/// 一筆標籤定義的回應片段。
///
/// [acceptsNewAssignments] 是服務端派生值（可用**且**活動接受業務寫入才為真）：
/// 這裡刻意不與 available 綁死，才能演出「旗標還在、此刻貼不出去」那一格。
String _tagJson({
  required String id,
  String name = '冠軍',
  String description = '發給得名者的標記',
  String icon = 'trophy',
  String color = '#f0a020',
  int sortOrder = 0,
  bool available = true,
  bool publicFlag = false,
  bool? acceptsNewAssignments,
}) {
  return '{"tag_id":"$id","activity_id":"$_activityId","name":"$name",'
      '"description":"$description","icon":"$icon","color":"$color",'
      '"sort_order":$sortOrder,"available":$available,"public":$publicFlag,'
      '"accepts_new_assignments":${acceptsNewAssignments ?? available},'
      '"created_at":"2026-10-10T03:00:00.000Z",'
      '"updated_at":"2026-10-10T04:00:00.000Z"}';
}

String _listBody(List<String> rows) =>
    '{"tags":[${rows.join(',')}],"request_id":"r-tag-list"}';

String _writeBody(String tag) => '{"tag":$tag,"request_id":"r-tag-write"}';

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
    this.emptyList = false,
    this.invalidField,
  });

  final String activityStatus;
  final int createStatus;
  final int createCode;
  final int editStatus;
  final int editCode;

  /// 列表是否回空清單：空態與「讀不到」在界面上是兩句話，取證時要能做出真空列表。
  final bool emptyList;

  /// 失敗信封裡的 `details.invalid_field`：1004 點名哪一欄，界面就換哪一欄那句結論。
  final String? invalidField;

  int listCalls = 0;
  final List<http.Request> createWrites = <http.Request>[];
  final List<http.Request> editWrites = <http.Request>[];

  /// 第一次列表回兩行（一枚內部、一枚已公開且停用）；寫入成功後換第二份，
  /// 證明界面重讀服務端結果而不是本地拼一行。
  bool _written = false;

  /// 活動是否處於不收業務寫入的狀態（停止與歸檔）：派生值據它而不是據旗標翻假。
  bool get _frozen =>
      activityStatus == 'closed' || activityStatus == 'archived';

  /// 失敗信封：帶 invalid_field 時把 details 一起發出去（界面的欄位級結論靠它）。
  String _failureBody(int code) {
    final String details = invalidField == null
        ? ''
        : ',"details":{"invalid_field":"$invalidField"}';
    return '{"code":$code,"message":"rejected"$details,"request_id":"r-tag-fail"}';
  }

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final String method = request.method;
        if (method == 'GET' && path.endsWith('/tags')) {
          listCalls++;
          if (emptyList) {
            return _json(_listBody(<String>[]), 200);
          }
          if (_written) {
            return _json(
              _listBody(<String>[
                _tagJson(
                  id: _tagId,
                  name: '建立後的名字',
                  acceptsNewAssignments: !_frozen,
                ),
                _tagJson(
                  id: _otherTagId,
                  name: '冠軍',
                  icon: 'star',
                  color: '#102040',
                  sortOrder: 1,
                  available: false,
                  publicFlag: true,
                  acceptsNewAssignments: false,
                ),
              ]),
              200,
            );
          }
          return _json(
            _listBody(<String>[
              _tagJson(id: _tagId, acceptsNewAssignments: !_frozen),
              _tagJson(
                id: _otherTagId,
                name: '已停用的那枚',
                icon: 'moon',
                color: '#102040',
                sortOrder: 1,
                available: false,
                publicFlag: true,
                acceptsNewAssignments: false,
              ),
            ]),
            200,
          );
        }
        if (method == 'POST' && path.endsWith('/tags')) {
          createWrites.add(request);
          if (createStatus != 201) {
            return _json(_failureBody(createCode), createStatus);
          }
          _written = true;
          // 回應回讀的出生形態：新建即可用、且不公開——那兩格不是請求裡的意圖，
          // 是服務端決定的事實，界面據它顯示「這份目前是內部的」。
          return _json(
            _writeBody(
              _tagJson(
                id: _tagId,
                name: '建立後的名字',
                available: true,
                publicFlag: false,
                acceptsNewAssignments: !_frozen,
              ),
            ),
            201,
          );
        }
        if (method == 'PUT' && path.contains('/tags/')) {
          editWrites.add(request);
          if (editStatus != 200) {
            return _json(_failureBody(editCode), editStatus);
          }
          // 回應回讀的是資料庫現值：這裡按提交的本體組出「存下來之後的那一行」，
          // 於是界面的結果句只能讀回應、讀不到請求裡的意圖。
          final Map<String, Object?> sent =
              jsonDecode(request.body) as Map<String, Object?>;
          _written = true;
          final bool available = sent['available']! as bool;
          final bool publicFlag = sent['public']! as bool;
          return _json(
            _writeBody(
              _tagJson(
                id: _tagId,
                name: sent['name']! as String,
                description: sent['description']! as String,
                icon: sent['icon']! as String,
                color: sent['color']! as String,
                sortOrder: sent['sort_order']! as int,
                available: available,
                publicFlag: publicFlag,
                acceptsNewAssignments: available && !_frozen,
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
  // 控制項要在畫面內才打得到：高度拉高只為容納整卡，寬度由引數決定。
  tester.view.physicalSize = Size(width, 3200);
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
                      child: ActivityTagsCard(
                        // 每一趟掛樹帶自己的 tag：同一個 runtimeType 在 pumpWidget 之間會
                        // 共用 State，不區分就會帶著上一趟的編輯態、提示與在途狀態。
                        key: ValueKey<String>('activity-tags-card-$surfaceTag'),
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
  testWidgets('列表行、可用性、公開範圍與排序取服務端回顯（狀態用文字說）', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture());

    expect(find.byKey(ActivityTagsCard.rowKey(_tagId)), findsOneWidget);
    expect(find.text('冠軍'), findsOneWidget);
    expect(find.text('已停用的那枚'), findsOneWidget);
    // 兩行各有可用性一句與公開範圍一句：比對用 containing，比對的仍是 ARB 拼出來的
    // 整行組合句，而不是硬譯——顏色與圖標在這裡不單獨承擔任何一句狀態。
    expect(
      find.textContaining(
        l10n.labelValuePair(l10n.tagVisibilityLabel, l10n.tagInternalLabel),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        l10n.labelValuePair(l10n.tagVisibilityLabel, l10n.tagPublicLabel),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        l10n.labelValuePair(l10n.tagStatusLabel, l10n.tagAvailableLabel),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        l10n.labelValuePair(l10n.tagStatusLabel, l10n.tagDisabledLabel),
      ),
      findsOneWidget,
    );
    // 「此刻貼不貼得出去」是派生值那一列，與上面兩句分開：可用那一行為真、停用那行為假。
    expect(
      find.textContaining(
        l10n.labelValuePair(
          l10n.tagAcceptanceLabel,
          l10n.tagAcceptanceYesLabel,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        l10n.labelValuePair(l10n.tagAcceptanceLabel, l10n.tagAcceptanceNoLabel),
      ),
      findsOneWidget,
    );
    // 貼標尚未落地這件事寫在列表下方：這一卡沒有一格名單也沒有計數可冒充。
    expect(find.text(l10n.tagAssignmentPendingNotice), findsWidgets);
  });

  testWidgets('建立表單不長任何開關（公開沒有那一格），本體恰好四欄且回讀為內部', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    // 建立表單裡一個 Switch 都沒有：不是藏起來了，是建立白名單就沒有 public／available
    // 這兩格；界面若留一顆預設未勾的框，就等於假稱「這裡能決定」。
    expect(find.byType(Switch), findsNothing);
    expect(find.text(l10n.tagCreateInternalNote), findsOneWidget);

    await tester.enterText(
      find.byKey(ActivityTagsCard.createNameKey),
      '  建立後的名字  ',
    );
    await tester.tap(find.byKey(ActivityTagsCard.createSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.createWrites, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.createWrites.single.body) as Map<String, Object?>;
    expect(body.keys.toSet(), <String>{'name', 'description', 'icon', 'color'});
    expect(body.containsKey('public'), isFalse);
    expect(body.containsKey('available'), isFalse);
    expect(body['name'], '建立後的名字');
    expect(find.byKey(ActivityTagsCard.savedKey), findsOneWidget);
    // 成功後那一行讀回的是「內部」：出生即內部由服務端回讀支撐，不是界面的預設值。
    expect(
      find.textContaining(
        l10n.labelValuePair(l10n.tagVisibilityLabel, l10n.tagInternalLabel),
      ),
      findsOneWidget,
    );
  });

  testWidgets('空名、壞顏色與越界排序本地先擋：一個請求都不發', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(find.byKey(ActivityTagsCard.createSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.createWrites, isEmpty);
    expect(find.text(l10n.tagFormIncompleteNotice), findsOneWidget);

    await tester.enterText(find.byKey(ActivityTagsCard.createNameKey), '合法的');
    await tester.enterText(find.byKey(ActivityTagsCard.createColorKey), 'ff00');
    await tester.tap(find.byKey(ActivityTagsCard.createSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.createWrites, isEmpty);
    expect(find.text(l10n.tagInvalidColorNotice), findsOneWidget);

    await tester.enterText(find.byKey(ActivityTagsCard.createColorKey), '');
    await tester.enterText(
      find.byKey(ActivityTagsCard.createSortKey),
      '100000',
    );
    await tester.tap(find.byKey(ActivityTagsCard.createSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.createWrites, isEmpty);
    expect(find.text(l10n.tagInvalidSortNotice), findsOneWidget);
  });

  testWidgets('編輯預填現值並帶齊七欄依據值；七欄新值恰好在場', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pump(tester, fixture);

    await tester.tap(find.byKey(ActivityTagsCard.editActionKey(_tagId)));
    await tester.pumpAndSettle();
    final TextField nameField = tester.widget<TextField>(
      find.byKey(ActivityTagsCard.editNameKey),
    );
    expect(nameField.controller!.text, '冠軍');
    // 公開開關只活在這裡：翻動它要走確認框，而那顆開關的初值是服務端讀回的現值。
    final Switch publicSwitch = tester.widget<Switch>(
      find.byKey(ActivityTagsCard.editPublicKey),
    );
    expect(publicSwitch.value, isFalse);

    await tester.tap(find.byKey(ActivityTagsCard.editAvailableKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityTagsCard.editSaveKey));
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
      'public',
      'expected_name',
      'expected_description',
      'expected_icon',
      'expected_color',
      'expected_sort_order',
      'expected_available',
      'expected_public',
    });
    expect(body['available'], isFalse);
    expect(body['expected_available'], isTrue);
    // 這一次沒動公開那一欄：新值與依據值同現值，確認框也不該出現。
    expect(body['public'], isFalse);
    expect(body['expected_public'], isFalse);
    // 標識與歸屬不在本體裡：編輯動不了「這是哪一枚標籤、屬於哪場活動」。
    expect(body.containsKey('tag_id'), isFalse);
    expect(body.containsKey('activity_id'), isFalse);
    expect(body.containsKey('accepts_new_assignments'), isFalse);
    expect(find.byKey(ActivityTagsCard.savedKey), findsOneWidget);
  });

  testWidgets('編輯表單翻動公開那一欄必經確認框；取消一個請求都不發', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pump(tester, fixture);

    await tester.tap(find.byKey(ActivityTagsCard.editActionKey(_tagId)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityTagsCard.editPublicKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityTagsCard.editSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ActivityTagsCard.confirmSummaryKey), findsOneWidget);
    expect(fixture.editWrites, isEmpty);

    await tester.tap(find.byKey(ActivityTagsCard.confirmCancelKey));
    await tester.pumpAndSettle();
    expect(fixture.editWrites, isEmpty);
    expect(find.byKey(ActivityTagsCard.savedKey), findsNothing);
  });

  testWidgets('公開確認框點名標籤，並把會發生的一件與不會發生的四件一起唸完', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(find.byKey(ActivityTagsCard.publicActionKey(_tagId)));
    await tester.pumpAndSettle();

    // 標題點名是哪一枚；三行現值取列表讀回的那一行（操作還沒發生就先講清楚）。
    expect(find.text(l10n.tagPublishConfirmTitle('冠軍')), findsOneWidget);
    expect(
      find.text(
        l10n.labelValuePair(
          l10n.tagConfirmCurrentStatusLabel,
          l10n.tagAvailableLabel,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        l10n.labelValuePair(
          l10n.tagConfirmVisibilityLabel,
          l10n.tagInternalLabel,
        ),
      ),
      findsOneWidget,
    );
    // 影響摘要這一句全文由 ARB 承擔：會發生的（成員讀得到這份定義）與四件不會發生的
    // （不讓隱藏的人可見、不是角色、不給權限、不改既有引用）都在同一句裡。
    expect(find.text(l10n.tagPublishConfirmBody('冠軍')), findsOneWidget);
    expect(find.text(l10n.tagAssignmentPendingNotice), findsWidgets);

    await tester.tap(find.byKey(ActivityTagsCard.confirmActionKey));
    await tester.pumpAndSettle();

    final Map<String, Object?> body =
        jsonDecode(fixture.editWrites.single.body) as Map<String, Object?>;
    // 這一次 PUT 動的就是那一格：新值真、依據值假，其餘六欄新值與依據值同現值。
    expect(body['public'], isTrue);
    expect(body['expected_public'], isFalse);
    expect(body['available'], isTrue);
    expect(body['expected_available'], isTrue);
    expect(body['name'], '冠軍');
    expect(body['expected_name'], '冠軍');
    expect(body['description'], body['expected_description']);
    expect(body['icon'], body['expected_icon']);
    expect(body['color'], body['expected_color']);
    expect(body['sort_order'], body['expected_sort_order']);
    expect(find.text(l10n.tagPublishedNotice('冠軍')), findsOneWidget);
    expect(find.text(l10n.tagSavedNotice), findsNothing);
  });

  testWidgets('收回公開那一行長的是「收回公開」，摘要唸「下一次查詢不再列出」而非刪除', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    // 按鈕文案讀服務端現值：public 為真的那一行給的是收回，不是再一次公開。
    expect(
      find.widgetWithText(TextButton, l10n.tagPublishAction),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextButton, l10n.tagUnpublishAction),
      findsOneWidget,
    );

    await tester.tap(find.byKey(ActivityTagsCard.publicActionKey(_otherTagId)));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagUnpublishConfirmTitle('已停用的那枚')), findsOneWidget);
    expect(find.text(l10n.tagUnpublishConfirmBody('已停用的那枚')), findsOneWidget);
    await tester.tap(find.byKey(ActivityTagsCard.confirmActionKey));
    await tester.pumpAndSettle();

    final Map<String, Object?> body =
        jsonDecode(fixture.editWrites.single.body) as Map<String, Object?>;
    expect(body['public'], isFalse);
    expect(body['expected_public'], isTrue);
    // 收回不順手改寫任何東西：名稱、可用性與排序帶著現值原樣回來。
    expect(body['name'], '已停用的那枚');
    expect(body['available'], isFalse);
    expect(body['expected_available'], isFalse);
    expect(body['sort_order'], 1);
    expect(find.text(l10n.tagUnpublishedNotice('已停用的那枚')), findsOneWidget);
  });

  testWidgets('停用確認後只翻可用性，結果句念回應回讀的現值', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(find.byKey(ActivityTagsCard.toggleActionKey(_tagId)));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagDisableConfirmTitle('冠軍')), findsOneWidget);
    await tester.tap(find.byKey(ActivityTagsCard.confirmActionKey));
    await tester.pumpAndSettle();

    final Map<String, Object?> body =
        jsonDecode(fixture.editWrites.single.body) as Map<String, Object?>;
    expect(body['available'], isFalse);
    expect(body['expected_available'], isTrue);
    expect(body.containsKey('accepts_new_assignments'), isFalse);
    expect(find.text(l10n.tagDisabledNotice('冠軍')), findsOneWidget);
  });

  testWidgets('停用確認框取消：一個請求都不發，也不顯示已完成', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pump(tester, fixture);

    await tester.tap(find.byKey(ActivityTagsCard.toggleActionKey(_tagId)));
    await tester.pumpAndSettle();
    expect(find.byKey(ActivityTagsCard.confirmSummaryKey), findsOneWidget);
    await tester.tap(find.byKey(ActivityTagsCard.confirmCancelKey));
    await tester.pumpAndSettle();

    expect(fixture.editWrites, isEmpty);
    expect(find.byKey(ActivityTagsCard.confirmSummaryKey), findsNothing);
    expect(find.byKey(ActivityTagsCard.savedKey), findsNothing);
  });

  testWidgets('2040 重名轉述成「換個名字」那一句，不顯示成功', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(createStatus: 409, createCode: 2040),
    );
    await tester.enterText(find.byKey(ActivityTagsCard.createNameKey), '冠軍');
    await tester.tap(find.byKey(ActivityTagsCard.createSubmitKey));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorCodeTagNameTaken), findsOneWidget);
    expect(find.byKey(ActivityTagsCard.savedKey), findsNothing);
  });

  testWidgets('1004 點名哪一欄就念哪一欄那句；點名不出欄位時才落通用拒絕', (WidgetTester tester) async {
    // 編輯這一次由服務端回 1004 + details.invalid_field：界面據那一格換句子，
    // 因為「公開旗標的值不合法」與「依據值過期」處置完全不同（前者改值、後者重讀）。
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(editStatus: 400, editCode: 1004, invalidField: 'public'),
      surfaceTag: 'field-public',
    );
    await tester.tap(find.byKey(ActivityTagsCard.editActionKey(_tagId)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityTagsCard.editSaveKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tagInvalidPublicNotice), findsOneWidget);
    expect(find.text(l10n.tagRejectedNotice), findsNothing);
    expect(find.byKey(ActivityTagsCard.savedKey), findsNothing);

    // 同一枚 1004 但點名不出欄位（後端日後多發的欄位名）：落通用那一句而不是亂猜一欄。
    final AppLocalizations l2 = await _pump(
      tester,
      _Fixture(editStatus: 400, editCode: 1004, invalidField: 'sort_order'),
      surfaceTag: 'field-sort',
    );
    await tester.tap(find.byKey(ActivityTagsCard.editActionKey(_tagId)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityTagsCard.editSaveKey));
    await tester.pumpAndSettle();
    expect(find.text(l2.tagInvalidSortNotice), findsOneWidget);
    expect(find.text(l2.tagInvalidPublicNotice), findsNothing);
  });

  testWidgets('空列表那句是「還沒有標籤定義」，與讀取失敗與「沒有成員」都分得開', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(emptyList: true),
      surfaceTag: 'empty',
    );
    expect(find.byKey(ActivityTagsCard.emptyKey), findsOneWidget);
    expect(find.text(l10n.tagEmptyNotice), findsOneWidget);
    expect(find.byKey(ActivityTagsCard.listKey), findsNothing);
    expect(find.byKey(ActivityTagsCard.noticeKey), findsNothing);
    // 空列表不等于「貼標已可用但沒人」：那句「尚未落地」仍要在場。
    expect(find.text(l10n.tagAssignmentPendingNotice), findsWidgets);
  });

  testWidgets('2013 現值過期後收起寫入控件，只留重讀出口；重讀後恢復', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(editStatus: 409, editCode: 2013);
    await _pump(tester, fixture);

    await tester.tap(find.byKey(ActivityTagsCard.editActionKey(_tagId)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityTagsCard.editAvailableKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityTagsCard.editSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ActivityTagsCard.reloadKey), findsOneWidget);
    expect(find.byKey(ActivityTagsCard.createSubmitKey), findsNothing);
    expect(find.byKey(ActivityTagsCard.editActionKey(_tagId)), findsNothing);
    expect(find.byKey(ActivityTagsCard.publicActionKey(_tagId)), findsNothing);
    expect(find.byKey(ActivityTagsCard.savedKey), findsNothing);

    await tester.tap(find.byKey(ActivityTagsCard.reloadKey));
    await tester.pumpAndSettle();
    expect(find.byKey(ActivityTagsCard.createSubmitKey), findsOneWidget);
  });

  testWidgets('停止與歸檔：列表照列，寫入控件一顆都不長，各說各的句子', (WidgetTester tester) async {
    final AppLocalizations closedL10n = await _pump(
      tester,
      _Fixture(activityStatus: 'closed'),
      surfaceTag: 'closed',
    );
    expect(find.byKey(ActivityTagsCard.closedKey), findsOneWidget);
    expect(find.text(closedL10n.tagClosedNotice), findsOneWidget);
    expect(find.byKey(ActivityTagsCard.createSubmitKey), findsNothing);
    expect(find.byKey(ActivityTagsCard.editActionKey(_tagId)), findsNothing);
    expect(find.byKey(ActivityTagsCard.toggleActionKey(_tagId)), findsNothing);
    expect(find.byKey(ActivityTagsCard.publicActionKey(_tagId)), findsNothing);
    expect(find.byKey(ActivityTagsCard.rowKey(_tagId)), findsOneWidget);
    // 停止態的派生值是假（活動不收業務寫入），而那一枚標籤本身仍標著「可用」：
    // 兩句必須同時在場——界面不拿 available 自己猜出「此刻貼得出去」那種結論。
    expect(
      find.textContaining(
        closedL10n.labelValuePair(
          closedL10n.tagStatusLabel,
          closedL10n.tagAvailableLabel,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        closedL10n.labelValuePair(
          closedL10n.tagAcceptanceLabel,
          closedL10n.tagAcceptanceNoLabel,
        ),
      ),
      findsNWidgets(2),
    );
    expect(
      find.textContaining(
        closedL10n.labelValuePair(
          closedL10n.tagAcceptanceLabel,
          closedL10n.tagAcceptanceYesLabel,
        ),
      ),
      findsNothing,
    );

    final AppLocalizations archivedL10n = await _pump(
      tester,
      _Fixture(activityStatus: 'archived'),
      surfaceTag: 'archived',
    );
    expect(find.byKey(ActivityTagsCard.archivedKey), findsOneWidget);
    expect(find.text(archivedL10n.tagArchivedNotice), findsOneWidget);
    expect(find.byKey(ActivityTagsCard.createSubmitKey), findsNothing);
    expect(find.byKey(ActivityTagsCard.toggleActionKey(_tagId)), findsNothing);
  });

  testWidgets('360 px 窄屏渲染無異常，狀態句仍完整', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture(), width: 360);
    expect(tester.takeException(), isNull);
    expect(find.text(l10n.tagSectionTitle), findsOneWidget);
    expect(find.byKey(ActivityTagsCard.rowKey(_tagId)), findsOneWidget);
    expect(
      find.textContaining(
        l10n.labelValuePair(l10n.tagVisibilityLabel, l10n.tagInternalLabel),
      ),
      findsOneWidget,
    );
  });

  test('標籤卡與陣營卡共用同一份圖標封閉集合，每一鍵都有本地可繪圖標', () {
    // 兩族後端 CHECK 的是同一個集合（遷移 0013 與 0017）；這裡釘的是同一份清單，
    // 一旦有人複製成兩份而只改一處，這條就會報紅。
    expect(ActivityTagsCard.iconKeys, ActivityFactionsCard.iconKeys);
    for (final String key in ActivityTagsCard.iconKeys) {
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
