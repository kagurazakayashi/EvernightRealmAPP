/// 「活動成員名冊」介面測試：列表、加入、改名與真實錯誤轉述。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是幾件事：
///   1. 行、狀態與帳戶投影一律取服務端回顯；空名冊那一句不猜原因；
///   2. 加入只送白名單兩欄（身分欄與陣營格都沒有格子），成功後顯示的是服務端回來的現值，
///      成功句只在回應回來後出現，並以一次重讀收尾；
///   3. 本地先擋的空暱稱與越界暱稱不發注定 1004 的請求；
///   4. 改名表單與依據值同取自上一次讀回的那一行，PUT 恰好新值加依據值兩欄；
///   5. 2013 之後只給「重新讀取這份名冊」的出口；2035 另成一句「他已經是成員了」；
///      1001（終態目標、跨活動、幽靈同形）轉述成換目標那一句，界面不自己拆成兩套說法；
///   6. 寫入控件的有與無只由服務端讀回的活動狀態決定（停止與歸檔都不長按鈕）；
///   7. 「分配尚未落地」那句交代跟著列表出現，界面不擺一顆不存在的「分到某組」按鈕；
///   8. 360 px 窄屏下不出現佈局溢出（垂直滾動由殼承擔，這裡只放內容）。
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

const String _activityId = '01a1d000-0000-7000-8000-0000000000e1';
const String _memberId = '01a1d000-0000-7000-8000-0000000000m1';
const String _otherMemberId = '01a1d000-0000-7000-8000-0000000000m2';
const String _accountId = '01a1d000-0000-7000-8000-0000000000c1';

/// 一行成員的回應片段。[factionId] 是空字串＝尚未分組（本版本的常態）。
String _memberJson({
  required String id,
  String nickname = '夜行者',
  String factionId = '',
  String displayName = '名冊裡的玩家',
  String accountStatus = 'active',
  String directoryVisibility = 'inherit',
  String adminIdentity = 'false',
}) {
  return '{"member_id":"$id","activity_id":"$_activityId",'
      '"account_id":"$_accountId","nickname":"$nickname",'
      '"faction_id":"$factionId","display_name":"$displayName",'
      '"account_status":"$accountStatus",'
      '"directory_visibility":"$directoryVisibility",'
      '"admin_identity":$adminIdentity,'
      '"business_status":"normal",'
      '"custom_status_id":"",'
      '"custom_status_name":"",'
      '"status_display_name":"",'
      '"status_available":true,'
      '"restrict_login":false,"restrict_chat":false,"restrict_private_chat":false,"restrict_trade":false,"restrict_transfer":false,"restrict_item_use":false,'
      '"joined_at":"2026-10-10T03:00:00.000Z",'
      '"updated_at":"2026-10-10T04:00:00.000Z"}';
}

String _listBody(List<String> rows) =>
    '{"members":[${rows.join(',')}],"request_id":"r-mem-list"}';

String _writeBody(String member) =>
    '{"member":$member,"request_id":"r-mem-write"}';

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 依路徑與方法分流的假後端：寫入成功後名冊換第二份，證明界面重讀服務端結果。
class _Fixture {
  _Fixture({
    this.activityStatus = 'active',
    this.createStatus = 201,
    this.createCode = 0,
    this.editStatus = 200,
    this.editCode = 0,
    this.visibilityStatus = 200,
    this.visibilityCode = 0,
    this.projectionMissing = false,
    this.emptyRoster = false,
    this.hideOtherRow = false,
    this.otherAdminIdentity = false,
  });

  final String activityStatus;
  final int createStatus;
  final int createCode;
  final int editStatus;
  final int editCode;

  /// 覆蓋寫入的狀態碼與失敗時返回值（2013／2033／2029 各有各的一句）。
  final int visibilityStatus;
  final int visibilityCode;

  /// 演「其他玩家已經看不見那一行」：第二行帶著 directory_visibility=hidden。
  final bool hideOtherRow;

  /// 演「那一位此刻持有伺服器級授予」：名冊那一格必須唸得出來，
  /// 否則管理人看不懂 all_players_except_admin 收起來的是誰。
  final bool otherAdminIdentity;

  /// 演「軟參照那一行已讀不回」：顯示名與狀態都回空字串。
  final bool projectionMissing;

  /// 演「還沒有人參加」：名冊回空清單（那是事實而不是故障）。
  final bool emptyRoster;

  int listCalls = 0;
  final List<http.Request> createWrites = <http.Request>[];
  final List<http.Request> editWrites = <http.Request>[];
  final List<http.Request> visibilityWrites = <http.Request>[];

  bool _written = false;

  /// 假後端這邊「此刻被收起來的那一行」：覆蓋寫入成功後才換掉，
  /// 於是名冊重讀回來的那一行帶著新現值（界面唸的是回應而不是提交意圖）。
  String? _hiddenId;

  String _row(String id, {String nickname = '夜行者'}) {
    final bool hiddenNow =
        id == _hiddenId || (hideOtherRow && id == _otherMemberId);
    return _memberJson(
      id: id,
      nickname: nickname,
      displayName: projectionMissing ? '' : '名冊裡的玩家',
      accountStatus: projectionMissing ? '' : 'active',
      directoryVisibility: hiddenNow ? 'hidden' : 'inherit',
      adminIdentity: id == _otherMemberId && otherAdminIdentity
          ? 'true'
          : 'false',
    );
  }

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final String method = request.method;
        final bool isList = path.endsWith('/members');
        if (method == 'GET' && isList) {
          listCalls++;
          if (emptyRoster) {
            return _json(_listBody(<String>[]), 200);
          }
          if (_written) {
            return _json(
              _listBody(<String>[
                _row(_memberId, nickname: '建立後的名字'),
                _row(_otherMemberId, nickname: '夜行者'),
              ]),
              200,
            );
          }
          return _json(
            _listBody(<String>[
              _row(_memberId),
              _row(_otherMemberId, nickname: '另一位玩家'),
            ]),
            200,
          );
        }
        if (method == 'POST' && isList) {
          createWrites.add(request);
          if (createStatus != 201) {
            return _json(
              '{"code":$createCode,"message":"rejected","request_id":"r-mem-fail"}',
              createStatus,
            );
          }
          _written = true;
          return _json(_writeBody(_row(_memberId, nickname: '建立後的名字')), 201);
        }
        if (method == 'PUT' && path.endsWith('/directory-visibility')) {
          visibilityWrites.add(request);
          if (visibilityStatus != 200) {
            return _json(
              '{"code":$visibilityCode,"message":"rejected",'
              '"request_id":"r-mem-visibility"}',
              visibilityStatus,
            );
          }
          // 寫入回應帶著回讀的那一行：界面唸的是回應現值，不是提交時的想法。
          final Map<String, Object?> body =
              jsonDecode(request.body) as Map<String, Object?>;
          _hiddenId = body['visibility'] == 'hidden' ? _memberId : null;
          return _json(
            _writeBody(
              _memberJson(
                id: _memberId,
                directoryVisibility: body['visibility']! as String,
              ),
            ),
            200,
          );
        }
        if (method == 'PUT' && !isList) {
          editWrites.add(request);
          if (editStatus != 200) {
            return _json(
              '{"code":$editCode,"message":"rejected","request_id":"r-mem-edit"}',
              editStatus,
            );
          }
          // 改名成功後讀回的那一行帶著新暱稱：結果句只能讀回應，讀不到意圖。
          final Map<String, Object?> body =
              jsonDecode(request.body) as Map<String, Object?>;
          _written = true;
          return _json(
            _writeBody(_row(_memberId, nickname: body['nickname']! as String)),
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
  // 控件要在畫面內才打得到：高度拉高只為容納整卡，寬度由引數決定。
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
                        // 每次 _pump 都換一個 key：同一個測試裡連掛兩份現場時，
                        // State 必須重建並重新讀名冊，否則第二份斷言讀的是第一份的舊資料。
                        key: UniqueKey(),
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
  testWidgets('名冊行、狀態與尚未分組全取服務端回顯', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture());

    expect(find.byKey(ActivityMembersCard.rowKey(_memberId)), findsOneWidget);
    expect(find.text('夜行者'), findsOneWidget);
    expect(find.text('另一位玩家'), findsOneWidget);
    // 狀態用文字說而不是只變色；兩行都是 active，所以這句出現兩次。
    expect(
      find.textContaining(
        l10n.labelValuePair(
          l10n.memberAccountStatusLabel,
          l10n.memberStatusActiveLabel,
        ),
      ),
      findsNWidgets(2),
    );
    // 「尚未分組」是取值而不是留白：每一行都把它念出來。
    expect(
      find.textContaining(
        l10n.labelValuePair(
          l10n.memberFactionColumnLabel,
          l10n.memberFactionUnassignedLabel,
        ),
      ),
      findsNWidgets(2),
    );
    // 界面不擺不存在的按鈕：這一版沒有一顆「分到某組」。
    expect(find.byKey(ActivityMembersCard.factionPendingKey), findsOneWidget);
    expect(find.text(l10n.memberFactionPendingNotice), findsOneWidget);
  });

  testWidgets('空名冊念的是還沒有人參加，而不是故障', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(emptyRoster: true),
    );

    expect(find.byKey(ActivityMembersCard.emptyKey), findsOneWidget);
    expect(find.text(l10n.memberEmptyNotice), findsOneWidget);
    expect(find.byKey(ActivityMembersCard.listKey), findsNothing);
    // 空名冊不拿「0 位成員」或任何占位列冒充資料，也不因此收掉那句交代。
    expect(find.byKey(ActivityMembersCard.factionPendingKey), findsOneWidget);
    expect(find.byKey(ActivityMembersCard.createSubmitKey), findsOneWidget);
  });

  testWidgets('加入恰好送兩欄、成功句在回應回來後出現並重讀名冊', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);
    final int callsBefore = fixture.listCalls;

    await tester.enterText(
      find.byKey(ActivityMembersCard.createAccountKey),
      _accountId,
    );
    await tester.enterText(
      find.byKey(ActivityMembersCard.createNicknameKey),
      '  建立後的名字  ',
    );
    expect(find.byKey(ActivityMembersCard.savedKey), findsNothing);
    await tester.tap(find.byKey(ActivityMembersCard.createSubmitKey));
    await tester.pumpAndSettle();

    expect(fixture.createWrites, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.createWrites.single.body) as Map<String, Object?>;
    expect(body.keys.toSet(), <String>{'account_id', 'nickname'});
    expect(body['nickname'], '建立後的名字');
    // 身分欄與陣營格都沒有格子：不是被拒，而是前端發不出去。
    expect(body.containsKey('member_id'), isFalse);
    expect(body.containsKey('activity_id'), isFalse);
    expect(body.containsKey('faction_id'), isFalse);
    expect(find.byKey(ActivityMembersCard.savedKey), findsOneWidget);
    expect(find.text(l10n.memberCreatedNotice('建立後的名字')), findsOneWidget);
    expect(fixture.listCalls, greaterThan(callsBefore));
  });

  testWidgets('本地先擋：空暱稱與越界暱稱都不發注定失敗的請求', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.enterText(
      find.byKey(ActivityMembersCard.createAccountKey),
      _accountId,
    );
    await tester.enterText(
      find.byKey(ActivityMembersCard.createNicknameKey),
      '   ',
    );
    await tester.tap(find.byKey(ActivityMembersCard.createSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.createWrites, isEmpty);
    expect(find.text(l10n.memberInvalidNicknameNotice), findsOneWidget);

    await tester.enterText(
      find.byKey(ActivityMembersCard.createNicknameKey),
      '長' * (ActivityMembersCard.maxNicknameRunes + 1),
    );
    await tester.tap(find.byKey(ActivityMembersCard.createSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.createWrites, isEmpty);

    // 兩欄都必填：把帳戶標識清空後只填暱稱，念的是那句「兩欄都要填」。
    await tester.enterText(
      find.byKey(ActivityMembersCard.createAccountKey),
      '',
    );
    await tester.enterText(
      find.byKey(ActivityMembersCard.createNicknameKey),
      '沒有目標的人',
    );
    await tester.tap(find.byKey(ActivityMembersCard.createSubmitKey));
    await tester.pumpAndSettle();
    expect(fixture.createWrites, isEmpty);
    expect(find.text(l10n.memberFormIncompleteNotice), findsOneWidget);
  });

  testWidgets('改名的依據值取自讀回的那一行，PUT 恰好兩欄', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityMembersCard.renameActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ActivityMembersCard.editNicknameKey),
      '  改名後的名字  ',
    );
    await tester.tap(find.byKey(ActivityMembersCard.editSaveKey));
    await tester.pumpAndSettle();

    expect(fixture.editWrites, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.editWrites.single.body) as Map<String, Object?>;
    expect(body.keys.toSet(), <String>{'nickname', 'expected_nickname'});
    // 依據值是上一次 GET 讀到的現值，不是本地新值也不是猜。
    expect(body['nickname'], '改名後的名字');
    expect(body['expected_nickname'], '夜行者');
    expect(body.containsKey('faction_id'), isFalse);
    expect(body.containsKey('account_id'), isFalse);
    expect(find.text(l10n.memberNicknameSavedNotice('改名後的名字')), findsOneWidget);
  });

  testWidgets('取消改名零請求，且編輯態收起', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityMembersCard.renameActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ActivityMembersCard.editSaveKey), findsOneWidget);
    await tester.tap(find.byKey(ActivityMembersCard.editCancelKey));
    await tester.pumpAndSettle();
    expect(find.byKey(ActivityMembersCard.editSaveKey), findsNothing);
    expect(fixture.editWrites, isEmpty);
  });

  testWidgets('2013 之後只留重讀出口，寫入控件一律收起', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(editStatus: 409, editCode: 2013);
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityMembersCard.renameActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ActivityMembersCard.editNicknameKey),
      '拿舊畫面的改名',
    );
    await tester.tap(find.byKey(ActivityMembersCard.editSaveKey));
    await tester.pumpAndSettle();

    expect(fixture.editWrites, hasLength(1));
    expect(find.text(l10n.memberStaleNotice), findsOneWidget);
    expect(find.byKey(ActivityMembersCard.reloadKey), findsOneWidget);
    // 過期之後不再給第二顆寫入按鈕：既没有改名區也没有加入區。
    expect(find.byKey(ActivityMembersCard.createSubmitKey), findsNothing);
    expect(
      find.byKey(ActivityMembersCard.renameActionKey(_memberId)),
      findsNothing,
    );

    await tester.tap(find.byKey(ActivityMembersCard.reloadKey));
    await tester.pumpAndSettle();
    expect(find.byKey(ActivityMembersCard.createSubmitKey), findsOneWidget);
  });

  testWidgets('2035 念的是「他已經是成員了」，不進編輯態也不謊報成功', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(createStatus: 409, createCode: 2035);
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.enterText(
      find.byKey(ActivityMembersCard.createAccountKey),
      _accountId,
    );
    await tester.enterText(
      find.byKey(ActivityMembersCard.createNicknameKey),
      '想再建一份的人',
    );
    await tester.tap(find.byKey(ActivityMembersCard.createSubmitKey));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorCodeActivityMemberTaken), findsOneWidget);
    expect(find.byKey(ActivityMembersCard.savedKey), findsNothing);
    // 名冊沒有本地拼上去的第二行：界面只唒服務端回來的清單。
    expect(find.text('想再建一份的人'), findsNothing);
  });

  testWidgets('終態目標與幽靈同形：界面轉述的是換目標那一句', (WidgetTester tester) async {
    // 1001 在後端同時涵蓋「這個人不具參加資格」「跨活動標識」「從未存在」三種內部原因；
    // 界面因此不拆句、不猜是哪一半，只念那一句重讀後要換目標的話。
    final _Fixture fixture = _Fixture(createStatus: 404, createCode: 1001);
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.enterText(
      find.byKey(ActivityMembersCard.createAccountKey),
      _accountId,
    );
    await tester.enterText(
      find.byKey(ActivityMembersCard.createNicknameKey),
      '進不來的人',
    );
    await tester.tap(find.byKey(ActivityMembersCard.createSubmitKey));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorCodeNotFound), findsOneWidget);
    expect(find.text(l10n.errorCodeActivityMemberTaken), findsNothing);
    expect(find.byKey(ActivityMembersCard.savedKey), findsNothing);
  });

  testWidgets('停止與歸檔都不長寫入控件，並各念自己那一句', (WidgetTester tester) async {
    final AppLocalizations closed = await _pump(
      tester,
      _Fixture(activityStatus: 'closed'),
    );
    expect(find.byKey(ActivityMembersCard.createSubmitKey), findsNothing);
    expect(find.byKey(ActivityMembersCard.closedKey), findsOneWidget);
    expect(find.text(closed.memberClosedNotice), findsOneWidget);
    expect(find.text(closed.memberArchivedNotice), findsNothing);
    // 仍列、可讀：兩行照樣在場。
    expect(find.byKey(ActivityMembersCard.rowKey(_memberId)), findsOneWidget);

    final AppLocalizations archived = await _pump(
      tester,
      _Fixture(activityStatus: 'archived'),
    );
    expect(find.byKey(ActivityMembersCard.createSubmitKey), findsNothing);
    expect(
      find.byKey(ActivityMembersCard.renameActionKey(_memberId)),
      findsNothing,
    );
    expect(find.byKey(ActivityMembersCard.archivedKey), findsOneWidget);
    expect(find.text(archived.memberArchivedNotice), findsOneWidget);
  });

  testWidgets('帳戶投影讀不回時念通用句而不是編一個名字', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(projectionMissing: true),
    );
    expect(find.text(l10n.memberAccountUnreadableNotice), findsNWidgets(2));
    // 狀態那格也唸同一句：空的 account_status 不是「可登入」也不是「已停用」。
    expect(
      find.textContaining(
        l10n.labelValuePair(
          l10n.memberAccountStatusLabel,
          l10n.memberAccountUnreadableNotice,
        ),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('360 窄屏下整卡可渲染且不出現佈局溢出', (WidgetTester tester) async {
    await _pump(tester, _Fixture(), width: 360);
    expect(tester.takeException(), isNull);
    expect(find.byKey(ActivityMembersCard.listKey), findsOneWidget);
    expect(find.byKey(ActivityMembersCard.createSubmitKey), findsOneWidget);
  });

  testWidgets('每一行念出自己的目錄覆蓋現值；持有授予者另唸一句', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(hideOtherRow: true, otherAdminIdentity: true),
    );

    expect(
      find.byKey(ActivityMembersCard.visibilityLabelKey(_memberId)),
      findsOneWidget,
    );
    // 這一格的文字是「標籤／值」合成的一句（labelValuePair），而「恢復服從活動設定」
    // 那顆按鈕裡也含著同樣幾個字，所以要按 key 取那一列本體而不是全文搜尋。
    final Text hiddenRowLabel = tester.widget<Text>(
      find.byKey(ActivityMembersCard.visibilityLabelKey(_otherMemberId)),
    );
    expect(hiddenRowLabel.data, contains(l10n.memberVisibilityHiddenLabel));
    final Text ownRowLabel = tester.widget<Text>(
      find.byKey(ActivityMembersCard.visibilityLabelKey(_memberId)),
    );
    expect(ownRowLabel.data, contains(l10n.memberVisibilityInheritLabel));
    expect(ownRowLabel.data, isNot(contains(l10n.memberVisibilityHiddenLabel)));
    // 「他此刻持有授予」這句話只在管理名冊出現（玩家目錄那份投影刻意沒有這一格）。
    expect(find.text(l10n.memberAdminIdentityNotice), findsOneWidget);
  });

  testWidgets('收起來恰好送兩欄、依據值取讀回的那一格，成功後重讀名冊', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);
    final int listsBefore = fixture.listCalls;

    await tester.tap(
      find.byKey(ActivityMembersCard.visibilityActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.memberVisibilityConfirmTitle), findsOneWidget);
    // 確認正文要把「不會把人移出活動、也不會讓他對你自己消失」講在前面，
    // 否則這顆按鈕會被讀成移除成員。
    expect(
      find.text(l10n.memberVisibilityHideConfirmBody('夜行者')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ActivityMembersCard.visibilityCancelKey));
    await tester.pumpAndSettle();
    expect(fixture.visibilityWrites, isEmpty, reason: '取消時一個請求都不該發');

    await tester.tap(
      find.byKey(ActivityMembersCard.visibilityActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.visibilityConfirmKey));
    await tester.pumpAndSettle();

    expect(fixture.visibilityWrites, hasLength(1));
    final Map<String, Object?> body = jsonDecode(
      fixture.visibilityWrites.single.body,
    ) as Map<String, Object?>;
    expect(body.keys, <String>{'visibility', 'expected_visibility'});
    expect(body['visibility'], 'hidden');
    // 依據值是這一行剛讀回的 inherit，不是本地推測，也不是活動那一欄模式。
    expect(body['expected_visibility'], 'inherit');
    expect(
      fixture.visibilityWrites.single.url.path,
      adminMemberDirectoryVisibilityPath(_activityId, _memberId),
    );
    expect(find.text(l10n.memberVisibilityHiddenNotice('夜行者')), findsOneWidget);
    expect(fixture.listCalls, greaterThan(listsBefore), reason: '成功後以一次重讀收尾');
    // 重讀回來的現值換成了 hidden：按鈕隨之改成「恢復服從活動設定」那一顆。
    expect(find.text(l10n.memberVisibilityRestoreAction), findsOneWidget);
  });

  testWidgets('覆蓋撞上 2013 時只留重讀，不自動補發第二次寫入', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(
      visibilityStatus: 409,
      visibilityCode: 2013,
    );
    await _pump(tester, fixture);

    await tester.tap(
      find.byKey(ActivityMembersCard.visibilityActionKey(_memberId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityMembersCard.visibilityConfirmKey));
    await tester.pumpAndSettle();

    expect(fixture.visibilityWrites, hasLength(1));
    expect(
      find.byKey(ActivityMembersCard.reloadKey),
      findsOneWidget,
      reason: '2013 的出口只有重讀這份名冊',
    );
    expect(
      find.byKey(ActivityMembersCard.visibilityActionKey(_memberId)),
      findsNothing,
      reason: '過期之後寫入控件一律收起',
    );
  });

  testWidgets('停止與歸檔時名冊不長出覆蓋開關（读得到、改不了）', (WidgetTester tester) async {
    for (final String status in <String>['closed', 'archived']) {
      final _Fixture fixture = _Fixture(activityStatus: status);
      await _pump(tester, fixture);
      expect(
        find.byKey(ActivityMembersCard.visibilityActionKey(_memberId)),
        findsNothing,
        reason: '$status 態不該長出寫入入口',
      );
      expect(
        find.byKey(ActivityMembersCard.visibilityLabelKey(_memberId)),
        findsOneWidget,
        reason: '但仍要如實唸出那一行的覆蓋現值（仍列、可讀）',
      );
    }
  });
}
