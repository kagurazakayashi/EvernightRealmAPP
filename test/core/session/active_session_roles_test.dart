/// ActiveSession 的角色承載：身份只來自伺服器回應，輪換不憑空抹掉。
///
/// 這裡問的是「界面拿到的身份是不是後端說的那個」，不問授權——授權在服務端逐請求現讀。
/// 前端把角色讀錯或讀丟，結果是入口呈現錯句，而請求照常被打回；兩者都該被點名。
library;

import 'package:evernightrealm/core/api/server_models.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

LoginReport _login({String? roles}) => LoginReport.decode(<String, Object?>{
  'subject_kind': 'account',
  'account_id': 'acct-1',
  'device_id': 'device-1',
  'expires_at': '2026-10-02T10:00:00.000Z',
  if (roles != null) 'roles': <String>[roles],
  'request_id': 'r-1',
});

CurrentSessionReport _session({List<String> roles = const <String>[]}) =>
    CurrentSessionReport.decode(<String, Object?>{
      'subject_kind': 'account',
      'account_id': 'acct-1',
      'device_id': 'device-1',
      'rotation_seq': 1,
      'created_at': '2026-10-02T09:00:00.000Z',
      'last_active_at': '2026-10-02T09:30:00.000Z',
      'expires_at': '2026-10-02T10:00:00.000Z',
      if (roles.isNotEmpty) 'roles': roles,
      'request_id': 'r-2',
    });

void main() {
  test('登入回應帶授予即認得管理員，欄位缺席時是普通帳戶', () {
    final ActiveSession admin = ActiveSession.fromLogin(
      _login(roles: kServerAdminRole),
    );
    expect(admin.isServerAdmin, isTrue);
    expect(admin.roles, <String>[kServerAdminRole]);

    final ActiveSession plain = ActiveSession.fromLogin(_login());
    expect(plain.isServerAdmin, isFalse, reason: '沒有授予就沒有身份');
    expect(plain.roles, isEmpty);
  });

  test('當前會話的授予現讀優先於本地記憶', () {
    expect(
      ActiveSession.fromCurrentSession(
        _session(roles: <String>[kServerAdminRole]),
      ).isServerAdmin,
      isTrue,
    );
    // 後端把授予收回後的回應不再帶 roles：界面必須跟著收，而不是停在「他還是管理員」。
    expect(ActiveSession.fromCurrentSession(_session()).isServerAdmin, isFalse);
  });

  test('輪換不換身份：沿用輪換前的授予', () {
    final RotationReport report = RotationReport.decode(<String, Object?>{
      'subject_kind': 'account',
      'account_id': 'acct-1',
      'device_id': 'device-1',
      'rotation_seq': 2,
      'expires_at': '2026-10-02T10:00:00.000Z',
      'request_id': 'r-3',
    });
    final ActiveSession rotated = ActiveSession.fromRotation(
      report,
      previousRoles: <String>[kServerAdminRole],
    );
    expect(rotated.isServerAdmin, isTrue);
    expect(rotated.roles, <String>[kServerAdminRole]);

    // 未帶 previousRoles（原本就不是管理員的會話）時不得憑空多出角色。
    expect(
      ActiveSession.fromRotation(report).isServerAdmin,
      isFalse,
      reason: '輪換回應不帶 roles，空值只能沿用成空',
    );
  });

  test('未知角色值原樣保留，不讓整份回應變成「讀不懂」', () {
    final ActiveSession future = ActiveSession.fromLogin(
      _login(roles: 'activity_owner'),
    );
    expect(future.roles, <String>['activity_owner']);
    expect(future.isServerAdmin, isFalse);
  });
}
