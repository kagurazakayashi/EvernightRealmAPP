/// 「訪戶綁定執行」四條端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：路徑與方法（管理員簽發掛在來源那一側、本人三條通路全在
/// /auth 之下）、請求欄位集合（簽發恰好 target_account_id、核銷恰好 ticket，
/// 沒有任何格子可以宣稱身分、角色、有效期或「代替誰同意」）、回應的必填欄位
/// （ticket／ticket_id／expires_at／revoked_sessions／bound_at 缺席一律判合同違例，
/// 不降級成空字串或 0）、consent_mode 表外值判違例（新同意形態＝新決定的日子，
/// 舊客戶端不能靜默放行）、影響記號的前進相容（認不得的記號原樣保留成字串），
/// 以及兩枚新機器碼 2025／2026 的數值、可判別性與「不屬於可重試」定位。
///
/// 這四條通路共同的形状要求：回應裡沒有一格裝得下口令、雜湊或會話材料；
/// 而憑證明文只在簽發那一個回應裡出現（它不落庫、也不進本地儲存）。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

const String _sourceId = '01a0e000-0000-7000-8000-0000000000aa';
const String _targetId = '01a0e000-0000-7000-8000-0000000000bb';
const String _bindingId = '01a0e000-0000-7000-8000-0000000000ee';

/// 一枚形状合法的憑證明文（22 字元 base64url；只活在這次注入的假傳輸裡）。
const String _ticket = 'Zm9vYmFyMTIzNDU2Nzg5MGFiY2Q';

const String _sourceJson =
    '{"account_id":"$_sourceId","login_name":"guest_seed_name",'
    '"display_name":"待綁旅人","account_type":"guest","status":"active",'
    '"must_change_password":false,"created_at":"2026-10-02T08:00:00.000Z"}';

/// 執行之後的來源現值：退休態並帶著 retired_at（合同上這是「動的是誰」的正面證據）。
const String _retiredSourceJson =
    '{"account_id":"$_sourceId","login_name":"guest_seed_name",'
    '"display_name":"待綁旅人","account_type":"guest","status":"retired",'
    '"must_change_password":false,"created_at":"2026-10-02T08:00:00.000Z",'
    '"retired_at":"2026-10-09T09:20:00.000Z"}';

const String _targetJson =
    '{"account_id":"$_targetId","login_name":"Ready.Host",'
    '"display_name":"承接者","account_type":"standard","status":"active",'
    '"must_change_password":false,"created_at":"2026-09-01T00:00:00.000Z"}';

const List<String> _fullImpacts = <String>[
  'revoke_source_sessions',
  'retire_source_account',
  'keep_history_references',
  'transfer_future_attribution',
  'target_unchanged',
];

String _quoted(List<String> items) => items.map((String i) => '"$i"').join(',');

/// 簽發成功的回應本體（與後端 guestBindTicketResponse 同形）。
String _ticketBody({
  List<String> impacts = _fullImpacts,
  int openSessions = 2,
}) {
  return '{"ticket":"$_ticket","ticket_id":"$_bindingId",'
      '"source":$_sourceJson,"target":$_targetJson,'
      '"impacts":[${_quoted(impacts)}],"source_open_sessions":$openSessions,'
      '"schema_version":11,"expires_at":"2026-10-09T09:20:00.000Z",'
      '"consent_mode":"target_self_initiated","request_id":"r-ticket"}';
}

/// 本人預覽的回應本體（與後端 guestBindClaimPreviewResponse 同形：沒有 ticket 明文）。
String _previewBody({List<String> impacts = _fullImpacts}) {
  return '{"ticket_id":"$_bindingId","source":$_sourceJson,"target":$_targetJson,'
      '"impacts":[${_quoted(impacts)}],"source_open_sessions":1,'
      '"schema_version":11,"expires_at":"2026-10-09T09:20:00.000Z",'
      '"consent_mode":"target_self_initiated","request_id":"r-preview"}';
}

/// 綁定完成的回應本體。
String _confirmBody({int revoked = 2}) {
  return '{"binding_id":"$_bindingId","source":$_retiredSourceJson,'
      '"target":$_targetJson,"revoked_sessions":$revoked,'
      '"bound_at":"2026-10-09T09:12:00.000Z",'
      '"consent_mode":"target_self_initiated","request_id":"r-confirm"}';
}

/// 本人清單的回應本體。
String _listBody({int total = 1, String item = ''}) {
  return '{"bindings":[$item],"total":$total,"request_id":"r-list"}';
}

String _listItem({int revoked = 2}) {
  return '{"binding_id":"$_bindingId","source_account_id":"$_sourceId",'
      '"source_login_name":"guest_seed_name","source_display_name":"待綁旅人",'
      '"bound_at":"2026-10-09T09:12:00.000Z","revoked_sessions":$revoked,'
      '"consent_mode":"target_self_initiated"}';
}

/// 依要測的通路裝一台假後端，並把收過的請求留在 [sent]。
ServerApi _api(
  List<http.Request> sent, {
  String? responseOverride,
  int status = 200,
}) {
  return apiWithHandler((http.Request request) async {
    sent.add(request);
    final String body =
        responseOverride ??
        switch (request.url.path) {
          '/admin/accounts/$_sourceId/bind-ticket' => _ticketBody(),
          kAuthGuestBindingsPreviewPath => _previewBody(),
          kAuthGuestBindingsPath when request.method == 'POST' =>
            _confirmBody(),
          kAuthGuestBindingsPath => _listBody(item: _listItem()),
          _ => '{}',
        };
    return http.Response(
      body,
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  });
}

Future<Object?> _failure(Future<Object?> Function() call) async {
  try {
    await call();
  } on Object catch (error) {
    return error;
  }
  throw StateError('預期失敗，卻拿到一次成功');
}

/// 回應本體裡「按鍵名」逐層找一格（不做子串掃描：retired_at 是合法可展示欄）。
String? _findKey(Object? node, String key) {
  if (node is Map<String, Object?>) {
    if (node.containsKey(key)) {
      return key;
    }
    for (final MapEntry<String, Object?> entry in node.entries) {
      final String? found = _findKey(entry.value, key);
      if (found != null) {
        return found;
      }
    }
  }
  if (node is List<Object?>) {
    for (final Object? child in node) {
      final String? found = _findKey(child, key);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

void main() {
  group('簽發憑證端點合同', () {
    test(
      'issueGuestBindTicket 發 POST /admin/accounts/{id}/bind-ticket、本體恰好一欄',
      () async {
        final List<http.Request> sent = <http.Request>[];
        final GuestBindTicketReport report = await _api(sent)
            .issueGuestBindTicket(
              accountId: _sourceId,
              targetAccountId: _targetId,
            );

        expect(sent.single.method, 'POST');
        expect(sent.single.url.path, adminAccountBindTicketPath(_sourceId));
        final Map<String, Object?> body =
            jsonDecode(sent.single.body) as Map<String, Object?>;
        expect(body.keys.toSet(), <String>{'target_account_id'});
        // 沒有也不准出現的格子：有效期、同意形態、來源、角色都是後端說的了才算。
        for (final String forbidden in <String>[
          'password',
          'role',
          'account_type',
          'status',
          'ttl',
          'expires',
          'consent',
          'source_account_id',
        ]) {
          expect(sent.single.body, isNot(contains(forbidden)));
        }

        expect(report.ticket, _ticket);
        expect(report.ticketId, _bindingId);
        expect(report.source.accountId, _sourceId);
        expect(report.target.accountId, _targetId);
        expect(report.impacts, hasLength(_fullImpacts.length));
        expect(report.sourceOpenSessions, 2);
        expect(report.schemaVersion, 11);
        expect(report.expiresAt.toUtc().year, 2026);
        expect(
          report.consentMode,
          kBindPreflightConsentModeTargetSelfInitiated,
        );
      },
    );

    test('ticket／expires_at 缺席各自判合同違例，不降級成空值', () async {
      const String noTicket =
          '{"ticket_id":"$_bindingId","source":$_sourceJson,"target":$_targetJson,'
          '"impacts":[],"source_open_sessions":0,"schema_version":11,'
          '"expires_at":"2026-10-09T09:20:00.000Z",'
          '"consent_mode":"target_self_initiated","request_id":"r"}';
      expect(
        await _failure(
          () => _api(<http.Request>[], responseOverride: noTicket)
              .issueGuestBindTicket(
                accountId: _sourceId,
                targetAccountId: _targetId,
              ),
        ),
        isA<ApiError>().having(
          (ApiError e) => e.kind,
          'kind',
          ApiErrorKind.invalidResponse,
        ),
      );

      const String noExpiry =
          '{"ticket":"$_ticket","ticket_id":"$_bindingId","source":$_sourceJson,'
          '"target":$_targetJson,"impacts":[],"source_open_sessions":0,'
          '"schema_version":11,"consent_mode":"target_self_initiated","request_id":"r"}';
      expect(
        await _failure(
          () => _api(<http.Request>[], responseOverride: noExpiry)
              .issueGuestBindTicket(
                accountId: _sourceId,
                targetAccountId: _targetId,
              ),
        ),
        isA<ApiError>().having(
          (ApiError e) => e.kind,
          'kind',
          ApiErrorKind.invalidResponse,
        ),
      );
    });

    test('consent_mode 表外值判違例：新同意形態不能靜默放行', () async {
      final String body = _ticketBody().replaceFirst(
        '"consent_mode":"target_self_initiated"',
        '"consent_mode":"admin_initiated"',
      );
      expect(
        await _failure(
          () => _api(<http.Request>[], responseOverride: body)
              .issueGuestBindTicket(
                accountId: _sourceId,
                targetAccountId: _targetId,
              ),
        ),
        isA<ApiError>().having(
          (ApiError e) => e.kind,
          'kind',
          ApiErrorKind.invalidResponse,
        ),
      );
    });
  });

  group('本人預覽與執行端點合同', () {
    test(
      'guestBindPreview 發 POST 到 /auth/guest-bindings/preview、本體恰好 ticket',
      () async {
        final List<http.Request> sent = <http.Request>[];
        final GuestBindClaimPreviewReport report = await _api(sent)
            .guestBindPreview(ticket: _ticket);

        expect(sent.single.method, 'POST');
        expect(sent.single.url.path, kAuthGuestBindingsPreviewPath);
        final Map<String, Object?> body =
            jsonDecode(sent.single.body) as Map<String, Object?>;
        expect(body.keys.toSet(), <String>{'ticket'});
        expect(report.ticketId, _bindingId);
        expect(report.source.accountId, _sourceId);
        expect(report.impacts, hasLength(_fullImpacts.length));
        expect(report.expiresAt.isUtc, isTrue);
        // 預覽回應不該帶著明文（它自己沒有那格，模型也不該憑空捏出一格）。
        expect(_findKey(jsonDecode(_previewBody()), 'ticket'), isNull);
      },
    );

    test(
      'guestBindConfirm 發 POST 到 /auth/guest-bindings，並如實帶出退休與撤銷數量',
      () async {
        final List<http.Request> sent = <http.Request>[];
        final GuestBindResultReport report = await _api(sent)
            .guestBindConfirm(ticket: _ticket);

        expect(sent.single.method, 'POST');
        expect(sent.single.url.path, kAuthGuestBindingsPath);
        final Map<String, Object?> body =
            jsonDecode(sent.single.body) as Map<String, Object?>;
        expect(body.keys.toSet(), <String>{'ticket'});
        expect(report.bindingId, _bindingId);
        expect(report.source.status, 'retired');
        expect(report.source.retiredAt, isNotNull);
        expect(report.target.accountId, _targetId);
        expect(report.revokedSessions, 2);
        expect(report.boundAt.toUtc().minute, 12);
        // 完成的回應裡不得再出現明文，也不得有任何憑據形態的欄位。
        final Map<String, Object?> decoded =
            jsonDecode(_confirmBody()) as Map<String, Object?>;
        for (final String forbidden in <String>[
          'password',
          'hash',
          'token',
          'secret',
          'cookie',
          'ticket',
        ]) {
          expect(_findKey(decoded, forbidden), isNull, reason: forbidden);
        }
      },
    );

    test('revoked_sessions 缺席判違例而不是降級成 0（界面那句數字猜不得）', () async {
      final String body = _confirmBody().replaceFirst(
        '"revoked_sessions":2,',
        '',
      );
      expect(
        await _failure(
          () => _api(
            <http.Request>[],
            responseOverride: body,
          ).guestBindConfirm(ticket: _ticket),
        ),
        isA<ApiError>().having(
          (ApiError e) => e.kind,
          'kind',
          ApiErrorKind.invalidResponse,
        ),
      );
    });

    test('未知影響記號原樣保留成字串（合同只增不刪，舊前端如實承認不認得）', () async {
      final String body = _previewBody(
        impacts: <String>[..._fullImpacts, 'move_activity_membership'],
      );
      final GuestBindClaimPreviewReport report = await _api(
        <http.Request>[],
        responseOverride: body,
      ).guestBindPreview(ticket: _ticket);
      expect(report.impacts.last, 'move_activity_membership');
    });

    test('預覽與執行都不帶任何來源／目標標識欄：那兩格釘在憑證行上', () async {
      final List<http.Request> sent = <http.Request>[];
      await _api(sent).guestBindConfirm(ticket: _ticket);
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.containsKey('source_account_id'), isFalse);
      expect(body.containsKey('target_account_id'), isFalse);
      expect(body.containsKey('account_id'), isFalse);
    });
  });

  group('本人清單端點合同', () {
    test('guestBindingsList 發 GET；空清單是 [] 而不是欄位缺席', () async {
      final List<http.Request> sent = <http.Request>[];
      final GuestBindingListReport empty = await _api(
        sent,
        responseOverride: _listBody(total: 0),
      ).guestBindingsList();

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, kAuthGuestBindingsPath);
      expect(empty.bindings, isEmpty);
      expect(empty.bindings, isNotNull);
      expect(empty.total, 0);

      final GuestBindingListReport one = await _api(<http.Request>[])
          .guestBindingsList();
      expect(one.bindings.single.sourceAccountId, _sourceId);
      expect(one.bindings.single.sourceLoginName, 'guest_seed_name');
      expect(
        one.bindings.single.consentMode,
        kBindPreflightConsentModeTargetSelfInitiated,
      );
    });

    test('total 與實際行數不符判合同違例（回顯的總數不能與清單各說一套）', () async {
      expect(
        await _failure(
          () => _api(
            <http.Request>[],
            responseOverride: _listBody(total: 3, item: _listItem()),
          ).guestBindingsList(),
        ),
        isA<ApiError>().having(
          (ApiError e) => e.kind,
          'kind',
          ApiErrorKind.invalidResponse,
        ),
      );
    });

    test('清單行裡沒有憑據格子，未知新欄位容忍', () async {
      final String body = _listBody(
        item: _listItem().replaceFirst(
          '"consent_mode":"target_self_initiated"}',
          '"consent_mode":"target_self_initiated","server_note":"hello"}',
        ),
      );
      final GuestBindingListReport report = await _api(
        <http.Request>[],
        responseOverride: body,
      ).guestBindingsList();
      expect(report.bindings.single.revokedSessions, 2);
    });
  });

  group('新機器碼合同', () {
    test('2025 與 2026 各自可判別、不與相鄰幾枚互換', () {
      expect(ApiMachineCode.bindTicketInvalid.value, 2025);
      expect(ApiMachineCode.bindPlanStale.value, 2026);
      expect(ApiMachineCode.fromValue(2025), ApiMachineCode.bindTicketInvalid);
      expect(ApiMachineCode.fromValue(2026), ApiMachineCode.bindPlanStale);
      expect(ApiMachineCode.fromValue(2027), isNull);
      // 已發布的數值不得重用：整張表的數值必須兩兩不同（新增一枚也不能撞到舊值）。
      final List<int> values = ApiMachineCode.values
          .map((ApiMachineCode c) => c.value)
          .toList();
      expect(values.toSet().length, values.length);
    });

    test('兩枚碼的失敗信封都能解析成對應碼（界面靠碼選句子）', () async {
      for (final (int status, ApiMachineCode code) in <(int, ApiMachineCode)>[
        (403, ApiMachineCode.bindTicketInvalid),
        (409, ApiMachineCode.bindPlanStale),
      ]) {
        final Object? failure = await _failure(
          () => _api(
            <http.Request>[],
            responseOverride:
                '{"code":${code.value},"message":"nope","request_id":"r-fail"}',
            status: status,
          ).guestBindConfirm(ticket: _ticket),
        );
        expect(failure, isA<ApiError>());
        final ApiError error = failure as ApiError;
        expect(error.knownCode, code);
        // 兩枚碼都不是「重試就會好」：憑據用掉就是用掉，舊計劃重發仍是舊計劃。
        expect(error.retryable, isFalse);
      }
    });
  });
}
