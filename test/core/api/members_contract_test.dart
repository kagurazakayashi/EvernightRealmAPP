/// 「活動成員名冊」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：三條路徑的方法、每條白名單**恰好**哪些欄位（建立只有帳戶標識
/// 與暱稱兩格、編輯只有暱稱加它的依據值，兩者都沒有身分欄與陣營格）、身分欄必填缺席判違例、
/// `faction_id` 的「空字串＝尚未分組」與「缺席＝抵觸合同」分得開、帳戶投影讀不回時的空值
/// 容忍，以及 2035 這枚新碼在前端各自成值。未知新欄位一律容忍（後端只增不刪）。
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

/// 一筆成員的可展示事實。[factionId] 傳 null 演的是「這一格根本沒回」，
/// 傳空字串演的是合法現值「尚未分組」；[extraField] 用來演未知欄位必須被容忍。
String _memberJson({
  String nickname = '夜行者',
  String? factionId = '',
  String displayName = '名冊裡的玩家',
  String accountStatus = 'active',
  String directoryVisibility = 'inherit',
  String adminIdentity = 'false',
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"member_id":"$_memberId"',
    '"activity_id":"$_activityId"',
    '"account_id":"$_accountId"',
    '"nickname":"$nickname"',
    if (factionId != null) '"faction_id":"$factionId"',
    '"display_name":"$displayName"',
    '"account_status":"$accountStatus"',
    // 目錄覆蓋現值與「此刻是不是管理員身分」都是服務端讀回的投影：缺席判合同違例，
    // 因為界面拿「預設沒覆蓋」去畫那一格，會把管理人剛收起來的行畫成還亮著。
    '"directory_visibility":"$directoryVisibility"',
    '"admin_identity":$adminIdentity',
    '"business_status":"normal"',
    '"custom_status_id":""',
    '"custom_status_name":""',
    '"status_display_name":""',
    '"status_available":true',
    '"restrict_login":false',
    '"restrict_chat":false',
    '"restrict_private_chat":false',
    '"restrict_trade":false',
    '"restrict_transfer":false',
    '"restrict_item_use":false',
    '"joined_at":"2026-10-10T03:00:00.000Z"',
    '"updated_at":"2026-10-10T04:00:00.000Z"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

String _listBody(List<String> rows) {
  return '{"members":[${rows.join(',')}],"request_id":"r-mem-list"}';
}

String _writeBody({String? member}) {
  return '{"member":${member ?? _memberJson()},"request_id":"r-mem-write"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('成員名冊的讀法', () {
    test('activityMembers 發 GET 到集合子路徑，空名冊是合法事實', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_listBody(<String>[]), 200);
      });

      final MemberListReport report = await api.activityMembers(
        activityId: _activityId,
      );

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, adminActivityMembersPath(_activityId));
      expect(report.members, isEmpty);
      expect(report.requestId, 'r-mem-list');
    });

    test('名冊行讀得出全部白名單欄；未知新欄位容忍', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _listBody(<String>[
            _memberJson(extraField: '"next_step_field":"whatever"'),
          ]),
          200,
        ),
      );
      final MemberReport member = (await api.activityMembers(
        activityId: _activityId,
      )).members.single;

      expect(member.memberId, _memberId);
      expect(member.activityId, _activityId);
      expect(member.accountId, _accountId);
      expect(member.nickname, '夜行者');
      expect(member.factionId, '');
      expect(member.hasFaction, isFalse);
      expect(member.displayName, '名冊裡的玩家');
      expect(member.accountStatus, 'active');
      expect(member.joinedAt.toUtc().year, 2026);
    });

    test('空字串的陣營歸屬是合法現值（尚未分組），不是讀不到', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_listBody(<String>[_memberJson(factionId: '')]), 200),
      );
      final MemberReport member = (await api.activityMembers(
        activityId: _activityId,
      )).members.single;
      expect(member.hasFaction, isFalse);
    });

    test('有歸屬時讀得出那個標識（本版本不會發生，形狀先釘住）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _listBody(<String>[
            _memberJson(factionId: '01a1b000-0000-7000-8000-0000000000f1'),
          ]),
          200,
        ),
      );
      final MemberReport member = (await api.activityMembers(
        activityId: _activityId,
      )).members.single;
      expect(member.hasFaction, isTrue);
    });

    test('faction_id 缺席判合同違例：不降級成「尚未分組」', () async {
      // 缺席與空值是兩回事：降級會讓界面把「这一格我讀不懂」唸成「還沒分組」，
      // 那是憑空發明的結論（口徑同陣營派生值缺席判違例）。
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_listBody(<String>[_memberJson(factionId: null)]), 200),
      );
      expect(
        () => api.activityMembers(activityId: _activityId),
        throwsA(isA<ApiError>()),
      );
    });

    test('身分欄、暱稱與目錄投影都是必填：任一缺席都判合同違例', () async {
      for (final String missing in <String>[
        '"member_id"',
        '"account_id"',
        '"nickname"',
        // 這兩格缺席時界面只能靠猜：猜「沒覆蓋」會把管理人剛收起來的行畫成還亮著，
        // 猜「不是管理員」會讓 all_players_except_admin 那一態看起來收錯人。
        '"directory_visibility"',
        '"admin_identity"',
      ]) {
        final ServerApi api = apiWithHandler(
          (http.Request request) async => _json(
            '{"members":[{"activity_id":"$_activityId",'
                    '"member_id":"$_memberId","account_id":"$_accountId",'
                    '"nickname":"夜行者","faction_id":"",'
                    '"display_name":"名冊裡的玩家","account_status":"active",'
                    '"directory_visibility":"inherit","admin_identity":false,'
                    '"joined_at":"2026-10-10T03:00:00.000Z",'
                    '"updated_at":"2026-10-10T03:00:00.000Z"}],"request_id":"r-x"}'
                .replaceAll(missing, '"unused_field"'),
            200,
          ),
        );
        expect(
          () => api.activityMembers(activityId: _activityId),
          throwsA(isA<ApiError>()),
          reason: '$missing 缺席時該判合同違例',
        );
      }
    });

    test('帳戶投影讀不回時兩格都是空字串：這是事實而不是失敗', () async {
      // 軟參照指向的行被物理清理後，界面要能唸「讀不到那個帳戶」而不是崩在解析上。
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _listBody(<String>[_memberJson(displayName: '', accountStatus: '')]),
          200,
        ),
      );
      final MemberReport member = (await api.activityMembers(
        activityId: _activityId,
      )).members.single;
      expect(member.displayName, '');
      expect(member.accountStatus, '');
    });
  });

  group('建立成員', () {
    test('createMember 發 POST 到集合路徑，本體恰好兩欄（沒有身分欄也沒有陣營格）', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(), 201);
      });

      final MemberWriteReport report = await api.createMember(
        activityId: _activityId,
        accountId: _accountId,
        nickname: '夜行者',
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, adminActivityMembersPath(_activityId));
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'account_id', 'nickname'});
      // 身分三欄與時刻都由服務端決定，陣營分配則根本還沒有通路：
      // 「加入順手把他分進某一組」在前端就發不出去，後端對未知欄位的回答是 1004 點名。
      expect(body.containsKey('member_id'), isFalse);
      expect(body.containsKey('activity_id'), isFalse);
      expect(body.containsKey('faction_id'), isFalse);
      expect(body.containsKey('joined_at'), isFalse);
      expect(body.containsKey('role'), isFalse);
      expect(report.member.factionId, '');
      expect(report.requestId, 'r-mem-write');
    });
  });

  group('編輯暱稱', () {
    test('updateMemberNickname 發 PUT 到單筆路徑，本體恰好新值加依據值', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(member: _memberJson(nickname: '改名後的玩家')), 200);
      });

      final MemberWriteReport report = await api.updateMemberNickname(
        activityId: _activityId,
        memberId: _memberId,
        nickname: '改名後的玩家',
        expectedNickname: '夜行者',
      );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        adminActivityMemberItemPath(_activityId, _memberId),
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'nickname', 'expected_nickname'});
      expect(body['expected_nickname'], '夜行者');
      // 改名這一跳不碰身分也不碰陣營：那些欄位在本體裡沒有一個可以填的格子。
      expect(body.containsKey('faction_id'), isFalse);
      expect(body.containsKey('account_id'), isFalse);
      expect(body.containsKey('activity_id'), isFalse);
      expect(report.member.nickname, '改名後的玩家');
    });

    test('標識進路徑時按 URL 規則編碼，這一族也沒有刪除通路', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(), 200);
      });
      await api.updateMemberNickname(
        activityId: _activityId,
        memberId: _memberId,
        nickname: '正常名字',
        expectedNickname: '舊名字',
      );
      expect(sent.single.url.path.endsWith(_memberId), isTrue);
      // 用戶批准：沒有把成員移出活動的通路，所以這一路徑族只有 GET／HEAD／POST／PUT。
      expect(
        adminActivityMembersPath(_activityId),
        '/admin/activities/$_activityId/members',
      );
      expect(
        adminActivityMemberItemPath(_activityId, _memberId),
        '/admin/activities/$_activityId/members/$_memberId',
      );
    });
  });

  group('一枚新機器碼與失敗信封', () {
    test('2035 各自成值，不併入 1001／2013／2034', () {
      expect(
        ApiMachineCode.fromValue(2035),
        ApiMachineCode.activityMemberTaken,
      );
      expect(ApiMachineCode.fromValue(1001), ApiMachineCode.notFound);
      expect(ApiMachineCode.fromValue(2013), ApiMachineCode.profileConflict);
      expect(ApiMachineCode.fromValue(2034), ApiMachineCode.factionNameTaken);
      expect(
        ApiMachineCode.activityMemberTaken.value,
        isNot(ApiMachineCode.factionNameTaken.value),
      );
    });

    test('失敗信封帶著 2035 時原樣保留碼值，409 不標可重試', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"code":2035,"message":"already a member","request_id":"r-fail"}',
          409,
        ),
      );
      final Object? failure = await api
          .activityMembers(activityId: _activityId)
          .then<Object?>((_) => null)
          .catchError((Object? error) => error);
      expect(failure, isA<ApiError>());
      final ApiError error = failure! as ApiError;
      expect(error.knownCode, ApiMachineCode.activityMemberTaken);
      expect(error.retryable, isFalse);
    });

    test('失敗信封帶著 1001 時不會被讀成「他已經是成員」', () async {
      // 終態目標、跨活動標識與幽靈都收斂成 1001 那一句；界面據此念「換個目標」，
      // 而不是把同一個碼拆成兩套說法（拆就是替管理人新增一枚列舉信號）。
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"code":1001,"message":"not found","request_id":"r-fail-2"}',
          404,
        ),
      );
      final Object? failure = await api
          .createMember(
            activityId: _activityId,
            accountId: _accountId,
            nickname: '進不來的名字',
          )
          .then<Object?>((_) => null)
          .catchError((Object? error) => error);
      expect((failure! as ApiError).knownCode, ApiMachineCode.notFound);
    });
  });
}
