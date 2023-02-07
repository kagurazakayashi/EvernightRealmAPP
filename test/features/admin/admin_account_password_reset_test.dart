/// 管理員端「重置普通帳戶登入憑據」的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何真實憑據。這一檔問的是幾件事：
///   1. 重置區不按狀態分岔（停用中的目標也合法，因為重置不是解除停用），
///      但訪客目標按來源出局——界面不擺那顆註定拿 2018 的按鈕，而說一句「等升級通路」；
///   2. 確認對話框把三件效果與兩件不會發生講完，取消是一條正經出路（一請求都不發）；
///   3. 口令只在請求那一側出現一次：送出即清空、成功與失敗都不回填，
///      界面上任何一處都不再出現那串字；
///   4. 本體恰好 password 一欄（沒有依據值、也沒有狀態／旗標／類型／角色的格子）；
///   5. 成功句的撤銷數量與現值一律換成 PUT 回應，並觸發目錄重讀；
///   6. 三條白名單不並發：任一寫入進行中時其餘按鈕停用最，結果不明時不自動補發；
///   7. 1004 點名口令欄位另成一句、2018 另成一句，兩者的處置不同且都不給「再點一次」。
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
const String _targetId = '01a0e000-0000-7000-8000-0000000000aa';

/// 測試交付的一次性口令：只活在這次的假傳輸裡，不進任何回應。
const String _delivered = '一次性重置口令-not-a-real-one';

/// 停用時刻（disabled 形態的回應；界面只轉述，不做換算）。
const String _disabledAt = '2026-10-03T09:30:00.000Z';

/// 目錄一頁：只列目標這一行，免得斷言被別的行列染到。
String _directoryPage(String status, String accountType) {
  return '{"accounts":[{"account_id":"$_targetId","login_name":"alpha.player",'
      '"display_name":"目錄上的名字","account_type":"$accountType",'
      '"status":"$status","must_change_password":false,'
      '"created_at":"2026-10-02T08:00:00.000Z"}],'
      '"page":1,"page_size":20,"total":1,"request_id":"r-dir"}';
}

/// 單筆詳情：狀態與停用時刻成對，來源類型由夹具決定。
String _detailRecord({
  String status = 'active',
  String accountType = 'standard',
  bool mustChange = true,
  String displayName = '服務端的現在顯示名',
}) {
  final String disabledPart = status == 'disabled'
      ? '"disabled_at":"$_disabledAt",'
      : '';
  return '{"account":{"account_id":"$_targetId","login_name":"alpha.player",'
      '"display_name":"$displayName","account_type":"$accountType",'
      '"status":"$status","must_change_password":$mustChange,'
      '"created_at":"2026-10-02T08:00:00.000Z",'
      '$disabledPart"last_login_at":"2026-10-03T07:15:00.000Z"},'
      '"request_id":"r-detail"}';
}

/// 重置成功的回應：account 是「重置之後」的現值（恆欠首改、狀態原樣），帶撤銷數量。
String _resetReport({
  required String status,
  required int revokedSessions,
  String accountType = 'standard',
}) {
  final String disabledPart = status == 'disabled'
      ? '"disabled_at":"$_disabledAt",'
      : '';
  return '{"account":{"account_id":"$_targetId","login_name":"alpha.player",'
      '"display_name":"服務端的現在顯示名","account_type":"$accountType",'
      '"status":"$status","must_change_password":true,'
      '"created_at":"2026-10-02T08:00:00.000Z",'
      '$disabledPart"last_login_at":"2026-10-03T07:15:00.000Z"},'
      '"revoked_sessions":$revokedSessions,"request_id":"r-reset"}';
}

/// 依路徑與方法分流的一台假後端。
class _Fixture {
  _Fixture({
    this.detailStatus = 'active',
    this.accountType = 'standard',
    this.resetWriteStatus = 200,
    this.resetWriteCode = 0,
    this.resetInvalidField,
    this.revokedSessions = 2,
  }) : _detailBody = _detailRecord(
         status: detailStatus,
         accountType: accountType,
       );

  /// 服務端現狀（詳情讀回的那一份）。
  final String detailStatus;

  /// 目標來源類型（standard|guest）。
  final String accountType;

  /// 重置端點的 HTTP 狀態（200 之外的值代表失敗）。
  final int resetWriteStatus;

  /// 失敗信封裡的機器碼（403/2018、404/1001、403/2011）。
  final int resetWriteCode;

  /// 1004 時點名的欄位（其他失敗不帶 details）。
  final String? resetInvalidField;

  /// 成功回應裡的撤銷數量。
  final int revokedSessions;

  final String _detailBody;

  /// 目錄讀取趟數（成功後重讀的證據）。
  int directoryCalls = 0;

  /// 重置端點收過的請求（本體與方法都由斷言讀）。
  final List<http.Request> resetWrites = <http.Request>[];

  /// 狀態端點收過的請求（用來證明三條白名單各走各路）。
  final List<http.Request> statusWrites = <http.Request>[];

  bool _holdNextResetWrite = false;

  /// 讓下一趟重置延後四十毫秒（夠泵一次 frame 斷言按鈕停用）。
  void holdNextResetWrite() => _holdNextResetWrite = true;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final bool onPasswordSubpath = path.endsWith('/password');
        final bool onStatusSubpath = path.endsWith('/status');
        if (request.method == 'GET' && path == kAdminAccountsPath) {
          directoryCalls++;
          return _reply(200, _directoryPage(detailStatus, accountType));
        }
        if (request.method == 'GET') {
          return _reply(200, _detailBody);
        }
        if (onPasswordSubpath) {
          resetWrites.add(request);
          if (_holdNextResetWrite) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            _holdNextResetWrite = false;
          }
          if (resetWriteStatus != 200) {
            final String details = resetInvalidField == null
                ? ''
                : '"details":{"invalid_field":"$resetInvalidField"},';
            return _reply(
              resetWriteStatus,
              '{"code":$resetWriteCode,$details"message":"failed",'
              '"request_id":"r-fail"}',
            );
          }
          return _reply(
            200,
            _resetReport(
              status: detailStatus,
              revokedSessions: revokedSessions,
              accountType: accountType,
            ),
          );
        }
        if (onStatusSubpath) {
          statusWrites.add(request);
          return _reply(
            200,
            _statusReport(
              status: detailStatus == 'active' ? 'disabled' : 'active',
            ),
          );
        }
        return _reply(200, _detailRecord(displayName: '保存後的顯示名'));
      }),
    );
  }

  /// 狀態端點的成功回應（本檔只需要成功形態，用來量互斥）。
  String _statusReport({required String status}) {
    final String disabledPart = status == 'disabled'
        ? '"disabled_at":"$_disabledAt",'
        : '';
    return '{"account":{"account_id":"$_targetId","login_name":"alpha.player",'
        '"display_name":"服務端的現在顯示名","account_type":"$accountType",'
        '"status":"$status","must_change_password":true,'
        '"created_at":"2026-10-02T08:00:00.000Z",'
        '$disabledPart"last_login_at":"2026-10-03T07:15:00.000Z"},'
        '"revoked_sessions":2,"request_id":"r-status"}';
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
                      key: const ValueKey<String>('reset'),
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

  /// 填入一次性口令並按下重置鈕（停在確認對話框打開的那一刻）。
  Future<void> fillAndTapReset(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(StandardAccountProfileCard.resetFieldKey),
      _delivered,
    );
    await tapVisible(
      tester,
      find.byKey(StandardAccountProfileCard.resetActionKey),
    );
  }

  group('重置憑據區的形狀', () {
    testWidgets('普通目標：有遮蔽的口令欄與一顆重置鈕，影響範圍句常在', (WidgetTester tester) async {
      await pump(tester, _Fixture());
      await openProfile(tester);

      expect(
        find.byKey(StandardAccountProfileCard.resetFieldKey),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.resetActionKey),
        findsOneWidget,
      );
      final TextField field = tester.widget<TextField>(
        find.byKey(StandardAccountProfileCard.resetFieldKey),
      );
      expect(field.obscureText, isTrue);
      expect(
        find.byKey(StandardAccountProfileCard.resetScopeKey),
        findsOneWidget,
      );
    });

    testWidgets('訪客目標：不長口令欄與按鈕，只說「要等訪客升級功能」那一句', (WidgetTester tester) async {
      await pump(tester, _Fixture(accountType: 'guest'));
      await openProfile(tester);

      expect(
        find.byKey(StandardAccountProfileCard.resetFieldKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.resetActionKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.guestResetNoticeKey),
        findsOneWidget,
      );
      expect(
        find.text(textOf(tester, (l) => l.stdAccountResetGuestNotice)),
        findsOneWidget,
      );
    });

    testWidgets('停用中的目標仍有重置區：重置不是解除停用，不按狀態分岔', (WidgetTester tester) async {
      await pump(tester, _Fixture(detailStatus: 'disabled'));
      await openProfile(tester);

      expect(
        find.byKey(StandardAccountProfileCard.resetFieldKey),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.resetActionKey),
        findsOneWidget,
      );
      // 狀態那顆「恢復」鈕也還在：兩條白名單各說各話，誰也不替誰開門。
      expect(find.byKey(StandardAccountProfileCard.restoreKey), findsOneWidget);
    });
  });

  group('確認對話框與取消', () {
    testWidgets('確認文點名目標、講完三件效果與兩件不會發生，取消一請求都不發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapReset(tester);

      final String body = textOf(
        tester,
        (l) => l.stdAccountResetConfirmBody('alpha.player'),
      );
      expect(find.text(body), findsOneWidget);
      expect(body, contains('alpha.player'));
      expect(body, contains('現行口令立即失效'));
      expect(body, contains('這不是停用／恢復那一條通路'));
      expect(
        find.byKey(StandardAccountProfileCard.resetConfirmKey),
        findsOneWidget,
      );

      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.resetConfirmCancelKey),
      );
      expect(fixture.resetWrites, isEmpty);
      // 取消後口令仍留在輸入框裡（還沒交付），界面停在上一份伺服器真相。
      final TextField field = tester.widget<TextField>(
        find.byKey(StandardAccountProfileCard.resetFieldKey),
      );
      expect(field.controller!.text, _delivered);
    });

    testWidgets('沒填口令就按：本地擋一句，不發請求', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.resetActionKey),
      );

      expect(fixture.resetWrites, isEmpty);
      expect(
        find.byKey(StandardAccountProfileCard.resetConfirmKey),
        findsNothing,
      );
      expect(
        find.text(textOf(tester, (l) => l.adminResetFormIncompleteNotice)),
        findsOneWidget,
      );
    });

    testWidgets('訪客按不到：界面根本沒有那顆鈕，也就不可能發出一趟注定 2018 的請求', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(accountType: 'guest');
      await pump(tester, fixture);
      await openProfile(tester);

      expect(
        find.byKey(StandardAccountProfileCard.resetActionKey),
        findsNothing,
      );
      expect(fixture.resetWrites, isEmpty);
    });
  });

  group('提交與成功', () {
    testWidgets('本體恰好 password 一欄：沒有依據值，也沒有狀態／旗標／類型／角色', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapReset(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.resetConfirmKey),
      );

      final http.Request request = fixture.resetWrites.single;
      expect(request.method, 'PUT');
      expect(request.url.path, adminAccountPasswordPath(_targetId));
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'password'});
      expect(body['password'], _delivered);
    });

    testWidgets('送出即清空：請求發出後輸入框不再留口令，成功句也不含那串字', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapReset(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.resetConfirmKey),
      );

      final TextField field = tester.widget<TextField>(
        find.byKey(StandardAccountProfileCard.resetFieldKey),
      );
      expect(field.controller!.text, isEmpty);
      // 整頁任何一處都不該再出現那串口令（成功句只講數量與交付責任）。
      expect(find.textContaining(_delivered), findsNothing);
      expect(
        find.byKey(StandardAccountProfileCard.resetNoticeKey),
        findsOneWidget,
      );
    });

    testWidgets('成功句的撤銷數量取自回應，並觸發目錄重讀', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(revokedSessions: 3);
      await pump(tester, fixture);
      await openProfile(tester);
      final int readsBefore = fixture.directoryCalls;
      await fillAndTapReset(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.resetConfirmKey),
      );

      expect(
        find.text(textOf(tester, (l) => l.stdAccountResetSuccessNotice(3))),
        findsOneWidget,
      );
      expect(fixture.directoryCalls, greaterThan(readsBefore));
    });

    testWidgets('數量為 0 時說「沒有需要退出的現有會話」，不謊報成別人被登出', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        detailStatus: 'disabled',
        revokedSessions: 0,
      );
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapReset(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.resetConfirmKey),
      );

      final String notice = textOf(
        tester,
        (l) => l.stdAccountResetSuccessNotice(0),
      );
      expect(find.text(notice), findsOneWidget);
      expect(notice, contains('沒有需要退出的現有會話'));
      // 成功展示換成 PUT 回應：停用中的目標重置後仍是 disabled。
      expect(find.byKey(StandardAccountProfileCard.restoreKey), findsOneWidget);
    });

    testWidgets('寫入進行中不重發：第二顆鈕按下去也只發一趟', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()..holdNextResetWrite();
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapReset(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.resetConfirmKey),
      );

      final Finder action = find.byKey(
        StandardAccountProfileCard.resetActionKey,
      );
      await tester.ensureVisible(action);
      await tester.pump();
      await tester.tap(action);
      await tester.pump();
      expect(fixture.resetWrites.length, 1);
      await tester.pumpAndSettle();
      expect(fixture.resetWrites.length, 1);
    });

    testWidgets('三條白名單互斥：重置進行中時停用鈕停用最', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()..holdNextResetWrite();
      await pump(tester, fixture);
      await openProfile(tester);
      await tester.enterText(
        find.byKey(StandardAccountProfileCard.resetFieldKey),
        _delivered,
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.resetActionKey),
      );
      await tester.ensureVisible(
        find.byKey(StandardAccountProfileCard.resetConfirmKey),
      );
      await tester.pump();
      // 只泵一幀：寫入還在飛，此刻才是「進行中」的那個瞬間。
      await tester.tap(find.byKey(StandardAccountProfileCard.resetConfirmKey));
      await tester.pump();

      final OutlinedButton disable = tester.widget<OutlinedButton>(
        find.byKey(StandardAccountProfileCard.disableKey),
      );
      expect(disable.onPressed, isNull);
      expect(fixture.statusWrites, isEmpty);
      await tester.pumpAndSettle();
      expect(fixture.resetWrites.length, 1);
    });
  });

  group('失敗分流', () {
    testWidgets('1004 點名口令欄位另成一句，界面不填回口令也不自動補發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        resetWriteStatus: 400,
        resetWriteCode: 1004,
        resetInvalidField: 'password',
      );
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapReset(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.resetConfirmKey),
      );

      expect(
        find.text(textOf(tester, (l) => l.adminResetInvalidPasswordNotice)),
        findsOneWidget,
      );
      final TextField field = tester.widget<TextField>(
        find.byKey(StandardAccountProfileCard.resetFieldKey),
      );
      expect(field.controller!.text, isEmpty);
      expect(fixture.resetWrites.length, 1);
    });

    testWidgets('2018 說的是「等訪客升級通路」那一句，與 1001／2011 各說各話', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture(
        resetWriteStatus: 403,
        resetWriteCode: 2018,
      );
      await pump(tester, fixture);
      await openProfile(tester);
      await fillAndTapReset(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.resetConfirmKey),
      );

      final String guest = textOf(tester, (l) => l.stdAccountResetGuestNotice);
      expect(find.text(guest), findsOneWidget);
      expect(
        guest,
        isNot(textOf(tester, (l) => l.stdAccountProfileNotFoundNotice)),
      );
      expect(
        guest,
        isNot(textOf(tester, (l) => l.stdAccountProfileDeniedNotice)),
      );
      // 一句「再點一次也不會變」的處置：界面不摆自動補發，請求也只發過一趟。
      expect(fixture.resetWrites.length, 1);
    });

    testWidgets('1001 與 2011 各自成句（目標不在目錄／主體不對）', (WidgetTester tester) async {
      for (final (int status, int code, String Function(AppLocalizations)) cases
          in <(int, int, String Function(AppLocalizations))>[
            (404, 1001, (l) => l.stdAccountProfileNotFoundNotice),
            (403, 2011, (l) => l.stdAccountProfileDeniedNotice),
          ]) {
        final _Fixture fixture = _Fixture(
          resetWriteStatus: cases.$1,
          resetWriteCode: cases.$2,
        );
        await pump(tester, fixture);
        await openProfile(tester);
        await fillAndTapReset(tester);
        await tapVisible(
          tester,
          find.byKey(StandardAccountProfileCard.resetConfirmKey),
        );
        expect(
          find.text(textOf(tester, cases.$3)),
          findsOneWidget,
          reason: 'code ${cases.$2} 該有自己的那一句',
        );
      }
    });
  });
}
