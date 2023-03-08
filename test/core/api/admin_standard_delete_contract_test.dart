/// 「普通帳戶與訪戶軟刪除」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：DELETE 的方法與路徑、**本體一個欄位都不帶**這件事、
/// 成功回應的必填欄位（`revoked_sessions` 缺席判合同違例而不是降級成 0——界面那句
/// 「這次讓 N 臺裝置失去登入狀態」猜不得）、兩種終態在前端的可判別性
/// （`deleted` 與 `retired` 是两个值而不是一個旗標）、時刻欄位的缺席與解析規則，
/// 以及 2027／2028 兩枚新碼各自成句、都不被當成「重試就會好」。
/// 未知新欄位一律容忍（後端只增不刪），但必填欄位缺席必須失敗而不是補一個假值。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

const String _deletedAccountId = '01a0f000-0000-7000-8000-0000000000ad';
const String _retiredAccountId = '01a0f000-0000-7000-8000-0000000000ae';

/// 一行的可展示事實（與後端 standardAccountItem 同源）。
String _accountJson({
  required String id,
  required String status,
  String loginName = 'del.contract.target',
  String displayName = 'DEL_20261010_合約原名',
  String accountType = 'standard',
  String? deletedAt,
  String? retiredAt,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"account_id":"$id"',
    '"login_name":"$loginName"',
    '"display_name":"$displayName"',
    '"account_type":"$accountType"',
    '"status":"$status"',
    '"must_change_password":false',
    '"created_at":"2026-09-01T00:00:00.000Z"',
  ];
  if (deletedAt != null) parts.add('"deleted_at":"$deletedAt"');
  if (retiredAt != null) parts.add('"retired_at":"$retiredAt"');
  if (extraField != null) parts.add(extraField);
  return '{${parts.join(',')}}';
}

/// DELETE 成功回應本體。
String _deleteBody({String? account, int? revokedSessions = 3}) {
  final List<String> parts = <String>[
    '"account":${account ?? _accountJson(id: _deletedAccountId, status: 'deleted', deletedAt: '2026-10-10T09:30:00.000Z')}',
    '"request_id":"r-del"',
  ];
  if (revokedSessions != null) {
    parts.insert(1, '"revoked_sessions":$revokedSessions');
  }
  return '{${parts.join(',')}}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

Future<Object?> _failure(
  Future<Object?> Function(ServerApi api) call, {
  required int status,
  required int code,
}) async {
  final ServerApi api = apiWithHandler(
    (http.Request request) async => _json(
      '{"code":$code,"message":"server sentence","request_id":"r-fail"}',
      status,
    ),
  );
  Object? succeeded;
  try {
    succeeded = await call(api);
  } on ApiError catch (error) {
    return error;
  }
  // 走到這裡代表伺服器沒有拒絕：合同測試要在這裡失敗，而不是讓用例悄悄通過。
  throw StateError('預期抛出 ApiError，卻拿到一次成功：$succeeded');
}

void main() {
  group('刪除端點合同', () {
    test('deleteStandardAccount 發 DELETE、打的是詳情那條父路徑、且不帶本體', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_deleteBody(), 200);
      });

      final StandardAccountDeleteReport report = await api
          .deleteStandardAccount(accountId: _deletedAccountId);

      expect(sent.single.method, 'DELETE');
      expect(sent.single.url.path, adminAccountItemPath(_deletedAccountId));
      // 本體是空的：這條通路沒有依據值、沒有原因文本、也沒有「順帶物理清庫」的欄位。
      // 介面若在這裡多塞一欄，等於替一個不存在的選項假造出口。
      expect(sent.single.body, isEmpty);
      expect(report.account.status, 'deleted');
      expect(report.account.isDeleted, isTrue);
      expect(report.account.isTerminal, isTrue);
      expect(report.revokedSessions, 3);
      expect(report.requestId, 'r-del');
    });

    test('revoked_sessions 缺席判合同違例，不降級成 0', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_deleteBody(revokedSessions: null), 200),
      );
      expect(
        () => api.deleteStandardAccount(accountId: _deletedAccountId),
        throwsA(isA<ApiError>()),
      );
    });

    test('account 缺席或形態不對一樣判違例（界面不能拿空物件當作刪除後的真相）', () async {
      for (final String body in <String>[
        '{"revoked_sessions":0,"request_id":"r-x"}',
        '{"account":"not-an-object","revoked_sessions":0,"request_id":"r-x"}',
      ]) {
        final ServerApi api = apiWithHandler(
          (http.Request request) async => _json(body, 200),
        );
        expect(
          () => api.deleteStandardAccount(accountId: _deletedAccountId),
          throwsA(isA<ApiError>()),
          reason: body,
        );
      }
    });

    test('回應帶未知新欄位時容忍（後端只增不刪）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _deleteBody(
            account: _accountJson(
              id: _deletedAccountId,
              status: 'deleted',
              deletedAt: '2026-10-10T09:30:00.000Z',
              extraField: '"future_field":42',
            ),
          ),
          200,
        ),
      );
      final StandardAccountDeleteReport report = await api
          .deleteStandardAccount(accountId: _deletedAccountId);
      expect(report.account.isDeleted, isTrue);
    });
  });

  group('兩種終態在前端的判讀', () {
    test('deleted 帶 deleted_at、retired 帶 retired_at，未刪除時該欄缺席而不是零值', () {
      final StandardAccountReport deleted = StandardAccountReport.decode(
        jsonDecode(
          _accountJson(
            id: _deletedAccountId,
            status: 'deleted',
            deletedAt: '2026-10-10T09:30:00.000Z',
          ),
        ) as Map<String, Object?>,
      );
      final StandardAccountReport retired = StandardAccountReport.decode(
        jsonDecode(
          _accountJson(
            id: _retiredAccountId,
            status: 'retired',
            displayName: '已被綁走的旅人',
            accountType: 'guest',
            retiredAt: '2026-10-09T12:00:00.000Z',
          ),
        ) as Map<String, Object?>,
      );
      final StandardAccountReport alive = StandardAccountReport.decode(
        jsonDecode(
          _accountJson(
            id: _deletedAccountId,
            status: 'active',
            displayName: '還在的',
          ),
        ) as Map<String, Object?>,
      );

      expect(deleted.isDeleted, isTrue);
      expect(deleted.isRetired, isFalse);
      expect(deleted.deletedAt, isNotNull);
      // 退休不是刪除：兩句在歷史裡的含義不同，前端不許把它們讀成同一個旗標。
      expect(retired.isRetired, isTrue);
      expect(retired.isDeleted, isFalse);
      expect(retired.isTerminal, isTrue);
      expect(retired.retiredAt, isNotNull);
      expect(alive.isTerminal, isFalse);
      expect(alive.deletedAt, isNull);
    });

    test('顯示名不透明化由服務端決定：前端不改寫、也不從別處推一個名字', () {
      final StandardAccountReport deleted = StandardAccountReport.decode(
        jsonDecode(_accountJson(id: _deletedAccountId, status: 'deleted'))
            as Map<String, Object?>,
      );
      expect(deleted.displayName, 'DEL_20261010_合約原名');
      expect(deleted.loginName, 'del.contract.target');
    });

    test('deleted_at 寫法不合法判合同違例，不降級成「沒有刪除時刻」', () {
      expect(
        () => StandardAccountReport.decode(
          jsonDecode(
            _accountJson(
              id: _deletedAccountId,
              status: 'deleted',
              deletedAt: 'not-a-timestamp',
            ),
          ) as Map<String, Object?>,
        ),
        throwsA(isA<Object>()),
      );
    });
  });

  group('終態拒絕的兩枚碼', () {
    test('2027 與 2028 各自可判別，且都不是「重試就會好」', () async {
      final List<(int, int, ApiMachineCode)> cases =
          <(int, int, ApiMachineCode)>[
            (409, 2027, ApiMachineCode.accountDeleted),
            (409, 2028, ApiMachineCode.accountRetired),
          ];
      for (final (int status, int code, ApiMachineCode expected) in cases) {
        final Object? failure = await _failure(
          (ServerApi api) =>
              api.deleteStandardAccount(accountId: _deletedAccountId),
          status: status,
          code: code,
        );
        expect(failure, isA<ApiError>());
        final ApiError error = failure as ApiError;
        expect(error.knownCode, expected);
        expect(error.retryable, isFalse);
      }
    });

    test('1004（本體多帶了欄位）仍是可判別的輸入拒絕，不被讀成終態', () async {
      final Object? failure = await _failure(
        (ServerApi api) => api.updateStandardAccountProfile(
          accountId: _deletedAccountId,
          displayName: '新名字',
          expectedDisplayName: '舊名字',
        ),
        status: 400,
        code: 1004,
      );
      final ApiError error = failure as ApiError;
      expect(error.knownCode, ApiMachineCode.invalidBody);
      expect(error.knownCode, isNot(ApiMachineCode.accountDeleted));
    });
  });
}
