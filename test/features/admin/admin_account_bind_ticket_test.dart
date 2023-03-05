/// 管理員端「簽發訪戶綁定憑證」的介面測試。
///
/// 這一區是綁定預覽區旁邊唯一會寫資料的那顆按鈕，測試問的是界線有沒有被界面放寬：
///   1. 只由服務端讀回的來源欄決定出現與否（訪戶才有；普通帳戶整區不存在），
///      停用中的訪戶這一區仍在——可不可行由後端回答，界面不預判也不藏入口；
///   2. 本體恰好 target_account_id 一欄、方法 POST、路徑掛在來源那一側；
///   3. 這一動會寫東西，所以它要確認框（預檢不要）：對話框必須點名被准的目標，
///      並明說這不是綁定本身；取消是一條正經出路，零請求；
///   4. 明文只在成功那一次的面板裡出現，並與「它不是口令、執行只能由目標本人確認」
///      「何時失效」同屏講完；界面沒有任何「已代他完成綁定」的措辭；
///   5. 簽發在飛時停住其餘寫入入口、連點只發一趟；任何一次寫入成功都收起那份憑證；
///   6. 失敗分流各說各話：1004 點名欄位、2026 說要重新預檢、1001／2011 不是憑證問題。
///
/// 全程走注入的假傳輸：不碰網路、不落任何真實憑據。
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

/// 詳情卡的來源（訪戶）標識。
const String _guestId = '01a0e000-0000-7000-8000-0000000000aa';

/// 管理員填寫的目標帳戶標識（假 UUID，只活在這次注入的假傳輸裡）。
const String _targetId = '01a0e000-0000-7000-8000-0000000000bb';

/// 假憑證明文：22 字元，與後端 base64url(16 bytes) 的長度一致。
const String _ticket = 'Zm9vYmFyMTIzNDU2Nzg5MGFi';

const String _disabledAt = '2026-10-03T09:30:00.000Z';
const String _expiresAt = '2026-10-09T09:20:00.000Z';

/// 五條影響記號的可執行清單（與後端 impacts 的穩定值逐字同）。
const List<String> _fullImpacts = <String>[
  'revoke_source_sessions',
  'retire_source_account',
  'keep_history_references',
  'transfer_future_attribution',
  'target_unchanged',
];

/// 來源（訪戶）一行的現值：類型與狀態由夹具決定。
String _sourceRecord({String status = 'active', String accountType = 'guest'}) {
  final String disabledPart = status == 'disabled'
      ? '"disabled_at":"$_disabledAt",'
      : '';
  return '{"account_id":"$_guestId","login_name":"guest_seed_name",'
      '"display_name":"服務端的現在顯示名","account_type":"$accountType",'
      '"status":"$status","must_change_password":false,'
      '"created_at":"2026-10-02T08:00:00.000Z",'
      '$disabledPart"last_login_at":"2026-10-03T07:15:00.000Z"}';
}

/// 目標（普通帳戶）的投影：簽發回應裡的那一側。
const String _targetRecord =
    '{"account_id":"$_targetId","login_name":"Already.Real",'
    '"display_name":"正式受體","account_type":"standard","status":"active",'
    '"must_change_password":false,"created_at":"2026-09-01T00:00:00.000Z"}';

/// 目錄一頁：只列來源這一行。
String _directoryPage(String status, String accountType) {
  return '{"accounts":[${_sourceRecord(status: status, accountType: accountType)}],'
      '"page":1,"page_size":20,"total":1,"request_id":"r-dir"}';
}

/// 單筆詳情（來源）。
String _detailRecord({String status = 'active', String accountType = 'guest'}) {
  return '{"account":${_sourceRecord(status: status, accountType: accountType)},'
      '"request_id":"r-detail"}';
}

/// 停用成功的回應（供「寫入成功收起已簽發憑證」那條斷言用）。
String _statusDisabledReport() {
  return '{"account":${_sourceRecord(status: "disabled")},'
      '"revoked_sessions":1,"request_id":"r-status"}';
}

/// 簽發成功的回應本體：明文、兩側投影、影響、版本與失效時刻。
String _ticketReport() {
  return '{"ticket":"$_ticket","ticket_id":"01a0e000-0000-7000-8000-0000000000ee",'
      '"source":${_sourceRecord()},"target":$_targetRecord,'
      '"impacts":[${_fullImpacts.map((String i) => '"$i"').join(',')}],'
      '"source_open_sessions":2,"schema_version":11,'
      '"expires_at":"$_expiresAt",'
      '"consent_mode":"target_self_initiated","request_id":"r-ticket"}';
}

/// 預覽回應本體（簽發前那一步只讀預檢的真值）：目標登入名取自這裡。
String _preflightReport() {
  return '{"source":${_sourceRecord()},"target":$_targetRecord,'
      '"executable":true,"blockers":[],'
      '"impacts":[${_fullImpacts.map((String i) => '"$i"').join(',')}],'
      '"source_open_sessions":2,"schema_version":11,'
      '"consent_mode":"target_self_initiated","request_id":"r-preflight"}';
}

/// 依路徑與方法分流的一台假後端。
class _Fixture {
  _Fixture({
    this.accountType = 'guest',
    this.detailStatus = 'active',
    this.ticketStatus = 200,
    this.ticketCode = 0,
    this.ticketInvalidField,
  }) : _detailBody = _detailRecord(
         status: detailStatus,
         accountType: accountType,
       );

  /// 來源詳情讀回的來源類型與狀態。
  final String accountType;
  final String detailStatus;

  /// 簽發端點的 HTTP 狀態與失敗信封欄位。
  final int ticketStatus;
  final int ticketCode;
  final String? ticketInvalidField;

  final String _detailBody;

  int directoryCalls = 0;

  /// 簽發端點收過的請求。
  final List<http.Request> ticketWrites = <http.Request>[];

  /// 只讀預檢端點收過的請求（這一檔只把它當成目標登入名的來源）。
  final List<http.Request> preflightWrites = <http.Request>[];

  /// 狀態端點收過的請求數。
  int statusWrites = 0;

  bool _holdNextTicket = false;

  /// 讓下一趟簽發延後四十毫秒（夠泵幾幀斷言互斥與連點）。
  void holdNextTicketWrite() => _holdNextTicket = true;

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
          // 只讀預覽在這一檔一律可行：它存在的意義是把目標的登入名送進界面，
          // 讓「簽發」那一步的確認句有點名對象，而不是那枚標識。
          return _reply(200, _preflightReport());
        }
        if (path.endsWith('/bind-preflight')) {
          preflightWrites.add(request);
          return _reply(200, _preflightReport());
        }
        if (path.endsWith('/bind-ticket')) {
          ticketWrites.add(request);
          if (_holdNextTicket) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            _holdNextTicket = false;
          }
          if (ticketStatus != 200) {
            final String details = ticketInvalidField == null
                ? ''
                : '"details":{"invalid_field":"$ticketInvalidField"},';
            return _reply(
              ticketStatus,
              '{"code":$ticketCode,$details"message":"failed",'
              '"request_id":"r-fail"}',
            );
          }
          return _reply(200, _ticketReport());
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
    String pageKey = 'bind-ticket',
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
      find.byKey(StandardAccountDirectoryCard.actionKey(_guestId)),
    );
  }

  /// 填目標標識並按「簽發」，停在確認對話框出現的那一刻。
  Future<void> openTicketConfirm(WidgetTester tester, String target) async {
    await tester.enterText(
      find.byKey(StandardAccountProfileCard.bindPreflightTargetKey),
      target,
    );
    await tapVisible(
      tester,
      find.byKey(StandardAccountProfileCard.bindTicketActionKey),
    );
  }

  /// 先跑一趟只讀預覽（同一格輸入、兩個動作），再按「簽發」。
  Future<void> openTicketConfirmAfterPreflight(
    WidgetTester tester,
    String target,
  ) async {
    await tester.enterText(
      find.byKey(StandardAccountProfileCard.bindPreflightTargetKey),
      target,
    );
    await tapVisible(
      tester,
      find.byKey(StandardAccountProfileCard.bindPreflightActionKey),
    );
    expect(
      find.byKey(StandardAccountProfileCard.bindPreflightResultKey),
      findsOneWidget,
    );
    await tapVisible(
      tester,
      find.byKey(StandardAccountProfileCard.bindTicketActionKey),
    );
  }

  group('簽發區的形狀', () {
    testWidgets('訪戶才有這一區：常駐句在場，尚未簽發時畫面上沒有任何明文', (WidgetTester tester) async {
      await pump(tester, _Fixture());
      await openProfile(tester);
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketScopeKey),
        findsOneWidget,
      );
      expect(
        find.text(textOf(tester, (l) => l.stdAccountBindTicketScopeHint)),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketActionKey),
        findsOneWidget,
      );
      // 還沒按過：面板不存在，明文也不該以任何形式出现在界面上。
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketResultKey),
        findsNothing,
      );
      expect(find.textContaining(_ticket), findsNothing);
    });

    testWidgets('來源是普通帳戶：整區不存在（來源不是訪戶就不談綁定）', (WidgetTester tester) async {
      await pump(tester, _Fixture(accountType: 'standard'));
      await openProfile(tester);
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightScopeKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketScopeKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketActionKey),
        findsNothing,
      );
    });

    testWidgets('停用中的訪戶這一區仍在：可不可行交給後端回答，界面不預判', (WidgetTester tester) async {
      await pump(tester, _Fixture(detailStatus: 'disabled'));
      await openProfile(tester);
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketActionKey),
        findsOneWidget,
      );
    });

    testWidgets('空白目標本地攔住：確認框不出現、零請求', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.bindTicketActionKey),
      );
      expect(fixture.ticketWrites, isEmpty);
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindTicketIncompleteNotice),
        ),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketResultKey),
        findsNothing,
      );
    });

    testWidgets('本體恰好 target_account_id 一欄、POST、路徑掛在來源那一側', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await openTicketConfirm(tester, _targetId);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.bindTicketConfirmKey),
      );

      final http.Request request = fixture.ticketWrites.single;
      expect(request.method, 'POST');
      expect(request.url.path, adminAccountBindTicketPath(_guestId));
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'target_account_id'});
      expect(body['target_account_id'], _targetId);
      for (final String forbidden in <String>[
        'password',
        'roles',
        'account_type',
        'status',
        'ttl',
        'consent',
      ]) {
        expect(request.body, isNot(contains(forbidden)));
      }
    });
  });

  group('確認對話框與結果面板', () {
    testWidgets('預覽讀過這一對時，對話框點名目標登入名；取消時零請求', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await openTicketConfirmAfterPreflight(tester, _targetId);
      expect(
        find.text(textOf(tester, (l) => l.stdAccountBindTicketConfirmTitle)),
        findsOneWidget,
      );
      // 這一欄剛被預覽讀過：對話框唸出目標的登入名，不是那枚標識。
      expect(
        find.text(
          textOf(
            tester,
            (l) => l.stdAccountBindTicketConfirmBody('Already.Real'),
          ),
        ),
        findsOneWidget,
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.bindTicketConfirmCancelKey),
      );
      expect(fixture.ticketWrites, isEmpty);
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketResultKey),
        findsNothing,
      );
    });

    testWidgets('沒先跑預覽時退回點名那枚標識：界面不拿「看起來像」冒充讀過的事實', (
      WidgetTester tester,
    ) async {
      await pump(tester, _Fixture());
      await openProfile(tester);
      await openTicketConfirm(tester, _targetId);
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindTicketConfirmBody(_targetId)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('確認後：明文與交付句、失效時刻同屏，且沒有一句「已代他綁定」', (WidgetTester tester) async {
      await pump(tester, _Fixture());
      await openProfile(tester);
      await openTicketConfirm(tester, _targetId);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.bindTicketConfirmKey),
      );

      expect(
        find.byKey(StandardAccountProfileCard.bindTicketResultKey),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(
            tester,
            (l) => l.stdAccountBindTicketIssuedNotice(_ticket, 'Already.Real'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(textOf(tester, (l) => l.stdAccountBindTicketDeliveryNotice)),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(
            tester,
            (l) => l.stdAccountBindTicketExpiresNotice(_expiresAt),
          ),
        ),
        findsOneWidget,
      );
      // 這一步沒有綁定任何人：預檢結果面板（那句「尚未綁定」的落點）不在場，
      // 界面也沒有任何「執行綁定」的動詞可以按。
      expect(
        find.byKey(StandardAccountProfileCard.bindPreflightResultKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketConfirmKey),
        findsNothing,
      );
      // 這一側永遠不該有「代他完成綁定」的那一動。
      expect(find.text('執行綁定'), findsNothing);
      expect(find.text('代他綁定'), findsNothing);
      // 收尾按鈕回到空閒態：可以為另一對再簽一枚。
      final FilledButton idle = tester.widget<FilledButton>(
        find.byKey(StandardAccountProfileCard.bindTicketActionKey),
      );
      expect(idle.onPressed, isNotNull);
    });
  });

  group('互斥、單趟與快照收起', () {
    testWidgets('簽發在飛時停住另一條寫入入口，連點只發一趟', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()..holdNextTicketWrite();
      await pump(tester, fixture);
      await openProfile(tester);
      await openTicketConfirm(tester, _targetId);
      await tester.tap(
        find.byKey(StandardAccountProfileCard.bindTicketConfirmKey),
      );
      await tester.pump();
      await tester.pump();
      expect(fixture.ticketWrites.length, 1);
      final FilledButton save = tester.widget<FilledButton>(
        find.byKey(StandardAccountProfileCard.submitKey),
      );
      expect(save.onPressed, isNull);
      final FilledButton upgrade = tester.widget<FilledButton>(
        find.byKey(StandardAccountProfileCard.upgradeActionKey),
      );
      expect(upgrade.onPressed, isNull);
      // 在飛時再點簽發鈕：它自己也被停住，所以第二趟請求根本發不出去。
      final FilledButton during = tester.widget<FilledButton>(
        find.byKey(StandardAccountProfileCard.bindTicketActionKey),
      );
      expect(during.onPressed, isNull);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(fixture.ticketWrites.length, 1);
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketResultKey),
        findsOneWidget,
      );
    });

    testWidgets('一次寫入成功收起先前那份憑證：它描述的事實已被這次寫入改變', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await openTicketConfirm(tester, _targetId);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.bindTicketConfirmKey),
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketResultKey),
        findsOneWidget,
      );
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
        find.byKey(StandardAccountProfileCard.bindTicketResultKey),
        findsNothing,
      );
      expect(find.textContaining(_ticket), findsNothing);
    });
  });

  group('失敗分流', () {
    testWidgets('2026 說「重新預檢」，與 1001／2011 各說各話', (WidgetTester tester) async {
      final List<_Fixture> cases = <_Fixture>[
        _Fixture(ticketStatus: 409, ticketCode: 2026),
        _Fixture(ticketStatus: 404, ticketCode: 1001),
        _Fixture(ticketStatus: 403, ticketCode: 2011),
      ];
      final List<String Function(AppLocalizations)> expects =
          <String Function(AppLocalizations)>[
            (l) => l.errorCodeBindPlanStale,
            (l) => l.stdAccountProfileNotFoundNotice,
            (l) => l.stdAccountProfileDeniedNotice,
          ];
      for (int i = 0; i < cases.length; i++) {
        await pump(tester, cases[i], pageKey: 'bind-ticket-fail-$i');
        await openProfile(tester);
        await openTicketConfirm(tester, _targetId);
        await tapVisible(
          tester,
          find.byKey(StandardAccountProfileCard.bindTicketConfirmKey),
        );
        expect(
          find.text(textOf(tester, expects[i])),
          findsOneWidget,
          reason: '第 $i 組失敗各說各話',
        );
        expect(
          find.byKey(StandardAccountProfileCard.bindTicketResultKey),
          findsNothing,
        );
      }
    });

    testWidgets('1004 依 invalid_field 點名目標標識，不改寫成憑證問題', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        _Fixture(
          ticketStatus: 400,
          ticketCode: 1004,
          ticketInvalidField: 'target_account_id',
        ),
      );
      await openProfile(tester);
      await openTicketConfirm(tester, _targetId);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.bindTicketConfirmKey),
      );
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountBindPreflightInvalidTargetNotice),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.bindTicketResultKey),
        findsNothing,
      );
    });
  });
}
