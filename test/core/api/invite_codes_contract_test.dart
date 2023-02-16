/// 伺服器級註冊邀請碼合同（R2-014 後端發布的 `/root/invite-codes` 形態）在前端的鏡像測試。
///
/// 釘的是「合同」而不是畫面：必填與可缺席欄位的取捨（到期／撤銷缺席是事實的缺席）、
/// 分頁數字一律取伺服器回顯、請求本體只有 label／max_uses／expires_at（沒有角色、狀態、
/// 帳戶、口令、活動的格子）、撤銷本體為空且刻意無依據值、明文碼只在簽發回應出現一次
/// 而名冊與撤銷回顯都不帶它，以及可判別機器碼 2022→語意、且與 2021／2014 分開。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

const String codeId = '01a0f000-0000-7000-8000-0000000000c1';

/// 永不過期、未撤銷的一行（active 形態：無 expires_at、無 revoked_at）。
const String activeRowBody =
    '{"code_id":"$codeId","label":"內測名額","status":"active",'
    '"max_uses":3,"used_count":1,"remaining":2,'
    '"created_at":"2026-10-07T08:00:00.000Z"}';

/// 已撤銷的一行（帶撤銷時刻）。
const String revokedRowBody =
    '{"code_id":"$codeId","label":"內測名額","status":"revoked",'
    '"max_uses":1,"used_count":0,"remaining":1,'
    '"created_at":"2026-10-07T08:00:00.000Z",'
    '"revoked_at":"2026-10-07T09:00:00.000Z"}';

String rosterBody(
  String row, {
  int page = 1,
  int pageSize = 20,
  int total = 1,
}) =>
    '{"invites":[$row],"page":$page,"page_size":$pageSize,"total":$total,'
    '"request_id":"r-roster"}';

const String issuedBody =
    '{"code":"Zm9vYmFyMTIzNDU2Nzg5MDEyMw",'
    '"invite":{"code_id":"$codeId","label":"內測名額","status":"active",'
    '"max_uses":1,"used_count":0,"remaining":1,'
    '"created_at":"2026-10-07T08:00:00.000Z"},"request_id":"r-issue"}';

const String revokeBody =
    '{"invite":{"code_id":"$codeId","label":"內測名額","status":"revoked",'
    '"max_uses":1,"used_count":0,"remaining":1,'
    '"created_at":"2026-10-07T08:00:00.000Z",'
    '"revoked_at":"2026-10-07T09:00:00.000Z"},"request_id":"r-revoke"}';

http.Response json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> jsonMapOf(String body) =>
    jsonDecode(body) as Map<String, Object?>;

Future<ApiError> captureApiError(Future<Object?> Function() run) async {
  try {
    await run();
  } on ApiError catch (error) {
    return error;
  }
  throw StateError('預期拋出 ApiError，實際卻成功了');
}

(ServerApi, List<http.Request>) recordingApi(
  String Function(http.Request request) bodyFor, [
  int status = 200,
]) {
  final List<http.Request> sent = <http.Request>[];
  final ServerApi api = apiWithHandler((http.Request request) async {
    sent.add(request);
    return json(bodyFor(request), status);
  });
  return (api, sent);
}

void main() {
  group('InviteCodeReport 嚴格解碼', () {
    test('active 行可讀；到期與撤銷缺席就是「沒這回事」，不冒充零值', () {
      final InviteCodeReport row = InviteCodeReport.decode(
        jsonMapOf(activeRowBody),
      );
      expect(row.codeId, codeId);
      expect(row.label, '內測名額');
      expect(row.status, 'active');
      expect(row.maxUses, 3);
      expect(row.usedCount, 1);
      expect(row.remaining, 2);
      expect(row.createdAt, DateTime.utc(2026, 10, 7, 8));
      expect(row.expiresAt, isNull);
      expect(row.revokedAt, isNull);
      expect(row.isRevoked, isFalse);
    });

    test('revoked 行帶得出撤銷時刻', () {
      final InviteCodeReport row = InviteCodeReport.decode(
        jsonMapOf(revokedRowBody),
      );
      expect(row.isRevoked, isTrue);
      expect(row.revokedAt, DateTime.utc(2026, 10, 7, 9));
    });

    test('表外狀態原字保留，不收緊成枚舉', () {
      final InviteCodeReport row = InviteCodeReport.decode(
        jsonMapOf(activeRowBody.replaceAll('"active"', '"recycled"')),
      );
      expect(row.status, 'recycled');
      expect(row.isRevoked, isFalse);
    });

    test('必填欄位缺失即合同違例', () {
      // 少 remaining 這一格：派生額度是名冊的必要元數據，缺席判失敗而非默認 0。
      expect(
        () => InviteCodeReport.decode(
          jsonMapOf(
            '{"code_id":"$codeId","label":"x","status":"active",'
            '"max_uses":1,"used_count":0,"created_at":"2026-10-07T08:00:00.000Z"}',
          ),
        ),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });
  });

  group('名冊回顯', () {
    test('分頁三個數字必填，頁數只由回顯推出', () {
      final InviteCodeRosterReport page = InviteCodeRosterReport.decode(
        jsonMapOf(rosterBody(activeRowBody, page: 3, pageSize: 2, total: 5)),
      );
      expect(page.invites.length, 1);
      expect(page.page, 3);
      expect(page.totalPages, 3);
      // total=5、page_size=2 → 3 頁；停在第 3 頁就是最後一頁。
      expect(page.hasMore, isFalse);
    });

    test('零筆時第 1 頁就是那個空但存在的頁', () {
      final InviteCodeRosterReport page = InviteCodeRosterReport.decode(
        jsonMapOf(
          '{"invites":[],"page":1,"page_size":20,"total":0,"request_id":"r"}',
        ),
      );
      expect(page.totalPages, 1);
      expect(page.hasMore, isFalse);
    });
  });

  test('簽發回應帶一次性明文碼與落庫那一行', () {
    final IssuedInviteCodeReport report = IssuedInviteCodeReport.decode(
      jsonMapOf(issuedBody),
    );
    expect(report.code, 'Zm9vYmFyMTIzNDU2Nzg5MDEyMw');
    expect(report.invite.status, 'active');
  });

  group('請求形態', () {
    test('名冊 GET 帶四參數，空關鍵字不發 q=', () async {
      final (ServerApi api, List<http.Request> sent) = recordingApi(
        (_) => rosterBody(activeRowBody),
      );
      await api.inviteCodeRoster(
        page: 2,
        pageSize: 10,
        status: 'active',
        query: '  ',
      );
      expect(sent.single.method, 'GET');
      final Uri uri = sent.single.url;
      expect(uri.path, '/root/invite-codes');
      expect(uri.queryParameters['page'], '2');
      expect(uri.queryParameters['page_size'], '10');
      expect(uri.queryParameters['status'], 'active');
      expect(uri.queryParameters.containsKey('q'), isFalse);
    });

    test('簽發 POST 本體只有 label（+ 可選額度/有效期），禁欄不出現', () async {
      final (ServerApi api, List<http.Request> sent) = recordingApi(
        (_) => issuedBody,
        201,
      );
      await api.issueInviteCode(
        label: '內測名額',
        maxUses: 5,
        expiresAt: '2026-12-31T00:00:00.000Z',
      );
      final Map<String, Object?> body = jsonMapOf(sent.single.body);
      expect(sent.single.method, 'POST');
      expect(body['label'], '內測名額');
      expect(body['max_uses'], 5);
      expect(body['expires_at'], '2026-12-31T00:00:00.000Z');
      for (final String forbidden in <String>[
        'role',
        'account_type',
        'status',
        'password',
        'code',
        'code_hash',
        'activity_id',
        'account_id',
        'max_uses_extra',
      ]) {
        expect(body.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });

    test('簽發缺席額度/有效期就不發該欄，交給後端默認', () async {
      final (ServerApi api, List<http.Request> sent) = recordingApi(
        (_) => issuedBody,
        201,
      );
      await api.issueInviteCode(label: '甲');
      final Map<String, Object?> body = jsonMapOf(sent.single.body);
      expect(body.keys, containsAll(<String>['label']));
      expect(body.containsKey('max_uses'), isFalse);
      expect(body.containsKey('expires_at'), isFalse);
    });

    test('撤銷 DELETE 掛在標識下、本體為空、標識不被撐開路徑段', () async {
      final (ServerApi api, List<http.Request> sent) = recordingApi(
        (_) => revokeBody,
      );
      await api.revokeInviteCode(codeId: 'a/b?c');
      expect(sent.single.method, 'DELETE');
      // encodeComponent 之後那枚標識仍是一個路徑段（斜槓與問號被轉義進同一段），
      // 證明它沒被拆成多段而改變「撤銷哪一枚」這句話。
      expect(sent.single.url.pathSegments, <String>[
        'root',
        'invite-codes',
        'a/b?c',
      ]);
    });

    test('名冊那一行不帶明文碼與會話材料（合同形狀）', () {
      final Map<String, Object?> row = jsonMapOf(activeRowBody);
      for (final String forbidden in <String>[
        'code',
        'code_hash',
        'token',
        'session',
        'cookie',
        'password',
        'roles',
      ]) {
        expect(row.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  group('機器碼', () {
    test('2022 可判別且 retryable=false，與 2021/2014 分開', () {
      final ApiMachineCode? code = ApiMachineCode.fromValue(2022);
      expect(code, ApiMachineCode.inviteAlreadyRevoked);
      final ApiError error = ApiError(
        kind: ApiErrorKind.httpStatus,
        path: '/root/invite-codes/$codeId',
        httpStatus: 409,
        machineCode: 2022,
      );
      expect(error.retryable, isFalse);
      expect(error.knownCode, ApiMachineCode.inviteAlreadyRevoked);
      // 與相鄰兩枚不互相冒充。
      expect(ApiMachineCode.fromValue(2021), ApiMachineCode.applicationDecided);
      expect(
        ApiMachineCode.fromValue(2014),
        ApiMachineCode.adminStatusConflict,
      );
    });

    test('未收錄數值原樣保留', () {
      final ApiError error = ApiError(
        kind: ApiErrorKind.httpStatus,
        path: '/root/invite-codes/$codeId',
        httpStatus: 418,
        machineCode: 2099,
      );
      expect(error.machineCode, 2099);
      expect(error.knownCode, isNull);
    });
  });

  test('合同牴觸（invites 不是清單）判失敗', () async {
    final (ServerApi api, _) = recordingApi(
      (_) =>
          '{"invites":{},"page":1,"page_size":20,"total":0,"request_id":"r"}',
    );
    final ApiError error = await captureApiError(() => api.inviteCodeRoster());
    expect(error.kind, ApiErrorKind.invalidResponse);
  });
}
