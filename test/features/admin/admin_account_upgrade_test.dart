/// 管理員端「訪戶原地升級為普通帳戶」的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何真實憑據。這一檔問的是幾件事：
///   1. 升級區只由服務端讀回的來源欄位決定出現與否：訪客且有登入能力才有那顆按鈕；
///      停用中的訪客看到的是處置說明（先恢復登入再決定），標準目標整區不存在；
///   2. 「原地升級」與「綁定到既有帳戶」在界面上分開：確認文點名目標與新的正式登入名，
///      並寫明這不是綁定——混按一次就是一個不可分岔的歷史；
///   3. 口令與重置同規：遮蔽欄、送出即清空、成功與失敗都不回填，頁面任何一處不再出現那串字；
///   4. 本體恰好 login_name 與 password 兩欄（沒有類型／角色／狀態／旗標／顯示名／依據值格子）；
///   5. 成功句的撤銷數量與轉正現值一律換成 PUT 回應並觸發目錄重讀；轉正後升級區收起、
///      憑據區如實出現（界面跟著伺服器真相走，不靠本地改類型）；
///   6. 四條白名單不並發：任一寫入進行中時其餘入口停用，結果不明時不自動補發；
///   7. 失敗分流各說各話：1004 依欄位、2012 換名字、2024 重讀現值，訪客的伺服器真相不動。
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

/// 詳情卡的目標標識（隨機 UUIDv7 形態，不是任何環境的真實資料）。
const String _targetId = '01a0e000-0000-7000-8000-0000000000bb';

/// 測試交付的一次性升級口令：只活在這次的假傳輸裡，不進任何回應。
const String _delivered = '一次性升級口令-not-a-real-one';

/// 操作者填寫的正式登入名。
const String _newLogin = 'Real.Upgrade.One';

/// 停用時刻（disabled 形態的回應；界面只轉述，不做換算）。
const String _disabledAt = '2026-10-03T09:30:00.000Z';

/// 目錄一頁：只列目標這一行，免得斷言被別的行列染到。
String _directoryPage(String status, String accountType) {
  return '{"accounts":[{"account_id":"$_targetId","login_name":"guest_seed_name",'
      '"display_name":"目錄上的名字","account_type":"$accountType",'
      '"status":"$status","must_change_password":false,'
      '"created_at":"2026-10-02T08:00:00.000Z"}],'
      '"page":1,"page_size":20,"total":1,"request_id":"r-dir"}';
}

/// 單筆詳情：來源類型與狀態由夹具決定（訪客恆無 must_change 那回事，讀到 false）。
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

/// 升級成功的回應：account 是「轉正之後」的現值（standard＋欠首改），帶撤銷數量。
String _upgradeReport({required int revokedSessions}) {
  return '{"account":{"account_id":"$_targetId","login_name":"$_newLogin",'
      '"display_name":"服務端的現在顯示名","account_type":"standard",'
      '"status":"active","must_change_password":true,'
      '"created_at":"2026-10-02T08:00:00.000Z",'
      '"last_login_at":"2026-10-03T07:15:00.000Z"},'
      '"revoked_sessions":$revokedSessions,"request_id":"r-upgrade"}';
}

/// 依路徑與方法分流的一台假後端。
class _Fixture {
  _Fixture({
    this.detailStatus = 'active',
    this.accountType = 'guest',
    this.upgradeWriteStatus = 200,
    this.upgradeWriteCode = 0,
    this.upgradeInvalidField,
    this.revokedSessions = 2,
  }) : _detailBody = _detailRecord(
         status: detailStatus,
         accountType: accountType,
       );

  /// 服務端現狀（詳情讀回的那一份）。
  final String detailStatus;

  /// 目標來源類型（standard|guest）。
  final String accountType;

  /// 升級端點的 HTTP 狀態（200 之外的值代表失敗）。
  final int upgradeWriteStatus;

  /// 失敗信封裡的機器碼（409/2024、409/2012、404/1001、403/2011）。
  final int upgradeWriteCode;

  /// 1004 時點名的欄位（其他失敗不帶 details）。
  final String? upgradeInvalidField;

  /// 成功回應裡的撤銷數量。
  final int revokedSessions;

  final String _detailBody;

  /// 目錄讀取趟數（成功後重讀的證據）。
  int directoryCalls = 0;

  /// 升級端點收過的請求（本體與方法都由斷言讀）。
  final List<http.Request> upgradeWrites = <http.Request>[];

  /// 憑據端點收過的請求（用來證明轉正前沒有人替訪客按重置）。
  final List<http.Request> passwordWrites = <http.Request>[];

  bool _holdNextUpgradeWrite = false;

  /// 讓下一趟升級延後四十毫秒（夠泵一次 frame 斷言按鈕停用）。
  void holdNextUpgradeWrite() => _holdNextUpgradeWrite = true;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final bool onUpgradeSubpath = path.endsWith('/upgrade');
        final bool onPasswordSubpath = path.endsWith('/password');
        if (request.method == 'GET' && path == kAdminAccountsPath) {
          directoryCalls++;
          return _reply(200, _directoryPage(detailStatus, accountType));
        }
        if (request.method == 'GET') {
          return _reply(200, _detailBody);
        }
        if (onUpgradeSubpath) {
          upgradeWrites.add(request);
          if (_holdNextUpgradeWrite) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            _holdNextUpgradeWrite = false;
          }
          if (upgradeWriteStatus != 200) {
            final String details = upgradeInvalidField == null
                ? ''
                : '"details":{"invalid_field":"$upgradeInvalidField"},';
            return _reply(
              upgradeWriteStatus,
              '{"code":$upgradeWriteCode,$details"message":"failed",'
              '"request_id":"r-fail"}',
            );
          }
          return _reply(200, _upgradeReport(revokedSessions: revokedSessions));
        }
        if (onPasswordSubpath) {
          passwordWrites.add(request);
          return _reply(
            403,
            '{"code":2018,"message":"guest","request_id":"r-18"}',
          );
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

  /// 把管理端頁面掛上必要作用域後泵入（每次落在全新的 State 上）。
  Future<void> pump(WidgetTester tester, _Fixture fixture) async {
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
                    child: AdminConsolePage(
                      key: const ValueKey<String>('upgrade'),
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

  String textOf(WidgetTester tester, String Function(AppLocalizations) pick) =>
      pick(AppLocalizations.of(tester.element(find.byType(AdminConsolePage))));

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 打開目標那行的詳情卡。
  Future<void> openProfile(WidgetTester tester) async {
    await tapVisible(
      tester,
      find.byKey(StandardAccountDirectoryCard.actionKey(_targetId)),
    );
    await tester.pumpAndSettle();
  }

  /// 填入正式登入名與一次性口令並按下升級鈕（停在確認對話框打開的那一刻）。
  Future<void> fillAndTapUpgrade(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(StandardAccountProfileCard.upgradeLoginKey),
      _newLogin,
    );
    await tester.enterText(
      find.byKey(StandardAccountProfileCard.upgradePasswordFieldKey),
      _delivered,
    );
    await tapVisible(
      tester,
      find.byKey(StandardAccountProfileCard.upgradeActionKey),
    );
  }

  group('升級區的形狀', () {
    testWidgets('訪客且有登入能力：說明句、兩個欄位與一顆就地升級鈕都在，口令欄遮蔽', (
      WidgetTester tester,
    ) async {
      await pump(tester, _Fixture());
      await openProfile(tester);

      expect(
        find.byKey(StandardAccountProfileCard.upgradeScopeKey),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.upgradeLoginKey),
        findsOneWidget,
      );
      final TextField password = tester.widget<TextField>(
        find.byKey(StandardAccountProfileCard.upgradePasswordFieldKey),
      );
      expect(password.obscureText, isTrue);
      expect(
        find.byKey(StandardAccountProfileCard.upgradeActionKey),
        findsOneWidget,
      );
      // 憑據區對訪客仍不長重置鈕：兩個動詞各走各的路徑，界面无處混淆。
      expect(
        find.byKey(StandardAccountProfileCard.resetActionKey),
        findsNothing,
      );
    });

    testWidgets('標準目標：整個升級區不存在（按鈕、欄位與說明句都不出現）', (WidgetTester tester) async {
      await pump(tester, _Fixture(accountType: 'standard'));
      await openProfile(tester);

      expect(
        find.byKey(StandardAccountProfileCard.upgradeScopeKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.upgradeLoginKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.upgradeActionKey),
        findsNothing,
      );
    });

    testWidgets('停用中的訪客：不長那顆按鈕，只說「先恢復登入再決定」處置句（2024 那句）', (
      WidgetTester tester,
    ) async {
      await pump(tester, _Fixture(detailStatus: 'disabled'));
      await openProfile(tester);

      expect(
        find.byKey(StandardAccountProfileCard.upgradeActionKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.upgradeLoginKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.upgradeUnavailableKey),
        findsOneWidget,
      );
      expect(
        find.text(textOf(tester, (l) => l.errorCodeGuestNotUpgradable)),
        findsOneWidget,
      );
      // 狀態那顆「恢復」鈕仍在：處置是走它，不是讓升級順帶復活誰。
      expect(find.byKey(StandardAccountProfileCard.restoreKey), findsOneWidget);
    });
  });

  group('確認對話框與取消', () {
    testWidgets('確認文點名目標與新登入名、寫明「不是綁定」；取消一請求都不發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapUpgrade(tester);

      final String body = textOf(
        tester,
        (l) => l.stdAccountUpgradeConfirmBody('guest_seed_name', _newLogin),
      );
      expect(find.text(body), findsOneWidget);
      expect(body, contains('guest_seed_name'));
      expect(body, contains(_newLogin));
      expect(body, contains('不是綁定到另一個帳戶'));
      expect(
        find.byKey(StandardAccountProfileCard.upgradeConfirmKey),
        findsOneWidget,
      );

      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.upgradeConfirmCancelKey),
      );
      expect(fixture.upgradeWrites, isEmpty);
      // 取消後兩個輸入都還在（還沒交付），界面停在上一份伺服器真相。
      expect(
        tester
            .widget<TextField>(
              find.byKey(StandardAccountProfileCard.upgradeLoginKey),
            )
            .controller!
            .text,
        _newLogin,
      );
    });

    testWidgets('沒填齊就按：本地擋一句，不發請求', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.upgradeActionKey),
      );

      expect(fixture.upgradeWrites, isEmpty);
      expect(
        find.byKey(StandardAccountProfileCard.upgradeConfirmKey),
        findsNothing,
      );
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountUpgradeFormIncompleteNotice),
        ),
        findsOneWidget,
      );
    });
  });

  group('提交與成功', () {
    testWidgets('本體恰好兩欄：login_name 與 password，沒有依據值也沒有類型／旗標／狀態格子', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapUpgrade(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.upgradeConfirmKey),
      );

      final http.Request request = fixture.upgradeWrites.single;
      expect(request.method, 'PUT');
      expect(request.url.path, adminAccountUpgradePath(_targetId));
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'login_name', 'password'});
      expect(body['login_name'], _newLogin);
      expect(body['password'], _delivered);
    });

    testWidgets('送出即清空：成功後頁面不再出現口令字串，升級區收起、憑據區如實出現', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapUpgrade(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.upgradeConfirmKey),
      );

      expect(find.textContaining(_delivered), findsNothing);
      // 本地不改類型：界面換成 PUT 回應後，訪客那組控件自然收起、標準那組自然出現。
      expect(
        find.byKey(StandardAccountProfileCard.upgradeActionKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.resetFieldKey),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.resetActionKey),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.upgradeNoticeKey),
        findsOneWidget,
      );
      expect(
        find.text(textOf(tester, (l) => l.stdAccountUpgradeSuccessNotice(2))),
        findsOneWidget,
      );
    });

    testWidgets('撤銷數量取自回應並觸發目錄重讀；0 時如實說「沒有需要登出的會話」', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(revokedSessions: 0);
      await pump(tester, fixture);
      await openProfile(tester);
      final int readsBefore = fixture.directoryCalls;
      await fillAndTapUpgrade(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.upgradeConfirmKey),
      );

      final String notice = textOf(
        tester,
        (l) => l.stdAccountUpgradeSuccessNotice(0),
      );
      expect(find.text(notice), findsOneWidget);
      expect(notice, contains('沒有需要登出的活躍會話'));
      expect(fixture.directoryCalls, greaterThan(readsBefore));
    });

    testWidgets('寫入進行中不重發：在飛窗口裡連點升級鈕也只發一趟', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()..holdNextUpgradeWrite();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapUpgrade(tester);

      final Finder confirm = find.byKey(
        StandardAccountProfileCard.upgradeConfirmKey,
      );
      await tester.ensureVisible(confirm);
      await tester.pump();
      // 只泵一幀：寫入還在飛，此刻才是「進行中」的那個瞬間。
      await tester.tap(confirm);
      await tester.pump();

      final Finder action = find.byKey(
        StandardAccountProfileCard.upgradeActionKey,
      );
      await tester.ensureVisible(action);
      await tester.pump();
      await tester.tap(action);
      await tester.pump();
      expect(fixture.upgradeWrites.length, 1);
      await tester.pumpAndSettle();
      expect(fixture.upgradeWrites.length, 1);
    });

    testWidgets('升級進行中時其餘白名單停用：保存鈕此刻按下去也不發請求', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()..holdNextUpgradeWrite();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapUpgrade(tester);

      final Finder confirm = find.byKey(
        StandardAccountProfileCard.upgradeConfirmKey,
      );
      await tester.ensureVisible(confirm);
      await tester.pump();
      // 只泵一幀：寫入還在飛，此刻才是「進行中」的那個瞬間。
      await tester.tap(confirm);
      await tester.pump();

      final FilledButton save = tester.widget<FilledButton>(
        find.byKey(StandardAccountProfileCard.submitKey),
      );
      expect(save.onPressed, isNull);
      await tester.pumpAndSettle();
      expect(fixture.upgradeWrites.length, 1);
    });
  });

  group('失敗分流', () {
    testWidgets('1004 依點名欄位各成一句：口令不回填、訪客的伺服器真相不動', (WidgetTester tester) async {
      for (final (String field, String Function(AppLocalizations) pick)
          in <(String, String Function(AppLocalizations))>[
            ('login_name', (l) => l.adminProvisionInvalidLoginNameNotice),
            ('password', (l) => l.adminResetInvalidPasswordNotice),
          ]) {
        final _Fixture fixture = _Fixture(
          upgradeWriteStatus: 400,
          upgradeWriteCode: 1004,
          upgradeInvalidField: field,
        );
        await pump(tester, fixture);
        await openProfile(tester);
        await fillAndTapUpgrade(tester);
        await tapVisible(
          tester,
          find.byKey(StandardAccountProfileCard.upgradeConfirmKey),
        );
        expect(
          find.text(textOf(tester, pick)),
          findsOneWidget,
          reason: '欄位 $field 該有自己的那一句',
        );
        // 失敗不謊報轉正：來源仍是訪客，升級控件也還在（可改入力再確認）。
        expect(
          find.byKey(StandardAccountProfileCard.guestResetNoticeKey),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextField>(
                find.byKey(StandardAccountProfileCard.upgradePasswordFieldKey),
              )
              .controller!
              .text,
          isEmpty,
        );
      }
    });

    testWidgets('2012 換名字、2024 重讀現值：兩句處置不同、不互換，請求各只一趟', (
      WidgetTester tester,
    ) async {
      for (final (int code, String Function(AppLocalizations) pick)
          in <(int, String Function(AppLocalizations))>[
            (2012, (l) => l.errorCodeLoginNameTaken),
            (2024, (l) => l.errorCodeGuestNotUpgradable),
          ]) {
        final _Fixture fixture = _Fixture(
          upgradeWriteStatus: 409,
          upgradeWriteCode: code,
        );
        await pump(tester, fixture);
        await openProfile(tester);
        await fillAndTapUpgrade(tester);
        await tapVisible(
          tester,
          find.byKey(StandardAccountProfileCard.upgradeConfirmKey),
        );
        expect(
          find.text(textOf(tester, pick)),
          findsOneWidget,
          reason: 'code $code 該有自己的那一句',
        );
        expect(fixture.upgradeWrites.length, 1);
      }
    });

    testWidgets('1001 與 2011 各自成句（目標不在目錄／主體不對）', (WidgetTester tester) async {
      for (final (int status, int code, String Function(AppLocalizations) pick)
          in <(int, int, String Function(AppLocalizations))>[
            (404, 1001, (l) => l.stdAccountProfileNotFoundNotice),
            (403, 2011, (l) => l.stdAccountProfileDeniedNotice),
          ]) {
        final _Fixture fixture = _Fixture(
          upgradeWriteStatus: status,
          upgradeWriteCode: code,
        );
        await pump(tester, fixture);
        await openProfile(tester);
        await fillAndTapUpgrade(tester);
        await tapVisible(
          tester,
          find.byKey(StandardAccountProfileCard.upgradeConfirmKey),
        );
        expect(
          find.text(textOf(tester, pick)),
          findsOneWidget,
          reason: 'code $code 該有自己的那一句',
        );
      }
    });
  });
}
