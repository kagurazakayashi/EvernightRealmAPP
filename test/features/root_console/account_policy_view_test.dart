/// 「Root 帳戶建立策略」卡的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。測試問的是幾件事：
///   1. 三個值的底稿只來自服務端回應（讀失敗時不顯示任何猜測值）；
///   2. 保存必經確認對話框，取消時一個請求都不發；
///   3. 界面用詞把「策略不等於能力」講出來：存了 open，對外兩個布林仍是關；
///   4. 2016 與 1004 是兩句話，且寫入失敗後畫面回到上一份伺服器真相；
///   5. 現值是本版本選不了的模式時如實顯示那個名字，不預填、不降級；
///   6. 一次點擊只發一趟請求（重複按下不是「又確認一次」的入口）。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/root_console/account_policy_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';
import '../../support/test_server.dart';

const Locale _locale = Locale('zh', 'TW');

/// 策略卡的回應本體：三個值＋時刻＋巢狀 entry。
String _policyJson({
  bool adminCreate = false,
  String mode = 'closed',
  bool guest = false,
  bool signUpOpen = false,
  bool inviteCodeRequired = false,
  bool guestOpen = false,
}) {
  return jsonEncode(<String, Object?>{
    'admin_create_standard': adminCreate,
    'self_register_mode': mode,
    'guest_enabled': guest,
    'updated_at': '2026-10-03T09:00:00.000Z',
    'entry': <String, Object?>{
      'sign_up_open': signUpOpen,
      'invite_code_required': inviteCodeRequired,
      'guest_open': guestOpen,
    },
    'request_id': 'r-policy',
  });
}

/// 假端點現場：記錄發出的請求與可調的回應。
class _Fixture {
  /// GET 被問了幾趟。
  int reads = 0;

  /// 發出的 PUT 請求本體（依序）。
  final List<Map<String, Object?>> writes = <Map<String, Object?>>[];

  /// GET 的回應狀態碼與本體（非 200 時本體是錯誤信封）。
  int readStatus = 200;
  String readBody = _policyJson();

  /// PUT 的回應狀態碼、機器碼與成功本體。
  int writeStatus = 200;
  int? writeErrorCode;
  String? writeBody;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        if (request.url.path != kRootAccountPolicyPath) {
          return jsonOk('{}');
        }
        if (request.method == 'GET') {
          reads++;
          return _json(
            readStatus == 200 ? readBody : _error(readStatus),
            readStatus,
          );
        }
        writes.add(jsonDecode(request.body) as Map<String, Object?>);
        if (writeStatus != 200) {
          return _json(_error(writeStatus, code: writeErrorCode), writeStatus);
        }
        return _json(writeBody ?? _policyJson(), 200);
      }),
    );
  }

  static String _error(int status, {int? code}) {
    final int machineCode = code ?? (status == 403 ? 2011 : 1000);
    return '{"code":$machineCode,"message":"x","request_id":"r-err"}';
  }

  static http.Response _json(String body, int status) => http.Response(
    body,
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

void main() {
  late AppLocalizations l10n;
  late ServerAddressSettings settings;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  setUp(() async {
    settings = await buildAddressSettings(
      storedUrl: reachableUrl,
      reachable: <String>[reachableUrl],
    );
  });

  /// 把策略卡掛上必要作用域後泵入（宿主與 AppShell 內容區同形，DEC-020）。
  Future<void> pump(WidgetTester tester, _Fixture fixture) async {
    final ServerApi api = fixture.api(settings);
    await tester.pumpWidget(
      AppScope(
        dependencies: AppDependencies(api: api),
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
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AccountPolicyCard(api: api),
                    ),
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

  group('策略卡讀取', () {
    testWidgets('成功時以服務端現值填三個控件，並列出對外答案', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()
        ..readBody = _policyJson(
          adminCreate: true,
          mode: 'open',
          guest: true,
          signUpOpen: false,
          guestOpen: false,
        );
      await pump(tester, fixture);

      expect(fixture.reads, 1);
      expect(find.byKey(AccountPolicyCard.titleKey), findsOneWidget);
      final Switch adminSwitch = tester.widget<Switch>(
        find.byKey(AccountPolicyCard.adminCreateKey),
      );
      expect(adminSwitch.value, isTrue);
      final Switch guestSwitch = tester.widget<Switch>(
        find.byKey(AccountPolicyCard.guestKey),
      );
      expect(guestSwitch.value, isTrue);
      expect(find.byKey(AccountPolicyCard.modeOpenKey), findsOneWidget);
      // 策略已放開而通路未落地：對外答案仍為關，且這句話顯示在同一張卡上。
      expect(find.textContaining(l10n.accountPolicyClosedWord), findsWidgets);
      expect(find.byKey(AccountPolicyCard.capabilityKey), findsOneWidget);
      expect(
        find.text(l10n.accountPolicyUpdatedOnLabel('2026-10-03 09:00 UTC')),
        findsOneWidget,
      );
    });

    testWidgets('讀取失敗不顯示任何猜測值，只給一句原因與重讀出口', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()..readStatus = 500;
      await pump(tester, fixture);

      expect(find.text(l10n.accountPolicyLoadFailedNotice), findsOneWidget);
      expect(find.byKey(AccountPolicyCard.reloadKey), findsOneWidget);
      expect(find.byKey(AccountPolicyCard.adminCreateKey), findsNothing);
      expect(find.byKey(AccountPolicyCard.submitKey), findsNothing);

      await tester.tap(find.byKey(AccountPolicyCard.reloadKey));
      await tester.pumpAndSettle();
      expect(fixture.reads, 2);
    });

    testWidgets('2011 說成「你不是 Root」，不被人誤讀成「你被登出了」', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()
        ..readStatus = 403
        ..readBody = '{"code":2011,"message":"x","request_id":"r-err"}';
      await pump(tester, fixture);

      expect(find.text(l10n.accountPolicyDeniedNotice), findsOneWidget);
      expect(find.text(l10n.accountPolicyStaleRejectedNotice), findsNothing);
    });

    testWidgets('現值是四個名字之外的模式時如實顯示那個名字，四顆選項都未選', (WidgetTester tester) async {
      // 四個已批准名字之外的值（未來後端多出的那一個）：如實顯示那個原字並說「本版本選不了它」，
      // 不預填、不降級成 closed。invite 已入可選清單，不再是這一格的對象。
      final _Fixture fixture = _Fixture()
        ..readBody = _policyJson(mode: 'future_mode');
      await pump(tester, fixture);

      expect(
        find.text(l10n.accountPolicyModeExternalNotice('future_mode')),
        findsOneWidget,
      );
      for (final Key key in <Key>[
        AccountPolicyCard.modeClosedKey,
        AccountPolicyCard.modeOpenKey,
        AccountPolicyCard.modeApprovalKey,
        AccountPolicyCard.modeInviteKey,
      ]) {
        final ChoiceChip chip = tester.widget<ChoiceChip>(find.byKey(key));
        expect(chip.selected, isFalse, reason: '$key 不該被預填成選中');
      }
    });

    testWidgets('invite 選得也讀得：現值是它時那顆 chip 被選中並多講一句它做什麼', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture()
        ..readBody = _policyJson(
          mode: 'invite',
          signUpOpen: true,
          inviteCodeRequired: true,
        );
      await pump(tester, fixture);

      final ChoiceChip invite = tester.widget<ChoiceChip>(
        find.byKey(AccountPolicyCard.modeInviteKey),
      );
      expect(invite.selected, isTrue);
      // 選中時多講一句：只有持有效碼者可自行註冊、碼不帶角色、換出可立即登入的普通帳戶——
      // 這一格現值如今是「選得了」的那一側，因此不再出現「本版本選不了它」那句。
      expect(find.byKey(AccountPolicyCard.inviteHintKey), findsOneWidget);
      expect(
        find.text(l10n.accountPolicyModeExternalNotice('invite')),
        findsNothing,
      );
    });

    testWidgets('approval 選得也讀得：現值是它時那顆 chip 被選中並多講一句它做什麼', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture()
        ..readBody = _policyJson(mode: 'approval', signUpOpen: true);
      await pump(tester, fixture);

      final ChoiceChip approval = tester.widget<ChoiceChip>(
        find.byKey(AccountPolicyCard.modeApprovalKey),
      );
      expect(approval.selected, isTrue);
      // 選中時多講一句：收申請、但一份也不放行，而且切模式不動歷史——
      // 這一句擋的是把 approval 誤讀成「註冊被關掉了」或「等會兒會自己通過」。
      expect(find.byKey(AccountPolicyCard.approvalHintKey), findsOneWidget);
      expect(
        find.text(l10n.accountPolicyModeExternalNotice('approval')),
        findsNothing,
      );
    });
  });

  group('策略卡保存', () {
    testWidgets('確認對話框取消時一個請求都不發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      await tester.tap(find.byKey(AccountPolicyCard.submitKey));
      await tester.pumpAndSettle();
      expect(find.byKey(AccountPolicyCard.confirmCancelKey), findsOneWidget);
      await tester.tap(find.byKey(AccountPolicyCard.confirmCancelKey));
      await tester.pumpAndSettle();

      expect(fixture.writes, isEmpty);
      expect(find.byKey(AccountPolicyCard.savedKey), findsNothing);
    });

    testWidgets('確認後 PUT 帶三個欄位，成功句與現值都以回應為準', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()
        ..writeBody = _policyJson(
          adminCreate: false,
          mode: 'open',
          guest: false,
          signUpOpen: false,
          guestOpen: false,
        );
      await pump(tester, fixture);

      await tester.tap(find.byKey(AccountPolicyCard.guestKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.modeOpenKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.submitKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.confirmKey));
      await tester.pumpAndSettle();

      expect(fixture.writes, hasLength(1));
      expect(fixture.writes.single.keys, <String>{
        'admin_create_standard',
        'self_register_mode',
        'guest_enabled',
      });
      expect(fixture.writes.single['self_register_mode'], 'open');
      expect(fixture.writes.single['guest_enabled'], isTrue);
      expect(find.text(l10n.accountPolicySavedNotice), findsOneWidget);
      // 回應是 adminCreate=false／guest=false 的現值：界面換成伺服器說的那份，
      // 而不是留下 Root 剛才按出來的兩個 true。
      final Switch adminSwitch = tester.widget<Switch>(
        find.byKey(AccountPolicyCard.adminCreateKey),
      );
      expect(adminSwitch.value, isFalse);
    });

    testWidgets('選 approval 後保存：PUT 帶的就是 approval，不是被頂成 closed 或 open', (
      WidgetTester tester,
    ) async {
      // 這一條釘的是這張卡最容易被寫壞的地方：它交的是完整的三份值，
      // 清單少一個模式就等於 Root 為了改別欄而保存時，悄悄把伺服器的審批模式頂掉。
      final _Fixture fixture = _Fixture()
        ..writeBody = _policyJson(
          adminCreate: true,
          mode: 'approval',
          guest: false,
          signUpOpen: true,
          guestOpen: false,
        );
      await pump(tester, fixture);

      await tester.tap(find.byKey(AccountPolicyCard.adminCreateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.modeApprovalKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.submitKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.confirmKey));
      await tester.pumpAndSettle();

      expect(fixture.writes.single['self_register_mode'], 'approval');
      expect(fixture.writes.single['admin_create_standard'], isTrue);
      // 成功後現值以回應為準：模式仍是 approval，對外答案那一列這時是開。
      final ChoiceChip approval = tester.widget<ChoiceChip>(
        find.byKey(AccountPolicyCard.modeApprovalKey),
      );
      expect(approval.selected, isTrue);
      expect(
        find.text(
          l10n.accountPolicyEntryLabel(
            l10n.accountPolicyOpenWord,
            l10n.accountPolicyClosedWord,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('2016 另成一句，且三個值回到上一份伺服器真相', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()
        ..readBody = _policyJson(adminCreate: true, mode: 'closed', guest: true)
        ..writeStatus = 400
        ..writeErrorCode = 2016;
      await pump(tester, fixture);

      await tester.tap(find.byKey(AccountPolicyCard.guestKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.submitKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.confirmKey));
      await tester.pumpAndSettle();

      expect(fixture.writes, hasLength(1));
      expect(find.text(l10n.accountPolicyModeRejectedNotice), findsOneWidget);
      expect(find.text(l10n.errorCodeInvalidBody), findsNothing);
      final Switch guestSwitch = tester.widget<Switch>(
        find.byKey(AccountPolicyCard.guestKey),
      );
      expect(guestSwitch.value, isTrue);
    });

    testWidgets('一次點擊只發一趟 PUT：保存進行中不得重複提交', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);

      await tester.tap(find.byKey(AccountPolicyCard.submitKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.confirmKey));
      // 不 pumpAndSettle 就點第二次：按鈕應已停用，第二趟請求不該發生。
      await tester.pump();
      await tester.tap(find.byKey(AccountPolicyCard.submitKey));
      await tester.pumpAndSettle();

      expect(fixture.writes, hasLength(1));
    });

    testWidgets('只改訪客時另外兩欄原值送出（三個值彼此獨立）', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()
        ..readBody = _policyJson(adminCreate: true, mode: 'open', guest: false);
      await pump(tester, fixture);

      await tester.tap(find.byKey(AccountPolicyCard.guestKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.submitKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountPolicyCard.confirmKey));
      await tester.pumpAndSettle();

      expect(fixture.writes.single['admin_create_standard'], isTrue);
      expect(fixture.writes.single['self_register_mode'], 'open');
      expect(fixture.writes.single['guest_enabled'], isTrue);
    });
  });
}
