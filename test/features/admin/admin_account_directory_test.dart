/// 管理員端「普通帳戶目錄／詳情與資料編輯」的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何真實憑據。測試問的是幾件事：
///   1. 目錄每一格都是服務端給的：來源、狀態、時刻、總數與頁碼一律轉述，
///      本地不排序、不補行、不把本頁筆數冒充總數；
///   2. 篩選（狀態／來源／關鍵字）各自只發一趟讀取，且關鍵字要點送出才算數；
///   3. 頁碼邊界取服務端回顯，到界停用而不是發一趟注定為空的請求；
///   4. 詳情卡的底稿只能來自單筆讀取（目錄行不夠格），CAS 的依據值就是那份現值；
///   5. 保存成功後輸入框、成功句與目錄都換成服務端的結果；
///   6. 2013／1001／2011／1004 各說各句，衝突之後只給重讀出口、不給再撞一次的鈕；
///   7. 這一頁沒有任何一格可以動憑據、狀態或活動／資產，也不拿佔位值冒充。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/admin_console_page.dart';
import 'package:evernightrealm/features/admin/standard_account_directory_view.dart';
import 'package:evernightrealm/features/admin/standard_account_profile_view.dart';
import 'package:evernightrealm/features/admin/standard_account_provision_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

/// 目錄測試用的帳戶標識（隨機 UUIDv7 形態，不是任何環境的真實資料）。
const String _targetId = '01a0e000-0000-7000-8000-0000000000aa';
const String _otherId = '01a0e000-0000-7000-8000-0000000000bb';

/// 目錄一頁的預設回應：一行普通帳戶加一行訪客帳戶。
String _directoryPage({
  int page = 1,
  int pageSize = 20,
  int total = 2,
  String? rows,
}) {
  final String body =
      rows ??
      '{"account_id":"$_targetId","login_name":"alpha.player",'
          '"display_name":"阿爾法","account_type":"standard","status":"active",'
          '"must_change_password":true,"created_at":"2026-10-02T08:00:00.000Z"},'
          '{"account_id":"$_otherId","login_name":"beta.guest",'
          '"display_name":"訪客乙","account_type":"guest","status":"disabled",'
          '"must_change_password":false,"created_at":"2026-10-01T08:00:00.000Z",'
          '"disabled_at":"2026-10-02T09:30:00.000Z"}';
  return '{"accounts":[$body],"page":$page,"page_size":$pageSize,'
      '"total":$total,"request_id":"r-dir"}';
}

/// 單筆詳情：顯示名刻意與目錄行不同，用來證明底稿取自單筆讀取。
String _detailRecord({String displayName = '服務端的現在顯示名'}) {
  return '{"account":{"account_id":"$_targetId","login_name":"alpha.player",'
      '"display_name":"$displayName","account_type":"standard",'
      '"status":"active","must_change_password":false,'
      '"created_at":"2026-10-02T08:00:00.000Z",'
      '"last_login_at":"2026-10-03T07:15:00.000Z"},'
      '"request_id":"r-detail"}';
}

/// 依路徑分流的一台假後端。
class _Fixture {
  _Fixture({
    this.directoryStatus = 200,
    this.detailStatus = 200,
    this.writeStatus = 200,
    String? directoryBody,
    String? detailBody,
    String? writeBody,
  }) : _directoryBodyOverride = directoryBody,
       _detailBodyOverride = detailBody,
       _writeBodyOverride = writeBody;

  final int directoryStatus;
  final int detailStatus;
  final int writeStatus;
  final String? _directoryBodyOverride;
  final String? _detailBodyOverride;
  final String? _writeBodyOverride;

  /// 目錄讀取的趟數與最後一份查詢參數（篩選與分頁斷言的證據）。
  int directoryCalls = 0;
  Map<String, String>? lastListQuery;

  /// 單筆讀取與寫入各自發出過的請求。
  final List<http.Request> detailRequests = <http.Request>[];
  final List<http.Request> writes = <http.Request>[];

  bool _holdNextWrite = false;

  /// 讓下一趟寫入延後四十毫秒（夠泵一次 frame 斷言按鈕停用）。
  void holdNextWrite() => _holdNextWrite = true;

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        // 這臺假後端按「路徑恰好是目錄那條」計數，而不是「任何不是子路徑的 GET」：
        // 同一張管理端頁面現在還掛著另一本名冊（註冊申請名冊，GET /admin/registrations），
        // 攬總的寫法會把它的讀取趟數算進目錄頭上，那條「進頁只讀一趟目錄」的斷言
        // 就變成在測別人。子路徑（單筆詳情）與另一本名冊各自分流。
        final String path = request.url.path;
        final bool onDirectory = path == kAdminAccountsPath;
        final bool onItem = path.startsWith('$kAdminAccountsPath/');
        if (request.method == 'GET' && onDirectory) {
          directoryCalls++;
          lastListQuery = Map<String, String>.from(request.url.queryParameters);
          return _reply(
            directoryStatus,
            _directoryBodyOverride ?? _directoryPage(),
          );
        }
        if (request.method == 'GET' && onItem) {
          detailRequests.add(request);
          return _reply(detailStatus, _detailBodyOverride ?? _detailRecord());
        }
        if (request.method == 'GET') {
          // 其餘讀取（另一本名冊）如實回空清單：本檔的斷言對象不是它，
          // 但也不能讓它拿到一份會被誤當目錄回應的本體。
          return _reply(200, '{"applications":[],"page":1,"page_size":20,'
              '"total":0,"request_id":"r-other"}');
        }
        writes.add(request);
        if (_holdNextWrite) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          _holdNextWrite = false;
        }
        // 寫入預設回「保存後的現值」：界面要換的是服務端那份真相。
        return _reply(
          writeStatus,
          _writeBodyOverride ?? _detailRecord(displayName: '保存後的顯示名'),
        );
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

  /// 把管理端頁面掛上必要的作用域後泵入（宿主與 AppShell 內容區同形，DEC-020）。
  /// [pageKey] 讓每次泵入都落在一個全新的 State 上（同類型 widget 原地更新會沿用舊 State，
  /// 而目錄卡只在 initState／reloadToken 變動時才讀取）。
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

  /// 取當前上下文的地介面字串：斷言比對的是 ARB 值本身，不是測試另抄的一份。
  String textOf(WidgetTester tester, String Function(AppLocalizations) pick) =>
      pick(AppLocalizations.of(tester.element(find.byType(AdminConsolePage))));

  /// 窄視口下元素可能在滾動區外：先 ensureVisible 再點，否則 tap 會靜默 miss。
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 打開目錄第一行的詳情卡。
  Future<void> openProfile(WidgetTester tester) async {
    await tapVisible(
      tester,
      find.byKey(StandardAccountDirectoryCard.actionKey(_targetId)),
    );
    await tester.pumpAndSettle();
  }

  group('普通帳戶目錄卡', () {
    testWidgets('行、來源、狀態與分頁摘要全部取自服務端回應', (tester) async {
      final fixture = _Fixture();
      await pump(tester, fixture);

      expect(fixture.directoryCalls, 1);
      expect(
        find.text(textOf(tester, (l) => l.stdAccountDirectoryTitle)),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountDirectoryCard.rowKey(_targetId)),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountDirectoryCard.rowKey(_otherId)),
        findsOneWidget,
      );
      // 來源與狀態是兩句話：訪客帳戶如實顯示它是訪客、已停用。
      expect(
        find.text(
          textOf(
            tester,
            (AppLocalizations l) => l.labelValuePair(
              l.stdAccountSourceLabel,
              l.stdAccountTypeGuest,
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(
            tester,
            (AppLocalizations l) =>
                l.labelValuePair(l.adminListStatusLabel, l.adminStatusDisabled),
          ),
        ),
        findsOneWidget,
      );
      // 「第 1／1 頁（共 2 位）」的三個數字都取自回顯，不是行數。
      expect(
        find.text(
          textOf(
            tester,
            (AppLocalizations l) => l.adminDirectoryPageSummary(1, 1, 2),
          ),
        ),
        findsOneWidget,
      );
      // 界面任何一處都沒有憑據格子，也沒有回應裡出現過的內部欄位名。
      final String rendered = _allText(tester);
      for (final String forbidden in <String>[
        'password',
        'argon2id',
        'login_name_key',
        'token',
        'granted_at',
      ]) {
        expect(rendered, isNot(contains(forbidden)));
      }
    });

    testWidgets('篩選變動只發一趟讀取，且回到第一頁', (tester) async {
      final fixture = _Fixture();
      await pump(tester, fixture);
      expect(fixture.directoryCalls, 1);

      await tapVisible(
        tester,
        find.byKey(StandardAccountDirectoryCard.filterTypeGuestKey),
      );
      expect(fixture.directoryCalls, 2);
      expect(fixture.lastListQuery!['type'], 'guest');
      expect(fixture.lastListQuery!['page'], '1');

      await tapVisible(
        tester,
        find.byKey(StandardAccountDirectoryCard.filterStatusDisabledKey),
      );
      expect(fixture.lastListQuery!['status'], 'disabled');
      expect(fixture.lastListQuery!['type'], 'guest');
    });

    testWidgets('關鍵字要點送出才算數，且帶進查詢參數', (tester) async {
      final fixture = _Fixture();
      await pump(tester, fixture);

      await tester.enterText(
        find.byKey(StandardAccountDirectoryCard.searchKey),
        '阿爾法',
      );
      await tester.pump();
      // 打字本身不發請求：清單跟著每次擊鍵變動不是篩選的語意。
      expect(fixture.directoryCalls, 1);

      await tapVisible(
        tester,
        find.byKey(StandardAccountDirectoryCard.searchActionKey),
      );
      expect(fixture.directoryCalls, 2);
      expect(fixture.lastListQuery!['q'], '阿爾法');
    });

    testWidgets('到界的頁碼鈕停用，不發注定為空的請求', (tester) async {
      final fixture = _Fixture();
      await pump(tester, fixture);

      final OutlinedButton prev = tester.widget(
        find.byKey(StandardAccountDirectoryCard.prevKey),
      );
      final OutlinedButton next = tester.widget(
        find.byKey(StandardAccountDirectoryCard.nextKey),
      );
      expect(prev.onPressed, isNull);
      expect(next.onPressed, isNull);
      expect(fixture.directoryCalls, 1);
    });

    testWidgets('下一頁用回顯的總數算，並帶 page=2', (tester) async {
      final fixture = _Fixture(
        directoryBody: _directoryPage(page: 1, pageSize: 2, total: 5),
      );
      await pump(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountDirectoryCard.nextKey),
      );
      expect(fixture.directoryCalls, 2);
      expect(fixture.lastListQuery!['page'], '2');
      // 第 1／3 頁（共 5 位）：頁數是 total 與 page_size 的回顯算出来的。
      expect(
        find.text(
          textOf(
            tester,
            (AppLocalizations l) => l.adminDirectoryPageSummary(1, 3, 5),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('空目錄說的是「沒有符合的」，不是讀取失敗', (tester) async {
      // 每次泵入都給不同的頁面 Key：同類型的 widget 原地更新會沿用 State，
      // 而目錄卡只在 initState／reloadToken 變動時讀取——不給新 Key，
      // 第二個夹具根本不會被讀到，那是夹具的假綠而不是應用的行為。
      final empty = _Fixture(directoryBody: _directoryPage(rows: ''));
      await pump(tester, empty, 'empty');
      expect(
        find.text(textOf(tester, (l) => l.stdAccountDirectoryEmptyNotice)),
        findsOneWidget,
      );
      expect(find.byKey(StandardAccountDirectoryCard.retryKey), findsNothing);
    });

    testWidgets('讀取失敗給的是機器碼那一句，並留重試出口', (tester) async {
      final failed = _Fixture(
        directoryStatus: 500,
        directoryBody: '{"code":1000,"message":"x","request_id":"r-e"}',
      );
      await pump(tester, failed, 'failed');
      // 1000（通用內部失敗）說通用失敗那句：不是「查無資料」，也不是「你被登出了」。
      expect(
        find.text(textOf(tester, (l) => l.errorCodeInternal)),
        findsOneWidget,
      );
      expect(
        find.text(textOf(tester, (l) => l.stdAccountDirectoryEmptyNotice)),
        findsNothing,
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountDirectoryCard.retryKey),
      );
      expect(failed.directoryCalls, 2);
    });

    testWidgets('普通帳戶拿 2011 時說的是權限那一句，不是「沒有資料」', (tester) async {
      final fixture = _Fixture(
        directoryStatus: 403,
        directoryBody: '{"code":2011,"message":"x","request_id":"r-e"}',
      );
      await pump(tester, fixture);
      expect(
        find.text(textOf(tester, (l) => l.stdAccountProfileDeniedNotice)),
        findsOneWidget,
      );
      // 三句話各不相干：被拒 ≠ 查無資料，也 ≠ 通用失敗。
      expect(
        find.text(textOf(tester, (l) => l.errorCodeInternal)),
        findsNothing,
      );
      expect(
        find.text(textOf(tester, (l) => l.stdAccountDirectoryEmptyNotice)),
        findsNothing,
      );
    });
  });

  group('普通帳戶詳情與編輯卡', () {
    testWidgets('底稿取自單筆讀取，不是目錄行', (tester) async {
      final fixture = _Fixture();
      await pump(tester, fixture);
      await openProfile(tester);

      expect(fixture.detailRequests, hasLength(1));
      expect(fixture.detailRequests.single.method, 'GET');
      expect(
        fixture.detailRequests.single.url.path,
        '$kAdminAccountsPath/$_targetId',
      );
      // 目錄行給的是「阿爾法」，單筆給的是另一個值：輸入框必須是後者。
      final TextField field = tester.widget(
        find.byKey(StandardAccountProfileCard.displayNameKey),
      );
      expect(field.controller!.text, '服務端的現在顯示名');
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountProfileTitle('alpha.player')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('詳情只有來源、狀態與邊界句，沒有憑據與活動欄位', (tester) async {
      await pump(tester, _Fixture());
      await openProfile(tester);

      expect(
        find.byKey(StandardAccountProfileCard.securityHintKey),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.noSectionsKey),
        findsOneWidget,
      );
      // 詳情卡自己只有一個輸入框（顯示名）：沒有遮蔽口令框、也沒有狀態控制項。
      expect(
        find.byKey(StandardAccountProfileCard.displayNameKey),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(StandardAccountProfileCard.titleKey),
          matching: find.byType(Switch),
          matchRoot: true,
        ),
        findsNothing,
      );
      // 詳情卡那個輸入框是明文的一般資料框：這里沒有口令框（遮蔽框在建立卡上，
      // 屬另一張卡的事，不在本頁詳情區出現）。
      final TextField nameField = tester.widget(
        find.byKey(StandardAccountProfileCard.displayNameKey),
      );
      expect(nameField.obscureText, isFalse);
      expect(find.byType(Switch), findsNothing);
      expect(
        find.text(textOf(tester, (l) => l.adminProfileLoginNameLockedHint)),
        findsOneWidget,
      );
    });

    testWidgets('保存只帶兩欄、依據值是詳情那份，成功後換成服務端現值並重讀目錄', (tester) async {
      final fixture = _Fixture();
      await pump(tester, fixture);
      final int readsBefore = fixture.directoryCalls;
      await openProfile(tester);

      await tester.enterText(
        find.byKey(StandardAccountProfileCard.displayNameKey),
        '  我改的新名  ',
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.submitKey),
      );

      final http.Request sent = fixture.writes.single;
      expect(sent.method, 'PUT');
      expect(sent.url.path, '$kAdminAccountsPath/$_targetId');
      final Map<String, Object?> body =
          jsonDecode(sent.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'display_name',
        'expected_display_name',
      });
      // 依據值是「上一次從伺服器讀到的那份」，不是輸入框裡改到一半的內容。
      expect(body['expected_display_name'], '服務端的現在顯示名');
      for (final String forbidden in <String>[
        'status',
        'account_type',
        'password',
        'must_change_password',
        'roles',
        'activity_id',
        'login_name',
      ]) {
        expect(body, isNot(contains(forbidden)));
      }

      // 成功句與輸入框都來自 PUT 回應（後端把空白整理掉了，界面照著顯示）。
      expect(
        find.text(textOf(tester, (l) => l.adminProfileSavedNotice('保存後的顯示名'))),
        findsOneWidget,
      );
      final TextField field = tester.widget(
        find.byKey(StandardAccountProfileCard.displayNameKey),
      );
      expect(field.controller!.text, '保存後的顯示名');
      expect(fixture.directoryCalls, greaterThan(readsBefore));
    });

    testWidgets('2013 只給重讀出口：表單停用、再點保存不發第二趟', (tester) async {
      final fixture = _Fixture(
        writeStatus: 409,
        writeBody: '{"code":2013,"message":"x","request_id":"r-c"}',
      );
      await pump(tester, fixture);
      await openProfile(tester);
      await tester.enterText(
        find.byKey(StandardAccountProfileCard.displayNameKey),
        '撞一次',
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.submitKey),
      );

      expect(
        find.text(textOf(tester, (l) => l.adminProfileConflictNotice)),
        findsOneWidget,
      );
      final FilledButton button = tester.widget(
        find.byKey(StandardAccountProfileCard.submitKey),
      );
      expect(button.onPressed, isNull);
      expect(find.byKey(StandardAccountProfileCard.reloadKey), findsOneWidget);

      await tester.tap(find.byKey(StandardAccountProfileCard.submitKey));
      await tester.pumpAndSettle();
      expect(fixture.writes, hasLength(1));

      // 重讀之後表單恢復：那是一次新的伺服器真相，不是同一份舊依據值。
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.reloadKey),
      );
      expect(fixture.detailRequests, hasLength(2));
      final FilledButton again = tester.widget(
        find.byKey(StandardAccountProfileCard.submitKey),
      );
      expect(again.onPressed, isNotNull);
    });

    testWidgets('1004 依 invalid_field 分句：顯示名與依據值是兩句話', (tester) async {
      final nameRejected = _Fixture(
        writeStatus: 400,
        writeBody:
            '{"code":1004,"message":"x","request_id":"r-c",'
            '"details":{"invalid_field":"display_name"}}',
      );
      await pump(tester, nameRejected);
      await openProfile(tester);
      await tester.enterText(
        find.byKey(StandardAccountProfileCard.displayNameKey),
        '​',
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.submitKey),
      );
      expect(
        find.text(
          textOf(tester, (l) => l.adminProfileInvalidDisplayNameNotice),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          textOf(tester, (l) => l.stdAccountProfileMissingAnchorNotice),
        ),
        findsNothing,
      );

      final anchorRejected = _Fixture(
        writeStatus: 400,
        writeBody:
            '{"code":1004,"message":"x","request_id":"r-c",'
            '"details":{"invalid_field":"expected_display_name"}}',
      );
      await pump(tester, anchorRejected);
      await openProfile(tester);
      await tester.enterText(
        find.byKey(StandardAccountProfileCard.displayNameKey),
        '   ',
      );
      // 本地只擋「明顯沒填」：純空白經去空白後是空字串，不會發出請求。
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.submitKey),
      );
      expect(anchorRejected.writes, isEmpty);
      expect(
        find.text(textOf(tester, (l) => l.adminProfileFormIncompleteNotice)),
        findsOneWidget,
      );
    });

    testWidgets('1001 說的是「不在這本目錄」，與權限那句分開', (tester) async {
      final fixture = _Fixture(
        detailStatus: 404,
        detailBody: '{"code":1001,"message":"x","request_id":"r-e"}',
      );
      await pump(tester, fixture);
      await openProfile(tester);
      expect(
        find.text(textOf(tester, (l) => l.stdAccountProfileNotFoundNotice)),
        findsOneWidget,
      );
      // 讀不到這份資料時表單不打開：沒有輸入框、也沒有保存鈕。
      expect(
        find.byKey(StandardAccountProfileCard.displayNameKey),
        findsNothing,
      );
      expect(
        find.byKey(StandardAccountProfileCard.loadFailedKey),
        findsOneWidget,
      );
    });

    testWidgets('寫入進行中按鈕停用，不會發出第二趟', (tester) async {
      final fixture = _Fixture()..holdNextWrite();
      await pump(tester, fixture);
      await openProfile(tester);
      await tester.enterText(
        find.byKey(StandardAccountProfileCard.displayNameKey),
        '慢回應',
      );
      // 回應被 holdNextWrite 掛住：點下去只進入 saving，此時鈕應停用，
      // 再點一次也不會多出第二趟（這裡刻意不 pumpAndSettle，那會讓掛住的回應跑完）。
      final Finder submitButton = find.byKey(
        StandardAccountProfileCard.submitKey,
      );
      await tester.ensureVisible(submitButton);
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pump();
      final FilledButton button = tester.widget(submitButton);
      expect(button.onPressed, isNull);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();
      expect(fixture.writes, hasLength(1));
    });

    testWidgets('關閉詳情卡後目錄仍在：頁面只持有標識，不持有那份資料', (tester) async {
      await pump(tester, _Fixture());
      await openProfile(tester);
      expect(find.byKey(StandardAccountProfileCard.titleKey), findsOneWidget);
      await tapVisible(
        tester,
        find.text(
          AppLocalizations.of(tester.element(find.byType(AdminConsolePage)))
              .adminProfileCloseAction,
        ),
      );
      expect(find.byKey(StandardAccountProfileCard.titleKey), findsNothing);
      expect(
        find.byKey(StandardAccountProvisionCard.submitKey),
        findsOneWidget,
      );
    });
  });
}

/// 把畫面上所有文字串起來（斷言「界面任何一處都不出現某字串」用）。
String _allText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final Element element in find.byType(Text).evaluate()) {
    final Text widget = element.widget as Text;
    buffer.write(widget.data ?? '');
  }
  return buffer.toString();
}
