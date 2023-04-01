/// 玩家目錄三條讀法在前端的合同鏡像測試。
///
/// 釘的是合同而不是畫面：
/// * 三條路徑的方法與形狀（目錄／單筆詳情／本人投影），以及目錄那一條**只有**四個查詢
///   引數（page、page_size、q、faction）——「用管理視角給我全部人」在客戶端也無處可填，
///   模式與派生值一律只出現在回應裡。
/// * 空字串與欄位缺席是兩回事：`faction_id`、`faction_name`、`self_member_id` 允許空值
///   （那是「尚未分組」與「這個視角沒有本人的行」兩句合法事實），
///   而 `member_directory_mode`、`faction_available`、`page`／`page_size`／`total` 缺席
///   判合同違例——界面不能把「讀不到那一欄」降級成「這一態沒開放」或「這個陣營已停用」。
/// * 未知新欄位一律容忍（後端只增不刪）。
/// * 1001 與 1004 都讀成值：1001 是那四句不可分辨（查無活動、非成員、跨活動、
///   此刻不可見）共用的一句話，且**不可自動重試**——重讀不會改變結論。
library;

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/test_server.dart';

const String _activityId = '01a1c000-0000-7000-8000-0000000000a1';
const String _memberId = '01a1c000-0000-7000-8000-0000000000m1';
const String _factionId = '01a1c000-0000-7000-8000-0000000000f1';

/// 一行目錄投影。[omitAvailability] 演「那一欄還沒上線」的舊服務器：必須判違例。
String _rowJson({
  String memberId = _memberId,
  String nickname = '夜行者',
  String factionId = _factionId,
  String factionName = '黎明軍',
  bool factionAvailable = true,
  bool omitAvailability = false,
}) {
  final List<String> parts = <String>[
    '"member_id":"$memberId"',
    '"nickname":"$nickname"',
    '"faction_id":"$factionId"',
    '"faction_name":"$factionName"',
    '"faction_icon":"star"',
    '"faction_color":"#12abcd"',
    if (!omitAvailability) '"faction_available":$factionAvailable',
    '"business_status":"normal"',
    '"custom_status_id":""',
    '"custom_status_name":""',
    '"status_display_name":""',
    '"status_available":true',
    '"joined_at":"2026-10-10T03:00:00.000Z"',
  ];
  return '{${parts.join(',')}}';
}

/// 目錄一讀的本體。
String _directoryBody({
  String mode = 'all_members',
  String selfMemberId = _memberId,
  List<String> rows = const <String>[],
  List<String> facets = const <String>[],
  int page = 1,
  int pageSize = 20,
  int total = 0,
  String? extraField,
}) {
  final List<String> parts = <String>[
    '"members":[${rows.join(',')}]',
    '"facets":[${facets.join(',')}]',
    '"member_directory_mode":"$mode"',
    '"self_member_id":"$selfMemberId"',
    '"page":$page',
    '"page_size":$pageSize',
    '"total":$total',
    if (extraField != null) '"$extraField":1',
    '"request_id":"r-dir"',
  ];
  return '{${parts.join(',')}}';
}

String _facetJson({String count = '3'}) {
  return '{"faction_id":"$_factionId","name":"黎明軍","icon":"star",'
      '"color":"#12abcd","count":$count}';
}

String _profileBody({
  String mode = 'hidden',
  String visibility = 'inherit',
  bool factionAvailable = true,
  bool omitAvailability = false,
}) {
  final List<String> parts = <String>[
    '"activity_id":"$_activityId"',
    '"name":"秋夜長談"',
    '"status":"active"',
    '"member_directory_mode":"$mode"',
    '"member_id":"$_memberId"',
    '"nickname":"夜行者"',
    '"faction_id":"$_factionId"',
    '"faction_name":"黎明軍"',
    '"faction_icon":"star"',
    '"faction_color":"#12abcd"',
    if (!omitAvailability) '"faction_available":$factionAvailable',
    '"business_status":"normal"',
    '"custom_status_id":""',
    '"custom_status_name":""',
    '"status_display_name":""',
    '"status_available":true',
    '"directory_visibility":"$visibility"',
    '"joined_at":"2026-10-10T03:00:00.000Z"',
    '"request_id":"r-profile"',
  ];
  return '{${parts.join(',')}}';
}

/// 把一次注定失敗的讀取收成 [ApiError]：合同層只問「失敗以哪一句呈現」，不吞例外。
Future<ApiError> _captureError(Future<Object?> Function() run) async {
  try {
    await run();
  } on ApiError catch (error) {
    return error;
  }
  throw StateError('這條呼叫注定失敗，卻回來了值');
}

void main() {
  test('三條讀法的路徑與方法，且目錄帶 page／page_size', () async {
    final List<String> seen = <String>[];
    final ServerApi api = apiWithHandler((http.Request request) async {
      seen.add('${request.method} ${request.url.path}?${request.url.query}');
      return jsonOk(
        request.url.path.endsWith('/profile')
            ? _profileBody()
            : request.url.path.contains(_memberId)
            ? '{"member":${_rowJson()},"request_id":"r-one"}'
            : _directoryBody(rows: <String>[_rowJson()], total: 1),
      );
    });
    await api.playerMemberDirectory(activityId: _activityId);
    await api.playerDirectoryMember(
      activityId: _activityId,
      memberId: _memberId,
    );
    await api.playerOwnMemberProfile(activityId: _activityId);
    expect(seen, <String>[
      'GET /player/activities/$_activityId/members?page=1&page_size=20',
      'GET /player/activities/$_activityId/members/$_memberId?',
      'GET /player/activities/$_activityId/profile?',
    ]);
  });

  test('空關鍵字與空篩選不發參數；帶值時逐參數編碼', () async {
    final List<String> queries = <String>[];
    final ServerApi api = apiWithHandler((http.Request request) async {
      queries.add(request.url.query);
      return jsonOk(_directoryBody());
    });
    await api.playerMemberDirectory(
      activityId: _activityId,
      query: '   ',
      factionId: '',
    );
    await api.playerMemberDirectory(
      activityId: _activityId,
      page: 3,
      pageSize: 50,
      query: '甲 &乙',
      factionId: _factionId,
    );
    expect(queries[0], 'page=1&page_size=20');
    expect(Uri.splitQueryString(queries[1]), <String, String>{
      'page': '3',
      'page_size': '50',
      'q': '甲 &乙',
      'faction': _factionId,
    });
  });

  test('路徑引數逐字編碼：標識裡帶斜線也走同一條路徑段', () async {
    String? path;
    final ServerApi api = apiWithHandler((http.Request request) async {
      path = request.url.path;
      return jsonOk(
        '{"member":${_rowJson(memberId: "a/b")},"request_id":"r-one"}',
      );
    });
    await api.playerDirectoryMember(activityId: 'x y', memberId: 'a/b');
    expect(path, '/player/activities/x%20y/members/a%2Fb');
  });

  test('目錄讀回行、候選、模式與分頁；越界頁是空行而總數照實', () async {
    final ServerApi api = stubApi(
      overrides: <String, String>{
        '/player/activities/$_activityId/members': _directoryBody(
          mode: 'same_faction_only',
          rows: <String>[
            _rowJson(),
            _rowJson(memberId: '01a1c-2', nickname: '很長的暱稱名字名字名字'),
          ],
          facets: <String>[_facetJson()],
          page: 4,
          total: 61,
        ),
      },
    );
    final MemberDirectoryReport report = await api.playerMemberDirectory(
      activityId: _activityId,
      page: 4,
    );
    expect(report.members.length, 2);
    expect(report.members.first.factionAvailable, isTrue);
    expect(report.members.first.hasFaction, isTrue);
    expect(report.memberDirectoryMode, 'same_faction_only');
    expect(report.isHiddenByPolicy, isFalse);
    expect(report.facets.single.count, 3);
    expect(report.total, 61);
    // 總頁數與「還有下一頁」都由後端回顯的 page／page_size／total 算出，界面不自己數行。
    expect(report.totalPages, 4);
    expect(report.hasMore, isFalse);
  });

  test('hidden 態讀成空的一頁加模式現值，不是一種錯誤', () async {
    final ServerApi api = stubApi(
      overrides: <String, String>{
        '/player/activities/$_activityId/members': _directoryBody(
          mode: 'hidden',
        ),
      },
    );
    final MemberDirectoryReport report = await api.playerMemberDirectory(
      activityId: _activityId,
    );
    expect(report.members, isEmpty);
    expect(report.total, 0);
    expect(report.isHiddenByPolicy, isTrue);
    expect(report.totalPages, 1);
  });

  test('self_member_id 與 faction_id 允許空字串：那是合法現值而不是違例', () async {
    final ServerApi api = stubApi(
      overrides: <String, String>{
        '/player/activities/$_activityId/members': _directoryBody(
          selfMemberId: '',
          rows: <String>[_rowJson(factionId: '', factionName: '')],
          total: 1,
        ),
      },
    );
    final MemberDirectoryReport report = await api.playerMemberDirectory(
      activityId: _activityId,
    );
    expect(report.selfMemberId, isEmpty);
    expect(report.members.single.hasFaction, isFalse);
    expect(report.members.single.hasFactionDisplay, isFalse);
  });

  test('member_directory_mode 缺席判合同違例，不降級成「沒開放」', () async {
    final ServerApi api = apiWithHandler((http.Request request) async {
      return jsonOk(
        _directoryBody().replaceFirst(
          '"member_directory_mode":"all_members",',
          '',
        ),
      );
    });
    final ApiError error = await _captureError(
      () => api.playerMemberDirectory(activityId: _activityId),
    );
    expect(error.kind, ApiErrorKind.invalidResponse);
  });

  test('faction_available 缺席判合同違例：讀不到那一欄不等於「已停用」', () async {
    final ServerApi directoryApi = apiWithHandler((http.Request request) async {
      return jsonOk(
        _directoryBody(rows: <String>[_rowJson(omitAvailability: true)]),
      );
    });
    final ApiError listError = await _captureError(
      () => directoryApi.playerMemberDirectory(activityId: _activityId),
    );
    expect(listError.kind, ApiErrorKind.invalidResponse);

    final ServerApi profileApi = apiWithHandler((http.Request request) async {
      return jsonOk(_profileBody(omitAvailability: true));
    });
    final ApiError profileError = await _captureError(
      () => profileApi.playerOwnMemberProfile(activityId: _activityId),
    );
    expect(profileError.kind, ApiErrorKind.invalidResponse);
  });

  test('本人投影讀回覆蓋、模式與停用旗標；未知欄位容忍', () async {
    final ServerApi api = stubApi(
      overrides: <String, String>{
        '/player/activities/$_activityId/profile': _profileBody(
          visibility: 'hidden',
          factionAvailable: false,
          mode: 'all_members',
        ),
      },
    );
    final OwnMemberProfileReport report = await api.playerOwnMemberProfile(
      activityId: _activityId,
    );
    expect(report.directoryVisibility, 'hidden');
    expect(report.isSelfHidden, isTrue);
    expect(report.factionAvailable, isFalse);
    expect(report.memberDirectoryMode, 'all_members');
    expect(report.joinedAt.isUtc, isTrue);

    final ServerApi withExtra = apiWithHandler((http.Request request) async {
      return jsonOk(
        _profileBody().replaceFirst(
          '"request_id":"r-profile"',
          '"request_id":"r-profile","future_field":"x"',
        ),
      );
    });
    expect(
      (await withExtra.playerOwnMemberProfile(activityId: _activityId))
          .memberId,
      _memberId,
    );
  });

  test('單筆詳情要嘛帶整個 member 物件，要嘛判違例', () async {
    final ServerApi bad = apiWithHandler((http.Request request) async {
      return jsonOk('{"request_id":"r-one"}');
    });
    final ApiError error = await _captureError(
      () => bad.playerDirectoryMember(
        activityId: _activityId,
        memberId: _memberId,
      ),
    );
    expect(error.kind, ApiErrorKind.invalidResponse);
  });

  test('1001 讀成 notFound 且不可自動重試；四句不可分辨在介面就是同一句', () async {
    final ServerApi api = apiWithHandler((http.Request request) async {
      return http.Response(
        '{"code":1001,"message":"not found","request_id":"r-404"}',
        404,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    final ApiError error = await _captureError(
      () => api.playerMemberDirectory(activityId: _activityId),
    );
    expect(error.knownCode, ApiMachineCode.notFound);
    expect(error.retryable, isFalse);
    final ApiError detail = await _captureError(
      () => api.playerDirectoryMember(
        activityId: _activityId,
        memberId: _memberId,
      ),
    );
    expect(detail.machineCode, 1001);
    expect(detail.retryable, isFalse);
  });

  test('1004 點名是哪個查詢引數：page 與 page_size 各說各的一句', () async {
    for (final String field in <String>['page', 'page_size', 'q', 'faction']) {
      final ServerApi api = apiWithHandler((http.Request request) async {
        return http.Response(
          '{"code":1004,"message":"bad","details":{"invalid_field":"$field"},'
          '"request_id":"r-400"}',
          400,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final ApiError error = await _captureError(
        () => api.playerMemberDirectory(activityId: _activityId),
      );
      expect(error.knownCode, ApiMachineCode.invalidBody);
      expect(error.details?['invalid_field'], field);
    }
  });
}
