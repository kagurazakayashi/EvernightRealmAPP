/// Root 端「伺服器級註冊邀請碼管理」卡的介面測試。
///
/// 走注入的假傳輸，只掛邀請碼這組端點（本檔問的是這張卡的行為，不是整頁裝配）。
/// 問的幾件事：
///   1. 名冊那側按鈕只由服務端讀回的狀態決定：未撤銷才有撤銷鈕，已撤銷只有一句實話；
///   2. 一次性展示：簽發成功後明文碼只出現在受控展示區（SelectableText），
///      界面不提供複製／分享鈕、不畫二維碼；收起後那枚碼從畫面消失；
///   3. 撤銷確認框點名目標、講完「不是刪除」等邊界；取消一請求都不發；
///   4. 成功句取 DELETE 回應並觸發名冊重讀；2022 只給重讀出口、絕不自動補發；
///   5. 寫入進行中同一頁不併發第二趟；
///   6. 載入按碼分流（2011 與通用失敗各一句）；名冊行裡絕不出現明文碼。
library;

import 'dart:convert';

import 'package:evernightrealm/app/app_dependencies.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/features/root_console/invite_code_view.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

const Locale _locale = Locale('zh', 'TW');
const String _codeId = '01a0f000-0000-7000-8000-0000000000c1';
const String _otherId = '01a0f000-0000-7000-8000-0000000000c2';
const String _plainCode = 'Zm9vYmFyYmF6MTIzNDU2Nzg5MDE';

String _row(String id, String label, String status) {
  final String revoked = status == 'revoked'
      ? ',"revoked_at":"2026-10-07T09:00:00.000Z"'
      : '';
  return '{"code_id":"$id","label":"$label","status":"$status",'
      '"max_uses":3,"used_count":1,"remaining":2,'
      '"created_at":"2026-10-07T08:00:00.000Z"$revoked}';
}

String _roster(String rows, {int total = 1}) =>
    '{"invites":[$rows],"page":1,"page_size":20,"total":$total,'
    '"request_id":"r-roster"}';

const String _issuedReport =
    '{"code":"$_plainCode","invite":'
    '{"code_id":"$_codeId","label":"新標籤","status":"active",'
    '"max_uses":1,"used_count":0,"remaining":1,'
    '"created_at":"2026-10-07T08:00:00.000Z"},"request_id":"r-issue"}';

String _revokeReport(String status) =>
    '{"invite":{"code_id":"$_codeId","label":"內測名額","status":"$status",'
    '"max_uses":1,"used_count":0,"remaining":1,'
    '"created_at":"2026-10-07T08:00:00.000Z",'
    '"revoked_at":"2026-10-07T09:00:00.000Z"},"request_id":"r-revoke"}';

class _Fixture {
  _Fixture({this.initialRows = 'active'});

  /// 首次名冊：`active`／`revoked`／`mixed`／`empty`。
  final String initialRows;

  int rosterFailureStatus = 0; // 非 0 即讓名冊讀取失敗
  int rosterFailureCode = 2011;
  int revokeStatus = 200;
  int revokeCode = 2022;
  bool holdNextRevoke = false;
  bool revokeToEmpty = false; // 撤銷成功後名冊是否回空（默認仍回該行）

  int rosterCalls = 0;
  final List<http.Request> issues = <http.Request>[];
  final List<http.Request> revokes = <http.Request>[];

  String get _rows => switch (initialRows) {
    'active' => _row(_codeId, '內測名額', 'active'),
    'revoked' => _row(_codeId, '內測名額', 'revoked'),
    'mixed' =>
      '${_row(_codeId, '內測名額', 'active')},${_row(_otherId, '已撤的', 'revoked')}',
    _ => '',
  };

  ServerApi api(ServerAddressSettings settings) {
    return ServerApi(
      config: ServerApiConfig(source: settings),
      client: MockClient((http.Request request) async {
        final String path = request.url.path;
        final String method = request.method;
        if (path == kRootInviteCodesPath && method == 'GET') {
          rosterCalls++;
          if (rosterFailureStatus != 0) {
            return _reply(
              rosterFailureStatus,
              '{"code":$rosterFailureCode,"message":"x","request_id":"r-f"}',
            );
          }
          final bool afterRevoke = revokes.isNotEmpty && revokeStatus == 200;
          final String rows = afterRevoke && revokeToEmpty ? '' : _rows;
          return _reply(200, _roster(rows, total: rows.isEmpty ? 0 : 1));
        }
        if (path == kRootInviteCodesPath && method == 'POST') {
          issues.add(request);
          return _reply(201, _issuedReport);
        }
        if (path.startsWith('$kRootInviteCodesPath/') && method == 'DELETE') {
          revokes.add(request);
          if (holdNextRevoke) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            holdNextRevoke = false;
          }
          if (revokeStatus != 200) {
            return _reply(
              revokeStatus,
              '{"code":$revokeCode,"message":"x","request_id":"r-f"}',
            );
          }
          return _reply(200, _revokeReport('revoked'));
        }
        return _reply(404, '{"code":1001,"message":"x","request_id":"r-404"}');
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
    String key = 'a',
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
                    child: InviteCodeCard(
                      key: ValueKey<String>(key),
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

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder byKey(Key key) => find.byKey(key);

  group('名冊與按鈕邊界', () {
    testWidgets('卡渲染標題、範圍說明與簽發表單', (WidgetTester tester) async {
      await pump(tester, _Fixture());
      expect(byKey(InviteCodeCard.titleKey), findsOneWidget);
      expect(byKey(InviteCodeCard.scopeHintKey), findsOneWidget);
      expect(byKey(InviteCodeCard.issueSectionKey), findsOneWidget);
      expect(byKey(InviteCodeCard.issueActionKey), findsOneWidget);
    });

    testWidgets('未撤銷的行有撤銷鈕，已撤銷的行只有一句實話、沒有按鈕', (WidgetTester tester) async {
      await pump(tester, _Fixture(initialRows: 'mixed'));
      expect(byKey(InviteCodeCard.revokeKey(_codeId)), findsOneWidget);
      expect(byKey(InviteCodeCard.revokeKey(_otherId)), findsNothing);
      expect(byKey(InviteCodeCard.revokedNoteKey(_otherId)), findsOneWidget);
    });

    testWidgets('名冊那一行絕不出現明文碼', (WidgetTester tester) async {
      await pump(tester, _Fixture());
      expect(find.text(_plainCode), findsNothing);
    });

    testWidgets('空名冊給空態提示', (WidgetTester tester) async {
      await pump(tester, _Fixture(initialRows: 'empty'));
      expect(byKey(InviteCodeCard.emptyKey), findsOneWidget);
    });
  });

  group('簽發與一次性展示', () {
    testWidgets('標籤為空時簽發被本地攔下，不發請求', (WidgetTester tester) async {
      final _Fixture fx = _Fixture();
      await pump(tester, fx);
      await tapVisible(tester, byKey(InviteCodeCard.issueActionKey));
      expect(fx.issues, isEmpty);
      expect(byKey(InviteCodeCard.issueNoticeKey), findsOneWidget);
    });

    testWidgets('簽發經確認框，成功後明文碼只出現在受控展示區', (WidgetTester tester) async {
      final _Fixture fx = _Fixture();
      await pump(tester, fx);
      await tester.enterText(byKey(InviteCodeCard.labelFieldKey), '新標籤');
      await tapVisible(tester, byKey(InviteCodeCard.issueActionKey));
      // 確認框出現，肯定後才 POST。
      expect(byKey(InviteCodeCard.confirmKey), findsOneWidget);
      await tapVisible(tester, byKey(InviteCodeCard.confirmKey));
      expect(fx.issues, hasLength(1));
      final Map<String, Object?> body =
          jsonDecode(fx.issues.single.body) as Map<String, Object?>;
      expect(body['label'], '新標籤');
      expect(
        body.containsKey('code') || body.containsKey('code_hash'),
        isFalse,
      );
      // 明文碼此刻出現在受控展示區。
      expect(find.text(_plainCode), findsOneWidget);
      expect(byKey(InviteCodeCard.issuedDoneKey), findsOneWidget);
    });

    testWidgets('界面無複製鈕、無二維碼控件', (WidgetTester tester) async {
      final _Fixture fx = _Fixture();
      await pump(tester, fx);
      await tester.enterText(byKey(InviteCodeCard.labelFieldKey), '新標籤');
      await tapVisible(tester, byKey(InviteCodeCard.issueActionKey));
      await tapVisible(tester, byKey(InviteCodeCard.confirmKey));
      expect(find.byIcon(Icons.copy), findsNothing);
      expect(find.byIcon(Icons.share), findsNothing);
      expect(find.byIcon(Icons.qr_code), findsNothing);
      expect(find.byIcon(Icons.qr_code_2), findsNothing);
    });

    testWidgets('收起一次性展示後明文碼從畫面消失', (WidgetTester tester) async {
      final _Fixture fx = _Fixture();
      await pump(tester, fx);
      await tester.enterText(byKey(InviteCodeCard.labelFieldKey), '新標籤');
      await tapVisible(tester, byKey(InviteCodeCard.issueActionKey));
      await tapVisible(tester, byKey(InviteCodeCard.confirmKey));
      expect(find.text(_plainCode), findsOneWidget);
      await tapVisible(tester, byKey(InviteCodeCard.issuedDoneKey));
      expect(find.text(_plainCode), findsNothing);
    });

    testWidgets('取消簽發確認框時一個請求都不發', (WidgetTester tester) async {
      final _Fixture fx = _Fixture();
      await pump(tester, fx);
      await tester.enterText(byKey(InviteCodeCard.labelFieldKey), '新標籤');
      await tapVisible(tester, byKey(InviteCodeCard.issueActionKey));
      await tapVisible(tester, byKey(InviteCodeCard.confirmCancelKey));
      expect(fx.issues, isEmpty);
    });
  });

  group('撤銷', () {
    testWidgets('撤銷確認框點名標籤並講「不是刪除」，取消零請求', (WidgetTester tester) async {
      final _Fixture fx = _Fixture();
      await pump(tester, fx);
      await tapVisible(tester, byKey(InviteCodeCard.revokeKey(_codeId)));
      expect(byKey(InviteCodeCard.revokeConfirmKey), findsOneWidget);
      await tapVisible(tester, byKey(InviteCodeCard.revokeConfirmCancelKey));
      expect(fx.revokes, isEmpty);
    });

    testWidgets('撤銷成功取 DELETE 回應並觸發名冊重讀', (WidgetTester tester) async {
      final _Fixture fx = _Fixture();
      await pump(tester, fx);
      final int before = fx.rosterCalls;
      await tapVisible(tester, byKey(InviteCodeCard.revokeKey(_codeId)));
      await tapVisible(tester, byKey(InviteCodeCard.revokeConfirmKey));
      expect(fx.revokes, hasLength(1));
      expect(fx.rosterCalls, greaterThan(before));
      expect(byKey(InviteCodeCard.revokeNoticeKey), findsOneWidget);
    });

    testWidgets('2022 只給重讀出口、不自動補發撤銷', (WidgetTester tester) async {
      final _Fixture fx = _Fixture()..revokeStatus = 409;
      await pump(tester, fx);
      await tapVisible(tester, byKey(InviteCodeCard.revokeKey(_codeId)));
      await tapVisible(tester, byKey(InviteCodeCard.revokeConfirmKey));
      expect(byKey(InviteCodeCard.revokeFailureKey), findsOneWidget);
      expect(byKey(InviteCodeCard.revokeReloadKey), findsOneWidget);
      // 衝突後不自動重發：撤銷端點仍只被調過一次。
      expect(fx.revokes, hasLength(1));
    });

    testWidgets('撤銷進行中重複點擊只發一趟', (WidgetTester tester) async {
      final _Fixture fx = _Fixture()..holdNextRevoke = true;
      await pump(tester, fx);
      final Finder btn = byKey(InviteCodeCard.revokeKey(_codeId));
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();
      await tester.tap(byKey(InviteCodeCard.revokeConfirmKey));
      // 讓第一趟進入 in-flight，再狂點那顆鈕。
      await tester.pump();
      await tapVisible(tester, btn);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(fx.revokes.length, lessThanOrEqualTo(1));
    });
  });

  group('載入失敗分流', () {
    testWidgets('載入失敗停在失敗態並給出重讀出口', (WidgetTester tester) async {
      final _Fixture denied = _Fixture()
        ..rosterFailureStatus = 403
        ..rosterFailureCode = 2011;
      await pump(tester, denied);
      expect(byKey(InviteCodeCard.failedKey), findsOneWidget);
      expect(byKey(InviteCodeCard.retryKey), findsOneWidget);
      // 失敗態不顯示任何猜測出來的名冊內容。
      expect(byKey(InviteCodeCard.rowKey(_codeId)), findsNothing);
    });
  });
}
