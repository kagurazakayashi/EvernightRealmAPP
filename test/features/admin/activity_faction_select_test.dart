/// 「玩家自選陣營」配置卡介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是幾件事：
///   1. 現值一律取服務端回顯，三個模式各帶自己那句語意（選之前就講清「僅首次今日沒人改得了」）；
///   2. 保存按鈕只在「選了、且與現值不同」時才亮；提交恰好 mode 加 expected_mode 兩欄，
///      依據值同取自上一次讀回的那一格；
///   3. 成功句只在回應回來後出現，並以一次重讀收尾（界面不本地蓋值）；
///   4. 2013 之後只給「重新讀取這場活動」的出口，不自動補發；
///   5. 歸檔與表外取值都收起寫入控件並各自說一句原因（不是靜默變灰讓人以為載入壞了）；
///   6. 360 px 窄屏下不出現佈局溢出（垂直滾動由殼承擔，這裡只放內容）。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/activity_faction_select_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _activityId = '01a1d000-0000-7000-8000-0000000000e1';

/// 一份活動詳情本體（本卡只讀 activity 那一格裡的兩欄：狀態與自選模式）。
String _detailBody({String status = 'active', required String mode}) {
  return '{"activity":{"activity_id":"$_activityId","name":"秋夜長談",'
      '"description":"","status":"$status","faction_select_mode":"$mode",'
      '"member_directory_mode":"hidden",'
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
    this.mode = 'disabled',
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
        if (request.method == 'GET' && path.endsWith('/faction-select')) {
          // 不該發生：這一族沒有 GET。走到這裡表示前端自己發了合同外的請求。
          return _json('{"code":1002,"request_id":"r-x"}', 405);
        }
        if (request.method == 'PUT' && path.endsWith('/faction-select')) {
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
  ValueSetter<ActivitySaveResult>? onSaved,
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
                child: FactionSelectConfigCard(
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
  testWidgets('現值與三態語意都如實顯示，保存按鈕在未改動時停著', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(tester, _Fixture());

    expect(find.byKey(FactionSelectConfigCard.currentKey), findsOneWidget);
    expect(find.text(l10n.factionSelectModeDisabled), findsWidgets);
    // 三個取值各帶自己那句說明：僅首次那條要把「選錯今日無人能改」寫在選之前。
    expect(find.text(l10n.factionSelectModeHintFirstOnly), findsOneWidget);
    expect(find.text(l10n.factionSelectModeHintFree), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(FactionSelectConfigCard.saveKey))
          .onPressed,
      isNull,
    );
  });

  testWidgets('換一個模式並確認後 PUT 恰好兩欄，依據值是上一次讀到的現值', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(find.byKey(FactionSelectConfigCard.pickKey('first_only')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(FactionSelectConfigCard.saveKey))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(FactionSelectConfigCard.saveKey));
    await tester.pumpAndSettle();

    // 最小確認清單：講完「只動這一欄」與兩件不會發生的事，取消時一請求都不發。
    expect(find.text(l10n.factionSelectConfirmTitle), findsOneWidget);
    await tester.tap(find.byKey(FactionSelectConfigCard.cancelKey));
    await tester.pumpAndSettle();
    expect(fixture.writes, isEmpty);

    await tester.tap(find.byKey(FactionSelectConfigCard.saveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FactionSelectConfigCard.confirmKey));
    await tester.pumpAndSettle();

    expect(fixture.writes, hasLength(1));
    final Map<String, Object?> body =
        jsonDecode(fixture.writes.single.body) as Map<String, Object?>;
    expect(body.keys.toSet(), <String>{'mode', 'expected_mode'});
    expect(body['mode'], 'first_only');
    expect(body['expected_mode'], 'disabled');
    expect(find.byKey(FactionSelectConfigCard.savedKey), findsOneWidget);
  });

  testWidgets('保存成功會帶著回應現值回呼父層（界面不本地蓋值）', (WidgetTester tester) async {
    String? seen;
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(
      tester,
      fixture,
      onSaved: (ActivitySaveResult result) => seen = result.factionSelectMode,
    );

    await tester.tap(find.byKey(FactionSelectConfigCard.pickKey('free')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FactionSelectConfigCard.saveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FactionSelectConfigCard.confirmKey));
    await tester.pumpAndSettle();

    expect(seen, 'free');
    expect(find.text(l10n.factionSelectSavedNotice), findsOneWidget);
  });

  testWidgets('2013 只留重讀出口，不給成功句也不自動補發', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(writeStatus: 409, writeCode: 2013);
    final AppLocalizations l10n = await _pump(tester, fixture);

    await tester.tap(find.byKey(FactionSelectConfigCard.pickKey('free')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FactionSelectConfigCard.saveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FactionSelectConfigCard.confirmKey));
    await tester.pumpAndSettle();

    // 2013 那句由統一對映轉述，成功句不出現。
    expect(find.text(l10n.errorCodeProfileConflict), findsOneWidget);
    expect(find.byKey(FactionSelectConfigCard.savedKey), findsNothing);
    expect(fixture.reloadCalls, 0);
    expect(find.byKey(FactionSelectConfigCard.reloadKey), findsOneWidget);
    await tester.tap(find.byKey(FactionSelectConfigCard.reloadKey));
    await tester.pumpAndSettle();
    expect(fixture.reloadCalls, 1);
    // 落敗那一次只有這趟請求：界面不會自己再補發一次。
    expect(fixture.writes, hasLength(1));
  });

  testWidgets('歸檔收起全部寫入控件並說那一句', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(status: 'archived', mode: 'free'),
    );

    expect(find.byKey(FactionSelectConfigCard.archivedKey), findsOneWidget);
    expect(find.text(l10n.factionSelectArchivedNotice), findsOneWidget);
    expect(find.byKey(FactionSelectConfigCard.saveKey), findsNothing);
    expect(find.byKey(FactionSelectConfigCard.pickKey('free')), findsNothing);
  });

  testWidgets('表外取值不長出保存控件：依據值只能是猜的', (WidgetTester tester) async {
    final AppLocalizations l10n = await _pump(
      tester,
      _Fixture(mode: 'sometimes'),
    );

    expect(find.byKey(FactionSelectConfigCard.unknownKey), findsOneWidget);
    expect(find.text(l10n.factionSelectUnknownBlocksNotice), findsOneWidget);
    expect(find.byKey(FactionSelectConfigCard.saveKey), findsNothing);
    // 現值那一句照實唸原值，不靜默歸類成「沒開放」。
    expect(
      find.text(l10n.factionSelectModeUnknown('sometimes')),
      findsOneWidget,
    );
  });

  testWidgets('360 窄屏下整卡照樣渲染，不拋佈局異常', (WidgetTester tester) async {
    await _pump(tester, _Fixture(), width: 360);
    expect(tester.takeException(), isNull);
    expect(find.byKey(FactionSelectConfigCard.currentKey), findsOneWidget);
  });
}
