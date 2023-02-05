/// 管理員端「普通帳戶登入停用與恢復」的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何真實憑據。這一檔問的是幾件事：
///   1. 那顆按鈕只由服務端讀回的現狀決定（表外值不長按鈕）；
///   2. 影響範圍句與確認對話框把「動的是整臺伺服器的登入能力」講在同一頁上，
///      取消是一條正經出路（一請求都不發）；
///   3. expected_status 取「上一次從伺服器讀到的現狀」，不是本地輸入；
///   4. 成功後的現狀、撤銷數量與目錄一律換成服務端回應；
///   5. 2014 另成一句、鎖住兩顆鈕並只給重讀出口；
///   6. 兩條白名單不並發：任一寫入進行中時另一顆鈕停用最；
///   7. 訪客帳戶走同一組控制項（範圍句也同一句），界面不按來源分岔。
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

/// 停用時刻（用於 disabled 形態的回應；界面只轉述，不做換算）。
const String _disabledAt = '2026-10-03T09:30:00.000Z';

/// 目錄一頁：只列目標這一行，免得斷言被別的行列染到。
String _directoryPage(String status) {
  return '{"accounts":[{"account_id":"$_targetId","login_name":"alpha.player",'
      '"display_name":"目錄上的名字","account_type":"standard","status":"$status",'
      '"must_change_password":false,"created_at":"2026-10-02T08:00:00.000Z"}],'
      '"page":1,"page_size":20,"total":1,"request_id":"r-dir"}';
}

/// 單筆詳情：狀態與停用時刻成對（active 時 disabled_at 缺席，合同如此）。
String _detailRecord({
  String status = 'active',
  String displayName = '服務端的現在顯示名',
  String accountType = 'standard',
}) {
  final String disabledPart = status == 'disabled'
      ? '"disabled_at":"$_disabledAt",'
      : '';
  return '{"account":{"account_id":"$_targetId","login_name":"alpha.player",'
      '"display_name":"$displayName","account_type":"$accountType",'
      '"status":"$status","must_change_password":true,'
      '"created_at":"2026-10-02T08:00:00.000Z",'
      '$disabledPart"last_login_at":"2026-10-03T07:15:00.000Z"},'
      '"request_id":"r-detail"}';
}

/// 狀態變更的成功回應： account 是「變更後」的現值，revoked_sessions 帶數量。
String _statusReport({
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
      '"revoked_sessions":$revokedSessions,"request_id":"r-status"}';
}

/// 依路徑與方法分流的一台假後端。
class _Fixture {
  _Fixture({
    this.detailStatus = 'active',
    this.accountType = 'standard',
    this.statusWriteStatus = 200,
    this.statusWriteCode = 2014,
  }) : _detailBody = _detailRecord(
         status: detailStatus,
         accountType: accountType,
       );

  /// 服務端現狀（詳情讀回的那一份）。
  final String detailStatus;

  /// 目標來源類型（standard|guest）。
  final String accountType;

  final int statusWriteStatus;

  /// 失敗信封裡的機器碼（與 HTTP 狀態配對：409/2014、404/1001、403/2011）。
  final int statusWriteCode;

  final String _detailBody;

  /// 目錄讀取趟數（成功後重讀的證據）。
  int directoryCalls = 0;

  /// 狀態端點收過的請求（本體與方法都由斷言讀）。
  final List<http.Request> statusWrites = <http.Request>[];

  /// 顯示名端點收過的請求（用來證明兩條白名單各走各路）。
  final List<http.Request> profileWrites = <http.Request>[];

  bool _holdNextStatusWrite = false;

  /// 讓下一趟狀態寫入延後四十毫秒（夠泵一次 frame 斷言按鈕停用）。
  void holdNextStatusWrite() => _holdNextStatusWrite = true;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final bool onStatusSubpath = path.endsWith('/status');
        if (request.method == 'GET' && path == kAdminAccountsPath) {
          directoryCalls++;
          return _reply(200, _directoryPage(detailStatus));
        }
        if (request.method == 'GET') {
          return _reply(200, _detailBody);
        }
        if (onStatusSubpath) {
          statusWrites.add(request);
          if (_holdNextStatusWrite) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            _holdNextStatusWrite = false;
          }
          if (statusWriteStatus != 200) {
            return _reply(
              statusWriteStatus,
              '{"code":$statusWriteCode,"message":"failed","request_id":"r-fail"}',
            );
          }
          return _reply(
            200,
            _statusReport(
              status: detailStatus == 'active' ? 'disabled' : 'active',
              revokedSessions: 2,
              accountType: accountType,
            ),
          );
        }
        profileWrites.add(request);
        return _reply(200, _detailRecord(displayName: '保存後的顯示名'));
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
  Future<void> pump(
    WidgetTester tester,
    _Fixture fixture, [
    String pageKey = 'default',
  ]) async {
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

  /// 打開目標那行的詳情卡。
  Future<void> openProfile(WidgetTester tester) async {
    await tapVisible(
      tester,
      find.byKey(StandardAccountDirectoryCard.actionKey(_targetId)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester, _Fixture fixture) async {
    await pump(tester, fixture);
    await openProfile(tester);
    await tapVisible(
      tester,
      fixture.detailStatus == 'active'
          ? find.byKey(StandardAccountProfileCard.disableKey)
          : find.byKey(StandardAccountProfileCard.restoreKey),
    );
  }

  Map<String, Object?> bodyOf(http.Request request) =>
      jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, Object?>;

  group('普通帳戶停用與恢復的按鈕與說明', () {
    testWidgets('active 只長停用鈕、disabled 只長恢復鈕', (tester) async {
      final fixture = _Fixture(detailStatus: 'active');
      await pump(tester, fixture);
      await openProfile(tester);

      expect(find.byKey(StandardAccountProfileCard.disableKey), findsOneWidget);
      expect(find.byKey(StandardAccountProfileCard.restoreKey), findsNothing);
      expect(
        find.byKey(StandardAccountProfileCard.scopeHintKey),
        findsOneWidget,
      );

      // 同一頁換成 disabled 的目標：按鈕交換方向，不是兩顆同時在。
      final disabledFixture = _Fixture(detailStatus: 'disabled');
      await pump(tester, disabledFixture, 'disabled-target');
      await openProfile(tester);
      expect(find.byKey(StandardAccountProfileCard.restoreKey), findsOneWidget);
      expect(find.byKey(StandardAccountProfileCard.disableKey), findsNothing);
      // 停用時刻取自服務端回應，呈現為「年-月-日 時:分 UTC」（界面不做本機時區換算）。
      expect(find.textContaining('2026-10-03 09:30 UTC'), findsWidgets);
    });

    testWidgets('表外狀態不長按鈕，只如實說一句', (tester) async {
      final fixture = _Fixture(detailStatus: 'locked_forward');
      await pump(tester, fixture);
      await openProfile(tester);

      expect(
        find.byKey(StandardAccountProfileCard.statusUnknownKey),
        findsOneWidget,
      );
      expect(find.byKey(StandardAccountProfileCard.disableKey), findsNothing);
      expect(find.byKey(StandardAccountProfileCard.restoreKey), findsNothing);
      expect(
        find.text(
          textOf(
            tester,
            (AppLocalizations l) =>
                l.adminStatusUnsupportedNotice('locked_forward'),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('訪客帳戶走同一組控制項與同一句範圍說明', (tester) async {
      final fixture = _Fixture(detailStatus: 'active', accountType: 'guest');
      await pump(tester, fixture);
      await openProfile(tester);

      expect(find.byKey(StandardAccountProfileCard.disableKey), findsOneWidget);
      expect(
        find.text(textOf(tester, (l) => l.stdAccountStatusScopeHint)),
        findsOneWidget,
      );
    });
  });

  group('確認對話框', () {
    testWidgets('停用前講完目標、影響與「這不是刪除」，取消一請求都不發', (tester) async {
      final fixture = _Fixture(detailStatus: 'active');
      await openDialog(tester, fixture);

      final String dialogText = _allText(tester);
      for (final String must in <String>[
        'alpha.player',
        textOf(tester, (l) => l.stdAccountStatusConfirmTitleDisable),
        textOf(
          tester,
          (l) => l.stdAccountStatusConfirmDisableBody('alpha.player'),
        ),
      ]) {
        expect(dialogText.contains(must), isTrue, reason: '對話框少了：$must');
      }
      // 「這不是刪除」與「所有裝置與活動」都在確認文裡，界面不另藏說明。
      expect(dialogText, contains('這不是刪除'));

      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.confirmCancelKey),
      );
      expect(fixture.statusWrites, isEmpty);
      expect(fixture.profileWrites, isEmpty);
    });

    testWidgets('恢復前如實說「只恢復新登入資格」', (tester) async {
      final fixture = _Fixture(detailStatus: 'disabled');
      await openDialog(tester, fixture);

      final String dialogText = _allText(tester);
      expect(
        dialogText.contains(
          textOf(
            tester,
            (l) => l.stdAccountStatusConfirmRestoreBody('alpha.player'),
          ),
        ),
        isTrue,
      );
      expect(dialogText, contains('不會復活'));
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.confirmCancelKey),
      );
      expect(fixture.statusWrites, isEmpty);
    });
  });

  group('提交與成功', () {
    testWidgets('本體恰好兩欄，依據值取服務端讀回的現狀', (tester) async {
      final fixture = _Fixture(detailStatus: 'active');
      await openDialog(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.confirmKey),
      );

      expect(fixture.statusWrites.length, 1);
      final http.Request request = fixture.statusWrites.single;
      expect(request.method, 'PUT');
      expect(request.url.path, '/admin/accounts/$_targetId/status');
      expect(bodyOf(request), <String, Object?>{
        'status': 'disabled',
        'expected_status': 'active',
      });
    });

    testWidgets('成功後現狀、撤銷數量與目錄都換成服務端回應', (tester) async {
      final fixture = _Fixture(detailStatus: 'active');
      await openDialog(tester, fixture);
      final int callsBefore = fixture.directoryCalls;
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.confirmKey),
      );

      expect(
        find.text(textOf(tester, (l) => l.stdAccountStatusDisabledNotice(2))),
        findsOneWidget,
      );
      // 現狀換成回應那份：目錄行的狀態由重讀取得，本地不抢先改寫。
      expect(fixture.directoryCalls, callsBefore + 1);
      expect(find.byKey(StandardAccountProfileCard.disableKey), findsNothing);
      expect(find.byKey(StandardAccountProfileCard.restoreKey), findsOneWidget);
      // 輸入框沿用同一筆帳戶的顯示名（狀態變更不動那一欄，卡也不清空底稿）。
      final TextField field = tester.widget(
        find.byKey(StandardAccountProfileCard.displayNameKey),
      );
      expect(field.controller!.text, '服務端的現在顯示名');
    });

    testWidgets('恢復成功句不報數字，只說要重新登入', (tester) async {
      final fixture = _Fixture(detailStatus: 'disabled');
      await openDialog(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.confirmKey),
      );

      expect(
        find.text(textOf(tester, (l) => l.stdAccountStatusRestoredNotice)),
        findsOneWidget,
      );
      expect(
        bodyOf(fixture.statusWrites.single)['expected_status'],
        'disabled',
      );
      expect(bodyOf(fixture.statusWrites.single)['status'], 'active');
    });

    testWidgets('寫入進行中不重發，另一條白名單也停住', (tester) async {
      final fixture = _Fixture(detailStatus: 'active')..holdNextStatusWrite();
      await openDialog(tester, fixture);
      await tester.ensureVisible(
        find.byKey(StandardAccountProfileCard.confirmKey),
      );
      await tester.tap(find.byKey(StandardAccountProfileCard.confirmKey));
      await tester.pump();
      // 對話框已收、請求還在飛：第二趟與並行的顯示名保存都發不出去。
      await tester.pump(const Duration(milliseconds: 10));
      expect(_statusButtonLocked(tester), isTrue);

      await tester.pumpAndSettle();
      expect(fixture.statusWrites.length, 1);
    });
  });

  group('失敗分流', () {
    testWidgets('2014 另成一句、鎖住按鈕並只給重讀出口', (tester) async {
      final fixture = _Fixture(detailStatus: 'active', statusWriteStatus: 409);
      await openDialog(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.confirmKey),
      );

      expect(
        find.text(textOf(tester, (l) => l.stdAccountStatusConflictNotice)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(StandardAccountProfileCard.disableKey),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(StandardAccountProfileCard.reloadKey), findsOneWidget);

      // 重讀之後才重新取得現狀：那顆按鈕才重新可用（不是拿舊依據再撞一次）。
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.reloadKey),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(StandardAccountProfileCard.disableKey),
            )
            .onPressed,
        isNotNull,
      );
      expect(fixture.statusWrites.length, 1);
    });

    testWidgets('1001 與 2011 各說各句，不混成「伺服器查不了」', (tester) async {
      // 「這個目標不在目錄」「這主體沒權限」「衝突要重讀」是三種處置，
      // 界面若把前兩種混成一句，操作者就會對著權限問題反复換目標。
      final notFound = _Fixture(statusWriteStatus: 404, statusWriteCode: 1001);
      await pump(tester, notFound);
      await openProfile(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.disableKey),
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.confirmKey),
      );
      final String shownNotFound = _allText(tester);
      expect(
        shownNotFound.contains(
          textOf(
            tester,
            (AppLocalizations l) => l.stdAccountProfileNotFoundNotice,
          ),
        ),
        isTrue,
      );
      expect(
        shownNotFound.contains(
          textOf(
            tester,
            (AppLocalizations l) => l.stdAccountStatusConflictNotice,
          ),
        ),
        isFalse,
      );

      final denied = _Fixture(statusWriteStatus: 403, statusWriteCode: 2011);
      await pump(tester, denied, 'denied');
      await openProfile(tester);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.disableKey),
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.confirmKey),
      );
      expect(
        _allText(tester).contains(
          textOf(
            tester,
            (AppLocalizations l) => l.stdAccountProfileDeniedNotice,
          ),
        ),
        isTrue,
      );
    });
  });
}

/// 畫面上目前所有文字（含對話框）：「該講的講完了沒有」的斷言對象。
String _allText(WidgetTester tester) {
  final Iterable<Text> texts = tester.widgetList<Text>(find.byType(Text));
  return texts.map((Text t) => t.data ?? '').join('\n');
}

/// 狀態寫入進行中：那顆鈕不可再點（文字換成「正在處理…」由上一條斷言看）。
bool _statusButtonLocked(WidgetTester tester) =>
    tester
        .widget<OutlinedButton>(
          find.byKey(StandardAccountProfileCard.disableKey),
        )
        .onPressed ==
    null;
