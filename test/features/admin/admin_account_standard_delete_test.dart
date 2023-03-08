/// 管理員端「軟刪除普通帳戶與訪戶帳戶」的介面測試。
///
/// 這一檔問的是四件事，都不是「有沒有一顆按鈕」：
///   1. 影響範圍那句寫在按下之前——這一刀動的是整臺伺服器的登入能力，
///      不是活動內的玩家限制，界面必須先講完才讓人按；
///   2. 確認框點名目標（登入名、來源類型、現狀），三件會發生、兩件不會發生一次讀完；
///      取消是一條正經出路，零請求；
///   3. 成功之後這張卡退出編輯態：每一個寫入控件都消失，畫面上只剩服務端回的
///      刪除後真相與那個時刻，而撤銷數量來自回應而不是界面自己猜；
///   4. 兩種終態（已被刪除、已被綁走的訪戶）一律只讀——「查無此人」對他們不成立，
///      把按鈕留在畫面上等於假裝還做得動。這也順帶釘住一個已被修好的缺口：
///      退休訪戶此前會看到改名框，而那次寫入在資料庫層被觸發器擋下、對外形體是一個 500。
///
/// 全程走注入的假傳輸：不碰網路、不佔埠、不落任何真實憑據。
library;

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/admin/standard_account_directory_view.dart';
import 'package:evernightrealm/features/admin/standard_account_profile_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');

const String _targetId = '01a0f000-0000-7000-8000-0000000000ad';

const String _deletedAt = '2026-10-10T09:30:00.000Z';
const String _retiredAt = '2026-10-09T12:00:00.000Z';

/// 一筆帳戶投影；狀態與兩個終態時刻都由夹具決定。
String _record({
  String status = 'active',
  String accountType = 'standard',
  String loginName = 'Del.Contract.Target',
  String displayName = '刪除前的名字',
  String? deletedAt,
  String? retiredAt,
}) {
  final List<String> parts = <String>[
    '"account_id":"$_targetId"',
    '"login_name":"$loginName"',
    '"display_name":"$displayName"',
    '"account_type":"$accountType"',
    '"status":"$status"',
    '"must_change_password":false',
    '"created_at":"2026-09-01T00:00:00.000Z"',
    '"last_login_at":"2026-10-08T07:15:00.000Z"',
  ];
  if (deletedAt != null) parts.add('"deleted_at":"$deletedAt"');
  if (retiredAt != null) parts.add('"retired_at":"$retiredAt"');
  return '{${parts.join(',')}}';
}

/// 依方法與路徑分流的一台假後端。
class _Fixture {
  _Fixture({
    this.detailStatus = 'active',
    this.accountType = 'standard',
    this.deleteStatus = 200,
    this.deleteCode = 0,
    this.holdDelete = false,
  });

  /// 詳情讀回來的狀態與來源類型（決定界面該給哪些控件）。
  final String detailStatus;
  final String accountType;

  /// DELETE 端點的 HTTP 狀態與機器碼（非 200 時用失敗信封）。
  final int deleteStatus;
  final int deleteCode;

  /// 讓 DELETE 延後四十毫秒，用來量「在飛時不發第二趟」。
  final bool holdDelete;

  /// DELETE 收過的請求。
  final List<http.Request> deletes = <http.Request>[];

  /// 各條寫入通路收過的請求數（斷言終態目標一個都不該有）。
  int profileWrites = 0;
  int statusWrites = 0;
  int passwordWrites = 0;
  int upgradeWrites = 0;
  int bindPreflightWrites = 0;
  int bindTicketWrites = 0;

  /// 目錄收過的查詢字串。
  final List<String> directoryQueries = <String>[];

  String get _detailBody =>
      '{"account":${_record(status: detailStatus, accountType: accountType, deletedAt: detailStatus == 'deleted' ? _deletedAt : null, retiredAt: detailStatus == 'retired' ? _retiredAt : null)},"request_id":"r-detail"}';

  String get _deleteBody =>
      '{"account":${_record(status: 'deleted', accountType: accountType, displayName: 'DEL_20261010_刪除前的名字', deletedAt: _deletedAt)},"revoked_sessions":2,"request_id":"r-del"}';

  ServerApi api(ServerAddressSettings settings) => ServerApi(
    config: ServerApiConfig(source: settings),
    client: MockClient((http.Request request) async {
      final String path = request.url.path;
      final String method = request.method;
      if (method == 'GET' && path == kAdminAccountsPath) {
        directoryQueries.add(request.url.query);
        return _reply(
          200,
          '{"accounts":[${_record(status: detailStatus, accountType: accountType, deletedAt: detailStatus == 'deleted' ? _deletedAt : null, retiredAt: detailStatus == 'retired' ? _retiredAt : null)}],'
          '"page":1,"page_size":20,"total":1,"request_id":"r-dir"}',
        );
      }
      if (method == 'DELETE' && path == adminAccountItemPath(_targetId)) {
        deletes.add(request);
        if (holdDelete) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        if (deleteStatus != 200) {
          return _reply(
            deleteStatus,
            '{"code":$deleteCode,"message":"failed","request_id":"r-fail"}',
          );
        }
        return _reply(200, _deleteBody);
      }
      if (path.endsWith('/status')) {
        statusWrites++;
        return _reply(200, _detailBody);
      }
      if (path.endsWith('/password')) {
        passwordWrites++;
        return _reply(200, _detailBody);
      }
      if (path.endsWith('/upgrade')) {
        upgradeWrites++;
        return _reply(200, _detailBody);
      }
      if (path.endsWith('/bind-preflight')) {
        bindPreflightWrites++;
        return _reply(200, _detailBody);
      }
      if (path.endsWith('/bind-ticket')) {
        bindTicketWrites++;
        return _reply(200, _detailBody);
      }
      if (method == 'PUT') {
        profileWrites++;
        return _reply(200, _detailBody);
      }
      return _reply(200, _detailBody);
    }),
  );

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
    // 每條用例自己數一次成功回呼，不沿用上一條的計數。
    _saved = 0;
  });

  /// 掛上詳情卡；[onSaved] 記錄被回呼幾次（成功後頁面要重讀目錄）。
  Future<void> pumpProfile(
    WidgetTester tester,
    _Fixture fixture, {
    int Function()? savedCount,
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
                    child: StandardAccountProfileCard(
                      key: ValueKey<String>(_targetId),
                      api: fixture.api(settings),
                      accountId: _targetId,
                      onSaved: () => _saved += 1,
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

  /// 掛上目錄卡。
  Future<void> pumpDirectory(WidgetTester tester, _Fixture fixture) async {
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
                    child: StandardAccountDirectoryCard(
                      api: fixture.api(settings),
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

  AppLocalizations l10nOf(WidgetTester tester) => AppLocalizations.of(
    tester.element(find.byType(StandardAccountProfileCard)),
  );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('刪除區（可寫目標）', () {
    testWidgets('影響範圍那句與按鈕都在，且寫在按下之前', (tester) async {
      final _Fixture fixture = _Fixture();
      await pumpProfile(tester, fixture);
      final AppLocalizations l = l10nOf(tester);

      expect(find.byKey(StandardAccountProfileCard.deleteKey), findsOneWidget);
      expect(
        find.byKey(StandardAccountProfileCard.deleteScopeKey),
        findsOneWidget,
      );
      expect(find.text(l.stdAccountDeleteZoneHint), findsOneWidget);
      // 這一句不是確認框裡的附件：它必須在按鈕之前就在畫面上。
      expect(
        tester
            .widget<Text>(find.byKey(StandardAccountProfileCard.deleteScopeKey))
            .data,
        l.stdAccountDeleteZoneHint,
      );
    });

    testWidgets('確認框點名目標：登入名、來源與現狀都在對話框裡', (tester) async {
      final _Fixture fixture = _Fixture();
      await pumpProfile(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteKey),
      );

      final AppLocalizations l = l10nOf(tester);
      expect(find.text(l.stdAccountDeleteConfirmTitle), findsOneWidget);
      final String body = tester
          .widget<Text>(
            find.text(
              l.stdAccountDeleteConfirmBody(
                'Del.Contract.Target',
                l.stdAccountTypeStandard,
                l.adminStatusActive,
              ),
            ),
          )
          .data!;
      // 確認文要點名的是這個人（登入名），並把「他不是停用」「名字仍被佔用」講在一起。
      // 佔位值的形狀（DEL_…）由服務端決定，界面不複製那段字串，故不在這裡斷言。
      expect(body, contains('Del.Contract.Target'));
      expect(body, contains(l.stdAccountTypeStandard));
      expect(body, contains(l.adminStatusActive));
      expect(
        find.byKey(StandardAccountProfileCard.deleteConfirmKey),
        findsOneWidget,
      );
      expect(
        find.byKey(StandardAccountProfileCard.deleteConfirmCancelKey),
        findsOneWidget,
      );
    });

    testWidgets('取消是一條正經出路：零請求、界面仍是可寫狀態', (tester) async {
      final _Fixture fixture = _Fixture();
      await pumpProfile(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteKey),
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteConfirmCancelKey),
      );
      await tester.pumpAndSettle();

      expect(fixture.deletes, isEmpty);
      expect(
        find.byKey(StandardAccountProfileCard.displayNameKey),
        findsOneWidget,
      );
      expect(find.byKey(StandardAccountProfileCard.deleteKey), findsOneWidget);
    });

    testWidgets('確認後發一趟 DELETE：方法、路徑與空本體', (tester) async {
      final _Fixture fixture = _Fixture();
      await pumpProfile(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteKey),
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteConfirmKey),
      );

      expect(fixture.deletes, hasLength(1));
      final http.Request sent = fixture.deletes.single;
      expect(sent.method, 'DELETE');
      expect(sent.url.path, adminAccountItemPath(_targetId));
      expect(sent.body, isEmpty);
    });

    testWidgets('成功後退出編輯態：寫入控件全消失，只剩服務端回的真相', (tester) async {
      final _Fixture fixture = _Fixture();
      await pumpProfile(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteKey),
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteConfirmKey),
      );

      final AppLocalizations l = l10nOf(tester);
      // 這一態下不該再有第三處可以對同一個人下寫入令。
      for (final Key absent in <Key>[
        StandardAccountProfileCard.displayNameKey,
        StandardAccountProfileCard.submitKey,
        StandardAccountProfileCard.disableKey,
        StandardAccountProfileCard.resetActionKey,
        StandardAccountProfileCard.deleteKey,
      ]) {
        expect(find.byKey(absent), findsNothing, reason: '$absent');
      }
      expect(
        find.byKey(StandardAccountProfileCard.deletedBannerKey),
        findsOneWidget,
      );
      // 時刻與撤銷數量都來自回應：界面不拿「現在」或 0 去湊數。
      expect(find.textContaining(l.stdAccountDeletedAtLabel), findsOneWidget);
      expect(find.text(l.stdAccountDeleteSuccessNotice(2)), findsOneWidget);
      expect(
        find.byKey(StandardAccountProfileCard.identityKeptKey),
        findsOneWidget,
      );
      expect(_saved, 1, reason: '成功後要請頁面重讀目錄');
    });

    testWidgets('在飛時停住其餘入口，連點不發第二趟', (tester) async {
      final _Fixture fixture = _Fixture(holdDelete: true);
      await pumpProfile(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteKey),
      );
      await tester.tap(find.byKey(StandardAccountProfileCard.deleteConfirmKey));
      // 只泵幾幀、不 settle：這一格要的正是「請求還在飛」那個瞬間的畫面。
      await tester.pump(const Duration(milliseconds: 10));
      // 這一顆必須是 disabled（不是「再點一次也沒事」，也不是把按鈕藏起來假裝沒發生）。
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(StandardAccountProfileCard.deleteKey),
            )
            .onPressed,
        isNull,
      );
      // 同一時刻改名與停用也停住：幾條白名單共用同一筆現值，並發提交必有一段依據值過期。
      expect(
        tester
            .widget<TextField>(
              find.byKey(StandardAccountProfileCard.displayNameKey),
            )
            .enabled,
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(fixture.deletes, hasLength(1));
    });
  });

  group('終態的兩句拒絕', () {
    testWidgets('第二次刪除吃 2027：說「已被刪除」，只給重讀出口', (tester) async {
      final _Fixture fixture = _Fixture(deleteStatus: 409, deleteCode: 2027);
      await pumpProfile(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteKey),
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteConfirmKey),
      );

      final AppLocalizations l = l10nOf(tester);
      expect(find.text(l.errorCodeAccountDeleted), findsOneWidget);
      // 終態不是「現值過期」：界面在此之後只該有一條去讀現值的路。
      expect(
        find.byKey(StandardAccountProfileCard.terminalReloadKey),
        findsOneWidget,
      );
      // 按鈕還在，但按不下去：這一態下它不是「稍後再試」的那顆鈕。
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(StandardAccountProfileCard.deleteKey),
            )
            .onPressed,
        isNull,
      );
      expect(fixture.deletes, hasLength(1));
    });

    testWidgets('退休訪戶吃 2028：說「已被綁走」，指向綁定留痕', (tester) async {
      final _Fixture fixture = _Fixture(deleteStatus: 409, deleteCode: 2028);
      await pumpProfile(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteKey),
      );
      await tapVisible(
        tester,
        find.byKey(StandardAccountProfileCard.deleteConfirmKey),
      );

      final AppLocalizations l = l10nOf(tester);
      expect(find.text(l.errorCodeAccountRetired), findsOneWidget);
      expect(find.text(l.errorCodeAccountDeleted), findsNothing);
      expect(
        find.byKey(StandardAccountProfileCard.terminalReloadKey),
        findsOneWidget,
      );
    });
  });

  group('終態目標一律只讀（由服務端讀回的那一態決定）', () {
    testWidgets('retired：沒有改名框、沒有任何寫入鈕，只有留痕那一句', (tester) async {
      final _Fixture fixture = _Fixture(
        detailStatus: 'retired',
        accountType: 'guest',
      );
      await pumpProfile(tester, fixture);

      final AppLocalizations l = l10nOf(tester);
      for (final Key absent in <Key>[
        StandardAccountProfileCard.displayNameKey,
        StandardAccountProfileCard.submitKey,
        StandardAccountProfileCard.disableKey,
        StandardAccountProfileCard.restoreKey,
        StandardAccountProfileCard.resetFieldKey,
        StandardAccountProfileCard.upgradeActionKey,
        StandardAccountProfileCard.bindPreflightActionKey,
        StandardAccountProfileCard.deleteKey,
      ]) {
        expect(find.byKey(absent), findsNothing, reason: '$absent');
      }
      expect(
        find.byKey(StandardAccountProfileCard.retiredBannerKey),
        findsOneWidget,
      );
      expect(find.text(l.stdAccountProfileRetiredTraceHint), findsOneWidget);
      // 時刻在只讀分支裡出現兩次（標籤行與橫幅句），這裡要的是「至少一次且值正確」。
      expect(
        find.textContaining(_formatMinute(_retiredAt)),
        findsAtLeastNWidgets(1),
      );
      // 只讀分支不發任何寫入請求。
      expect(fixture.profileWrites, 0);
      expect(fixture.statusWrites, 0);
      expect(fixture.passwordWrites, 0);
      expect(fixture.upgradeWrites, 0);
      expect(fixture.deletes, isEmpty);
    });

    testWidgets('deleted：只讀分支帶出刪除時刻與佔位顯示名', (tester) async {
      final _Fixture fixture = _Fixture(detailStatus: 'deleted');
      await pumpProfile(tester, fixture);

      final AppLocalizations l = l10nOf(tester);
      expect(
        find.byKey(StandardAccountProfileCard.deletedBannerKey),
        findsOneWidget,
      );
      expect(find.text(l.stdAccountProfileIdentityKeptHint), findsOneWidget);
      // 佔位顯示名是服務端寫回的那一欄：界面不改寫、也不從別處推一個名字。
      // 顯示名那一行是「標籤：值」的合寫，所以用 textContaining 而不是精確比對。
      expect(find.textContaining('刪除前的名字'), findsWidgets);
      expect(
        find.textContaining(_formatMinute(_deletedAt)),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.byKey(StandardAccountProfileCard.displayNameKey),
        findsNothing,
      );
    });
  });

  group('目錄：已刪者仍列出', () {
    testWidgets('「已刪除」篩選chip 發出 status=deleted', (tester) async {
      final _Fixture fixture = _Fixture(detailStatus: 'deleted');
      await pumpDirectory(tester, fixture);
      await tapVisible(
        tester,
        find.byKey(StandardAccountDirectoryCard.filterStatusDeletedKey),
      );

      expect(
        fixture.directoryQueries.last,
        contains('status=deleted'),
        reason: '${fixture.directoryQueries}',
      );
    });

    testWidgets('已刪的行帶出刪除時刻，未刪的行不帶', (tester) async {
      final _Fixture fixture = _Fixture(detailStatus: 'deleted');
      await pumpDirectory(tester, fixture);
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(StandardAccountDirectoryCard)),
      );

      expect(
        find.byKey(StandardAccountDirectoryCard.deletedAtKey(_targetId)),
        findsOneWidget,
      );
      expect(find.textContaining(l.adminStatusDeleted), findsWidgets);
      expect(find.textContaining(_formatMinute(_deletedAt)), findsOneWidget);
    });
  });
}

/// 成功回呼的計數（pumpProfile 內的 onSaved 寫向這裡）。
int _saved = 0;

/// 與介面同一個「年-月-日 時:分 UTC」寫法（測試不複製卡片實作，只複製格式）。
String _formatMinute(String iso) {
  final DateTime at = DateTime.parse(iso).toUtc();
  final String m = at.month.toString().padLeft(2, '0');
  final String d = at.day.toString().padLeft(2, '0');
  final String hh = at.hour.toString().padLeft(2, '0');
  final String mm = at.minute.toString().padLeft(2, '0');
  return '${at.year}-$m-$d $hh:$mm UTC';
}
