/// 「狀態能力規則」管理卡的介面測試：七列矩陣、revision、保存本體與歸檔只讀。
///
/// 這一檔問的是：
///   1. 出廠 revision 0 顯示「尚未保存」，七列中 custom 只有說明、沒有勾選格；
///   2. 勾選某一格後保存，本體是完整的七列＋expected_revision，不是逐格補丁；
///   3. 成功後以回應的 revision 為準，不把本地那份當成下一份底稿；
///   4. 歸檔時保存控件收起，但規則仍可讀；
///   5. 自訂狀態永遠不出現勾選格（名稱不得推測行為）。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:evernightrealm/features/admin/activity_capability_rules_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');
const String _activityId = '01b20000-0000-7000-8000-0000000000a1';

String _rulesBody({
  int revision = 0,
  bool configured = false,
  List<String> normalDenied = const <String>[],
}) {
  String group(String status, List<String> denied) =>
      '{"status_key":"$status",'
      '"denied_capabilities":[${denied.map((String key) => '"$key"').join(',')}]}';
  final List<String> rules = <String>[
    group('normal', normalDenied),
    group('suspended', const <String>[
      'login',
      'chat',
      'private_chat',
      'trade',
      'transfer',
      'item_use',
    ]),
    group('eliminated', const <String>[
      'chat',
      'private_chat',
      'trade',
      'transfer',
      'item_use',
    ]),
    group('dead', const <String>[
      'chat',
      'private_chat',
      'trade',
      'transfer',
      'item_use',
    ]),
    group('arrested', const <String>['trade', 'transfer', 'item_use']),
    group('offline', const <String>[]),
    group('custom', const <String>[]),
  ];
  return '{"activity_id":"$_activityId","revision":$revision,'
      '"configured":$configured,'
      '"capability_keys":["login","chat","private_chat","trade","transfer","item_use"],'
      '"rules":[${rules.join(',')}],'
      '"request_id":"r-rules"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

class _Fixture {
  _Fixture({this.activityStatus = 'active'});

  final String activityStatus;
  final List<Map<String, Object?>> writes = <Map<String, Object?>>[];
  int reads = 0;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        if (path == '/admin/activities/$_activityId/capability-rules' &&
            request.method == 'GET') {
          reads++;
          return _json(
            writes.isEmpty
                ? _rulesBody()
                : _rulesBody(
                    revision: 1,
                    configured: true,
                    normalDenied: const <String>['chat'],
                  ),
            200,
          );
        }
        if (path == '/admin/activities/$_activityId/capability-rules' &&
            request.method == 'PUT') {
          writes.add(jsonDecode(request.body) as Map<String, Object?>);
          return _json(
            _rulesBody(
              revision: 1,
              configured: true,
              normalDenied: const <String>['chat'],
            ),
            200,
          );
        }
        return _json(
          '{"code":1001,"message":"not found","request_id":"r-nope"}',
          404,
        );
      }),
    );
  }
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _Fixture fixture,
) async {
  final ServerAddressSettings settings = await buildAddressSettings(
    storedUrl: reachableUrl,
    reachable: <String>[reachableUrl],
  );
  final ServerApi api = fixture.api(settings);
  final Size previousSize = tester.view.physicalSize;
  final double previousRatio = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(720, 2600);
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
                child: SingleChildScrollView(
                  child: ActivityCapabilityRulesCard(
                    api: api,
                    activityId: _activityId,
                    activityStatus: fixture.activityStatus,
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
  testWidgets('出廠矩陣：七列、custom 只有說明、保存本體是完整七列', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    final AppLocalizations l10n = await _pump(tester, fixture);

    expect(fixture.reads, 1);
    expect(
      find.text(l10n.capabilityRulesRevisionUnconfigured),
      findsOneWidget,
    );
    expect(
      find.byKey(ActivityCapabilityRulesCard.customNoteKey),
      findsOneWidget,
    );
    // custom 沒有勾選格。
    expect(
      find.byKey(
        ActivityCapabilityRulesCard.cellKey('custom', 'chat'),
      ),
      findsNothing,
    );
    // 七個狀態各有一列，六項能力各有勾選格（custom 除外）。
    for (final String status in kCapabilityStatusKeys) {
      expect(
        find.byKey(ActivityCapabilityRulesCard.statusRowKey(status)),
        findsOneWidget,
      );
      if (status != 'custom') {
        for (final String capability in kCapabilityKeys) {
          expect(
            find.byKey(
              ActivityCapabilityRulesCard.cellKey(status, capability),
            ),
            findsOneWidget,
          );
        }
      }
    }

    // 勾選 normal 的 chat，保存。
    await tester.tap(
      find.byKey(
        ActivityCapabilityRulesCard.cellKey('normal', 'chat'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ActivityCapabilityRulesCard.saveKey));
    await tester.pumpAndSettle();

    expect(fixture.writes, hasLength(1));
    final Map<String, Object?> body = fixture.writes.single;
    expect(body.keys.toSet(), <String>{'expected_revision', 'rules'});
    expect(body['expected_revision'], 0);
    final List<Object?> rules = body['rules'] as List<Object?>;
    expect(rules, hasLength(7));
    final Map<String, Object?> normal = rules.first as Map<String, Object?>;
    expect(normal['status_key'], 'normal');
    expect(normal['denied_capabilities'], <String>['chat']);
    // 成功後以回應的 revision 為準。
    expect(
      find.text(l10n.capabilityRulesSaved(1)),
      findsOneWidget,
    );
  });

  testWidgets('歸檔時保存控件收起，但矩陣仍可讀', (WidgetTester tester) async {
    final _Fixture fixture = _Fixture(activityStatus: 'archived');
    final AppLocalizations l10n = await _pump(tester, fixture);

    expect(
      find.byKey(ActivityCapabilityRulesCard.archivedKey),
      findsOneWidget,
    );
    final FilledButton save = tester.widget<FilledButton>(
      find.byKey(ActivityCapabilityRulesCard.saveKey),
    );
    expect(save.onPressed, isNull);
    // 讀法仍在：七列與 revision 行都長出來。
    expect(
      find.byKey(ActivityCapabilityRulesCard.revisionKey),
      findsOneWidget,
    );
    expect(
      find.byKey(ActivityCapabilityRulesCard.statusRowKey('normal')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.capabilityRulesArchivedNote),
      findsOneWidget,
    );
    expect(fixture.writes, isEmpty);
  });
}
