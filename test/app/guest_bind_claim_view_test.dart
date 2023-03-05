/// 「用憑證綁定訪戶」本人面板的介面測試。
///
/// 這一張卡是整個產品裡唯一能執行綁定的地方，因此測試問的是那幾條界線有沒有被界面
/// 悄悄放宽：
///   1. 先預覽、再確認是兩趟請求：沒跑過預覽就沒有確認那顆按鈕；預覽之後改過憑證欄，
///      那颗按鈕就收起（不拿舊的准許去按新的動作）；
///   2. 本體恰好 ticket 一欄、路徑與方法各就各位，界面不傳任何主體標識；
///   3. 預覽面板第一句是「尚未綁定」，其後逐條唸已驗證的影響（數量取自回應），
///      認不得的記號顯示通用句並保留原記號；
///   4. 執行前另有一次確認對話框，唸出目標與將被登出的會話數；取消零請求；
///   5. 完成句的撤銷數量取自回應，並重讀本人清單讓留痕自己說話；
///   6. 拿不到回應時說的是「結果待確認」而不是失敗或成功，且不自動補發；
///   7. 2025／2026／1004 各說各話；空憑證本地攔住且零請求。
///
/// 全程走注入的假傳輸：不碰網路、不落任何真實憑據。
library;

import 'dart:convert';

import 'package:evernightrealm/app/widgets/guest_bind_claim_view.dart';
import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/test_server.dart';

const Locale _locale = Locale('zh', 'TW');

const String _sourceId = '01a0e000-0000-7000-8000-0000000000aa';
const String _targetId = '01a0e000-0000-7000-8000-0000000000bb';
const String _bindingId = '01a0e000-0000-7000-8000-0000000000ee';

/// 一枚形狀合法的憑證明文（22 字元：與輸入框的 maxLength 同界，截不掉尾巴）。
const String _ticketText = 'Zm9vYmFyMTIzNDU2Nzg5MG';

/// 另一枚同長度但不同的明文：驗「預覽之後改過憑證欄就要重新預覽」。
const String _otherTicket = 'MDEyMzQ1Njc4OTBhYmNkZW';

const String _sourceJson =
    '{"account_id":"$_sourceId","login_name":"guest_seed_name",'
    '"display_name":"待綁旅人","account_type":"guest","status":"active",'
    '"must_change_password":false,"created_at":"2026-10-02T08:00:00.000Z"}';
const String _retiredSourceJson =
    '{"account_id":"$_sourceId","login_name":"guest_seed_name",'
    '"display_name":"待綁旅人","account_type":"guest","status":"retired",'
    '"must_change_password":false,"created_at":"2026-10-02T08:00:00.000Z",'
    '"retired_at":"2026-10-09T09:20:00.000Z"}';
const String _targetJson =
    '{"account_id":"$_targetId","login_name":"Ready.Host",'
    '"display_name":"承接者","account_type":"standard","status":"active",'
    '"must_change_password":false,"created_at":"2026-09-01T00:00:00.000Z"}';

const List<String> _impacts = <String>[
  'revoke_source_sessions',
  'retire_source_account',
  'keep_history_references',
  'transfer_future_attribution',
  'target_unchanged',
];

String _quoted(List<String> items) => items.map((String i) => '"$i"').join(',');

String _previewBody({
  List<String> impacts = _impacts,
  int openSessions = 3,
  int schemaVersion = 11,
}) {
  return '{"ticket_id":"$_bindingId","source":$_sourceJson,"target":$_targetJson,'
      '"impacts":[${_quoted(impacts)}],"source_open_sessions":$openSessions,'
      '"schema_version":$schemaVersion,'
      '"expires_at":"2026-10-09T09:20:00.000Z",'
      '"consent_mode":"target_self_initiated","request_id":"r-preview"}';
}

String _confirmBody({int revoked = 3}) =>
    '{"binding_id":"$_bindingId","source":$_retiredSourceJson,"target":$_targetJson,'
    '"revoked_sessions":$revoked,"bound_at":"2026-10-09T09:12:00.000Z",'
    '"consent_mode":"target_self_initiated","request_id":"r-confirm"}';

String _listBody({int count = 1}) {
  final List<String> rows = <String>[];
  for (int i = 0; i < count; i++) {
    rows.add(
      '{"binding_id":"$_bindingId-$i","source_account_id":"$_sourceId",'
      '"source_login_name":"guest_seed_name_$i","source_display_name":"旅人 $i",'
      '"bound_at":"2026-10-09T09:12:00.000Z","revoked_sessions":$i,'
      '"consent_mode":"target_self_initiated"}',
    );
  }
  return '{"bindings":[${rows.join(',')}],"total":$count,"request_id":"r-list"}';
}

/// 一台按路徑與方法分流的假後端，把收過的請求留在對應清單裡。
class _Fixture {
  _Fixture({
    this.previewStatus = 200,
    this.previewCode = 0,
    this.confirmStatus = 200,
    this.confirmCode = 0,
    this.listCount = 1,
    this.impacts = _impacts,
    this.offlineOnConfirm = false,
  });

  final int previewStatus;
  final int previewCode;
  final int confirmStatus;
  final int confirmCode;
  final int listCount;
  final List<String> impacts;

  /// true 時確認那趟直接拋底層異常（離線與逾時那一類：拿不到回應）。
  final bool offlineOnConfirm;

  final List<http.Request> previewWrites = <http.Request>[];
  final List<http.Request> confirmWrites = <http.Request>[];
  int listCalls = 0;

  bool _holdPreview = false;

  /// 讓下一趟預覽延後，供「進行中不發第二趟」與按鈕停用取證。
  void holdNextPreview() => _holdPreview = true;

  ServerApi get api => ServerApi(
    config: ServerApiConfig.fixed(testBaseUrl),
    client: MockClient((http.Request request) async {
      final String path = request.url.path;
      if (path == '/auth/guest-bindings/preview') {
        previewWrites.add(request);
        if (_holdPreview) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          _holdPreview = false;
        }
        if (previewStatus != 200) {
          return _reply(
            previewStatus,
            '{"code":$previewCode,"message":"nope","request_id":"r-fail"}',
          );
        }
        return _reply(
          200,
          _previewBody(
            impacts: impacts,
            openSessions: previewStatus == 200 ? 3 : 0,
          ),
        );
      }
      if (path == '/auth/guest-bindings' && request.method == 'POST') {
        confirmWrites.add(request);
        if (offlineOnConfirm) {
          throw http.ClientException('offline for test');
        }
        if (confirmStatus != 200) {
          return _reply(
            confirmStatus,
            '{"code":$confirmCode,"message":"nope","request_id":"r-fail"}',
          );
        }
        return _reply(200, _confirmBody());
      }
      if (path == '/auth/guest-bindings') {
        listCalls++;
        return _reply(200, _listBody(count: listCount));
      }
      return _reply(404, '{"code":1001,"message":"nope","request_id":"r-404"}');
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
  late AppLocalizations l10n;

  Future<_Fixture> pump(WidgetTester tester, _Fixture fixture) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: _locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: GuestBindView(api: fixture.api)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    l10n = AppLocalizations.of(tester.element(find.byType(GuestBindView)));
    return fixture;
  }

  /// 把明文打進憑證欄：先_focus_（未聚焦時 enterText 會被編輯器吞掉，
  /// 這不是界面的規則而是測試框架的手法），再輸入並 settle 讓 onChanged 的
  /// setState 真正走完一趟重建。
  Future<void> fillTicket(WidgetTester tester, String value) async {
    final Finder field = find.byKey(GuestBindView.ticketKey);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  group('預覽與確認的走線', () {
    testWidgets('常駐句在場；沒有預覽就沒有確認那顆按鈕', (WidgetTester tester) async {
      await pump(tester, _Fixture());
      expect(find.byKey(GuestBindView.scopeKey), findsOneWidget);
      expect(find.text(l10n.guestBindScopeHint), findsOneWidget);
      expect(find.byKey(GuestBindView.confirmKey), findsNothing);
      // 打开時就讀一次本人清單（完成與否的證據要有地方放）。
      expect(find.text(l10n.guestBindLedgerTitle), findsOneWidget);
    });

    testWidgets('空白憑證本地攔住，一個請求都不發', (WidgetTester tester) async {
      final _Fixture fixture = await pump(tester, _Fixture());
      await tap(tester, GuestBindView.previewKey);
      expect(fixture.previewWrites, isEmpty);
      expect(find.text(l10n.guestBindIncompleteNotice), findsOneWidget);
    });

    testWidgets('預覽成功：首句「尚未綁定」、五條影響與數量都取自回應', (WidgetTester tester) async {
      final _Fixture fixture = await pump(tester, _Fixture());
      await fillTicket(tester, _ticketText);
      await tap(tester, GuestBindView.previewKey);

      expect(fixture.previewWrites.single.method, 'POST');
      expect(
        fixture.previewWrites.single.url.path,
        '/auth/guest-bindings/preview',
      );
      final Map<String, Object?> body =
          jsonDecode(fixture.previewWrites.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'ticket'});

      expect(find.byKey(GuestBindView.previewResultKey), findsOneWidget);
      expect(find.text(l10n.guestBindNotBoundNotice), findsOneWidget);
      expect(
        find.text(l10n.guestBindPreviewHead('guest_seed_name', 3)),
        findsOneWidget,
      );
      expect(
        find.text(l10n.stdAccountBindPreflightImpactRevoke(3)),
        findsOneWidget,
      );
      expect(
        find.text(l10n.stdAccountBindPreflightImpactRetire),
        findsOneWidget,
      );
      expect(
        find.text(l10n.stdAccountBindPreflightImpactTargetUnchanged),
        findsOneWidget,
      );
      expect(find.text(l10n.guestBindConsentNotice), findsOneWidget);
      expect(
        find.text(l10n.stdAccountBindPreflightDataVersion(11)),
        findsOneWidget,
      );
      // 有了一致的預覽，確認那顆按鈕才出現。
      expect(find.byKey(GuestBindView.confirmKey), findsOneWidget);
    });

    testWidgets('認不得的影響記號：通用句並保留原記號，不崩潰也不靜默', (WidgetTester tester) async {
      await pump(
        tester,
        _Fixture(impacts: <String>[..._impacts, 'move_activity_membership']),
      );
      await fillTicket(tester, _ticketText);
      await tap(tester, GuestBindView.previewKey);
      expect(
        find.text(
          l10n.stdAccountBindPreflightUnknownToken('move_activity_membership'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('預覽之後改動憑證欄：確認按鈕收起，須重新預覽', (WidgetTester tester) async {
      await pump(tester, _Fixture());
      await fillTicket(tester, _ticketText);
      await tap(tester, GuestBindView.previewKey);
      expect(find.byKey(GuestBindView.confirmKey), findsOneWidget);

      await fillTicket(tester, _otherTicket);
      expect(find.byKey(GuestBindView.confirmKey), findsNothing);
      expect(find.byKey(GuestBindView.previewResultKey), findsNothing);
    });
  });

  group('執行的確認與結果', () {
    testWidgets('確認對話框點名訪戶與將登出的會話數；取消時零請求', (WidgetTester tester) async {
      final _Fixture fixture = await pump(tester, _Fixture());
      await fillTicket(tester, _ticketText);
      await tap(tester, GuestBindView.previewKey);
      await tap(tester, GuestBindView.confirmKey);

      expect(find.text(l10n.guestBindConfirmTitle), findsOneWidget);
      expect(
        find.text(l10n.guestBindConfirmBody('guest_seed_name', 3)),
        findsOneWidget,
      );
      await tap(tester, GuestBindView.confirmDialogCancelKey);
      expect(fixture.confirmWrites, isEmpty);
      // 取消是一條正經出路：那份預覽仍在，按鈕還能再按。
      expect(find.byKey(GuestBindView.confirmKey), findsOneWidget);
    });

    testWidgets('確認執行：本體恰好 ticket、完成句數量取自回應並重讀清單', (WidgetTester tester) async {
      final _Fixture fixture = await pump(tester, _Fixture(listCount: 0));
      await fillTicket(tester, _ticketText);
      await tap(tester, GuestBindView.previewKey);
      final int listsBefore = fixture.listCalls;
      await tap(tester, GuestBindView.confirmKey);
      await tap(tester, GuestBindView.confirmDialogKey);

      expect(fixture.confirmWrites.single.method, 'POST');
      expect(fixture.confirmWrites.single.url.path, '/auth/guest-bindings');
      final Map<String, Object?> body =
          jsonDecode(fixture.confirmWrites.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'ticket'});

      expect(
        find.text(l10n.guestBindDoneNotice('guest_seed_name', 3)),
        findsOneWidget,
      );
      expect(fixture.listCalls, greaterThan(listsBefore));
      // 用掉的小票不再能按：預覽面板與確認按鈕都收起，輸入欄也清空。
      expect(find.byKey(GuestBindView.confirmKey), findsNothing);
      expect(find.byKey(GuestBindView.previewResultKey), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(GuestBindView.ticketKey))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('清單有行時逐行唸出來源、時刻與那次撤銷數', (WidgetTester tester) async {
      final _Fixture two = await pump(tester, _Fixture(listCount: 2));
      expect(find.byKey(GuestBindView.ledgerKey), findsOneWidget);
      expect(two.listCalls, 1);
      // 逐行比對內容而不是整句句子的拼寫：句子由 ARB 定，界面只保證「這個人的這一行的
      // 時刻與數量都被唸出來」。
      final List<String> rows = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(GuestBindView.ledgerKey),
              matching: find.byType(Text),
            ),
          )
          .map((Text t) => t.data ?? '')
          .toList();
      expect(rows, hasLength(2));
      expect(rows[0], contains('guest_seed_name_0'));
      expect(rows[0], contains('2026-10-09T09:12:00.000Z'));
      expect(rows[1], contains('guest_seed_name_1'));
    });

    testWidgets('空清單說的是「還沒有接住過」，與查不到各說各話', (WidgetTester tester) async {
      await pump(tester, _Fixture(listCount: 0));
      expect(find.byKey(GuestBindView.ledgerEmptyKey), findsOneWidget);
      expect(find.byKey(GuestBindView.ledgerKey), findsNothing);
      expect(find.text(l10n.guestBindLedgerEmptyNotice), findsOneWidget);
    });

    testWidgets('回應遺失時說「結果待確認」並重讀清單，不自動補發', (WidgetTester tester) async {
      final _Fixture fixture = await pump(
        tester,
        _Fixture(offlineOnConfirm: true),
      );
      await fillTicket(tester, _ticketText);
      await tap(tester, GuestBindView.previewKey);
      final int listsBefore = fixture.listCalls;
      await tap(tester, GuestBindView.confirmKey);
      await tap(tester, GuestBindView.confirmDialogKey);

      expect(find.text(l10n.guestBindPendingResultNotice), findsOneWidget);
      expect(
        find.text(l10n.guestBindDoneNotice('guest_seed_name', 3)),
        findsNothing,
      );
      // 重讀過清單，但絕沒有把同一枚憑證再發一次。
      expect(fixture.listCalls, greaterThan(listsBefore));
      expect(fixture.confirmWrites.length, 1);
    });
  });

  group('失敗分流', () {
    testWidgets('2025 說憑證不可用這一句，且面板不出現預覽結果', (WidgetTester tester) async {
      await pump(tester, _Fixture(previewStatus: 403, previewCode: 2025));
      await fillTicket(tester, _ticketText);
      await tap(tester, GuestBindView.previewKey);
      expect(find.text(l10n.errorCodeBindTicketInvalid), findsOneWidget);
      expect(find.byKey(GuestBindView.previewResultKey), findsNothing);
      expect(find.byKey(GuestBindView.confirmKey), findsNothing);
    });

    testWidgets('2026 與 2025 各說各話（處置一個是重發憑證、一個是重新預檢）', (
      WidgetTester tester,
    ) async {
      await pump(tester, _Fixture(confirmStatus: 409, confirmCode: 2026));
      await fillTicket(tester, _ticketText);
      await tap(tester, GuestBindView.previewKey);
      await tap(tester, GuestBindView.confirmKey);
      await tap(tester, GuestBindView.confirmDialogKey);
      expect(find.text(l10n.errorCodeBindPlanStale), findsOneWidget);
      expect(find.text(l10n.errorCodeBindTicketInvalid), findsNothing);
    });

    testWidgets('2011 說「你的身分做不了這一動」，不冒充憑證問題', (WidgetTester tester) async {
      await pump(tester, _Fixture(previewStatus: 403, previewCode: 2011));
      await fillTicket(tester, _ticketText);
      await tap(tester, GuestBindView.previewKey);
      expect(find.text(l10n.errorCodePermissionDenied), findsOneWidget);
      expect(find.text(l10n.errorCodeBindTicketInvalid), findsNothing);
    });
  });

  group('進行中的單趟與互斥', () {
    testWidgets('預覽在飛時連點只發一趟，並停住輸入與重讀', (WidgetTester tester) async {
      final _Fixture fixture = await pump(tester, _Fixture());
      fixture.holdNextPreview();
      await fillTicket(tester, _ticketText);
      await tester.ensureVisible(find.byKey(GuestBindView.previewKey));
      await tester.tap(find.byKey(GuestBindView.previewKey));
      await tester.pump();
      // 在飛的那一刻取證（settle 就會把這趟跑完，等於測到事後）：輸入欄停用。
      expect(
        tester.widget<TextField>(find.byKey(GuestBindView.ticketKey)).enabled,
        isFalse,
      );
      await tester.tap(find.byKey(GuestBindView.previewKey));
      await tester.pumpAndSettle();

      expect(fixture.previewWrites.length, 1);
      // 跑完之後輸入欄恢復可用；「重讀清單」是另一條只讀通路，不陪著停。
      expect(
        tester.widget<TextField>(find.byKey(GuestBindView.ticketKey)).enabled,
        isTrue,
      );
    });
  });
}
