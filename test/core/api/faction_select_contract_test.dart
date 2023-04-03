/// 「玩家自選陣營與活動開關」端點在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：四條路徑的方法、每條白名單**恰好**哪些欄位（配置只帶模式與
/// 它的依據值、自選只帶目標陣營與它的依據值，兩側都沒有身分欄與派生值的格子）、
/// `faction_select_mode` 與 `can_select_now`／`selectable` 必填而缺席判合同違例、
/// `faction_id` 的「空字串＝尚未分組」與「缺席＝抵觸合同」分得開，以及 2036～2039
/// 這四枚新碼在前端各自成值、都不值得自動重試。未知新欄位一律容忍（後端只增不刪）。
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
const String _factionId = '01a1b000-0000-7000-8000-0000000000f1';
const String _accountId = '01a1b000-0000-7000-8000-0000000000c1';

/// 一個候選陣營的回顯。[selectable] 是後端派生值，缺席就判合同違例——
/// 界面靠它決定長不長那顆按鈕，讀不到時猜「可選」會把停用的陣營畫成能點。
String _optionJson({
  String factionId = _factionId,
  bool available = true,
  bool selectable = true,
}) {
  final List<String> parts = <String>[
    '"faction_id":"$factionId"',
    '"name":"黎明軍"',
    '"description":""',
    '"icon":"star"',
    '"color":"#12abcd"',
    '"sort_order":0',
    '"available":$available',
    if (selectable) '"selectable":true' else '"selectable":false',
  ];
  return '{${parts.join(',')}}';
}

/// 本人現況一讀的本體。`factionId` 傳 null 演的是「這一格根本沒回」，
/// 傳空字串演的是合法現值「尚未分組」——兩者必須分得開。
String _viewBody({
  String status = 'active',
  String mode = 'first_only',
  bool canSelectNow = true,
  String? factionId = '',
  List<String> options = const <String>[],
  List<String> omitted = const <String>[],
}) {
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"name":"秋夜長談"',
    '"status":"$status"',
    '"faction_select_mode":"$mode"',
    '"access_restricted":false',
    if (!omitted.contains('can_select_now')) '"can_select_now":$canSelectNow',
    '"member_id":"$_memberId"',
    '"nickname":"夜行者"',
    if (factionId != null) '"faction_id":"$factionId"',
    '"factions":[${options.join(',')}]',
    '"request_id":"r-view"',
  ];
  return '{${parts.join(',')}}';
}

/// 活動詳情本體（自選模式取值可由呼叫端指定，也能抽掉那一格演缺席）。
String _activityBody({
  String mode = 'free',
  String? extraField,
  bool omitMode = false,
}) {
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"name":"秋夜長談"',
    '"description":""',
    '"status":"active"',
    if (!omitMode) '"faction_select_mode":"$mode"',
    // 目錄那一欄是活動詳情现在必須帶著的一格（本檔只在 omitMode 那一条演缺席，
    // 這裡補上合法值是为了讓其餘案例仍走完整合同）。
    '"member_directory_mode":"hidden"',
    '"created_by_account_id":"$_accountId"',
    '"manager_count":1',
    '"created_at":"2026-10-10T03:00:00.000Z"',
    '"updated_at":"2026-10-10T04:00:00.000Z"',
    ?extraField,
  ];
  return '{"activity":{${parts.join(',')}},"request_id":"r-1"}';
}

/// 自選寫入本體。
String _writeBody({String? extraField}) {
  final List<String> parts = <String>[
    '"member_id":"$_memberId"',
    '"activity_id":"$_activityId"',
    '"nickname":"夜行者"',
    '"faction_id":"$_factionId"',
    '"updated_at":"2026-10-10T05:00:00.000Z"',
    '"request_id":"r-w"',
    ?extraField,
  ];
  return '{${parts.join(',')}}';
}

http.Response _json(String body, int status) => http.Response(
  body,
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// 取出一條請求本體裡的欄位名集合（白名單「恰好哪些格」只這樣釘得住）。
Set<String> _bodyKeys(http.Request request) =>
    (jsonDecode(request.body) as Map<String, Object?>).keys.toSet();

/// captured 的失敗：本檔每條斷言都只問「拋出來的那一枚是不是 ApiError 且程式碼是哪個」。
Future<ApiError?> _failure(Future<void> Function() body) async {
  try {
    await body();
  } on ApiError catch (error) {
    return error;
  }
  return null;
}

void main() {
  group('管理側那一欄配置', () {
    test('updateFactionSelectMode 發 PUT 到子資源，本體恰好兩個欄位', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_activityBody(), 200);
      });

      final ActivityDetailReport report = await api.updateFactionSelectMode(
        activityId: _activityId,
        mode: 'free',
        expectedMode: 'disabled',
      );

      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, adminActivityFactionSelectPath(_activityId));
      expect(_bodyKeys(sent.single), <String>{'mode', 'expected_mode'});
      expect(report.activity.factionSelectMode, 'free');
    });

    test('活動回應少了 faction_select_mode 判合同違例，不降級成「沒開放」', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return _json(_activityBody(omitMode: true), 200);
      });

      expect(
        await _failure(() => api.activityDetail(activityId: _activityId)),
        isNotNull,
      );
    });

    test('活動回應多出未知欄位時容忍（後端只增不刪）', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return _json(_activityBody(extraField: '"brand_new":"x"'), 200);
      });

      final ActivityDetailReport report = await api.activityDetail(
        activityId: _activityId,
      );
      expect(report.activity.factionSelectMode, 'free');
    });
  });

  group('玩家側三條通路', () {
    test('myActivities 發 GET 到 /player/activities，空清單是合法事實', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json('{"activities":[],"request_id":"r-list"}', 200);
      });

      final MyActivityListReport report = await api.myActivities();

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, playerActivitiesPath());
      expect(report.activities, isEmpty);
      expect(report.requestId, 'r-list');
    });

    test('本人清單每行同時帶活動現值與我的歸屬；空字串讀成尚未分組', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return _json(
          '{"activities":[{"activity_id":"$_activityId","name":"秋夜長談",'
          '"status":"active","faction_select_mode":"free","access_restricted":false,"member_id":"$_memberId",'
          '"nickname":"夜行者","faction_id":"","joined_at":"2026-10-10T03:00:00.000Z"},'
          '{"activity_id":"$_activityId","name":"另一場","status":"draft",'
          '"faction_select_mode":"disabled","access_restricted":false,'
          '"member_id":"$_memberId",'          '"nickname":"夜行者","faction_id":"$_factionId",'
          '"joined_at":"2026-10-09T03:00:00.000Z"}],"request_id":"r-list"}',
          200,
        );
      });

      final MyActivityListReport report = await api.myActivities();

      expect(report.activities, hasLength(2));
      expect(report.activities.first.hasFaction, isFalse);
      expect(report.activities.last.hasFaction, isTrue);
      expect(report.activities.last.factionSelectMode, 'disabled');
      expect(report.activities.last.status, 'draft');
    });

    test('myFactionSelection 讀出現值、派生值與候選清單', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_viewBody(options: <String>[_optionJson()]), 200);
      });

      final FactionSelectionReport report = await api.myFactionSelection(
        activityId: _activityId,
      );

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, playerActivityFactionPath(_activityId));
      expect(report.canSelectNow, isTrue);
      expect(report.factionSelectMode, 'first_only');
      expect(report.factions.single.selectable, isTrue);
      expect(report.optionById(_factionId)?.name, '黎明軍');
      // 讀不到時回 null 而不是編一個名字：這一格只可能來自合同外的歸屬，
      // 界面要能如實說「這一格我讀不懂」。
      expect(report.optionById('沒有這一個'), isNull);
    });

    test('現況少了 can_select_now 這一格判合同違例，不由界面猜組合', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return _json(_viewBody(omitted: <String>['can_select_now']), 200);
      });

      expect(
        await _failure(() => api.myFactionSelection(activityId: _activityId)),
        isNotNull,
      );
    });

    test('候選項少了 selectable 判合同違例（猜「可選」會把停用陣營畫成能點）', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return _json(
          _viewBody(
            options: <String>[
              '{"faction_id":"$_factionId","name":"黎明軍","description":"",'
                  '"icon":"","color":"","sort_order":0,"available":true}',
            ],
          ),
          200,
        );
      });

      expect(
        await _failure(() => api.myFactionSelection(activityId: _activityId)),
        isNotNull,
      );
    });

    test('selectOwnFaction 發 PUT 到本人路徑，本體恰好兩個欄位', () async {
      final List<http.Request> sent = <http.Request>[];
      final ServerApi api = apiWithHandler((http.Request request) async {
        sent.add(request);
        return _json(_writeBody(), 200);
      });

      final SelfFactionWriteReport report = await api.selectOwnFaction(
        activityId: _activityId,
        factionId: _factionId,
        expectedFactionId: '',
      );

      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, playerActivityFactionPath(_activityId));
      expect(_bodyKeys(sent.single), <String>{
        'faction_id',
        'expected_faction_id',
      });
      expect(report.factionId, _factionId);
      expect(report.memberId, _memberId);
      expect(
        report.updatedAt,
        DateTime.parse('2026-10-10T05:00:00.000Z').toUtc(),
      );
    });

    test('自選回應不帶帳戶投影那一格：多出未知欄位照樣容忍', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return _json(_writeBody(extraField: '"brand_new":true'), 200);
      });

      final SelfFactionWriteReport report = await api.selectOwnFaction(
        activityId: _activityId,
        factionId: _factionId,
        expectedFactionId: '',
      );
      expect(report.nickname, '夜行者');
    });

    test('1001 不被讀成自選那幾枚碼：幽靈活動只得到不可分辨那一句', () async {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return _json('{"code":1001,"message":"gone","request_id":"r-e"}', 404);
      });

      final ApiError? failure = await _failure(
        () => api.myFactionSelection(activityId: _activityId),
      );
      expect(failure?.knownCode, ApiMachineCode.notFound);
      expect(failure?.retryable, isFalse);
    });
  });

  group('本步發布的四枚機器碼', () {
    test('2036～2039 各自成值、彼此不同，且都收錄在值表裡', () {
      expect(ApiMachineCode.factionNotAcceptingMembers.value, 2036);
      expect(ApiMachineCode.factionSelectDisabled.value, 2037);
      expect(ApiMachineCode.factionSelectNotOpen.value, 2038);
      expect(ApiMachineCode.factionSelectLockedIn.value, 2039);
      expect(
        ApiMachineCode.fromValue(2036),
        ApiMachineCode.factionNotAcceptingMembers,
      );
      expect(
        ApiMachineCode.fromValue(2039),
        ApiMachineCode.factionSelectLockedIn,
      );
      expect(
        ApiMachineCode.values.map((ApiMachineCode c) => c.value).toList(),
        ApiMachineCode.values
            .map((ApiMachineCode c) => c.value)
            .toSet()
            .toList(),
        reason: '已發布的數值不得重用',
      );
    });

    test('四句都是「原樣重發還是同一句」：不標為可自動重試', () async {
      for (final int code in <int>[2036, 2037, 2038, 2039]) {
        final ServerApi api = apiWithHandler((http.Request request) async {
          return _json('{"code":$code,"message":"no","request_id":"r-e"}', 409);
        });
        final ApiError? failure = await _failure(
          () => api.selectOwnFaction(
            activityId: _activityId,
            factionId: _factionId,
            expectedFactionId: '',
          ),
        );
        expect(failure, isNotNull, reason: '編碼 $code 應被識別成一句失敗');
        expect(failure!.retryable, isFalse, reason: '編碼 $code 不值得自動重發');
        expect(failure.httpStatus, 409);
      }
    });
  });
}
