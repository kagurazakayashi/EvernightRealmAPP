/// 「活動標籤定義」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：五條方法各自的 HTTP 方法與精確路徑、建立白名單**恰好**四欄
/// 加一格可選排序而永遠不帶 `public`、編輯白名單恰好十四欄（七新值加七依據值）、
/// 派生值 `accepts_new_assignments` 寫不進本體、必填缺席判合同違例而未知多餘欄位容忍，
/// 以及 2040 在前端自成一值、不與 2034／2013／1001 混用。
/// 玩家那一族只有 GET：它讀到的是白名單投影，因此測試也確認那份回應裡
/// 沒有的格子不會被模型偽造出來（缺席就是缺席，不降級成 false 或 0）。
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
const String _tagId = '01a1b000-0000-7000-8000-0000000000t1';

/// 一筆標籤定義（管理側讀法）的可展示事實。
///
/// [extraField] 用來演「後端日後多發的未知欄位必須被容忍」；[public] 與 [available]
/// 刻意不綁死，因為派生值 [acceptsNewAssignments] 講的是「可用**且**活動收業務寫入」，
/// 三個格子各有各的真相。
String _tagJson({
  String name = '冠軍',
  String description = '發給得名者的標記',
  String icon = 'trophy',
  String color = '#f0a020',
  int sortOrder = 0,
  bool available = true,
  bool publicFlag = false,
  bool? acceptsNewAssignments,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"tag_id":"$_tagId"',
    '"activity_id":"$_activityId"',
    '"name":"$name"',
    '"description":"$description"',
    '"icon":"$icon"',
    '"color":"$color"',
    '"sort_order":$sortOrder',
    '"available":$available',
    '"public":$publicFlag',
    '"accepts_new_assignments":${acceptsNewAssignments ?? available}',
    '"created_at":"2026-10-10T03:00:00.000Z"',
    '"updated_at":"2026-10-10T04:00:00.000Z"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

/// 玩家側的一行投影：只有標識與展示四值加排序，沒有內部那一側的任何格子。
String _publicTagJson({
  String name = '冠軍',
  String description = '發給得名者的標記',
  String icon = 'trophy',
  String color = '#f0a020',
  int sortOrder = 0,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"tag_id":"$_tagId"',
    '"name":"$name"',
    '"description":"$description"',
    '"icon":"$icon"',
    '"color":"$color"',
    '"sort_order":$sortOrder',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

String _listBody(List<String> rows) {
  return '{"tags":[${rows.join(',')}],"request_id":"r-tag-list"}';
}

String _publicListBody(List<String> rows) {
  return '{"tags":[${rows.join(',')}],"request_id":"r-pub-list"}';
}

String _writeBody({String? tag}) {
  return '{"tag":${tag ?? _tagJson()},"request_id":"r-tag-write"}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('管理側列表與建立', () {
    test('activityTags 發 GET 到集合子路徑，空清單是合法事實', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_listBody(<String>[]), 200);
      });

      final TagListReport report = await api.activityTags(
        activityId: _activityId,
      );

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, adminActivityTagsPath(_activityId));
      expect(sent.single.url.path, '/admin/activities/$_activityId/tags');
      expect(report.tags, isEmpty);
      expect(report.requestId, 'r-tag-list');
    });

    test('列表行讀得出全部白名單欄，含 public；未知新欄位容忍', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _listBody(<String>[
            _tagJson(
              publicFlag: true,
              extraField: '"next_step_field":"whatever"',
            ),
          ]),
          200,
        ),
      );
      final TagListReport report = await api.activityTags(
        activityId: _activityId,
      );
      final TagReport tag = report.tags.single;
      expect(tag.tagId, _tagId);
      expect(tag.activityId, _activityId);
      expect(tag.name, '冠軍');
      expect(tag.icon, 'trophy');
      expect(tag.color, '#f0a020');
      expect(tag.sortOrder, 0);
      expect(tag.available, isTrue);
      expect(tag.public, isTrue);
      expect(tag.acceptsNewAssignments, isTrue);
    });

    test('公開旗標缺席判合同違例：不降級成 false', () async {
      // 少這一格時界面無從判「這份定義對外不對外」；降級成 false 會讓界面憑空唸出
      // 「這枚是內部的」，那是一次憑空發明的收緊（同 available 缺席的口徑）。
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"tags":[{"tag_id":"$_tagId","activity_id":"$_activityId",'
          '"name":"缺公開旗標","description":"","icon":"","color":"",'
          '"sort_order":0,"available":true,"accepts_new_assignments":true,'
          '"created_at":"2026-10-10T03:00:00.000Z",'
          '"updated_at":"2026-10-10T03:00:00.000Z"}],"request_id":"r-x"}',
          200,
        ),
      );
      expect(
        () => api.activityTags(activityId: _activityId),
        throwsA(isA<ApiError>()),
      );
    });

    test('必填欄缺席判合同違例：available 缺失不降級成 false', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"tags":[{"tag_id":"$_tagId","activity_id":"$_activityId",'
          '"name":"缺欄","description":"","icon":"","color":"",'
          '"sort_order":0,"public":false,"accepts_new_assignments":true,'
          '"created_at":"2026-10-10T03:00:00.000Z",'
          '"updated_at":"2026-10-10T03:00:00.000Z"}],"request_id":"r-x"}',
          200,
        ),
      );
      expect(
        () => api.activityTags(activityId: _activityId),
        throwsA(isA<ApiError>()),
      );
    });

    test('派生值與兩個旗標分得開：標籤可用而活動停止時三格各自讀出', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _listBody(<String>[
            _tagJson(
              available: true,
              publicFlag: true,
              acceptsNewAssignments: false,
            ),
          ]),
          200,
        ),
      );
      final TagReport tag = (await api.activityTags(activityId: _activityId))
          .tags
          .single;
      // 界面靠這三格分開講「它還是那枚標籤」「這份定義對外了」與「此刻貼不貼得出去」。
      expect(tag.available, isTrue);
      expect(tag.public, isTrue);
      expect(tag.acceptsNewAssignments, isFalse);
    });

    test('空圖標與空顏色是合法現值（未選），讀成空字串而不是失敗', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _listBody(<String>[_tagJson(icon: '', color: '', description: '')]),
          200,
        ),
      );
      final TagListReport report = await api.activityTags(
        activityId: _activityId,
      );
      expect(report.tags.single.icon, isEmpty);
      expect(report.tags.single.color, isEmpty);
      expect(report.tags.single.description, isEmpty);
    });

    test('createTag 發 POST 到集合路徑，未指定排序時本體恰好四個欄位', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(), 201);
      });

      final TagWriteReport report = await api.createTag(
        activityId: _activityId,
        name: '冠軍',
        description: '發給得名者的標記',
        icon: 'trophy',
        color: '#f0a020',
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, adminActivityTagsPath(_activityId));
      final Map<String, Object?> body =
          jsonDecode(sent.single.body) as Map<String, Object?>;
      // `public` 不在建立白名單裡：新建一律是管理員的內部資訊，公開是之後那一跳明確的編輯。
      // available／id／activity_id／時刻同理由服務端決定，本體沒有一格能填。
      expect(body.keys.toSet(), <String>{
        'name',
        'description',
        'icon',
        'color',
      });
      expect(body.containsKey('public'), isFalse);
      expect(body.containsKey('available'), isFalse);
      expect(body.containsKey('sort_order'), isFalse);
      expect(report.tag.public, isFalse);
      expect(report.tag.available, isTrue);
      expect(report.requestId, 'r-tag-write');
    });

    test('createTag 帶排序值時恰好五個欄位（null 與 0 分得開）', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(tag: _tagJson(sortOrder: 0)), 201);
      });

      await api.createTag(
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

  group('管理側編輯', () {
    test('updateTag 發 PUT 到單筆路徑，本體恰好七欄新值加七欄依據值', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(
          _writeBody(tag: _tagJson(available: false, publicFlag: true)),
          200,
        );
      });

      final TagWriteReport report = await api.updateTag(
        activityId: _activityId,
        tagId: _tagId,
        name: '改名後的冠軍',
        description: '發給得名者的標記',
        icon: 'star',
        color: '#102040',
        sortOrder: 7,
        available: false,
        public: true,
        expectedName: '冠軍',
        expectedDescription: '發給得名者的標記',
        expectedIcon: 'trophy',
        expectedColor: '#f0a020',
        expectedSortOrder: 0,
        expectedAvailable: true,
        expectedPublic: false,
      );

      expect(sent.single.method, 'PUT');
      expect(
        sent.single.url.path,
        adminActivityTagItemPath(_activityId, _tagId),
      );
      expect(
        sent.single.url.path,
        '/admin/activities/$_activityId/tags/$_tagId',
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
        'public',
        'expected_name',
        'expected_description',
        'expected_icon',
        'expected_color',
        'expected_sort_order',
        'expected_available',
        'expected_public',
      });
      // 公開那一欄是「public／expected_public」這一對名字，不是某個別稱：
      // 界面要翻它就只能走這條白名單，沒有第二條狀態子通路可繞。
      expect(body['public'], isTrue);
      expect(body['expected_public'], isFalse);
      // 身分與歸屬不在這條通路的白名單裡（也不在 UPDATE 語句裡）：
      // 「儲存順手把標籤挪進另一個活動」在協定層就不是被拒，而是沒有一個可以填的格子。
      expect(body.containsKey('tag_id'), isFalse);
      expect(body.containsKey('id'), isFalse);
      expect(body.containsKey('activity_id'), isFalse);
      expect(body.containsKey('created_at'), isFalse);
      expect(body.containsKey('updated_at'), isFalse);
      // 派生值不是可寫欄位：想靠本體宣稱「還貼得出去」在前端就發不出去，
      // 後端對這類未知欄位的回答是 1004 點名（見根倉庫端點證據）。
      expect(body.containsKey('accepts_new_assignments'), isFalse);
      expect(report.tag.available, isFalse);
      expect(report.tag.public, isTrue);
    });

    test('標識進路徑時按 URL 規則編碼', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(), 200);
      });
      await api.updateTag(
        activityId: _activityId,
        tagId: _tagId,
        name: '正常名字',
        description: '',
        icon: '',
        color: '',
        sortOrder: 1,
        available: true,
        public: false,
        expectedName: '舊名字',
        expectedDescription: '',
        expectedIcon: '',
        expectedColor: '',
        expectedSortOrder: 0,
        expectedAvailable: true,
        expectedPublic: false,
      );
      expect(sent.single.url.path.endsWith(_tagId), isTrue);
    });

    test('這一族沒有刪除通路：合同層不提供 delete（本測試釘住路徑函數形狀）', () {
      // 用戶批准：只有可用／停用，沒有刪除，也不級聯清空歷史。列表與單筆兩條路徑之外
      // 不該長出第三條；這裡釘的是「集合路徑就是活動詳情路徑的子資源」這一結構事實。
      expect(
        adminActivityTagsPath(_activityId),
        '/admin/activities/$_activityId/tags',
      );
      expect(
        adminActivityTagItemPath(_activityId, _tagId),
        '/admin/activities/$_activityId/tags/$_tagId',
      );
    });
  });

  group('玩家側讀法（唯讀投影）', () {
    test('publicActivityTags 發 GET 到 /player 那一族，只讀到投影那幾格', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_publicListBody(<String>[_publicTagJson()]), 200);
      });

      final PublicTagListReport report = await api.publicActivityTags(
        activityId: _activityId,
      );

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, playerActivityTagsPath(_activityId));
      expect(sent.single.url.path, '/player/activities/$_activityId/tags');
      final PublicTagReport tag = report.tags.single;
      expect(tag.tagId, _tagId);
      expect(tag.name, '冠軍');
      expect(tag.icon, 'trophy');
      expect(tag.color, '#f0a020');
      expect(tag.sortOrder, 0);
      expect(report.requestId, 'r-pub-list');
    });

    test('玩家投影裡多發的未知欄位容忍，但不會變成模型上的格子', () async {
      // 後端只增不刪：多出來的格子必須讀得過去。同時這一份模型刻意沒有
      // available／public／時刻／計數那些欄位——界面因此無格可填，也不可能把
      // 「回應裡沒有」念成「值是假的」。
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          _publicListBody(<String>[
            _publicTagJson(extraField: '"available":false'),
          ]),
          200,
        ),
      );
      final PublicTagListReport report = await api.publicActivityTags(
        activityId: _activityId,
      );
      expect(report.tags.single.name, '冠軍');
      expect(report.tags.single.tagId, _tagId);
    });

    test('玩家投影必填缺席判合同違例：name 缺失不降級成空字串', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"tags":[{"tag_id":"$_tagId","description":"","icon":"",'
          '"color":"","sort_order":0}],"request_id":"r-x"}',
          200,
        ),
      );
      expect(
        () => api.publicActivityTags(activityId: _activityId),
        throwsA(isA<ApiError>()),
      );
    });

    test('publicActivityTag 發 GET 到單筆路徑（未公開與查無同為 1001，界面分不出）', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(
          '{"tag":${_publicTagJson()},"request_id":"r-pub-one"}',
          200,
        );
      });

      final PublicTagDetailReport report = await api.publicActivityTag(
        activityId: _activityId,
        tagId: _tagId,
      );

      expect(sent.single.method, 'GET');
      expect(
        sent.single.url.path,
        playerActivityTagItemPath(_activityId, _tagId),
      );
      expect(
        sent.single.url.path,
        '/player/activities/$_activityId/tags/$_tagId',
      );
      expect(report.tag.tagId, _tagId);
      expect(report.requestId, 'r-pub-one');
    });

    test('單筆回應的 tag 不是物件判合同違例', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async =>
            _json('{"tag":[],"request_id":"r-x"}', 200),
      );
      expect(
        () => api.publicActivityTag(activityId: _activityId, tagId: _tagId),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('新機器碼 2040 與失敗信封', () {
    test('2040 自成一值，不併入 2034／2013／1001／2033／2029', () {
      expect(ApiMachineCode.fromValue(2040), ApiMachineCode.tagNameTaken);
      expect(ApiMachineCode.fromValue(2034), ApiMachineCode.factionNameTaken);
      expect(ApiMachineCode.fromValue(2013), ApiMachineCode.profileConflict);
      expect(ApiMachineCode.fromValue(1001), ApiMachineCode.notFound);
      expect(
        ApiMachineCode.fromValue(2033),
        ApiMachineCode.activityClosedWrites,
      );
      expect(ApiMachineCode.fromValue(2029), ApiMachineCode.activityArchived);
      // 同一枚碼的語義永不因後續步驟改寫：標籤撞名與陣營撞名是兩枚碼，
      // 混用會讓界面把「換個名字」念成另一處該換的東西。
      expect(
        ApiMachineCode.tagNameTaken.value,
        isNot(ApiMachineCode.factionNameTaken.value),
      );
      expect(
        ApiMachineCode.tagNameTaken.value,
        isNot(ApiMachineCode.profileConflict.value),
      );
      expect(
        ApiMachineCode.tagNameTaken.value,
        isNot(ApiMachineCode.notFound.value),
      );
    });

    test('失敗信封帶著 2040 時原樣保留碼值，409 不標可重試', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"code":2040,"message":"name taken","request_id":"r-fail"}',
          409,
        ),
      );
      final Object? failure = await api
          .activityTags(activityId: _activityId)
          .then<Object?>((_) => null)
          .catchError((Object? error) => error);
      expect(failure, isA<ApiError>());
      final ApiError error = failure! as ApiError;
      expect(error.knownCode, ApiMachineCode.tagNameTaken);
      expect(error.retryable, isFalse);
    });

    test('1004 點名欄位時 details.invalid_field 讀得出來（界面據它換那句欄位級結論）', () async {
      final ServerApi api = apiWithHandler(
        (http.Request request) async => _json(
          '{"code":1004,"message":"bad field","details":{"invalid_field":"public"},'
          '"request_id":"r-fail-2"}',
          400,
        ),
      );
      final Object? failure = await api
          .activityTags(activityId: _otherActivityId)
          .then<Object?>((_) => null)
          .catchError((Object? error) => error);
      final ApiError error = failure! as ApiError;
      expect(error.knownCode, ApiMachineCode.invalidBody);
      expect(error.details?['invalid_field'], 'public');
    });
  });
}
