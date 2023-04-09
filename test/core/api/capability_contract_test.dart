/// 「狀態規則與手動限制的組合判定」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：三條新路的方法與精確路徑、規則矩陣的本體恰好
/// `expected_revision` 加七列 `rules`（自訂狀態不得拒絕能力）、revision 與 configured
/// 的讀法、管理摘要的逐來源布林、玩家摘要只帶能力鍵／允許／拒絕／來源類別，
/// 以及 2044 在前端自成一值（不與 2043、2011、1001、2013、2029、2033 混用）。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

const String _activityId = '01b10000-0000-7000-8000-0000000000a1';
const String _memberId = '01b10000-0000-7000-8000-0000000000m1';

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 一份七列規則的回應片段；[normalDenied] 可指定 normal 那一列的拒絕能力。
String _rulesBody({
  int revision = 0,
  bool configured = false,
  List<String> normalDenied = const <String>[],
  String? extraField,
}) {
  String group(String status, List<String> denied) =>
      '{"status_key":"$status",'
      '"denied_capabilities":[${denied.map((String key) => '"$key"').join(',')}]}';
  final List<String> rules = <String>[
    group('normal', normalDenied),
    group('suspended', const <String>[
      'login',
      'chat',
      'private_chat',
      'trade',
      'transfer',
      'item_use',
    ]),
    group('eliminated', const <String>[
      'chat',
      'private_chat',
      'trade',
      'transfer',
      'item_use',
    ]),
    group('dead', const <String>[
      'chat',
      'private_chat',
      'trade',
      'transfer',
      'item_use',
    ]),
    group('arrested', const <String>['trade', 'transfer', 'item_use']),
    group('offline', const <String>[]),
    group('custom', const <String>[]),
  ];
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"revision":$revision',
    '"configured":$configured',
    '"capability_keys":["login","chat","private_chat","trade","transfer","item_use"]',
    '"rules":[${rules.join(',')}]',
    '"request_id":"r-rules"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

/// 一項管理側能力結論。
String _memberCapability(
  String capability, {
  bool allowed = true,
  List<String> sources = const <String>[],
  bool manual = false,
  bool status = false,
  bool lifecycle = false,
  bool identity = false,
}) {
  return '{"capability":"$capability","allowed":$allowed,'
      '"sources":[${sources.map((String s) => '"$s"').join(',')}],'
      '"manual_denied":$manual,"status_denied":$status,'
      '"lifecycle_denied":$lifecycle,"identity_denied":$identity}';
}

String _memberCapabilitiesBody({
  String accountStatus = 'active',
  bool accessAllowed = true,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"member_id":"$_memberId"',
    '"business_status":"normal"',
    '"activity_status":"active"',
    '"account_status":"$accountStatus"',
    '"rules_revision":2',
    '"access_allowed":$accessAllowed',
    '"capabilities":[' 
        '${_memberCapability('login', allowed: accessAllowed, sources: accessAllowed ? const <String>[] : const <String>['manual'], manual: !accessAllowed)},'
        '${_memberCapability('chat', allowed: false, sources: const <String>['status', 'manual'], status: true, manual: true)},'
        '${_memberCapability('private_chat')},'
        '${_memberCapability('trade')},'
        '${_memberCapability('transfer')},'
        '${_memberCapability('item_use')}'
        ']',
    '"request_id":"r-member-capabilities"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

String _ownCapabilitiesBody({bool accessAllowed = true, String? extraField}) {
  String item(String key, bool allowed, List<String> sources) =>
      '{"capability":"$key","allowed":$allowed,'
      '"sources":[${sources.map((String s) => '"$s"').join(',')}]}';
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"member_id":"$_memberId"',
    '"rules_revision":3',
    '"access_allowed":$accessAllowed',
    '"capabilities":['
        '${item('login', accessAllowed, accessAllowed ? const <String>[] : const <String>['status'])},'
        '${item('chat', false, const <String>['status'])},'
        '${item('private_chat', true, const <String>[])},'
        '${item('trade', true, const <String>[])},'
        '${item('transfer', true, const <String>[])},'
        '${item('item_use', true, const <String>[])}'
        ']',
    '"request_id":"r-own-capabilities"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

void main() {
  group('三條新路的協議形態', () {
    test('規則走 /admin/activities/{id}/capability-rules', () {
      expect(
        adminActivityCapabilityRulesPath(_activityId),
        '/admin/activities/$_activityId/capability-rules',
      );
      expect(
        adminActivityCapabilityRulesPath('x y'),
        contains('x%20y'),
      );
    });

    test('管理摘要走成員單筆下的 capabilities', () {
      expect(
        adminActivityMemberCapabilitiesPath(_activityId, _memberId),
        '/admin/activities/$_activityId/members/$_memberId/capabilities',
      );
    });

    test('本人摘要走 /player/activities/{id}/capabilities', () {
      expect(
        playerActivityCapabilitiesPath(_activityId),
        '/player/activities/$_activityId/capabilities',
      );
    });

    test('讀規則：revision 0 與 configured 假、七列、六項能力鍵', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(_rulesBody(), 200),
      );
      final CapabilityRulesReport report = await api.capabilityRules(
        activityId: _activityId,
      );
      expect(report.revision, 0);
      expect(report.configured, isFalse);
      expect(report.capabilityKeys, kCapabilityKeys);
      expect(report.rules, hasLength(7));
      expect(report.deniedFor('suspended'), <String>{
        'login',
        'chat',
        'private_chat',
        'trade',
        'transfer',
        'item_use',
      });
      expect(report.deniedFor('custom'), isEmpty);
    });

    test('寫規則：本體恰好 expected_revision 與七列，能力鍵依固定順序', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(
          _rulesBody(
            revision: 1,
            configured: true,
            normalDenied: const <String>['private_chat', 'chat'],
          ),
          200,
        );
      });
      final CapabilityRulesReport report = await api.updateCapabilityRules(
        activityId: _activityId,
        expectedRevision: 0,
        deniedByStatus: <String, Set<String>>{
          'normal': <String>{'private_chat', 'chat'},
        },
      );
      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        adminActivityCapabilityRulesPath(_activityId),
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'expected_revision', 'rules'});
      expect(body['expected_revision'], 0);
      final List<Object?> rules = body['rules'] as List<Object?>;
      expect(rules, hasLength(7));
      final Map<String, Object?> normal =
          rules.first as Map<String, Object?>;
      expect(normal['status_key'], 'normal');
      // 請求端也排成固定順序：chat 在 private_chat 之前。
      expect(normal['denied_capabilities'], <String>['chat', 'private_chat']);
      expect(report.revision, 1);
      expect(report.configured, isTrue);
    });

    test('custom 拒絕能力在客戶端就擋，不發注定 1004 的請求', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_rulesBody(), 200);
      });
      expect(
        () => api.updateCapabilityRules(
          activityId: _activityId,
          expectedRevision: 0,
          deniedByStatus: <String, Set<String>>{
            'custom': <String>{'chat'},
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sent, isEmpty);
    });

    test('管理摘要：逐來源布林與來源陣列都逐格讀出', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(_memberCapabilitiesBody(), 200),
      );
      final MemberCapabilitiesReport report = await api.memberCapabilities(
        activityId: _activityId,
        memberId: _memberId,
      );
      expect(report.businessStatus, 'normal');
      expect(report.activityStatus, 'active');
      expect(report.accountStatus, 'active');
      expect(report.rulesRevision, 2);
      expect(report.accessAllowed, isTrue);
      final MemberCapabilityDecision? chat = report.decisionFor('chat');
      expect(chat, isNotNull);
      expect(chat!.allowed, isFalse);
      expect(chat.sources, <String>['status', 'manual']);
      expect(chat.statusDenied, isTrue);
      expect(chat.manualDenied, isTrue);
      expect(chat.lifecycleDenied, isFalse);
      expect(chat.identityDenied, isFalse);
    });

    test('管理摘要的帳戶狀態可以合法是空字串（帳戶行被清理）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_memberCapabilitiesBody(accountStatus: ''), 200),
      );
      final MemberCapabilitiesReport report = await api.memberCapabilities(
        activityId: _activityId,
        memberId: _memberId,
      );
      expect(report.accountStatus, isEmpty);
    });

    test('玩家摘要只有能力鍵、允許與來源；缺席／壞型別判合同違例', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_ownCapabilitiesBody(accessAllowed: false), 200),
      );
      final OwnCapabilitiesReport report = await api.ownCapabilities(
        activityId: _activityId,
      );
      expect(report.rulesRevision, 3);
      expect(report.accessAllowed, isFalse);
      expect(report.capabilities, hasLength(6));
      final OwnCapabilityDecision login = report.decisionFor('login')!;
      expect(login.allowed, isFalse);
      expect(login.sources, <String>['status']);
      final OwnCapabilityDecision chat = report.decisionFor('chat')!;
      expect(chat.allowed, isFalse);
      expect(chat.sources, <String>['status']);

      final ServerApi broken = apiWithHandler(
        (http.Request request) async => _json(
          '{"activity_id":"$_activityId","member_id":"$_memberId",'
          '"rules_revision":3,"access_allowed":true,'
          '"capabilities":[{"capability":"login","allowed":true}],'
          '"request_id":"r-broken"}',
          200,
        ),
      );
      await expectLater(
        broken.ownCapabilities(activityId: _activityId),
        throwsA(isA<ApiError>()),
      );
    });

    test('2044 在前端自成一值，不與相鄰碼混用', () {
      expect(ApiMachineCode.memberStatusRestricted.value, 2044);
      expect(ApiMachineCode.fromValue(2044), ApiMachineCode.memberStatusRestricted);
      expect(ApiMachineCode.fromValue(2043), ApiMachineCode.memberAccessRestricted);
      expect(ApiMachineCode.fromValue(2011), ApiMachineCode.permissionDenied);
      expect(ApiMachineCode.fromValue(9999), isNull);
    });
  });
}
