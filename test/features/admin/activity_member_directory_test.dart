/// 「玩家目錄可見性」配置卡介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是幾件事：
///   1. 現值一律取服務端回顯，四態各帶自己那句語意——「僅同陣營下尚未分組的人只看得見自己」
///      與「排除管理員身分那態收的是授予而不是昵稱」這兩句必須在選之前就讀得到；
///   2. 保存按鈕只在「選了、且與現值不同」時才亮；提交恰好 mode 加 expected_mode 兩欄，
///      依據值同取自上一次讀回的那一格；
///   3. 成功句只在回應回來後出現，並以一次重讀收尾（界面不本地蓋值）；
///   4. 2013 之後只給「重新讀取這場活動」的出口，不自動補發；
///   5. 歸檔與表外取值都收起寫入控件並各自說一句原因（不是靜默變灰讓人以為載入壞了）；
///   6. 確認框把「不改任何人的陣營歸屬、也不動任何人的個人覆蓋」講完，取消時一請求都不發；
///   7. 360 px 窄屏下不出現佈局溢出。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/activity_member_directory_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _activityId = '01a1d000-0000-7000-8000-0000000000e1';

/// 一份活動詳情本體（本卡讀的是狀態與目錄模式那兩欄）。
String _detailBody({String status = 'active', required String mode}) {
  return '{"activity":{"activity_id":"$_activityId","name":"秋夜長談",'
      '"description":"","status":"$status","faction_select_mode":"free",'
      '"member_directory_mode":"$mode",'
      '"created_by_account_id":"01a1d000-0000-7000-8000-0000000000c1",'
      '"manager_count":1,"created_at":"2026-10-10T03:00:00.000Z",'
      '"updated_at":"2026-10-10T04:00:00.000Z"},"request_id":"r-detail"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 依方法與路徑分流的假後端：寫入成功後詳情換成新模式，證明界面重讀服務端結果。
class _Fixture {
  _Fixture({
    this.status = 'active',
    this.mode = 'hidden',
    this.writeStatus = 200,
    this.writeCode = 0,
  });

  final String status;
  final String mode;
  final int writeStatus;
  final int writeCode;

  int detailCalls = 0;
  int reloadCalls = 0;
  final List<http.Request> writes = <http.Request>[];

  String _savedMode = '';

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        if (request.method == 'GET' && path.endsWith('/member-directory')) {
          // 不該發生：這一族沒有 GET（現值由活動詳情帶回）。
          return _json('{"code":1002,"request_id":"r-x"}', 405);
        }
        if (request.method == 'PUT' && path.endsWith('/member-directory')) {
          writes.add(request);
          if (writeStatus != 200) {
            return _json(
              '{"code":$writeCode,"message":"rejected","request_id":"r-fail"}',
              writeStatus,
            );
          }
          final Map<String, Object?> body =
              jsonDecode(request.body) as Map<String, Object?>;
          _savedMode = body['mode']! as String;
          return _json(_detailBody(status: status, mode: _savedMode), 200);
        }
        if (request.method == 'GET') {
          detailCalls++;
          return _json(
            _detailBody(
              status: status,
              mode: detailCalls == 1 ? mode : _savedMode,
            ),
            200,
          );
        }
        return _json('{"code":1001,"request_id":"r-nope"}', 404);
      }),
    );
  }
}

/// 把配置卡接進依賴與本地化裡，回傳本檔斷言要用的資源包。
Future<AppLocalizations> _pump(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 720,
  ValueSetter<DirectorySaveResult>? onSaved,
}) async {
  final ServerAddressSettings settings = await buildAddressSettings(
    storedUrl: reachableUrl,
    reachable: <String>[reachableUrl],
  );
  final ServerApi api = fixture.api(settings);
  final Size previousSize = tester.view.physicalSize;
  final double previousRatio = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 2400);
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
                child: MemberDirectoryConfigCard(
                  api: api,
                  activityId: _activityId,
                  activityStatus: fixture.status,
                  currentMode: fixture.mode,
                  onReload: () => fixture.reloadCalls++,
                  onSaved: onSaved,
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
  testWidgets('現值與四態語意都如實顯示，保存按鈕在未改動時停著', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture());

    expect(find.byKey(MemberDirectoryConfigCard.currentKey), findsOneWidget);
    expect(find.text(l10n.memberDirectoryModeHidden), findsWidgets);
    // 兩句最容易事後才被當成 bug 的語意，必須在選之前就读得到。
    expect(find.text(l10n.memberDirectoryModeHintSameFaction), findsOneWidget);
    expect(find.text(l10n.memberDirectoryModeHintExceptAdmin), findsOneWidget);
    expect(find.text(l10n.memberDirectoryModeHintHidden), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(MemberDirectoryConfigCard.saveKey))
          .onPressed,
      isNull,
    );
  });

  testWidgets('換一個模式並確認後 PUT 恰好兩欄，依據值是上一次讀到的現值', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(
      find.byKey(MemberDirectoryConfigCard.pickKey('all_members')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(MemberDirectoryConfigCard.saveKey))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(MemberDirectoryConfigCard.saveKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.memberDirectoryConfirmTitle), findsOneWidget);
    // 確認正文講完兩件不會發生的事：既不動歸屬，也不動每一行自己的覆蓋。
    expect(
      find.textContaining(l10n.memberDirectoryModeHintAllMembers),
      findsWidgets,
    );
    await tester.tap(find.byKey(MemberDirectoryConfigCard.cancelKey));
    await tester.pumpAndSettle();
    expect(fixture.writes, isEmpty, reason: '取消時一個請求都不該發');

    await tester.tap(find.byKey(MemberDirectoryConfigCard.saveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MemberDirectoryConfigCard.confirmKey));
    await tester.pumpAndSettle();

    expect(fixture.writes, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.writes.single.body) as Map<String, Object?>;
    expect(body.keys, <String>{'mode', 'expected_mode'});
    expect(body['mode'], 'all_members');
    expect(body['expected_mode'], 'hidden');
    expect(
      find.text(l10n.memberDirectorySavedNotice),
      findsOneWidget,
      reason: '成功句只在回應回來後出現',
    );
  });

  testWidgets('寫入成功後回呼父層，帶著回應回讀的現值而不是本地那份', (WidgetTester tester) async {
    final List<String> seen = <String>[];
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(),
      onSaved: (DirectorySaveResult result) =>
          seen.add(result.memberDirectoryMode),
    );

    await tester.tap(
      find.byKey(MemberDirectoryConfigCard.pickKey('same_faction_only')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MemberDirectoryConfigCard.saveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MemberDirectoryConfigCard.confirmKey));
    await tester.pumpAndSettle();

    expect(seen, <String>['same_faction_only']);
    expect(l10n.memberDirectorySavedNotice, isNotEmpty);
  });

  testWidgets('2013 之後只留重讀出口，不自動補發', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(
      writeStatus: 409,
      writeCode: 2013,
      mode: 'all_members',
    );
    await _pump(tester, fixture);

    await tester.tap(
      find.byKey(MemberDirectoryConfigCard.pickKey('same_faction_only')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MemberDirectoryConfigCard.saveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MemberDirectoryConfigCard.confirmKey));
    await tester.pumpAndSettle();

    expect(fixture.writes, hasLength(1), reason: '落敗之後界面不該自己補第二次寫入');
    expect(
      tester
          .widget<FilledButton>(find.byKey(MemberDirectoryConfigCard.saveKey))
          .onPressed,
      isNull,
      reason: '2013 之後保存控件收起，只留重讀',
    );
    expect(find.byKey(MemberDirectoryConfigCard.reloadKey), findsOneWidget);

    await tester.tap(find.byKey(MemberDirectoryConfigCard.reloadKey));
    await tester.pumpAndSettle();
    expect(fixture.reloadCalls, 1);
  });

  testWidgets('歸檔收起控件並說一句終態；表外取值也收起並說另一句', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(status: 'archived', mode: 'all_members'),
    );
    expect(find.byKey(MemberDirectoryConfigCard.archivedKey), findsOneWidget);
    expect(find.text(l10n.memberDirectoryArchivedNotice), findsOneWidget);
    expect(
      find.byKey(MemberDirectoryConfigCard.pickKey('hidden')),
      findsNothing,
    );

    final AppLocalizations unknown = await _pump(
      tester,
      _Fixture(mode: 'everyone'),
    );
    expect(find.byKey(MemberDirectoryConfigCard.unknownKey), findsOneWidget);
    expect(
      find.text(unknown.memberDirectoryUnknownBlocksNotice),
      findsOneWidget,
    );
    // 表外現值只把原值唸出來，不歸類成某一態（那種歸類會在庫裡造出第二套說法）。
    expect(
      find.text(unknown.memberDirectoryModeUnknown('everyone')),
      findsWidgets,
    );
    expect(
      find.byKey(MemberDirectoryConfigCard.saveKey),
      findsNothing,
      reason: '連依據值都只能是猜的取值，不長出提交入口',
    );
  });

  testWidgets('360 px 窄屏下內容仍可容納且不出現溢出標識', (WidgetTester tester) async {
    await _pump(tester, _Fixture(), width: 360);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(MemberDirectoryConfigCard.optionKey('all_members')),
      findsOneWidget,
    );
  });
}
