/// 「活動玩家目錄可見性」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：
/// * 兩條管理側路徑的方法與路徑（配置那條挂在活動子資源、覆蓋那條挂在成員子資源），
///   以及每條白名單**恰好**哪些欄位——配置只帶 `mode`＋`expected_mode`，
///   覆蓋只帶 `visibility`＋`expected_visibility`。兩側都沒有「哪個玩家」「哪個帳戶」，
///   更沒有一格能宣稱「用管理視角給我全部人」：那類欄位在前端也無處可填。
/// * 覆蓋的取值只有 inherit｜hidden 兩態，因此前端不該長出「單獨公開」那一格——
///   本檔把它釘成一句可執行的話：送 `visible` 這類值時前端照原樣送出，
///   而後端 1004 點名 `visibility`（合同上這是一枚「寫法不對」而不是一種新能力）。
/// * `member_directory_mode`（活動詳情）與 `directory_visibility`／`admin_identity`（名冊行）
///   都是必填：缺席判合同違例，不由界面降級成「當它沒覆蓋」「當他不是管理員」。
/// * 未知新欄位一律容忍（後端只增不刪）。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

const String _activityId = '01a1b000-0000-7000-8000-0000000000a1';
const String _memberId = '01a1b000-0000-7000-8000-0000000000m1';
const String _accountId = '01a1b000-0000-7000-8000-0000000000c1';

/// 一份活動詳情本體（本檔只关心 `member_directory_mode` 那一格在不在、值讀不讀得到）。
String _activityBody({
  String directoryMode = 'same_faction_only',
  bool omitMode = false,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"name":"秋夜長談"',
    '"description":""',
    '"status":"active"',
    '"faction_select_mode":"free"',
    if (!omitMode) '"member_directory_mode":"$directoryMode"',
    '"created_by_account_id":"$_accountId"',
    '"manager_count":1',
    '"created_at":"2026-10-10T03:00:00.000Z"',
    '"updated_at":"2026-10-10T04:00:00.000Z"',
    ?extraField,
  ];
  return '{"activity":{${parts.join(',')}},"request_id":"r-1"}';
}

/// 一行名冊本體（含兩格新投影）。[adminIdentity] 是服務端現讀的授予投影。
String _memberBody({
  String directoryVisibility = 'inherit',
  String adminIdentity = 'false',
  bool omitVisibility = false,
  bool omitAdminIdentity = false,
}) {
  final List<String> parts = <String>[
    '"member_id":"$_memberId"',
    '"activity_id":"$_activityId"',
    '"account_id":"$_accountId"',
    '"nickname":"夜行者"',
    '"faction_id":""',
    '"display_name":"名冊裡的玩家"',
    '"account_status":"active"',
    if (!omitVisibility) '"directory_visibility":"$directoryVisibility"',
    if (!omitAdminIdentity) '"admin_identity":$adminIdentity',
    '"joined_at":"2026-10-10T03:00:00.000Z"',
    '"updated_at":"2026-10-10T04:00:00.000Z"',
  ];
  return '{"member":{${parts.join(',')}},"request_id":"r-2"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 取出一條請求本體裡的欄位名集合（白名單「恰好哪些格」只這樣釘得住）。
Set<String> _bodyKeys(http.Request request) =>
    (jsonDecode(request.body) as Map<String, Object?>).keys.toSet();

Future<ApiError?> _failure(Future<void> Function() body) async {
  try {
    await body();
  } on ApiError catch (error) {
    return error;
  }
  return null;
}

void main() {
  group('活動那一欄配置', () {
    test('路徑是活動子資源，本體恰好 mode 與 expected_mode', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_activityBody(), 200);
      });

      final ActivityDetailReport report = await api.updateMemberDirectoryMode(
        activityId: _activityId,
        mode: 'all_players_except_admin',
        expectedMode: 'hidden',
      );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        adminActivityMemberDirectoryPath(_activityId),
      );
      expect(_bodyKeys(sent.single), <String>{'mode', 'expected_mode'});
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body['mode'], 'all_players_except_admin');
      expect(body['expected_mode'], 'hidden');
      // 回應讀回的是服務端寫後的現值，界面據此更新底稿而不是本地蓋值。
      expect(report.activity.memberDirectoryMode, 'same_faction_only');
    });

    test('路徑函數對標識做編碼（自訂活動標識不能拼出另一條路徑）', () {
      expect(
        adminActivityMemberDirectoryPath('a/b'),
        contains('a%2Fb'),
        reason: '路徑引數逐段編碼，否則一個標識就能多帶一段路徑',
      );
    });

    test('member_directory_mode 缺席判合同違例，不降級成「沒開放」', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_activityBody(omitMode: true), 200),
      );
      final ApiError? error = await _failure(
        () => api.updateMemberDirectoryMode(
          activityId: _activityId,
          mode: 'hidden',
          expectedMode: 'all_members',
        ),
      );
      expect(error, isNotNull, reason: '讀不懂那一欄時不猜預設值，直接判合同違例');
    });

    test('表外取值照實讀入（界面自己決定收起控件，模型不歸類）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_activityBody(directoryMode: 'everyone'), 200),
      );
      final ActivityDetailReport report = await api.updateMemberDirectoryMode(
        activityId: _activityId,
        mode: 'hidden',
        expectedMode: 'hidden',
      );
      expect(report.activity.memberDirectoryMode, 'everyone');
    });

    test('未知回應欄位被容忍（後端只增不刪）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_activityBody(extraField: '"future_field":123'), 200),
      );
      final ActivityDetailReport report = await api.updateMemberDirectoryMode(
        activityId: _activityId,
        mode: 'hidden',
        expectedMode: 'hidden',
      );
      expect(report.activity.memberDirectoryMode, 'same_faction_only');
    });
  });

  group('單一行成員的覆蓋', () {
    test('路徑是成員子資源，本體恰好 visibility 與 expected_visibility', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_memberBody(directoryVisibility: 'hidden'), 200);
      });

      final MemberWriteReport report = await api
          .updateMemberDirectoryVisibility(
            activityId: _activityId,
            memberId: _memberId,
            visibility: 'hidden',
            expectedVisibility: 'inherit',
          );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        adminMemberDirectoryVisibilityPath(_activityId, _memberId),
      );
      expect(_bodyKeys(sent.single), <String>{
        'visibility',
        'expected_visibility',
      });
      expect(report.member.directoryVisibility, 'hidden');
      expect(report.member.adminIdentity, isFalse);
    });

    test('本體沒有身分欄與管理視角那一格：前端也无處可填', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_memberBody(), 200);
      });
      await api.updateMemberDirectoryVisibility(
        activityId: _activityId,
        memberId: _memberId,
        visibility: 'inherit',
        expectedVisibility: 'hidden',
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      for (final String forbidden in <String>[
        'member_id',
        'account_id',
        'activity_id',
        'admin_view',
        'is_admin',
        'scope',
        'reason',
      ]) {
        expect(
          body.containsKey(forbidden),
          isFalse,
          reason: '$forbidden 無格子可填',
        );
      }
    });

    test('directory_visibility 與 admin_identity 任一缺席都判合同違例', () async {
      for (final bool omitVisibility in <bool>[true, false]) {
        final ServerApi api = apiWithHandler(
          (http.Request request) async => _json(
            _memberBody(
              omitVisibility: omitVisibility,
              omitAdminIdentity: !omitVisibility,
            ),
            200,
          ),
        );
        final ApiError? error = await _failure(
          () => api.updateMemberDirectoryVisibility(
            activityId: _activityId,
            memberId: _memberId,
            visibility: 'hidden',
            expectedVisibility: 'inherit',
          ),
        );
        expect(error, isNotNull, reason: '兩格都必填：缺席時界面只能靠猜，而猜的方向剛好是把人放大成可見');
      }
    });

    test('admin_identity 讀得到真值（名冊卡據此說出被收起來的是誰）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_memberBody(adminIdentity: 'true'), 200),
      );
      final MemberWriteReport report = await api
          .updateMemberDirectoryVisibility(
            activityId: _activityId,
            memberId: _memberId,
            visibility: 'hidden',
            expectedVisibility: 'inherit',
          );
      expect(report.member.adminIdentity, isTrue);
    });

    test('2013 與 2029 各自成值且都不值得自動重試', () async {
      for (final int code in <int>[2013, 2029, 2033, 1001, 1004]) {
        final ServerApi api = apiWithHandler(
          (http.Request request) async => _json(
            '{"code":$code,"message":"x","request_id":"r-e"}',
            code == 1001 ? 404 : 409,
          ),
        );
        final ApiError? error = await _failure(
          () => api.updateMemberDirectoryVisibility(
            activityId: _activityId,
            memberId: _memberId,
            visibility: 'hidden',
            expectedVisibility: 'inherit',
          ),
        );
        expect(error, isNotNull);
        expect(error!.machineCode, code);
        expect(error.retryable, isFalse, reason: '$code 的處置是重讀或換目標，不是自動補發');
      }
    });
  });
}
