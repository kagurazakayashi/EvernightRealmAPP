/// 管理員端「註冊申請審批」的介面測試。
///
/// 全部走注入的假傳輸：不碰網路、不落任何憑據。這一檔問的是幾件事：
///   1. 按鈕只由服務端讀回的狀態決定：pending 才有那兩顆，rejected 只有一句實話，
///      表外值一顆都不擺；
///   2. 確認對話框點名目標、講完落下什麼與四件不會發生的事；取消是一條正經出路
///      （一請求都不發，畫面停在上一份伺服器真相）；
///   3. 本體只有 decision 一欄，沒有依據值、沒有角色、也沒有理由或備註的格子；
///   4. 成功句的主詞與狀態一律換成 PUT 回應，並觸發名冊重讀（批准之後那行該消失）；
///   5. 2021 另成一句，而且只給「重新讀取名冊」這一個出口——不會自動補發決定；
///   6. 1001／2011／2002 各自成句，互不冒充；
///   7. 寫入進行中兩顆按鈕停用，連點只發一趟；
///   8. 這頁不顯示口令、憑據、審核人或理由，也不宣稱已發通知（本伺服器沒有通知模組）。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/admin_console_page.dart';
import 'package:evernightrealm/features/admin/registration_review_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

/// 申請標識（隨機 UUIDv7 形態，不是任何環境的真實資料）。
const String _appId = '01a0f000-0000-7000-8000-0000000000a1';
const String _otherId = '01a0f000-0000-7000-8000-0000000000b2';

/// 一行申請；`withDecision` 帶決定時刻（rejected 的行合同如此）。
String _row(
  String id,
  String login,
  String status, {
  bool withDecision = false,
}) {
  final String reviewed = withDecision
      ? ',"reviewed_at":"2026-10-07T09:30:00.000Z"'
      : '';
  return '{"account_id":"$id","login_name":"$login","display_name":"顯示名 $login",'
      '"status":"$status","submitted_at":"2026-10-07T08:00:00.000Z"$reviewed}';
}

/// 名冊一頁。
String _roster(String rows, {int total = 1, int page = 1, int pageSize = 20}) {
  return '{"applications":[$rows],"page":$page,"page_size":$pageSize,'
      '"total":$total,"request_id":"r-roster"}';
}

/// 普通帳戶目錄一頁（同一張管理端頁面裡另一本名冊；這裡讓它恆為空）。
const String _emptyDirectory =
    '{"accounts":[],"page":1,"page_size":20,"total":0,"request_id":"r-dir"}';

/// 決定成功的回應：application 是變更後的現值。
String _decisionReport(String status, String decision, String login) {
  return '{"application":{"account_id":"$_appId","login_name":"$login",'
      '"display_name":"顯示名 $login","status":"$status",'
      '"submitted_at":"2026-10-07T08:00:00.000Z",'
      '"reviewed_at":"2026-10-07T09:30:00.000Z"},'
      '"decision":"$decision","request_id":"r-decision"}';
}

/// 依路徑與方法分流的一臺假後端。
class _Fixture {
  /// 名冊第一次讀到的行（呼叫端可換成任意狀態組合）。
  _Fixture({
    this.firstRows = 'pending',
    this.decisionResult = 'approve',
    this.decisionResultStatus = 'active',
  });

  /// 首次讀取名冊的狀態：`pending`／`rejected`／`mixed`／`unknown`／`empty`。
  final String firstRows;

  /// 決定寫入的 HTTP 狀態與信封機器碼（默認 200 成功）。
  int decisionStatus = 200;
  int decisionCode = 2021;

  /// 決定成功時服務端說的狀態與落地的那個決定。
  final String decisionResult;
  final String decisionResultStatus;

  /// 名冊讀取失敗的 HTTP 狀態與機器碼（狀態 0 表示讀取成功）。
  int rosterFailureStatus = 0;
  int rosterFailureCode = 2011;

  /// 讓下一趟決定寫入延後（斷言「進行中連點只發一趟」用）。
  bool holdNextDecision = false;

  /// 名冊讀取趟數（成功後重讀的證據）。
  int rosterCalls = 0;

  /// 決定端點收過的請求。
  final List<http.Request> decisions = <http.Request>[];

  String get _initialRows {
    return switch (firstRows) {
      'pending' => _row(_appId, 'night.applicant', 'pending'),
      'rejected' => _row(
        _appId,
        'night.applicant',
        'rejected',
        withDecision: true,
      ),
      'mixed' => <String>[
        _row(_appId, 'night.applicant', 'pending'),
        _row(_otherId, 'already.declined', 'rejected', withDecision: true),
      ].join(','),
      'two-pending' => <String>[
        _row(_appId, 'first.applicant', 'pending'),
        _row(_otherId, 'second.applicant', 'pending'),
      ].join(','),
      'unknown' => _row(_appId, 'odd.status', 'waitlisted'),
      _ => '',
    };
  }

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        if (path == kAdminAccountsPath) {
          // 同頁的另一本名冊：恆為空，免得斷言被它的行列染到。
          return _reply(200, _emptyDirectory);
        }
        if (path == kAdminRegistrationsPath && request.method == 'GET') {
          rosterCalls++;
          if (rosterFailureStatus != 0) {
            return _reply(
              rosterFailureStatus,
              '{"code":$rosterFailureCode,"message":"failed",'
              '"request_id":"r-fail"}',
            );
          }
          // 批准成功後該行離開這本書：決定落地起回空名冊。
          final String rows = decisions.isEmpty || decisionStatus != 200
              ? _initialRows
              : '';
          final int total = rows.isEmpty ? 0 : (firstRows == 'mixed' ? 2 : 1);
          return _reply(200, _roster(rows, total: total));
        }
        if (path.endsWith('/decision')) {
          decisions.add(request);
          if (holdNextDecision) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            holdNextDecision = false;
          }
          if (decisionStatus != 200) {
            return _reply(
              decisionStatus,
              '{"code":$decisionCode,"message":"failed","request_id":"r-fail"}',
            );
          }
          return _reply(
            200,
            _decisionReport(
              decisionResultStatus,
              decisionResult,
              'night.applicant',
            ),
          );
        }
        return _reply(
          404,
          '{"code":1001,"message":"nope","request_id":"r-404"}',
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

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder keyFinder(Key key) => find.byKey(key);

  group('名冊列什麼、不列什麼', () {
    testWidgets('審批卡接進管理端頁面，並自帶一句影響範圍說明', (WidgetTester tester) async {
      await pump(tester, _Fixture());
      expect(find.byType(RegistrationReviewCard), findsOneWidget);
      expect(keyFinder(RegistrationReviewCard.scopeHintKey), findsOneWidget);
      expect(
        find.textContaining('批准只給「能登入」這一件事', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('待審批那一行有兩顆按鈕；被拒絕的那一行一顆都沒有', (WidgetTester tester) async {
      await pump(tester, _Fixture(firstRows: 'mixed'));
      expect(
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
        findsOneWidget,
      );
      expect(
        keyFinder(RegistrationReviewCard.rejectKey(_appId)),
        findsOneWidget,
      );
      expect(
        keyFinder(RegistrationReviewCard.approveKey(_otherId)),
        findsNothing,
      );
      expect(
        keyFinder(RegistrationReviewCard.rejectKey(_otherId)),
        findsNothing,
      );
      expect(
        keyFinder(RegistrationReviewCard.rejectedNoteKey(_otherId)),
        findsOneWidget,
      );
      // 那句要講實話：沒有改判通路，而登入名仍被佔用。
      expect(
        find.textContaining('本版本沒有改判的通路', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('表外狀態不擺按鈕，也不猜成「還在等」或「已批准」', (WidgetTester tester) async {
      await pump(tester, _Fixture(firstRows: 'unknown'));
      expect(
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
        findsNothing,
      );
      expect(keyFinder(RegistrationReviewCard.rejectKey(_appId)), findsNothing);
      expect(find.textContaining('認不得的狀態', findRichText: true), findsOneWidget);
    });

    testWidgets('決定時刻只在有決定時出現：等待中的那一行沒有「決定於」', (WidgetTester tester) async {
      await pump(tester, _Fixture(firstRows: 'pending'));
      expect(find.textContaining('提交於：', findRichText: true), findsOneWidget);
      expect(find.textContaining('決定於：', findRichText: true), findsNothing);

      await pump(tester, _Fixture(firstRows: 'rejected'), 'with-decision');
      expect(find.textContaining('決定於：', findRichText: true), findsOneWidget);
    });

    testWidgets('這一頁只有關鍵字那一格文字輸入：沒有理由、備註、口令或角色控件', (WidgetTester tester) async {
      await pump(tester, _Fixture(firstRows: 'mixed'));
      final Finder card = find.byType(RegistrationReviewCard);
      // 審批卡自己只擺一個 TextField（搜尋框）：界面不準備任何「填了也不會落庫」的格子。
      final Finder fields = find.descendant(
        of: card,
        matching: find.byType(TextField),
      );
      expect(fields, findsOneWidget);
      // 那一格的標籤是搜尋，不是理由、備註或口令——這條釘的是「內部備註與可公開理由
      // 都不落庫」在界面上的形態：連一個可填的位置都沒有。
      final TextField search = tester.widget<TextField>(fields);
      final String label = search.decoration?.labelText ?? '';
      expect(label, isNotEmpty);
      for (final String forbidden in <String>['理由', '備註', '口令', '角色']) {
        expect(
          label.contains(forbidden),
          isFalse,
          reason: '$forbidden 不該是一格輸入',
        );
      }
      expect(
        find.descendant(
          of: card,
          matching: find.byType(DropdownButton<String>),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.byType(Switch)),
        findsNothing,
      );
    });

    testWidgets('空名冊那句說明如實講「切模式不動歷史」，不假裝沒人申請過', (WidgetTester tester) async {
      await pump(tester, _Fixture(firstRows: 'empty'));
      expect(keyFinder(RegistrationReviewCard.emptyKey), findsOneWidget);
      expect(
        find.textContaining('切換自註冊模式不會讓已經交上來的申請消失', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('狀態篩選各發一趟帶 status 的讀取，切回全部也照發', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      final int before = fixture.rosterCalls;
      expect(before, 1);

      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.filterPendingKey),
      );
      expect(fixture.rosterCalls, before + 1);

      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.filterRejectedKey),
      );
      expect(fixture.rosterCalls, before + 2);

      await tapVisible(tester, keyFinder(RegistrationReviewCard.filterAllKey));
      expect(fixture.rosterCalls, before + 3);
    });

    testWidgets('打字本身不發請求；換關鍵字才發一趟，退回空白等價於不篩選', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      final int before = fixture.rosterCalls;

      await tester.enterText(keyFinder(RegistrationReviewCard.searchKey), '山夜');
      await tester.pumpAndSettle();
      expect(fixture.rosterCalls, before, reason: '打字不該發請求');

      // 送出真正不一樣的關鍵字：這才是「我要按這個詞篩一次」。
      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.searchActionKey),
      );
      expect(fixture.rosterCalls, before + 1);

      // 全空白送出等價於「不篩選」，與上一次已送出的實值不同 → 該發一趟；
      // 同一份空白再送出一次就沒什麼可重發的了（不讓清單閃一下）。
      await tester.enterText(
        keyFinder(RegistrationReviewCard.searchKey),
        '   ',
      );
      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.searchActionKey),
      );
      expect(fixture.rosterCalls, before + 2);
      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.searchActionKey),
      );
      expect(fixture.rosterCalls, before + 2);
    });
  });

  group('確認、提交與回顯', () {
    testWidgets('確認對話框點名目標並講完四件不會發生的事', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('night.applicant', findRichText: true),
        findsWidgets,
      );
      for (final String promise in <String>[
        '不帶任何伺服器級角色',
        '不簽發任何會話',
        '不是解除停用',
        '事後無法改判',
      ]) {
        expect(
          find.textContaining(promise, findRichText: true),
          findsWidgets,
          reason: '確認句要講到 $promise',
        );
      }
    });

    testWidgets('取消是一條正經出路：一請求都不發，畫面停在上一份伺服器真相', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
      );
      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.confirmCancelKey),
      );
      expect(fixture.decisions, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
        findsOneWidget,
      );
      expect(
        keyFinder(RegistrationReviewCard.decisionFailureKey),
        findsNothing,
      );
      expect(keyFinder(RegistrationReviewCard.decisionNoticeKey), findsNothing);
    });

    testWidgets('批准：恰一趟 PUT、本體只有 decision，成功句與名冊都換成服務端結果', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      final int readsBefore = fixture.rosterCalls;

      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
      );
      await tapVisible(tester, keyFinder(RegistrationReviewCard.confirmKey));

      expect(fixture.decisions, hasLength(1));
      final http.Request request = fixture.decisions.single;
      expect(request.method, 'PUT');
      expect(request.url.path.endsWith('/decision'), isTrue);
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'decision'});
      expect(body['decision'], 'approve');

      // 成功句的主詞取 PUT 回應，並明說「沒有替他登入、也沒有通知」。
      expect(
        find.textContaining('已批准：night.applicant', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('這台伺服器至今還沒有通知模組', findRichText: true),
        findsOneWidget,
      );
      // 批准之後那行離開這本書：界面重讀服務端名冊，而不是本地把它藏起來。
      expect(fixture.rosterCalls, readsBefore + 1);
      expect(
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
        findsNothing,
      );
      expect(keyFinder(RegistrationReviewCard.emptyKey), findsOneWidget);
    });

    testWidgets('拒絕：送出的是 reject，成功句是拒絕那句而不是批准那句', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(
        decisionResult: 'reject',
        decisionResultStatus: 'rejected',
      );
      await pump(tester, fixture);
      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.rejectKey(_appId)),
      );
      await tapVisible(tester, keyFinder(RegistrationReviewCard.confirmKey));

      final Map<String, Object?> body =
          jsonDecode(fixture.decisions.single.body) as Map<String, Object?>;
      expect(body['decision'], 'reject');
      expect(
        find.textContaining('已拒絕：night.applicant', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('已批准：', findRichText: true), findsNothing);
    });

    testWidgets('寫入進行中：同一頁不並發兩條決定，另一筆目標的按鈕停用', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture(firstRows: 'two-pending')
        ..holdNextDecision = true;
      await pump(tester, fixture);
      expect(
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
        findsOneWidget,
      );
      expect(
        keyFinder(RegistrationReviewCard.approveKey(_otherId)),
        findsOneWidget,
      );

      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
      );
      // 按下確認後先不 settle：讓那一趟 PUT 停在飛行中，界面才斷言得出「正在提交」的形態。
      await tester.tap(keyFinder(RegistrationReviewCard.confirmKey));
      await tester.pump();
      final FilledButton stillPending = tester.widget<FilledButton>(
        keyFinder(RegistrationReviewCard.approveKey(_otherId)),
      );
      expect(stillPending.onPressed, isNull, reason: '一趟決定還在飛行中，不該能並發第二趟');
      // 同一筆目標的另一顆按鈕也一起停用：批准與拒絕是同一格決定的兩個寫法，
      // 並發送出就會出現「兩個人各按一次、兩個決定都想落地」。
      final OutlinedButton ownReject = tester.widget<OutlinedButton>(
        keyFinder(RegistrationReviewCard.rejectKey(_appId)),
      );
      expect(ownReject.onPressed, isNull);
      await tester.pumpAndSettle();
      expect(fixture.decisions, hasLength(1));
    });

    testWidgets('2021 另成一句、只給重讀出口，且不會自動補發決定', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()..decisionStatus = 409;
      await pump(tester, fixture);
      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
      );
      await tapVisible(tester, keyFinder(RegistrationReviewCard.confirmKey));

      expect(
        find.textContaining('這份申請已經有過決定', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('沒有覆蓋先前那個決定', findRichText: true),
        findsOneWidget,
      );
      expect(keyFinder(RegistrationReviewCard.reloadKey), findsOneWidget);
      expect(fixture.decisions, hasLength(1));

      await tapVisible(tester, keyFinder(RegistrationReviewCard.reloadKey));
      expect(fixture.decisions, hasLength(1), reason: '重讀不該把決定再發一次');
      expect(fixture.rosterCalls, greaterThan(1));
    });

    testWidgets('1001、2011 與表外的衝突碼各自成句，互不冒充', (WidgetTester tester) async {
      final List<(int, int, String)> cases = <(int, int, String)>[
        (404, 1001, '不在這本名冊裡'),
        (403, 2011, '沒有伺服器級管理權限'),
        (409, 2014, '這名管理員的登入狀態'),
      ];
      for (final (int status, int code, String expectText) in cases) {
        final _Fixture fixture = _Fixture()
          ..decisionStatus = status
          ..decisionCode = code;
        await pump(tester, fixture, 'p-$code');
        await tapVisible(
          tester,
          keyFinder(RegistrationReviewCard.approveKey(_appId)),
        );
        await tapVisible(tester, keyFinder(RegistrationReviewCard.confirmKey));
        expect(
          keyFinder(RegistrationReviewCard.decisionFailureKey),
          findsOneWidget,
        );
        expect(
          find.textContaining(expectText, findRichText: true),
          findsWidgets,
          reason: '碼 $code 該落到「$expectText」這一句',
        );
        // 「已有決定」那句與它唯一的重讀出口只屬於 2021，不被其他結論借用。
        expect(
          find.textContaining('這份申請已經有過決定', findRichText: true),
          findsNothing,
        );
        expect(keyFinder(RegistrationReviewCard.reloadKey), findsNothing);
      }
    });

    testWidgets('名冊讀不到時按機器碼分流，並留一顆重試鈕', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()..rosterFailureStatus = 403;
      await pump(tester, fixture);
      expect(keyFinder(RegistrationReviewCard.failedKey), findsOneWidget);
      expect(
        find.textContaining('沒有伺服器級管理權限', findRichText: true),
        findsOneWidget,
      );
      await tapVisible(tester, keyFinder(RegistrationReviewCard.retryKey));
      expect(fixture.rosterCalls, 2);
    });

    testWidgets('會話失效那一簇說「重新登入」，不說「你沒有權限」', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture()
        ..rosterFailureStatus = 401
        ..rosterFailureCode = 2003;
      await pump(tester, fixture);
      expect(
        find.textContaining('請重新登入後再試', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('沒有伺服器級管理權限', findRichText: true),
        findsNothing,
      );
    });
  });

  group('這一頁不是一個認證入口', () {
    testWidgets('決定回應裡沒有任何會話材料，界面也不因此變成已登入', (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      await pump(tester, fixture);
      await tapVisible(
        tester,
        keyFinder(RegistrationReviewCard.approveKey(_appId)),
      );
      await tapVisible(tester, keyFinder(RegistrationReviewCard.confirmKey));

      // 送出去的請求不帶任何「我替他換一枚憑據」的欄位；回應本體也沒有會話欄。
      expect(fixture.decisions.single.body.contains('session'), isFalse);
      expect(fixture.decisions.single.body.contains('token'), isFalse);
      final String pageText =
          (tester
                  .widgetList(find.byType(Text))
                  .map((Widget widget) => (widget as Text).data ?? '')
                  .toList())
              .join('\n');
      for (final String forbidden in <String>[
        'argon2id',
        'password_hash',
        'token',
      ]) {
        expect(pageText.contains(forbidden), isFalse);
      }
      // 成功句如實說「沒有替他登入」。
      expect(
        find.textContaining('這一頁沒有替他登入', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
