/// 會話控制器的「本人改密」入口測試：每一種結局都要落對狀態。
///
/// 全部走真實控制器＋假傳輸＋記憶體安全儲存：要釘的是「伺服器回什麼 → 本機憑據與
/// 狀態怎麼變」——成功必須真的進入退出態並清掉已存秘密（含這一臺，已批準策略），
/// 現行口令不對不能踢人，1004 的兩種由來要分得開，連不上不能被講成改密成功或登出。
/// 另附合同的 `must_change_password` 欄位解碼證據：缺席容忍、壞型別必拒。
library;

import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/core/session/session_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';
import '../../support/test_server.dart';
import '../../support/test_session.dart';

/// 測試專屬的假口令：只活在本進程，不是任何環境的憑據。
const String _current = 'pw-current';
const String _newer = 'pw-newer';

http.Response jsonError(
  int status,
  int code,
  String requestId, {
  String? details,
}) {
  final String tail = details == null ? '' : ',"details":$details';
  return http.Response(
    '{"code":$code,"message":"server text","request_id":"$requestId"$tail}',
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

/// 一則改密成功回應：只有被撤銷的會話數與關聯 ID，沒有任何口令欄位。
http.Response changedOk(int revoked) =>
    jsonOk('{"revoked_sessions":$revoked,"request_id":"r-pw"}');

ServerApi _api({
  required ServerAddressSettings settings,
  Future<http.Response> Function(http.Request)? onChange,
  void Function(http.Request)? onAny,
}) {
  return ServerApi(
    config: ServerApiConfig(source: settings),
    client: MockClient((http.Request request) async {
      onAny?.call(request);
      switch (request.url.path) {
        case kAuthPasswordChangePath:
          return onChange == null ? changedOk(2) : await onChange(request);
        default:
          return jsonOk('{}');
      }
    }),
  );
}

/// 帶「首次登入必須改密」旗標的帳戶登入成果。
LoginExchange accountExchangeNeedingChange({bool mustChange = true}) {
  return LoginExchange(
    report: LoginReport(
      subjectKind: AuthSubjectKind.account,
      accountId: 'acct-pw-1',
      deviceId: 'device-pw',
      expiresAt: DateTime.utc(2026, 10, 2, 3, 4, 5),
      requestId: 'r-login-pw',
      mustChangePassword: mustChange,
    ),
    sessionSecret: 'tok-pw-1',
  );
}

void main() {
  late ServerAddressSettings settings;
  late InMemorySessionPersistence store;

  setUp(() async {
    settings = await buildAddressSettings(
      storedUrl: reachableUrl,
      reachable: <String>[reachableUrl],
    );
    store = InMemorySessionPersistence();
  });

  Future<SessionController> signIn() => signedInSession(
    api: _api(settings: settings),
    addresses: settings,
    persistence: store,
    exchange: accountExchangeNeedingChange(),
  );

  Future<SessionPasswordChangeOutcome> change(
    SessionController session, {
    String current = _current,
    String newer = _newer,
  }) => session.changePassword(currentPassword: current, newPassword: newer);

  group('本人改密', () {
    testWidgets('changed：進入退出態、清除本機與已存憑據', (WidgetTester tester) async {
      final SessionController session = await signIn();
      expect(session.mustChangePassword, isTrue);
      final SessionPasswordChangeOutcome outcome = await change(session);

      expect(outcome, SessionPasswordChangeOutcome.changed);
      expect(session.status, SessionStatus.signedOut);
      expect(session.activeSession, isNull);
      expect(store.credentials, isEmpty, reason: '全部退出策略下，已存秘密必須刪除');
      expect(session.bearerFor(reachableUrl), isNull);
    });

    testWidgets('invalidCurrent（2001）：什麼都不動，仍停在已登入', (
      WidgetTester tester,
    ) async {
      final SessionController session = await signedInSession(
        api: _api(
          settings: settings,
          onChange: (_) async => jsonError(401, 2001, 'r'),
        ),
        addresses: settings,
        persistence: store,
        exchange: accountExchangeNeedingChange(),
      );
      final SessionPasswordChangeOutcome outcome = await change(
        session,
        current: '打錯的口令',
      );

      expect(outcome, SessionPasswordChangeOutcome.invalidCurrent);
      expect(session.status, SessionStatus.signedIn);
      expect(store.credentials, isNotEmpty);
    });

    testWidgets('samePassword（1004＋reason）與 invalidNew（1004）分岔', (
      WidgetTester tester,
    ) async {
      // 由假伺服器直接演練兩種 1004：細節帶 reason 與不帶，落點不同。
      final SessionController session2 = await signedInSession(
        api: _api(
          settings: settings,
          onChange: (_) async => jsonError(
            400,
            1004,
            'r',
            details: '{"reason":"same_as_current"}',
          ),
        ),
        addresses: settings,
        persistence: store,
        exchange: accountExchangeNeedingChange(),
      );
      final SessionController session3 = await signedInSession(
        api: _api(
          settings: settings,
          onChange: (_) async => jsonError(400, 1004, 'r'),
        ),
        addresses: settings,
        persistence: store,
        exchange: accountExchangeNeedingChange(),
      );
      expect(await change(session2), SessionPasswordChangeOutcome.samePassword);
      expect(await change(session3), SessionPasswordChangeOutcome.invalidNew);
      expect(session2.status, SessionStatus.signedIn);
      expect(session3.status, SessionStatus.signedIn);
    });

    testWidgets('expired（2003）：清憑據、狀態轉為失效', (WidgetTester tester) async {
      final SessionController session = await signedInSession(
        api: _api(
          settings: settings,
          onChange: (_) async => jsonError(401, 2003, 'r'),
        ),
        addresses: settings,
        persistence: store,
        exchange: accountExchangeNeedingChange(),
      );
      expect(await change(session), SessionPasswordChangeOutcome.expired);
      expect(session.status, SessionStatus.expired);
      expect(store.credentials, isEmpty);
    });

    testWidgets('unavailable（500／連不上）：保留狀態，不謊報', (WidgetTester tester) async {
      final SessionController session = await signedInSession(
        api: _api(
          settings: settings,
          onChange: (_) async => jsonError(500, 1000, 'r'),
        ),
        addresses: settings,
        persistence: store,
        exchange: accountExchangeNeedingChange(),
      );
      expect(await change(session), SessionPasswordChangeOutcome.unavailable);
      expect(session.status, SessionStatus.signedIn);
      expect(store.credentials, isNotEmpty);
    });

    testWidgets('未登入：不發請求，回 notSignedIn', (WidgetTester tester) async {
      int asks = 0;
      final SessionController session = nativeSession(
        api: _api(settings: settings, onAny: (_) => asks++),
        addresses: settings,
        persistence: store,
      );
      expect(await change(session), SessionPasswordChangeOutcome.notSignedIn);
      expect(asks, 0);
    });

    testWidgets('請求本體只有兩個口令欄，路徑與憑據注入走既有通路', (WidgetTester tester) async {
      String? capturedBody;
      final SessionController session = await signedInSession(
        api: _api(
          settings: settings,
          onChange: (http.Request request) async {
            capturedBody = request.body;
            return changedOk(1);
          },
        ),
        addresses: settings,
        persistence: store,
        exchange: accountExchangeNeedingChange(),
      );
      await change(session, current: _current, newer: _newer);

      expect(capturedBody, contains('"current_password":"$_current"'));
      expect(capturedBody, contains('"new_password":"$_newer"'));
      expect(capturedBody, isNot(contains('account_id')));
    });
  });

  group('must_change_password 欄位合同', () {
    testWidgets('登入回應：缺席容忍為 false，true 如實讀出，壞型別判失敗', (
      WidgetTester tester,
    ) async {
      final LoginReport absent = LoginReport.decode(<String, Object?>{
        'subject_kind': 'account',
        'account_id': 'acct-1',
        'device_id': 'dev-1',
        'expires_at': '2026-10-02T03:04:05.000Z',
        'request_id': 'r',
      });
      expect(absent.mustChangePassword, isFalse);

      final LoginReport flagged = LoginReport.decode(<String, Object?>{
        'subject_kind': 'account',
        'account_id': 'acct-1',
        'device_id': 'dev-1',
        'expires_at': '2026-10-02T03:04:05.000Z',
        'request_id': 'r',
        'must_change_password': true,
      });
      expect(flagged.mustChangePassword, isTrue);

      expect(
        () => LoginReport.decode(<String, Object?>{
          'subject_kind': 'account',
          'account_id': 'acct-1',
          'device_id': 'dev-1',
          'expires_at': '2026-10-02T03:04:05.000Z',
          'request_id': 'r',
          'must_change_password': 'yes',
        }),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });

    testWidgets('當前會話回應：true 讀出並反映到控制器 getter', (WidgetTester tester) async {
      final CurrentSessionReport report = CurrentSessionReport.decode(
        <String, Object?>{
          'subject_kind': 'account',
          'account_id': 'acct-1',
          'device_id': 'dev-1',
          'rotation_seq': 0,
          'created_at': '2026-09-30T03:04:05.000Z',
          'last_active_at': '2026-09-30T03:05:05.000Z',
          'expires_at': '2026-10-02T03:04:05.000Z',
          'request_id': 'r',
          'must_change_password': true,
        },
      );
      final ActiveSession active = ActiveSession.fromCurrentSession(report);
      expect(active.mustChangePassword, isTrue);
    });

    test('改密報告只讀兩個合同欄位', () {
      final PasswordChangeReport report = PasswordChangeReport.decode(
        <String, Object?>{'revoked_sessions': 3, 'request_id': 'r'},
      );
      expect(report.revokedSessions, 3);
      expect(report.requestId, 'r');
      expect(
        () => PasswordChangeReport.decode(<String, Object?>{'request_id': 'r'}),
        throwsA(isA<ApiResponseShapeException>()),
      );
    });
  });
}
