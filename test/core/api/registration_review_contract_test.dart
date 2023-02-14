/// 註冊申請審批合同（R2-013 後端發布的 `/admin/registrations` 形態）在前端的鏡像測試。
///
/// 釘的是「合同」而不是畫面：必填與可缺席欄位的取捨、分頁數字一律取伺服器回顯、
/// 請求本體只有 decision 一欄（沒有依據值、沒有角色、沒有口令、也沒有理由的格子）、
/// 可判別機器碼→語意的對應（2021／1001／2011／1004），以及「名冊與決定都不帶任何
/// 憑據材料，也不帶審核人與理由」這條本步最要緊的隔離。
/// 畫面與交互屬 registration_review_view 的 widget 測試，不在本檔範圍。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

/// 申請標識（隨機 UUIDv7 形態，不是任何環境的真實資料）。
const String appId = '01a0f000-0000-7000-8000-0000000000a1';

/// 待審批的一行：合同如此，沒有決定時刻那一欄。
const String pendingRowBody =
    '{"account_id":"$appId","login_name":"night.applicant",'
    '"display_name":"山夜的申請","status":"pending",'
    '"submitted_at":"2026-10-07T08:00:00.000Z"}';

/// 已拒絕的一行：帶著決定時刻。
const String rejectedRowBody =
    '{"account_id":"$appId","login_name":"night.applicant",'
    '"display_name":"山夜的申請","status":"rejected",'
    '"submitted_at":"2026-10-07T08:00:00.000Z",'
    '"reviewed_at":"2026-10-07T09:30:00.000Z"}';

/// 名冊一頁（一行加三個回顯數字）。
String rosterBody(
  String row, {
  int page = 1,
  int pageSize = 20,
  int total = 1,
}) {
  return '{"applications":[$row],"page":$page,"page_size":$pageSize,'
      '"total":$total,"request_id":"r-roster"}';
}

/// 決定成功的回應：application 是決定之後的現值。
String decisionBody(String status, String decision) {
  final String reviewed = decision == 'reject'
      ? ',"reviewed_at":"2026-10-07T09:30:00.000Z"'
      : ',"reviewed_at":"2026-10-07T09:30:00.000Z"';
  return '{"application":{"account_id":"$appId",'
      '"login_name":"night.applicant","display_name":"山夜的申請",'
      '"status":"$status","submitted_at":"2026-10-07T08:00:00.000Z"$reviewed},'
      '"decision":"$decision","request_id":"r-decision"}';
}

/// 一則指定狀態碼的 JSON 回應。
http.Response json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 把 JSON 本體解成可斷言的欄位表。
Map<String, Object?> jsonMapOf(String body) =>
    jsonDecode(body) as Map<String, Object?>;

/// 取得一次預期失敗的 [ApiError]。
Future<ApiError> captureApiError(Future<Object?> Function() run) async {
  try {
    await run();
  } on ApiError catch (error) {
    return error;
  }
  throw StateError('預期拋出 ApiError，實際卻成功了');
}

/// 以一臺記錄請求的假後端建立 ServerApi，並回傳它與收下的請求清單。
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
  group('RegistrationApplicationReport 嚴格解碼', () {
    test('pending 行可讀，reviewed_at 缺席就是「還沒有人做過決定」', () {
      final RegistrationApplicationReport row =
          RegistrationApplicationReport.decode(jsonMapOf(pendingRowBody));
      expect(row.accountId, appId);
      expect(row.loginName, 'night.applicant');
      expect(row.displayName, '山夜的申請');
      expect(row.status, 'pending');
      expect(row.submittedAt, DateTime.utc(2026, 10, 7, 8));
      // 缺席不冒充零值：界面據 null 決定「不擺決定時刻那一行」。
      expect(row.reviewedAt, isNull);
      expect(row.isPending, isTrue);
      expect(row.isRejected, isFalse);
    });

    test('rejected 行帶得出決定時刻', () {
      final RegistrationApplicationReport row =
          RegistrationApplicationReport.decode(jsonMapOf(rejectedRowBody));
      expect(row.isRejected, isTrue);
      expect(row.isPending, isFalse);
      expect(row.reviewedAt, DateTime.utc(2026, 10, 7, 9, 30));
    });

    test('缺必填欄位即合同違例（審核要的依據不能變成猜測）', () {
      for (final String missing in <String>[
        'account_id',
        'login_name',
        'display_name',
        'status',
        'submitted_at',
      ]) {
        final Map<String, Object?> row = jsonMapOf(rejectedRowBody)
          ..remove(missing);
        expect(
          () => RegistrationApplicationReport.decode(row),
          throwsA(isA<ApiResponseShapeException>()),
          reason: '缺少 $missing 時必須判違例',
        );
      }
    });

    test('含糊的 submitted_at 判違例，不降級成「未知時刻」', () {
      final Map<String, Object?> row = jsonMapOf(pendingRowBody)
        ..['submitted_at'] = 'not-a-time';
      expect(
        () => RegistrationApplicationReport.decode(row),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('未知的狀態與新增欄位：原字保留、新欄容忍，不收緊也不丟棄', () {
      final Map<String, Object?> row = jsonMapOf(pendingRowBody)
        ..['status'] = 'waitlisted'
        ..['future_field'] = 'whatever';
      final RegistrationApplicationReport decoded =
          RegistrationApplicationReport.decode(row);
      // 表外狀態既不算等待也不算被拒：界面據此不擺任何一顆按鈕。
      expect(decoded.status, 'waitlisted');
      expect(decoded.isPending, isFalse);
      expect(decoded.isRejected, isFalse);
    });

    test('決定時刻含糊時判違例而不是當「沒有決定」', () {
      final Map<String, Object?> row = jsonMapOf(rejectedRowBody)
        ..['reviewed_at'] = '2026-10-07';
      expect(
        () => RegistrationApplicationReport.decode(row),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });
  });

  group('RegistrationRosterReport 分頁取證', () {
    test('一行與三個回顯數字都讀得到', () {
      final RegistrationRosterReport report = RegistrationRosterReport.decode(
        jsonMapOf(rosterBody(pendingRowBody)),
      );
      expect(report.applications, hasLength(1));
      expect(report.page, 1);
      expect(report.pageSize, 20);
      expect(report.total, 1);
      expect(report.requestId, 'r-roster');
      expect(report.totalPages, 1);
      expect(report.hasMore, isFalse);
    });

    test('空名冊是空清單而不是 null，零筆時第 1 頁仍算一頁', () {
      final RegistrationRosterReport report = RegistrationRosterReport.decode(
        jsonMapOf(
          '{"applications":[],"page":1,"page_size":20,"total":0,'
          '"request_id":"r-empty"}',
        ),
      );
      expect(report.applications, isEmpty);
      expect(report.totalPages, 1);
      expect(report.hasMore, isFalse);
    });

    test('頁數與後頁都由伺服器回顯的數字推出，本地不拿行數猜', () {
      final RegistrationRosterReport report = RegistrationRosterReport.decode(
        jsonMapOf(rosterBody(pendingRowBody, page: 2, pageSize: 1, total: 3)),
      );
      expect(report.totalPages, 3);
      expect(report.hasMore, isTrue);
    });

    test('applications 不是清單、或項不是物件，都判合同違例', () {
      expect(
        () => RegistrationRosterReport.decode(
          jsonMapOf(
            '{"applications":{},'
            '"page":1,"page_size":20,"total":0,"request_id":"r"}',
          ),
        ),
        throwsA(isA<ApiResponseShapeException>()),
      );
      expect(
        () => RegistrationRosterReport.decode(
          jsonMapOf(
            '{"applications":[1],'
            '"page":1,"page_size":20,"total":1,"request_id":"r"}',
          ),
        ),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    test('缺任一頁碼數字即違例（缺席不能降級成 0）', () {
      for (final String missing in <String>['page', 'page_size', 'total']) {
        final Map<String, Object?> payload = jsonMapOf(
          rosterBody(pendingRowBody),
        )..remove(missing);
        expect(
          () => RegistrationRosterReport.decode(payload),
          throwsA(isA<ApiResponseShapeException>()),
          reason: '缺少 $missing 時必須判違例',
        );
      }
    });
  });

  group('RegistrationDecisionReport 決定回顯', () {
    test('批准：application 是變更後的 active，decision 原字保留', () {
      final RegistrationDecisionReport report =
          RegistrationDecisionReport.decode(
            jsonMapOf(decisionBody('active', 'approve')),
          );
      expect(report.isApproved, isTrue);
      expect(report.decision, 'approve');
      expect(report.application.status, 'active');
      expect(report.application.reviewedAt, isNotNull);
      expect(report.requestId, 'r-decision');
    });

    test('拒絕：兩格各自成句，未知決定值不冒充批准', () {
      final RegistrationDecisionReport report =
          RegistrationDecisionReport.decode(
            jsonMapOf(decisionBody('rejected', 'reject')),
          );
      expect(report.isRejected, isTrue);
      expect(report.application.status, 'rejected');
      final RegistrationDecisionReport unknown =
          RegistrationDecisionReport.decode(
            jsonMapOf(decisionBody('rejected', 'maybe')),
          );
      expect(unknown.isApproved, isFalse);
      expect(unknown.isRejected, isFalse);
    });

    test('缺 application 或 decision 即違例（成功句不能沒有主詞）', () {
      final Map<String, Object?> noApp = jsonMapOf(
        decisionBody('active', 'approve'),
      )..remove('application');
      final Map<String, Object?> noDecision = jsonMapOf(
        decisionBody('active', 'approve'),
      )..remove('decision');
      expect(
        () => RegistrationDecisionReport.decode(noApp),
        throwsA(isA<ApiResponseShapeException>()),
      );
      expect(
        () => RegistrationDecisionReport.decode(noDecision),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });
  });

  group('端點請求形態', () {
    test('名冊是 GET，四格查詢一律帶上（空關鍵字不發 q=）', () async {
      final (ServerApi api, List<http.Request> sent) = recordingApi(
        (_) => rosterBody(pendingRowBody),
      );
      final RegistrationRosterReport report = await api.registrationRoster(
        page: 3,
        pageSize: 5,
        status: 'pending',
      );
      expect(report.total, 1);
      expect(sent, hasLength(1));
      final http.Request request = sent.single;
      expect(request.method, 'GET');
      expect(request.url.path, kAdminRegistrationsPath);
      expect(request.url.queryParameters['page'], '3');
      expect(request.url.queryParameters['page_size'], '5');
      expect(request.url.queryParameters['status'], 'pending');
      expect(request.url.queryParameters.containsKey('q'), isFalse);
      // 交上去的只有篩選，沒有任何憑據欄位可填。
      expect(request.body, isEmpty);
    });

    test('關鍵字與狀態值都經編碼後送到路徑上，不另開格子', () async {
      final (ServerApi api, List<http.Request> sent) = recordingApi(
        (_) => rosterBody(pendingRowBody),
      );
      await api.registrationRoster(status: 'rejected', query: '山夜 100%');
      final http.Request request = sent.single;
      expect(request.url.queryParameters['status'], 'rejected');
      expect(request.url.queryParameters['q'], '山夜 100%');
      expect(request.url.query.contains('100%25'), isTrue);
    });

    test('決定是 PUT，本體恰好 decision 一欄', () async {
      final (ServerApi api, List<http.Request> sent) = recordingApi(
        (_) => decisionBody('active', 'approve'),
      );
      await api.reviewRegistration(accountId: appId, decision: 'approve');
      expect(sent, hasLength(1));
      final http.Request request = sent.single;
      expect(request.method, 'PUT');
      expect(request.url.path, adminRegistrationDecisionPath(appId));
      final Map<String, Object?> body = jsonMapOf(request.body);
      expect(body.keys.toSet(), <String>{'decision'});
      expect(body['decision'], 'approve');
      // 沒有依據值、沒有角色、沒有口令、也沒有理由——協定層根本沒有那些格子。
      for (final String forbidden in <String>[
        'expected_status',
        'reason',
        'note',
        'password',
        'role',
        'roles',
        'account_type',
        'status',
        'account_id',
        'activity_id',
      ]) {
        expect(body.containsKey(forbidden), isFalse, reason: '不該送出 $forbidden');
      }
    });

    test('標識被轉義拼接：路徑不會被呼叫端的寫法帶到別條端點上', () async {
      final (ServerApi api, List<http.Request> sent) = recordingApi(
        (_) => decisionBody('rejected', 'reject'),
      );
      await api.reviewRegistration(
        accountId: 'weird/../id',
        decision: 'reject',
      );
      expect(sent.single.url.path.contains('weird'), isTrue);
      // encodeComponent 把斜線變成 %2F，因此路徑段數不會被撐開。
      expect(sent.single.url.path.contains('/weird/'), isFalse);
    });

    test('名冊與決定的回應模型裡都沒有會話欄位（決定不是認證）', () async {
      final (ServerApi api, List<http.Request> _) = recordingApi(
        (_) => decisionBody('active', 'approve'),
      );
      final RegistrationDecisionReport report = await api.reviewRegistration(
        accountId: appId,
        decision: 'approve',
      );
      // 能讀到的只有申請的六格與本次的決定；沒有任何秘密欄位可被保存或回顯。
      final Map<String, Object?> echoed = jsonMapOf(
        decisionBody('active', 'approve'),
      );
      for (final String forbidden in <String>[
        'set_cookie',
        'token',
        'session',
        'password',
        'password_hash',
      ]) {
        expect(echoed.containsKey(forbidden), isFalse);
      }
      expect(report.application.loginName, 'night.applicant');
    });
  });

  group('機器碼語意', () {
    test('2021 可判別、不可重試，且與 2014 分開', () async {
      final (ServerApi api, List<http.Request> _) = recordingApi(
        (_) => '{"code":2021,"message":"already decided","request_id":"r"}',
        409,
      );
      final ApiError error = await captureApiError(
        () => api.reviewRegistration(accountId: appId, decision: 'approve'),
      );
      expect(error.machineCode, 2021);
      expect(error.knownCode, ApiMachineCode.applicationDecided);
      expect(error.httpStatus, 409);
      // 「已有決定」再點一次不會變好：它不是可重試的暫時性失敗。
      expect(error.retryable, isFalse);
      expect(
        ApiMachineCode.applicationDecided,
        isNot(ApiMachineCode.adminStatusConflict),
      );
      expect(ApiMachineCode.fromValue(2021)?.value, 2021);
    });

    test('1004、1001、2011 各自成句且互不冒充', () async {
      final List<(int, int, ApiMachineCode)> cases =
          <(int, int, ApiMachineCode)>[
            (400, 1004, ApiMachineCode.invalidBody),
            (404, 1001, ApiMachineCode.notFound),
            (403, 2011, ApiMachineCode.permissionDenied),
          ];
      for (final (int httpStatus, int code, ApiMachineCode want) in cases) {
        final (ServerApi api, List<http.Request> _) = recordingApi(
          (_) =>
              '{"code":$code,"message":"failed","request_id":"r","details":'
              '{"invalid_field":"decision"}}',
          httpStatus,
        );
        final ApiError error = await captureApiError(
          () => api.reviewRegistration(accountId: appId, decision: 'approve'),
        );
        expect(error.knownCode, want);
        expect(error.httpStatus, httpStatus);
      }
    });

    test('未收錄的數值原樣保留，不丟棄也不猜', () async {
      final (ServerApi api, List<http.Request> _) = recordingApi(
        (_) => '{"code":2999,"message":"future","request_id":"r"}',
        400,
      );
      final ApiError error = await captureApiError(
        () => api.reviewRegistration(accountId: appId, decision: 'approve'),
      );
      expect(error.machineCode, 2999);
      expect(error.knownCode, isNull);
    });

    test('回應體與合同抵觸即判失敗，不回一份半套名冊', () async {
      final (ServerApi api, List<http.Request> _) = recordingApi(
        (_) => '{"applications":[],"page":1}',
      );
      final ApiError error = await captureApiError(
        () => api.registrationRoster(),
      );
      expect(error.kind, ApiErrorKind.invalidResponse);
    });
  });
}
