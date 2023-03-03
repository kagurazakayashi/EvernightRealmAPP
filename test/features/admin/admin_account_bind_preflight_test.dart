/// 管理員端「訪戶綁定預檢與衝突預覽」的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何真實憑據。這一檔問的是幾件事：
///   1. 預檢區只由服務端讀回的來源欄決定出現與否：訪戶才有這一區，標準目標整區不存在；
///      停用中的訪戶這一區仍在——狀態是不是問題由後端的預覽回答，界面不預判也不藏讀取；
///   2. 「尚未綁定」是結果面板的第一句而不是角落註腳：executable 與否都唸；
///   3. 本體恰好 target_account_id 一欄、方法 POST、路徑掛在來源那一側；
///   4. 「此刻不可綁定」是 200 預覽的一條原因記號：界面逐條唸句子，
///      認不得的記號顯示通用句並保留原記號，不崩潰也不靜默；
///   5. 預檢進行中與四條白名單互斥、連點只發一趟；舊快照在任何一次寫入成功後收起；
///   6. 失敗分流各說各話：1004 依欄位、1001／2011／會話那一簇各自成句。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/admin_console_page.dart';
import 'package:evernightrealm/features/admin/standard_account_directory_view.dart';
import 'package:evernightrealm/features/admin/standard_account_profile_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

/// 詳情卡的目標（來源訪戶）標識。
const String _targetId = '01a0e000-0000-7000-8000-0000000000bb';

/// 操作者填寫的目標帳戶標識（假 UUID，只活在這次注入的假傳輸裡）。
const String _candidateId = '01a0e000-0000-7000-8000-0000000000cc';

const String _disabledAt = '2026-10-03T09:30:00.000Z';

/// 五條影響記號的可執行回應（與後端 impacts 的穩定值逐字同）。
const List<String> _fullImpacts = <String>[
  'revoke_source_sessions',
  'retire_source_account',
  'keep_history_references',
  'transfer_future_attribution',
  'target_unchanged',
];

String _quoted(List<String> items) => items.map((String i) => '"$i"').join(',');

/// 目錄一頁：只列來源這一行。
String _directoryPage(String status, String accountType) {
  return '{"accounts":[{"account_id":"$_targetId","login_name":"guest_seed_name",'
      '"display_name":"目錄上的名字","account_type":"$accountType",'
      '"status":"$status","must_change_password":false,'
      '"created_at":"2026-10-02T08:00:00.000Z"}],'
      '"page":1,"page_size":20,"total":1,"request_id":"r-dir"}';
}

/// 單筆詳情（來源）：狀態與類型由夹具決定。
String _detailRecord({String status = 'active', String accountType = 'guest'}) {
  final String disabledPart = status == 'disabled'
      ? '"disabled_at":"$_disabledAt",'
      : '';
  return '{"account":{"account_id":"$_targetId","login_name":"guest_seed_name",'
      '"display_name":"服務端的現在顯示名","account_type":"$accountType",'
      '"status":"$status","must_change_password":false,'
      '"created_at":"2026-10-02T08:00:00.000Z",'
      '$disabledPart"last_login_at":"2026-10-03T07:15:00.000Z"},'
      '"request_id":"r-detail"}';
}

/// 預覽回應本體：target 是「另一位」的現值，記號清單由夹具參數決定。
String _preflightReport({
  required bool executable,
  required List<String> blockers,
  required List<String> impacts,
  int openSessions = 2,
  int schemaVersion = 10,
}) {
  return '{"source":{"account_id":"$_targetId","login_name":"guest_seed_name",'
      '"display_name":"服務端的現在顯示名","account_type":"guest",'
      '"status":"active","must_change_password":false,'
      '"created_at":"2026-10-02T08:00:00.000Z"},'
      '"target":{"account_id":"$_candidateId","login_name":"Already.Real",'
      '"display_name":"正式受體","account_type":"standard",'
      '"status":"active","must_change_password":false,'
      '"created_at":"2026-09-01T00:00:00.000Z"},'
      '"executable":$executable,"blockers":[${_quoted(blockers)}],'
      '"impacts":[${_quoted(impacts)}],'
      '"source_open_sessions":$openSessions,"schema_version":$schemaVersion,'
      '"consent_mode":"target_self_initiated","request_id":"r-preflight"}';
}

/// 停用成功的回應（供「寫入成功收起舊快照」那條斷言用）。
String _statusDisabledReport() {
  return '{"account":{"account_id":"$_targetId","login_name":"guest_seed_name",'
      '"display_name":"服務端的現在顯示名","account_type":"guest",'
      '"status":"disabled","must_change_password":false,'
      '"created_at":"2026-10-02T08:00:00.000Z",'
      '"disabled_at":"$_disabledAt"},'
      '"revoked_sessions":1,"request_id":"r-status"}';
}

/// 依路徑與方法分流的一台假後端。
class _Fixture {
  _Fixture({
    this.accountType = 'guest',
    this.detailStatus = 'active',
    this.preflightStatus = 200,
    this.preflightCode = 0,
    this.preflightInvalidField,
    this.executable = true,
    this.blockers = const <String>[],
    List<String>? impacts,
    this.openSessions = 2,
  }) : impacts = impacts ?? (executable ? _fullImpacts : const <String>[]),
       _detailBody = _detailRecord(
         status: detailStatus,
         accountType: accountType,
       );

  /// 來源詳情讀回的來源類型與狀態。
  final String accountType;
  final String detailStatus;

  /// 預檢端點的 HTTP 狀態與失敗信封欄位。
  final int preflightStatus;
  final int preflightCode;
  final String? preflightInvalidField;

  /// 200 預覽本體的三個面向。
  final bool executable;
  final List<String> blockers;
  final List<String> impacts;
  final int openSessions;

  final String _detailBody;

  int directoryCalls = 0;

  /// 預檢端點收過的請求。
  final List<http.Request> preflightWrites = <http.Request>[];

  /// 狀態端點收過的請求數。
  int statusWrites = 0;

  bool _holdNextPreflight = false;

  /// 讓下一趟預檢延後四十毫秒（夠泵一次 frame 斷言互斥與連點）。
  void holdNextPreflightWrite() => _holdNextPreflight = true;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        if (request.method == 'GET' && path == kAdminAccountsPath) {
          directoryCalls++;
          return _reply(200, _directoryPage(detailStatus, accountType));
        }
        if (request.method == 'GET') {
          return _reply(200, _detailBody);
        }
        if (path.endsWith('/bind-preflight')) {
          preflightWrites.add(request);
          if (_holdNextPreflight) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            _holdNextPreflight = false;
          }
          if (preflightStatus != 200) {
            final String details = preflightInvalidField == null
                ? ''
                : '"details":{"invalid_field":"$preflightInvalidField"},';
            return _reply(
              preflightStatus,
              '{"code":$preflightCode,$details"message":"failed",'
              '"request_id":"r-fail"}',
            );
          }
          return _reply(
            200,
            _preflightReport(
              executable: executable,
              blockers: blockers,
              impacts: impacts,
              openSessions: openSessions,
            ),
          );
        }
        if (path.endsWith('/status')) {
          statusWrites++;
          return _reply(200, _statusDisabledReport());
        }
        return _reply(200, _detailRecord());
      }),
    );
  }

  http.Response _reply(int status, String body) => http.Response(
    body,
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

void main() {
  late ServerAddressSettings settings;

  setUp(() async {
    settings = await buildAddressSettings(
      storedUrl: reachableUrl,
      reachable: <String>[reachableUrl],
    );
  });

  Future<void> pump(
    WidgetTester tester,
    _Fixture fixture, {
    String pageKey = 'bind-preflight',
  }) async {
    await tester.pumpWidget(
      AppScope(
        dependencies: AppDependencies(api: fixture.api(settings)),
        child: MaterialApp(
          locale: _locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SingleChildScrollView(
                    child: AdminConsolePage(key: ValueKey<String>(pageKey)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, String Function(AppLocalizations) pick) =>
      pick(AppLocalizations.of(tester.element(find.byType(AdminConsolePage))));

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 打開來源訪戶的詳情卡。
  Future<void> openProfile(WidgetTester tester) async {
    await tapVisible(
      tester,
      find.byKey(StandardAccountDirectoryCard.actionKey(_targetId)),
    );
    await tester.pumpAndSettle();
  }

  /// 填目標標識並按預檢鈕。
  Future<void> fillAndTapPreflight(
    WidgetTester tester, {
    String target = _candidateId,
  }) async {
    await tester.enterText(
      find.byKey(StandardAccountProfileCard.bindPreflightTargetKey),
      target,
    );
    await tapVisible(
      tester,
      find.byKey(StandardAccountProfileCard.bindPreflightActionKey),
    );
  }

  group('綁定預檢區的形狀', () {
    testWidgets('訪戶目標：常駐句、目標欄與預檢鈕都在', (WidgetTester tester) async {
      await pump(tester, _Fixture());
      await openProfile(tester);
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightScopeKey),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightTargetKey),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightActionKey),
        findsOneWidget,
      );
    });

    testWidgets('標準目標：整個綁定預檢區不存在（欄位、按鈕與常駐句都不出現）', (WidgetTester tester) async {
      await pump(tester, _Fixture(accountType: 'standard'));
      await openProfile(tester);
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightScopeKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightActionKey),
        findsNothing,
      );
    });

    testWidgets('停用中的訪戶這一區仍在：狀態是不是問題交給後端的預覽回答，界面不預判', (
      WidgetTester tester,
    ) async {
      await pump(tester, _Fixture(detailStatus: 'disabled'));
      await openProfile(tester);
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightActionKey),
        findsOneWidget,
      );
    });

    testWidgets('目標沒填就按：本地攔一句，一個請求都不發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.bindPreflightActionKey),
      );
      expect(fixture.preflightWrites, isEmpty);
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindPreflightIncompleteNotice),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightResultKey),
        findsNothing,
      );
    });

    testWidgets('本體恰好 target_account_id 一欄、POST、路徑掛在來源那一側', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapPreflight(tester);

      final http.Request request = fixture.preflightWrites.single;
      expect(request.method, 'POST');
      expect(request.url.path, adminAccountBindPreflightPath(_targetId));
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'target_account_id'});
      expect(body['target_account_id'], _candidateId);
      for (final String forbidden in <String>[
        'password',
        'roles',
        'account_type',
        'status',
        'expected',
        'consent',
      ]) {
        expect(request.body, isNot(contains(forbidden)));
      }
    });
  });

  group('預覽結果的唸法', () {
    testWidgets('可執行：首句「尚未綁定」、五條影響逐條唸、數量與版本取自回應、含同意句', (
      WidgetTester tester,
    ) async {
      await pump(tester, _Fixture());
      await openProfile(tester);
      await fillAndTapPreflight(tester);

      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightResultKey),
        findsOneWidget,
      );
      // 「尚未綁定」不是角落註腳：結果面板裡那句加重的首句必須在。
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindPreflightNotBoundNotice),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(
            tester,
            (l) => l.stdAccountBindPreflightExecutableHead(
              'guest_seed_name',
              'Already.Real',
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindPreflightImpactRevoke(2)),
        ),
        findsOneWidget,
      );
      expect(
        find.text(textOf(tester, (l) => l.stdAccountBindPreflightImpactRetire)),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindPreflightImpactKeepHistory),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(
            tester,
            (l) => l.stdAccountBindPreflightImpactFutureAttribution,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindPreflightImpactTargetUnchanged),
        ),
        findsOneWidget,
      );
      expect(
        find.text(textOf(tester, (l) => l.stdAccountBindPreflightConsentNote)),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindPreflightDataVersion(10)),
        ),
        findsOneWidget,
      );
      // 界面沒有一顆「執行綁定」的按鈕：本步今日不存在那個動詞。
      expect(find.text('執行綁定'), findsNothing);
    });

    testWidgets('被阻止：同一個 200 通道，逐條唸原因且不唸影響', (WidgetTester tester) async {
      await pump(
        tester,
        _Fixture(
          executable: false,
          blockers: const <String>['target_not_standard', 'target_not_active'],
          impacts: const <String>[],
          openSessions: 1,
        ),
      );
      await openProfile(tester);
      await fillAndTapPreflight(tester);

      expect(
        find.text(
          textOf(
            tester,
            (l) => l.stdAccountBindPreflightBlockedHead(
              'guest_seed_name',
              'Already.Real',
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(
            tester,
            (l) => l.stdAccountBindPreflightBlockerTargetNotStandard,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(
            tester,
            (l) => l.stdAccountBindPreflightBlockerTargetNotActive,
          ),
        ),
        findsOneWidget,
      );
      // 被阻止的綁定不會產生任何影響：影響句一條都不該出現。
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindPreflightImpactRevoke(2)),
        ),
        findsNothing,
      );
      expect(
        find.text(textOf(tester, (l) => l.stdAccountBindPreflightImpactRetire)),
        findsNothing,
      );
    });

    testWidgets('認不得的記號：通用句保留原記號，不崩潰也不靜默', (WidgetTester tester) async {
      await pump(
        tester,
        _Fixture(
          executable: false,
          blockers: const <String>['future_blocker_v9'],
          impacts: const <String>[],
        ),
      );
      await openProfile(tester);
      await fillAndTapPreflight(tester);
      expect(
        find.text(
          textOf(
            tester,
            (l) => l.stdAccountBindPreflightUnknownToken('future_blocker_v9'),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('每種已發布原因都有專屬句：逐條渲染不混唸', (WidgetTester tester) async {
      const Map<String, String Function(AppLocalizations)> known =
          <String, String Function(AppLocalizations)>{
            'same_source_target': l10nBlockerSame,
            'source_not_guest': l10nBlockerSourceNotGuest,
            'source_not_active': l10nBlockerSourceNotActive,
            'source_has_grants': l10nBlockerSourceHasGrants,
            'target_not_standard': l10nBlockerTargetNotStandard,
            'target_not_active': l10nBlockerTargetNotActive,
            'unknown_references': l10nBlockerUnknownRefs,
          };
      int round = 0;
      for (final MapEntry<String, String Function(AppLocalizations)> entry
          in known.entries) {
        round++;
        await pump(
          tester,
          _Fixture(
            executable: false,
            blockers: <String>[entry.key],
            impacts: const <String>[],
          ),
          pageKey: 'bind-preflight-cause-$round',
        );
        await openProfile(tester);
        await fillAndTapPreflight(tester);
        expect(
          find.text(textOf(tester, entry.value)),
          findsOneWidget,
          reason: entry.key,
        );
      }
    });
  });

  group('互斥、單趟與快照收起', () {
    testWidgets('在飛窗口連點只發一趟，進行中按鈕停用', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()..holdNextPreflightWrite();
      await pump(tester, fixture);
      await openProfile(tester);
      await tester.enterText(
        find.byKey(StandardAccountProfileCard.bindPreflightTargetKey),
        _candidateId,
      );
      final Finder action = find.byKey(
        StandardAccountProfileCard.bindPreflightActionKey,
      );
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pump();
      await tester.tap(action);
      await tester.pump();
      final FilledButton during = tester.widget<FilledButton>(action);
      expect(during.onPressed, isNull);
      // 只泵一幀時寫入還在飛；放到假時鐘越過 40 毫秒的握著窗才算收尾。
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(fixture.preflightWrites.length, 1);
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightResultKey),
        findsOneWidget,
      );
    });

    testWidgets('預檢在飛時停住既有四條白名單的入口', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()..holdNextPreflightWrite();
      await pump(tester, fixture);
      await openProfile(tester);
      await tester.enterText(
        find.byKey(StandardAccountProfileCard.bindPreflightTargetKey),
        _candidateId,
      );
      final Finder action = find.byKey(
        StandardAccountProfileCard.bindPreflightActionKey,
      );
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pump();
      final FilledButton save = tester.widget<FilledButton>(
        find.byKey(StandardAccountProfileCard.submitKey),
      );
      expect(save.onPressed, isNull);
      final FilledButton upgrade = tester.widget<FilledButton>(
        find.byKey(StandardAccountProfileCard.upgradeActionKey),
      );
      expect(upgrade.onPressed, isNull);
      final TextField target = tester.widget<TextField>(
        find.byKey(StandardAccountProfileCard.bindPreflightTargetKey),
      );
      expect(target.enabled, isFalse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(fixture.preflightWrites.length, 1);
    });

    testWidgets('舊快照不會跨寫入存活：停用成功後結果面板收起', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapPreflight(tester);
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightResultKey),
        findsOneWidget,
      );
      // 接著對同一個人真的停用（寫入成功）：那份預覽描述的事實已經變了。
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.disableKey),
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.confirmKey),
      );
      expect(fixture.statusWrites, 1);
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightResultKey),
        findsNothing,
      );
    });
  });

  group('失敗分流', () {
    testWidgets('1004 點名 target_account_id 專屬句；結果面板不出現', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        _Fixture(
          preflightStatus: 400,
          preflightCode: 1004,
          preflightInvalidField: 'target_account_id',
        ),
      );
      await openProfile(tester);
      await fillAndTapPreflight(tester);
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindPreflightInvalidTargetNotice),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightResultKey),
        findsNothing,
      );
    });

    testWidgets('1001、2011 與會話那一簇各說各話', (WidgetTester tester) async {
      final List<_Fixture> cases = <_Fixture>[
        _Fixture(preflightStatus: 404, preflightCode: 1001),
        _Fixture(preflightStatus: 403, preflightCode: 2011),
        _Fixture(preflightStatus: 401, preflightCode: 2003),
      ];
      final List<String Function(AppLocalizations)> expects =
          <String Function(AppLocalizations)>[
            (l) => l.stdAccountProfileNotFoundNotice,
            (l) => l.stdAccountProfileDeniedNotice,
            (l) => l.adminProfileStaleRejectedNotice,
          ];
      for (int i = 0; i < cases.length; i++) {
        await pump(tester, cases[i]);
        await openProfile(tester);
        await fillAndTapPreflight(tester);
        expect(
          find.text(textOf(tester, expects[i])),
          findsOneWidget,
          reason: '第 $i 組失敗各說各話',
        );
      }
    });
  });
}

// 已發布原因記號 → 界面句子的對照表（逐條引用 ARB 現值，不抄字面文案）。
String l10nBlockerSame(AppLocalizations l) =>
    l.stdAccountBindPreflightBlockerSame;
String l10nBlockerSourceNotGuest(AppLocalizations l) =>
    l.stdAccountBindPreflightBlockerSourceNotGuest;
String l10nBlockerSourceNotActive(AppLocalizations l) =>
    l.stdAccountBindPreflightBlockerSourceNotActive;
String l10nBlockerSourceHasGrants(AppLocalizations l) =>
    l.stdAccountBindPreflightBlockerSourceHasGrants;
String l10nBlockerTargetNotStandard(AppLocalizations l) =>
    l.stdAccountBindPreflightBlockerTargetNotStandard;
String l10nBlockerTargetNotActive(AppLocalizations l) =>
    l.stdAccountBindPreflightBlockerTargetNotActive;
String l10nBlockerUnknownRefs(AppLocalizations l) =>
    l.stdAccountBindPreflightBlockerUnknownRefs;
