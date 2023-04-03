/// 「玩家分項限制與活動訪問控制」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：兩條新路的 HTTP 方法與精確路徑、編輯本體的逐對白名單
/// （只出現被選中的欄；新值與依據值成對；一欄都没選時完全不發請求）、
/// 名冊行與本人查閱的六欄現值、清單行的 access_restricted 派生格，
/// 以及 2043 在前端自成一值——不與 2011／1001／2013／2029／2033 混用。
///
/// 另一件事在這裡講死：未上線的業務不發碼——前端枚舉裡沒有任何一枚「聊天被擋」
/// 之類的碼；六欄之中只有 login 有對外通路（2043），其餘五欄今日只是被保存與
/// 顯示的現值（用戶批准：未實現的能力不得偽裝可用）。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
// （合同違例在存取層被包成 ApiError(invalidResponse)：断言一律問對外那句，
//  不抓內部型別，口徑同其餘合同檔的「缺席判合同違例」案例。）
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

const String _activityId = '01a1e000-0000-7000-8000-0000000000a1';
const String _memberId = '01a1e000-0000-7000-8000-0000000000m1';

/// 一行成員的回應片段（六欄限制的取值可指定，其餘走穩定佔位）。
String _memberJson({
  bool restrictLogin = false,
  bool restrictChat = false,
  bool restrictPrivateChat = false,
  bool restrictTrade = false,
  bool restrictTransfer = false,
  bool restrictItemUse = false,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"member_id":"$_memberId"',
    '"activity_id":"$_activityId"',
    '"account_id":"01a1e000-0000-7000-8000-0000000000b1"',
    '"nickname":"夜行者"',
    '"faction_id":""',
    '"display_name":"玩家甲"',
    '"account_status":"active"',
    '"directory_visibility":"inherit"',
    '"admin_identity":false',
    '"business_status":"normal"',
    '"custom_status_id":""',
    '"custom_status_name":""',
    '"status_display_name":""',
    '"status_available":true',
    '"restrict_login":$restrictLogin',
    '"restrict_chat":$restrictChat',
    '"restrict_private_chat":$restrictPrivateChat',
    '"restrict_trade":$restrictTrade',
    '"restrict_transfer":$restrictTransfer',
    '"restrict_item_use":$restrictItemUse',
    '"joined_at":"2026-10-10T03:00:00.000Z"',
    '"updated_at":"2026-10-10T04:00:00.000Z"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

/// 本人限制查閱的回應本體（六欄取值可指定）。
String _ownRestrictionsBody({
  bool restrictLogin = false,
  bool restrictTrade = false,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"member_id":"$_memberId"',
    '"restrict_login":$restrictLogin',
    '"restrict_chat":false',
    '"restrict_private_chat":false',
    '"restrict_trade":$restrictTrade',
    '"restrict_transfer":false',
    '"restrict_item_use":false',
    '"request_id":"r-own-restriction"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

/// 本人活動清單的一行（access_restricted 是服務端派生格）。
String _activityRow({bool accessRestricted = false}) {
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"name":"秋夜長談"',
    '"status":"active"',
    '"faction_select_mode":"free"',
    '"member_id":"$_memberId"',
    '"nickname":"夜行者"',
    '"faction_id":""',
    '"access_restricted":$accessRestricted',
    '"joined_at":"2026-10-10T03:00:00.000Z"',
  ];
  return '{${parts.join(',')}}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('兩條新路的協議形態', () {
    test('編輯走 PUT 到成員單筆下的 restrictions 子路徑', () {
      expect(
        adminActivityMemberRestrictionsPath(_activityId, _memberId),
        '/admin/activities/$_activityId/members/$_memberId/restrictions',
      );
      expect(
        adminActivityMemberRestrictionsPath(_activityId, 'x y'),
        contains('x%20y'),
      );
    });

    test('本人查閱走 GET 到 /player/activities/{id}/restrictions', () {
      expect(
        playerActivityRestrictionsPath(_activityId),
        '/player/activities/$_activityId/restrictions',
      );
    });

    test('updateMemberRestrictions 本體只出現被選中的欄，且新值與依據值成對', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(
          '{"member":${_memberJson(restrictLogin: true)},'
          '"request_id":"r-restriction-write"}',
          200,
        );
      });

      final MemberWriteReport report = await api.updateMemberRestrictions(
        activityId: _activityId,
        memberId: _memberId,
        restrictions: <String, MemberRestrictionPatch>{
          'restrict_login': const MemberRestrictionPatch(
            value: true,
            expected: false,
          ),
          'restrict_chat': const MemberRestrictionPatch(
            value: false,
            expected: true,
          ),
        },
      );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        adminActivityMemberRestrictionsPath(_activityId, _memberId),
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      // 恰好四格：兩對「新值＋依據值」；沒選中的四欄連格子都沒有。
      expect(body.keys.toSet(), <String>{
        'restrict_login',
        'expected_restrict_login',
        'restrict_chat',
        'expected_restrict_chat',
      });
      expect(body['restrict_login'], isTrue);
      expect(body['expected_restrict_login'], isFalse);
      expect(body['restrict_chat'], isFalse);
      expect(body['expected_restrict_chat'], isTrue);
      // 回應帶著回讀的現值：界面唸的是這一份，不是提交時的想法。
      expect(report.member.restrictLogin, isTrue);
      expect(report.member.restrictChat, isFalse);
      expect(report.member.hasAnyRestriction, isTrue);
    });

    test('一欄都没選時完全不發請求（客戶端先擋，不發注定 1004 的往返）', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json('{}', 500);
      });

      expect(
        () => api.updateMemberRestrictions(
          activityId: _activityId,
          memberId: _memberId,
          restrictions: <String, MemberRestrictionPatch>{},
        ),
        throwsA(isA<ArgumentError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sent, isEmpty);
    });
  });

  group('六欄現值與派生格的讀取', () {
    test('名冊行六欄逐欄恆在；缺席判合同違例（不降級成「沒被限制」）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"members":[${_memberJson(restrictLogin: true, restrictTrade: true)}],'
          '"request_id":"r-mem"}',
          200,
        ),
      );
      final MemberListReport report = await api.activityMembers(
        activityId: _activityId,
      );
      final MemberReport row = report.members.single;
      expect(row.restrictLogin, isTrue);
      expect(row.restrictTrade, isTrue);
      expect(row.restrictChat, isFalse);
      expect(row.restrictPrivateChat, isFalse);
      expect(row.restrictTransfer, isFalse);
      expect(row.restrictItemUse, isFalse);
      expect(row.hasAnyRestriction, isTrue);

      // 少一欄就是合同違例：把缺席讀成預設值會讓管理人以為自己剛凍結的那行還亮著。
      final String missing = _memberJson().replaceFirst(
        '"restrict_item_use":false,',
        '',
      );
      final ServerApi missingApi = apiWithHandler(
        (http.Request request) async =>
            _json('{"members":[$missing],"request_id":"r-mem"}', 200),
      );
      try {
        await missingApi.activityMembers(activityId: _activityId);
        fail('少一欄限制必須判合同違例，不降級成「沒被限制」');
      } on ApiError catch (caught) {
        expect(caught.kind, ApiErrorKind.invalidResponse);
      }
    });

    test('本人查閱六欄逐欄恆在；未知新欄位容忍', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _ownRestrictionsBody(
            restrictLogin: true,
            extraField: '"next_step_field":"whatever"',
          ),
          200,
        ),
      );
      final OwnMemberRestrictionsReport report = await api
          .ownMemberRestrictions(activityId: _activityId);
      expect(report.memberId, _memberId);
      expect(report.restrictLogin, isTrue);
      expect(report.restrictTrade, isFalse);
      expect(report.hasAnyRestriction, isTrue);

      final ServerApi missingApi = apiWithHandler(
        (http.Request request) async => _json(
          _ownRestrictionsBody().replaceFirst('"restrict_chat":false,', ''),
          200,
        ),
      );
      try {
        await missingApi.ownMemberRestrictions(activityId: _activityId);
        fail('本人查閱少一欄必須判合同違例');
      } on ApiError catch (caught) {
        expect(caught.kind, ApiErrorKind.invalidResponse);
      }
    });

    test('清單行帶著 access_restricted 派生格；缺席判合同違例', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"activities":[${_activityRow(accessRestricted: true)}],'
          '"request_id":"r-list"}',
          200,
        ),
      );
      final MyActivityListReport report = await api.myActivities();
      expect(report.activities.single.accessRestricted, isTrue);

      final ServerApi missingApi = apiWithHandler(
        (http.Request request) async => _json(
          '{"activities":[${_activityRow().replaceFirst('"access_restricted":false,', '')}],"request_id":"r-list"}',
          200,
        ),
      );
      try {
        await missingApi.myActivities();
        fail('清單行少 access_restricted 必須判合同違例');
      } on ApiError catch (caught) {
        expect(caught.kind, ApiErrorKind.invalidResponse);
      }
    });
  });

  group('2043 自成一值', () {
    test('數值、解析與「不與別碼混用」', () {
      expect(ApiMachineCode.memberAccessRestricted.value, 2043);
      expect(
        ApiMachineCode.fromValue(2043),
        ApiMachineCode.memberAccessRestricted,
      );
      // 下一枚未發碼仍是 2044：前端不得提前收錄一枚還沒發布的碼。
      expect(ApiMachineCode.fromValue(2044), isNull);
      // 它與「不屬於管理員這個身份面」（2011）、「查無／不可分辨」（1001）、
      // 「現值過期」（2013）、「終態／停止」（2029／2033）都是不同的句子：
      // 數值互不相同，處置各說各話。
      for (final ApiMachineCode other in <ApiMachineCode>[
        ApiMachineCode.notFound,
        ApiMachineCode.permissionDenied,
        ApiMachineCode.profileConflict,
        ApiMachineCode.activityArchived,
        ApiMachineCode.activityClosedWrites,
      ]) {
        expect(ApiMachineCode.memberAccessRestricted.value, isNot(other.value));
      }
      // 整張表的數值兩兩不同（新增一枚也不能撞到舊值）。
      final List<int> values = ApiMachineCode.values
          .map((ApiMachineCode c) => c.value)
          .toList();
      expect(values.toSet().length, values.length);
    });

    test('403／2043 的錯誤信封解析成這枚碼，而不是混進 2011', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"code":2043,"message":"restricted","request_id":"r-gate"}',
          403,
        ),
      );
      ApiError? caught;
      try {
        await api.ownMemberRestrictions(activityId: _activityId);
      } on ApiError catch (error) {
        caught = error;
      }
      expect(caught, isNotNull);
      expect(caught!.knownCode, ApiMachineCode.memberAccessRestricted);
    });
  });
}
