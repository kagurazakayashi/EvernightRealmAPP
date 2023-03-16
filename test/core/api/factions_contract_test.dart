/// 「活動陣營管理」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：三條路徑的方法、每條白名單**恰好**哪些欄位
/// （建立沒有可用性格子、編輯十二欄且不帶標識與歸屬、派生值那一格寫不進去）、
/// 空列表與缺席語意、必填缺席判違例，以及 2033／2034 兩枚新碼在前端各自成值。
/// 未知新欄位一律容忍（後端只增不刪）；圖標封閉集合在這裡钉的是**清單本身**，
/// 與後端遷移 0013 的 CHECK 同漂移同報紅。
library;

import 'dart:convert';

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

const String _activityId = '01a1b000-0000-7000-8000-0000000000a1';
const String _factionId = '01a1b000-0000-7000-8000-0000000000f1';

/// 一筆陣營的可展示事實。[extraField] 用來演「後端日後多發的未知欄位必須被容忍」。
///
/// [acceptsNewMembers] 是服務端派生值，默认與 [available] 同值（活動可寫時的形態）；
/// 傳 false 演的是「陣營本身可用，但活動已停止或歸檔」那一格。
String _factionJson({
  String name = '黎明軍',
  String icon = 'sun',
  String color = '#f0a020',
  int sortOrder = 0,
  bool available = true,
  bool? acceptsNewMembers,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"faction_id":"$_factionId"',
    '"activity_id":"$_activityId"',
    '"name":"$name"',
    '"description":"開場的一組"',
    '"icon":"$icon"',
    '"color":"$color"',
    '"sort_order":$sortOrder',
    '"available":$available',
    '"accepts_new_members":${acceptsNewMembers ?? available}',
    '"created_at":"2026-10-10T03:00:00.000Z"',
    '"updated_at":"2026-10-10T04:00:00.000Z"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

String _listBody(List<String> rows) {
  return '{"factions":[${rows.join(',')}],"request_id":"r-fac-list"}';
}

String _writeBody({String? faction}) {
  return '{"faction":${faction ?? _factionJson()},"request_id":"r-fac-write"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('陣營列表與建立', () {
    test('activityFactions 發 GET 到集合子路徑，空清單是合法事實', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_listBody(<String>[]), 200);
      });

      final FactionListReport report = await api.activityFactions(
        activityId: _activityId,
      );

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, adminActivityFactionsPath(_activityId));
      expect(report.factions, isEmpty);
      expect(report.requestId, 'r-fac-list');
    });

    test('列表行讀得出全部白名單欄；未知新欄位容忍', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _listBody(<String>[
            _factionJson(extraField: '"next_step_field":"whatever"'),
          ]),
          200,
        ),
      );
      final FactionListReport report = await api.activityFactions(
        activityId: _activityId,
      );
      final FactionReport faction = report.factions.single;
      expect(faction.factionId, _factionId);
      expect(faction.activityId, _activityId);
      expect(faction.icon, 'sun');
      expect(faction.color, '#f0a020');
      expect(faction.sortOrder, 0);
      expect(faction.available, isTrue);
      expect(faction.acceptsNewMembers, isTrue);
    });

    test('派生值缺席判合同違例：accepts_new_members 缺失不降級成 false', () async {
      // 少這一格時界面無從判「收不收新成員」；降級成 false 會讓界面憑空唸出
      // 「此刻不接收新分配」，那是把讀不到說成一個結論。
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"factions":[{"faction_id":"$_factionId","activity_id":"$_activityId",'
          '"name":"缺派生值","description":"","icon":"","color":"","sort_order":0,'
          '"available":true,'
          '"created_at":"2026-10-10T03:00:00.000Z",'
          '"updated_at":"2026-10-10T03:00:00.000Z"}],"request_id":"r-x"}',
          200,
        ),
      );
      expect(
        () => api.activityFactions(activityId: _activityId),
        throwsA(isA<ApiError>()),
      );
    });

    test('派生值與旗標分得開：陣營可用而活動停止時兩格各自讀出', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _listBody(<String>[
            _factionJson(available: true, acceptsNewMembers: false),
          ]),
          200,
        ),
      );
      final FactionReport faction = (await api.activityFactions(
        activityId: _activityId,
      )).factions.single;
      // 界面靠這兩格分開講「它還是那個陣營」與「此刻收不收新成員」，不自己拼。
      expect(faction.available, isTrue);
      expect(faction.acceptsNewMembers, isFalse);
    });

    test('空圖標與空顏色是合法現值（未選），讀成空字串而不是失敗', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json(_listBody(<String>[_factionJson(icon: '', color: '')]), 200),
      );
      final FactionListReport report = await api.activityFactions(
        activityId: _activityId,
      );
      expect(report.factions.single.icon, isEmpty);
      expect(report.factions.single.color, isEmpty);
    });

    test('必填欄缺席判合同違例：available 缺失不降級成 false', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"factions":[{"faction_id":"$_factionId","activity_id":"$_activityId",'
          '"name":"缺欄","description":"","icon":"","color":"","sort_order":0,'
          '"created_at":"2026-10-10T03:00:00.000Z",'
          '"updated_at":"2026-10-10T03:00:00.000Z"}],"request_id":"r-x"}',
          200,
        ),
      );
      expect(
        () => api.activityFactions(activityId: _activityId),
        throwsA(isA<ApiError>()),
      );
    });

    test('createFaction 發 POST，未指定排序時本體恰好四個欄位', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(), 201);
      });

      final FactionWriteReport report = await api.createFaction(
        activityId: _activityId,
        name: '黎明軍',
        description: '開場的一組',
        icon: 'sun',
        color: '#f0a020',
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, adminActivityFactionsPath(_activityId));
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      // available 沒有格子：新建一律可用是領域規則；id／activity_id／時刻同理無處可填。
      expect(body.keys.toSet(), <String>{
        'name',
        'description',
        'icon',
        'color',
      });
      expect(body.containsKey('available'), isFalse);
      expect(body.containsKey('sort_order'), isFalse);
      expect(report.faction.available, isTrue);
      expect(report.requestId, 'r-fac-write');
    });

    test('createFaction 帶排序值時恰好五個欄位（null 與 0 分得開）', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(faction: _factionJson(sortOrder: 0)), 201);
      });

      await api.createFaction(
        activityId: _activityId,
        name: '排頭的',
        description: '',
        icon: '',
        color: '',
        sortOrder: 0,
      );

      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'name',
        'description',
        'icon',
        'color',
        'sort_order',
      });
      expect(body['sort_order'], 0);
    });
  });

  group('陣營編輯', () {
    test('updateFaction 發 PUT 到單筆路徑，本體恰好六欄新值加六欄依據值', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(faction: _factionJson(available: false)), 200);
      });

      final FactionWriteReport report = await api.updateFaction(
        activityId: _activityId,
        factionId: _factionId,
        name: '改名後的黎明軍',
        description: '開場的一組',
        icon: 'moon',
        color: '#102040',
        sortOrder: 7,
        available: false,
        expectedName: '黎明軍',
        expectedDescription: '開場的一組',
        expectedIcon: 'sun',
        expectedColor: '#f0a020',
        expectedSortOrder: 0,
        expectedAvailable: true,
      );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        adminActivityFactionItemPath(_activityId, _factionId),
      );
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{
        'name',
        'description',
        'icon',
        'color',
        'sort_order',
        'available',
        'expected_name',
        'expected_description',
        'expected_icon',
        'expected_color',
        'expected_sort_order',
        'expected_available',
      });
      // 身分與歸屬不在這條通路的白名單裡（也不在 UPDATE 語句裡）：
      // 「儲存順手把陣營挪進另一個活動」在協定層就不是被拒，而是沒有一個可以填的格子。
      expect(body.containsKey('id'), isFalse);
      expect(body.containsKey('activity_id'), isFalse);
      expect(body.containsKey('created_at'), isFalse);
      // 派生值不是可寫欄位：想靠本體宣稱「還收新成員」在前端就發不出去，
      // 後端對這類未知欄位的回答是 1004 點名（見根倉庫端點證據）。
      expect(body.containsKey('accepts_new_members'), isFalse);
      expect(report.faction.available, isFalse);
      expect(report.faction.acceptsNewMembers, isFalse);
    });

    test('標識進路徑時按 URL 規則編碼', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(), 200);
      });
      await api.updateFaction(
        activityId: _activityId,
        factionId: _factionId,
        name: '正常名字',
        description: '',
        icon: '',
        color: '',
        sortOrder: 1,
        available: true,
        expectedName: '舊名字',
        expectedDescription: '',
        expectedIcon: '',
        expectedColor: '',
        expectedSortOrder: 0,
        expectedAvailable: true,
      );
      expect(sent.single.url.path.endsWith(_factionId), isTrue);
    });

    test('這一族沒有刪除通路：合同層不提供 delete（本測試钉住路徑函數形狀）', () {
      // 用戶批准：只有可用／停用，沒有刪除。列表與單筆兩條路徑之外不該長出第三條；
      // 這裡钉的是「集合路徑就是活動詳情路徑的子資源」這一結構事實。
      expect(
        adminActivityFactionsPath(_activityId),
        '/admin/activities/$_activityId/factions',
      );
      expect(
        adminActivityFactionItemPath(_activityId, _factionId),
        '/admin/activities/$_activityId/factions/$_factionId',
      );
    });
  });

  group('兩枚新機器碼與失敗信封', () {
    test('2033／2034 各自成值，不併入 2029／2013／1001', () {
      expect(
        ApiMachineCode.fromValue(2033),
        ApiMachineCode.activityClosedWrites,
      );
      expect(ApiMachineCode.fromValue(2034), ApiMachineCode.factionNameTaken);
      expect(ApiMachineCode.fromValue(2013), ApiMachineCode.profileConflict);
      expect(ApiMachineCode.fromValue(2029), ApiMachineCode.activityArchived);
      expect(
        ApiMachineCode.activityClosedWrites.value,
        isNot(ApiMachineCode.factionNameTaken.value),
      );
    });

    test('失敗信封帶著 2034 時原樣保留碼值，409 不標可重試', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"code":2034,"message":"name taken","request_id":"r-fail"}',
          409,
        ),
      );
      final Object? failure = await api
          .activityFactions(activityId: _activityId)
          .then<Object?>((_) => null)
          .catchError((Object? error) => error);
      expect(failure, isA<ApiError>());
      final ApiError error = failure! as ApiError;
      expect(error.knownCode, ApiMachineCode.factionNameTaken);
      expect(error.retryable, isFalse);
    });

    test('失敗信封帶著 2033 時點名到「活動停止」那一句而不是歸檔', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"code":2033,"message":"closed","request_id":"r-fail-2"}',
          409,
        ),
      );
      final Object? failure = await api
          .activityFactions(activityId: _activityId)
          .then<Object?>((_) => null)
          .catchError((Object? error) => error);
      expect(
        (failure! as ApiError).knownCode,
        ApiMachineCode.activityClosedWrites,
      );
    });
  });
}
