/// 「玩家業務狀態與顯示名稱」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：五個方法各自的 HTTP 方法與精確路徑、目錄兩份清單的欄位、
/// 建立自訂狀態**恰好**一欄（可用性／標識／歸屬／時刻都寫不進本體）、
/// 編輯自訂狀態恰好四欄（兩新值加兩依據值）、顯示名稱恰好兩欄、
/// 成員狀態恰好四欄（含成對的兩個依據值），以及 2041／2042 在前端自成一值、
/// 不與 2036／2040／2013／1001 混用。
///
/// 另一件必須在測試裡講死的是「讀取不改狀態」：GET 那幾條通路在前端只能發 GET，
/// 而業務狀態那一欄的值永遠取自回應——界面沒有一格能让它随請求或時間自己翻轉。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

const String _activityId = '01a1b000-0000-7000-8000-0000000000a1';
const String _otherActivityId = '01a1b000-0000-7000-8000-0000000000a2';
const String _memberId = '01a1b000-0000-7000-8000-0000000000m1';
const String _statusId = '01a1b000-0000-7000-8000-0000000000s1';

/// 一欄內建狀態的展示現值（目錄裡的那七格之一）。
String _builtinJson({
  String statusKey = 'offline',
  String displayName = '',
  bool? usesDefaultDisplayName,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"status_key":"$statusKey"',
    '"display_name":"$displayName"',
    '"uses_default_display_name":'
        '${usesDefaultDisplayName ?? displayName.isEmpty}',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

/// 一行自訂狀態定義。
String _customJson({
  String name = '失蹤中',
  bool available = true,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"custom_status_id":"$_statusId"',
    '"name":"$name"',
    '"available":$available',
    '"created_at":"2026-10-10T03:00:00.000Z"',
    '"updated_at":"2026-10-10T04:00:00.000Z"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

String _catalogBody({
  List<String> builtins = const <String>[],
  List<String> custom = const <String>[],
}) {
  return '{"builtin_statuses":[${builtins.join(',')}],'
      '"custom_statuses":[${custom.join(',')}],'
      '"request_id":"r-status-catalog"}';
}

String _memberJson({
  String nickname = '夜行者',
  String businessStatus = 'normal',
  String customStatusId = '',
  String customStatusName = '',
  String statusDisplayName = '',
  bool statusAvailable = true,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"member_id":"$_memberId"',
    '"activity_id":"$_activityId"',
    '"account_id":"01a1b000-0000-7000-8000-0000000000b1"',
    '"nickname":"$nickname"',
    '"faction_id":""',
    '"display_name":"玩家甲"',
    '"account_status":"active"',
    '"directory_visibility":"inherit"',
    '"admin_identity":false',
    '"business_status":"$businessStatus"',
    '"custom_status_id":"$customStatusId"',
    '"custom_status_name":"$customStatusName"',
    '"status_display_name":"$statusDisplayName"',
    '"status_available":$statusAvailable',
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

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('狀態目錄的讀與寫', () {
    test('playerStatusCatalog 發 GET 到集合子路徑，兩份清單都能空', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_catalogBody(), 200);
      });

      final PlayerStatusCatalogReport report = await api.playerStatusCatalog(
        activityId: _activityId,
      );

      expect(sent.single.method, 'GET');
      expect(
        sent.single.url.path,
        adminActivityPlayerStatusesPath(_activityId),
      );
      expect(
        sent.single.url.path,
        '/admin/activities/$_activityId/player-statuses',
      );
      expect(report.builtinStatuses, isEmpty);
      expect(report.customStatuses, isEmpty);
      expect(report.requestId, 'r-status-catalog');
    });

    test('目錄行讀得出覆蓋現值與 uses_default 那一格；未知新欄位容忍', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _catalogBody(
            builtins: <String>[
              _builtinJson(statusKey: 'normal'),
              _builtinJson(
                statusKey: 'offline',
                displayName: '暫離現場',
                usesDefaultDisplayName: false,
                extraField: '"next_step_field":"whatever"',
              ),
            ],
            custom: <String>[_customJson(available: false)],
          ),
          200,
        ),
      );
      final PlayerStatusCatalogReport report = await api.playerStatusCatalog(
        activityId: _activityId,
      );

      final PlayerBuiltinStatusReport normal = report.builtinByKey('normal')!;
      expect(normal.displayName, '');
      expect(normal.usesDefaultDisplayName, isTrue);
      final PlayerBuiltinStatusReport offline = report.builtinByKey('offline')!;
      expect(offline.displayName, '暫離現場');
      expect(offline.usesDefaultDisplayName, isFalse);
      // 目錄沒列出的鍵回 null：界面據此唸「讀不到」而不是編一個名稱。
      expect(report.builtinByKey('dead'), isNull);

      final PlayerCustomStatusReport custom = report.customStatuses.single;
      expect(custom.customStatusId, _statusId);
      expect(custom.name, '失蹤中');
      expect(custom.available, isFalse);
      expect(custom.createdAt.toUtc(), DateTime.utc(2026, 10, 10, 3, 0, 0));
      expect(report.customById(_statusId), isNotNull);
      expect(report.customById('01a1b000-0000-7000-8000-0000000000zz'), isNull);
    });

    test('建立自訂狀態只發 name 一欄，標識／可用性／歸屬／時刻都寫不進本體', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(
          '{"custom_status":${_customJson()},'
          '"request_id":"r-status-create"}',
          201,
        );
      });

      final PlayerCustomStatusWriteReport report = await api.createPlayerStatus(
        activityId: _activityId,
        name: '失蹤中',
      );

      expect(sent.single.method, 'POST');
      expect(
        sent.single.url.path,
        adminActivityPlayerStatusesPath(_activityId),
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'name'});
      expect(report.customStatus.available, isTrue);
      expect(report.requestId, 'r-status-create');
    });

    test('顯示名稱路徑帶內建鍵、本體恰好兩欄；空字串是恢復預設而不是刪除', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(
          '{"builtin_status":${_builtinJson(statusKey: 'offline')},'
          '"request_id":"r-status-label"}',
          200,
        );
      });

      final PlayerStatusLabelWriteReport report = await api
          .updatePlayerStatusLabel(
            activityId: _activityId,
            statusKey: 'offline',
            displayName: '',
            expectedDisplayName: '暫離現場',
          );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        adminActivityPlayerStatusLabelPath(_activityId, 'offline'),
      );
      expect(
        sent.single.url.path,
        '/admin/activities/$_activityId/player-status-labels/offline',
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'display_name',
        'expected_display_name',
      });
      expect(body['display_name'], '');
      expect(report.builtinStatus.displayName, '');
      expect(report.builtinStatus.usesDefaultDisplayName, isTrue);
    });

    test('編輯自訂狀態恰好四欄（兩新值加兩依據值），可用與否都寫得進去', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(
          '{"custom_status":${_customJson(available: false)},'
          '"request_id":"r-status-update"}',
          200,
        );
      });

      await api.updatePlayerStatus(
        activityId: _activityId,
        statusId: _statusId,
        name: '改名後的定義',
        available: false,
        expectedName: '失蹤中',
        expectedAvailable: true,
      );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        adminActivityPlayerStatusItemPath(_activityId, _statusId),
      );
      expect(
        sent.single.url.path,
        '/admin/activities/$_activityId/player-statuses/$_statusId',
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'name',
        'available',
        'expected_name',
        'expected_available',
      });
      // 這一族沒有刪除通路：前端也沒有任何一格能發出 DELETE。
    });

    test('跨活動的標識走路徑而不是本體：activity_id 寫不進任何一條狀態通路', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(
          '{"custom_status":${_customJson()},'
          '"request_id":"r-other"}',
          201,
        );
      });

      await api.createPlayerStatus(activityId: _otherActivityId, name: '别人的定義');

      expect(sent.single.url.path, contains(_otherActivityId));
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.containsKey('activity_id'), isFalse);
    });
  });

  group('成員業務狀態', () {
    test('變更狀態恰好四欄，含成對的兩個依據值；custom 才帶自訂標識', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(
          '{"member":${_memberJson(businessStatus: 'custom', customStatusId: _statusId, customStatusName: '失蹤中', statusDisplayName: '失蹤中')},'
          '"request_id":"r-member-status"}',
          200,
        );
      });

      final MemberWriteReport report = await api.updateMemberBusinessStatus(
        activityId: _activityId,
        memberId: _memberId,
        businessStatus: 'custom',
        customStatusId: _statusId,
        expectedBusinessStatus: 'normal',
        expectedCustomStatusId: '',
      );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        adminActivityMemberBusinessStatusPath(_activityId, _memberId),
      );
      expect(
        sent.single.url.path,
        '/admin/activities/$_activityId/members/$_memberId/business-status',
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'business_status',
        'custom_status_id',
        'expected_business_status',
        'expected_custom_status_id',
      });
      expect(body['custom_status_id'], _statusId);
      expect(body['expected_custom_status_id'], '');

      final MemberReport member = report.member;
      expect(member.businessStatus, 'custom');
      expect(member.hasCustomStatus, isTrue);
      expect(member.customStatusId, _statusId);
      expect(member.customStatusName, '失蹤中');
      expect(member.statusDisplayName, '失蹤中');
      expect(member.statusUsesDefaultLabel, isFalse);
      expect(member.statusAvailable, isTrue);
    });

    test('切回內建值時自訂標識清空；沒有覆蓋就走四語言預設那句', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"member":${_memberJson()},"request_id":"r-member-back"}',
          200,
        ),
      );
      final MemberWriteReport report = await api.updateMemberBusinessStatus(
        activityId: _activityId,
        memberId: _memberId,
        businessStatus: 'offline',
        customStatusId: '',
        expectedBusinessStatus: 'custom',
        expectedCustomStatusId: _statusId,
      );
      final MemberReport member = report.member;
      expect(member.businessStatus, 'normal');
      expect(member.customStatusId, '');
      expect(member.statusDisplayName, '');
      // 「空字串」與「欄位缺席」是兩回事：後者是合同違例，前者才是「沒有覆蓋」。
      expect(member.statusUsesDefaultLabel, isTrue);
    });

    test('狀態欄缺席判合同違例：不降級成 normal 或假值', () {
      // 「欄位缺席」與「欄位是空字串」是兩回事：後者是合法現值（沒有覆蓋），
      // 前者讓界面無從判這一格到底是什麼，降級成 normal 等於憑空發明一次變更。
      final Map<String, Object?> row =
          jsonDecode(_memberJson()) as Map<String, Object?>;
      row.remove('business_status');
      expect(
        () => MemberReport.decode(row),
        throwsA(isA<ApiResponseShapeException>()),
      );
      final Map<String, Object?> withEmpty =
          jsonDecode(_memberJson()) as Map<String, Object?>;
      withEmpty['status_display_name'] = '';
      expect(MemberReport.decode(withEmpty).statusUsesDefaultLabel, isTrue);
    });

    test('名冊行也讀得出狀態四欄（只增不刪的相容演進欄位）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"members":[${_memberJson(businessStatus: 'offline', statusDisplayName: '暫離現場', extraField: '"next_step_field":"whatever"')}],"request_id":"r-roster"}',
          200,
        ),
      );
      final MemberListReport report = await api.activityMembers(
        activityId: _activityId,
      );
      final MemberReport member = report.members.single;
      expect(member.businessStatus, 'offline');
      expect(member.statusDisplayName, '暫離現場');
      expect(member.statusUsesDefaultLabel, isFalse);
      expect(member.statusAvailable, isTrue);
    });

    test('玩家目錄與本人投影都讀得出狀態四欄', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        if (request.url.path.endsWith('/profile')) {
          return _json(
            '{"activity_id":"$_activityId","name":"有狀態的場","status":"active",'
            '"member_directory_mode":"all_members","member_id":"$_memberId",'
            '"nickname":"夜行者","faction_id":"","faction_name":"",'
            '"faction_icon":"","faction_color":"","faction_available":true,'
            '"directory_visibility":"inherit","business_status":"custom",'
            '"custom_status_id":"$_statusId","custom_status_name":"失蹤中",'
            '"status_display_name":"失蹤中","status_available":true,'
            '"joined_at":"2026-10-10T03:00:00.000Z","request_id":"r-self"}',
            200,
          );
        }
        return _json(
          '{"members":[{"member_id":"$_memberId","nickname":"夜行者",'
          '"faction_id":"","faction_name":"","faction_icon":"",'
          '"faction_color":"","faction_available":true,'
          '"business_status":"offline","custom_status_id":"",'
          '"custom_status_name":"","status_display_name":"暫離現場",'
          '"status_available":true,"joined_at":"2026-10-10T03:00:00.000Z"}],'
          '"facets":[],"member_directory_mode":"all_members",'
          '"self_member_id":"$_memberId","page":1,"page_size":20,"total":1,'
          '"request_id":"r-dir"}',
          200,
        );
      });

      final MemberDirectoryReport page = await api.playerMemberDirectory(
        activityId: _activityId,
        page: 1,
        pageSize: 20,
      );
      final DirectoryMemberReport row = page.members.single;
      expect(row.businessStatus, 'offline');
      expect(row.statusDisplayName, '暫離現場');
      expect(row.statusAvailable, isTrue);
      expect(row.hasCustomStatus, isFalse);

      final OwnMemberProfileReport own = await api.playerOwnMemberProfile(
        activityId: _activityId,
      );
      expect(own.businessStatus, 'custom');
      expect(own.customStatusId, _statusId);
      expect(own.customStatusName, '失蹤中');
      expect(own.statusUsesDefaultLabel, isFalse);
    });
  });

  group('2041／2042 在前端自成一值', () {
    test('兩枚新碼各自成值，不與停用／重名／衝突／不可分辨混用', () {
      expect(ApiMachineCode.playerStatusUnavailable.value, 2041);
      expect(ApiMachineCode.playerStatusNameTaken.value, 2042);
      expect(
        ApiMachineCode.fromValue(2041),
        ApiMachineCode.playerStatusUnavailable,
      );
      expect(
        ApiMachineCode.fromValue(2042),
        ApiMachineCode.playerStatusNameTaken,
      );
      // 2043 已由玩家分項限制一步發布（在該活動的訪問資格已被限制——活動級，
      // 不是帳戶停用）：界線推到 2044，那一格仍必須讀不出來。
      expect(
        ApiMachineCode.fromValue(2043),
        ApiMachineCode.memberAccessRestricted,
      );
      expect(ApiMachineCode.fromValue(2044), isNull);
      // 「停用」的三枚碼各有各的實體：陣營不收新成員、標籤不收新貼標、
      // 自訂狀態不收新選用——同一枚碼的語義不因後續步驟改寫。
      expect(ApiMachineCode.factionNotAcceptingMembers.value, isNot(2041));
      expect(ApiMachineCode.tagNameTaken.value, isNot(2042));
      expect(ApiMachineCode.profileConflict.value, isNot(2041));
      expect(ApiMachineCode.notFound.value, isNot(2041));
      final List<int> values = ApiMachineCode.values
          .map((ApiMachineCode code) => code.value)
          .toList(growable: false);
      expect(values.toSet().length, values.length);
    });

    test('錯誤信封帶著 2041 時解析成該碼，不退成未知碼', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"code":2041,"message":"disabled","request_id":"r-2041"}',
          409,
        ),
      );
      late final ApiError error;
      try {
        await api.updateMemberBusinessStatus(
          activityId: _activityId,
          memberId: _memberId,
          businessStatus: 'custom',
          customStatusId: _statusId,
          expectedBusinessStatus: 'normal',
          expectedCustomStatusId: '',
        );
        fail('409 帶著 2041 必須拋出 ApiError');
      } on ApiError catch (caught) {
        error = caught;
      }
      expect(error.knownCode, ApiMachineCode.playerStatusUnavailable);
      expect(error.toString(), contains('2041'));
    });
  });

  group('讀取不寫狀態', () {
    test('目錄與名冊兩條讀法都只發 GET：業務狀態不隨請求翻轉', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        if (request.url.path.endsWith('/player-statuses')) {
          return _json(_catalogBody(builtins: <String>[_builtinJson()]), 200);
        }
        return _json(
          '{"members":[${_memberJson()}],"request_id":"r-roster"}',
          200,
        );
      });

      await api.playerStatusCatalog(activityId: _activityId);
      await api.activityMembers(activityId: _activityId);

      expect(
        sent.map((http.Request request) => request.method),
        everyElement('GET'),
      );
      expect(sent, hasLength(2));
    });
  });
}
