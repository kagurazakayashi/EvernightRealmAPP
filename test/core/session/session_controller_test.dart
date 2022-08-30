/// 會話状态控制器的测试：状态机、按伺服器身份的作用域与隔离、存储与恢复失败，
/// 以及「原生恢复时凭据被正确注入」这条闭环。
///
/// 这些路径大多无法在真机钥匙库上稳定重现（Linux 无鑰匙圈、Android 解锁失败等），
/// 因此用内存持久化替身与 MockClient 驱动真实控制器程式码——被测的是判定逻辑，
/// 不是平台绑定（后者见 `keyed_session_persistence_test.dart` 与实机未实测的说明）。
library;

import 'package:evernightrealm/core/api/api_client.dart';
import 'package:evernightrealm/core/api/server_address.dart';
import 'package:evernightrealm/core/api/server_address_settings.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:evernightrealm/core/session/session_controller.dart';
import 'package:evernightrealm/core/session/session_persistence.dart';
import 'package:evernightrealm/core/session/session_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/test_address.dart';

/// 一份合法「當前會話」回應本體（帳戶主體）。
const String sessionJson =
    '{"subject_kind":"account","account_id":"acc-1","device_id":"dev-1",'
    '"created_at":"2026-09-30T00:00:00.000Z",'
    '"last_active_at":"2026-09-30T00:00:00.000Z",'
    '"expires_at":"2026-10-01T00:00:00.000Z","request_id":"r"}';

const Map<String, String> _jsonHeader = <String, String>{
  'content-type': 'application/json; charset=utf-8',
};

/// 以状态码构造 `/auth/session` 的失败信封（2002 未认证、2003 失效）。
http.Response sessionFailure(int code) => http.Response(
  '{"code":$code,"message":"x","request_id":"r"}',
  401,
  headers: _jsonHeader,
);

/// 可控成败的内存持久化替身，记录每个被触碰的伺服器身份。
class FakePersistence implements SessionPersistence {
  final Map<String, String> store = <String, String>{};
  final List<String> readKeys = <String>[];
  final List<String> writeKeys = <String>[];
  final List<String> clearKeys = <String>[];

  Object? failRead;
  Object? failWrite;
  Object? failClear;

  @override
  Future<String?> readSecret(String serverIdentity) async {
    if (failRead != null) {
      throw failRead!;
    }
    readKeys.add(serverIdentity);
    return store[serverIdentity];
  }

  @override
  Future<void> writeSecret(String serverIdentity, String secret) async {
    if (failWrite != null) {
      throw failWrite!;
    }
    writeKeys.add(serverIdentity);
    store[serverIdentity] = secret;
  }

  @override
  Future<void> clearSecret(String serverIdentity) async {
    if (failClear != null) {
      throw failClear!;
    }
    clearKeys.add(serverIdentity);
    store.remove(serverIdentity);
  }
}

/// 一次组装的句柄：控制器、位址设定、被记录下来的请求标头、当前身份与持久化替身。
class Harness {
  Harness({
    required this.controller,
    required this.settings,
    required this.addressStore,
    required this.persistence,
    required this.identity,
    required this.authHeaders,
  });

  final SessionController controller;
  final ServerAddressSettings settings;
  final InMemoryServerAddressPersistence addressStore;
  final FakePersistence persistence;
  final String identity;
  final List<String?> authHeaders;
}

/// 用给定位址、形态与 `/auth/session` 响应器组一个控制器；凭据闭包按真实装配接到
/// [SessionController.bearerFor]，从而恢复流程里的注入走的是生产同一条路径。
Future<Harness> wire({
  required SessionTransportMode mode,
  String? storedUrl = 'http://server.invalid:5206',
  Future<http.Response> Function(http.Request)? sessionResponder,
  FakePersistence? persistence,
}) async {
  final FakePersistence store = persistence ?? FakePersistence();
  final InMemoryServerAddressPersistence addressStore =
      InMemoryServerAddressPersistence(storedUrl);
  final ServerAddressSettings settings = ServerAddressSettings(
    addressStore,
    preferInjected: false,
  );
  await settings.restore();

  final List<String?> authHeaders = <String?>[];
  final http.Client client = MockClient((http.Request request) async {
    authHeaders.add(request.headers['authorization']);
    final Future<http.Response> Function(http.Request)? responder =
        sessionResponder;
    if (responder == null) {
      return http.Response(sessionJson, 200, headers: _jsonHeader);
    }
    return responder(request);
  });

  SessionController? controller;
  final ServerApi api = ServerApi(
    config: ServerApiConfig(
      source: settings,
      transportMode: mode,
      credentials: mode == SessionTransportMode.native
          ? (String serverIdentity) => controller?.bearerFor(serverIdentity)
          : null,
    ),
    client: client,
  );
  controller = SessionController(
    api: api,
    addresses: settings,
    mode: mode,
    persistence: mode == SessionTransportMode.native ? store : null,
  );

  final String identity =
      ServerAddress.tryParse(storedUrl ?? '')?.displayText ?? '';
  return Harness(
    controller: controller,
    settings: settings,
    addressStore: addressStore,
    persistence: store,
    identity: identity,
    authHeaders: authHeaders,
  );
}

/// 构造一份登入成果（不經網路，直接给模型）。
LoginExchange exchange({
  String? secret,
  AuthSubjectKind kind = AuthSubjectKind.account,
}) {
  return LoginExchange(
    report: LoginReport(
      subjectKind: kind,
      accountId: kind == AuthSubjectKind.account ? 'acc-1' : null,
      deviceId: 'dev-1',
      expiresAt: DateTime.utc(2026, 10, 1),
      requestId: 'r',
    ),
    sessionSecret: secret,
  );
}

void main() {
  group('恢复', () {
    test('未设定位址时直接判为未登入，不发任何请求', () async {
      final Harness h = await wire(
        mode: SessionTransportMode.native,
        storedUrl: null,
      );

      await h.controller.restore();

      expect(h.controller.status, SessionStatus.signedOut);
      expect(h.authHeaders, isEmpty);
    });

    test('原生：没有已存秘密即未登入，且不去验证', () async {
      final Harness h = await wire(mode: SessionTransportMode.native);

      await h.controller.restore();

      expect(h.controller.status, SessionStatus.signedOut);
      expect(h.authHeaders, isEmpty, reason: '没秘密就不该带凭据去问');
    });

    test('原生：有秘密时验证请求确实注入了该秘密，成功后为已登入', () async {
      final Harness h = await wire(mode: SessionTransportMode.native);
      h.persistence.store[h.identity] = 'SECRET-A';

      await h.controller.restore();

      expect(h.controller.status, SessionStatus.signedIn);
      expect(h.controller.boundServerDisplay, h.identity);
      expect(h.authHeaders.single, 'Bearer SECRET-A');
    });

    test('原生：验证回 2003 判为失效并删除已存秘密', () async {
      final Harness h = await wire(
        mode: SessionTransportMode.native,
        sessionResponder: (_) async => sessionFailure(2003),
      );
      h.persistence.store[h.identity] = 'SECRET-A';

      await h.controller.restore();

      expect(h.controller.status, SessionStatus.expired);
      expect(h.persistence.store.containsKey(h.identity), isFalse);
      expect(h.controller.bearerFor(h.identity), isNull);
    });

    test('原生：验证回 2002 判为未登入', () async {
      final Harness h = await wire(
        mode: SessionTransportMode.native,
        sessionResponder: (_) async => sessionFailure(2002),
      );
      h.persistence.store[h.identity] = 'SECRET-A';

      await h.controller.restore();

      expect(h.controller.status, SessionStatus.signedOut);
    });

    test('原生：连不上时停在未知，保留秘密与绑定，不把“查不了”当未登入', () async {
      final Harness h = await wire(
        mode: SessionTransportMode.native,
        sessionResponder: (_) async => throw http.ClientException('down'),
      );
      h.persistence.store[h.identity] = 'SECRET-A';

      await h.controller.restore();

      expect(h.controller.status, SessionStatus.unknown);
      expect(h.controller.bearerFor(h.identity), 'SECRET-A');
      expect(h.persistence.store[h.identity], 'SECRET-A');
    });

    test('原生：存储读取失败判为未知并记录原因，不发验证请求', () async {
      final Harness h = await wire(
        mode: SessionTransportMode.native,
        persistence: FakePersistence()..failRead = StateError('no keyring'),
      );

      await h.controller.restore();

      expect(h.controller.status, SessionStatus.unknown);
      expect(h.controller.lastStorageFailure, isA<StateError>());
      expect(h.authHeaders, isEmpty, reason: '读都没读到，不该接着去验证');
    });

    test('浏览器：恢复不读任何本地秘密、请求不带 Bearer', () async {
      final Harness h = await wire(mode: SessionTransportMode.web);

      await h.controller.restore();

      expect(h.controller.status, SessionStatus.signedIn);
      expect(h.authHeaders.single, isNull, reason: 'Cookie 由浏览器附带，非 Bearer');
      expect(h.controller.bearerFor(h.identity), isNull);
    });

    test('浏览器：无 Cookie 时 2002 判为未登入', () async {
      final Harness h = await wire(
        mode: SessionTransportMode.web,
        sessionResponder: (_) async => sessionFailure(2002),
      );

      await h.controller.restore();

      expect(h.controller.status, SessionStatus.signedOut);
    });

    test('浏览器：Cookie 失效时 2003 判为失效', () async {
      final Harness h = await wire(
        mode: SessionTransportMode.web,
        sessionResponder: (_) async => sessionFailure(2003),
      );

      await h.controller.restore();

      expect(h.controller.status, SessionStatus.expired);
    });
  });

  group('完成登入', () {
    test('原生：建立已登入并保存秘密，凭据只对该伺服器可用', () async {
      final Harness h = await wire(mode: SessionTransportMode.native);

      final SessionLoginOutcome outcome = await h.controller.completeLogin(
        ServerAddress.tryParse(h.identity)!,
        exchange(secret: 'SECRET-A'),
      );

      expect(outcome, SessionLoginOutcome.established);
      expect(h.controller.status, SessionStatus.signedIn);
      expect(h.persistence.store[h.identity], 'SECRET-A');
      expect(h.controller.bearerFor(h.identity), 'SECRET-A');
      expect(
        h.controller.bearerFor('http://other.invalid:5206'),
        isNull,
        reason: '换到别的伺服器身份就拿不到秘密',
      );
    });

    test('原生：写入失败时如实回报，内存会话仍可用且不落明文', () async {
      final Harness h = await wire(
        mode: SessionTransportMode.native,
        persistence: FakePersistence()..failWrite = StateError('keystore down'),
      );

      final SessionLoginOutcome outcome = await h.controller.completeLogin(
        ServerAddress.tryParse(h.identity)!,
        exchange(secret: 'SECRET-A'),
      );

      expect(outcome, SessionLoginOutcome.persistenceFailed);
      expect(h.controller.status, SessionStatus.signedIn);
      expect(h.controller.lastStorageFailure, isA<StateError>());
      expect(h.persistence.store, isEmpty, reason: '写失败时底层不得留下任何明文值');
    });

    test('原生：拿不到秘密时判为无法确定，不谎报已登入', () async {
      final Harness h = await wire(mode: SessionTransportMode.native);

      final SessionLoginOutcome outcome = await h.controller.completeLogin(
        ServerAddress.tryParse(h.identity)!,
        exchange(secret: null),
      );

      expect(outcome, SessionLoginOutcome.missingCredential);
      expect(h.controller.status, SessionStatus.unknown);
      expect(h.controller.bearerFor(h.identity), isNull);
    });

    test('浏览器：建立已登入但不保存任何令牌', () async {
      final Harness h = await wire(mode: SessionTransportMode.web);

      final SessionLoginOutcome outcome = await h.controller.completeLogin(
        ServerAddress.tryParse(h.identity)!,
        exchange(secret: 'IGNORED-BY-BROWSER'),
      );

      expect(outcome, SessionLoginOutcome.established);
      expect(h.controller.status, SessionStatus.signedIn);
      expect(h.controller.bearerFor(h.identity), isNull);
    });

    test('原生：登入新伺服器前清除旧伺服器的已存秘密', () async {
      final Harness h = await wire(mode: SessionTransportMode.native);
      const String other = 'http://b.invalid:5206';
      h.persistence.store[h.identity] = 'OLD';

      await h.controller.completeLogin(
        ServerAddress.tryParse(h.identity)!,
        exchange(secret: 'OLD'),
      );
      await h.controller.completeLogin(
        ServerAddress.tryParse(other)!,
        exchange(secret: 'NEW'),
      );

      expect(h.persistence.store.containsKey(h.identity), isFalse);
      expect(h.persistence.store[other], 'NEW');
      expect(h.controller.bearerFor(h.identity), isNull);
      expect(h.controller.boundServerDisplay, other);
    });
  });

  group('登出', () {
    test('原生：清除内存与已存秘密并标为未登入', () async {
      final Harness h = await wire(mode: SessionTransportMode.native);
      await h.controller.completeLogin(
        ServerAddress.tryParse(h.identity)!,
        exchange(secret: 'SECRET-A'),
      );

      await h.controller.signOut();

      expect(h.controller.status, SessionStatus.signedOut);
      expect(h.persistence.store.containsKey(h.identity), isFalse);
      expect(h.controller.bearerFor(h.identity), isNull);
    });
  });

  group('伺服器切换的隔离', () {
    test('位址改变即清空旧凭据与活动上下文，旧秘密被删除', () async {
      final Harness h = await wire(mode: SessionTransportMode.native);
      await h.controller.completeLogin(
        ServerAddress.tryParse(h.identity)!,
        exchange(secret: 'SECRET-A'),
      );
      expect(h.controller.isSignedIn, isTrue);

      // 把位址换到另一台服务器并触发设定变更通知。
      const String other = 'http://b.invalid:5206';
      await _switchAddress(h, other);

      expect(h.controller.status, SessionStatus.unknown);
      expect(h.controller.isSignedIn, isFalse);
      expect(h.controller.bearerFor(h.identity), isNull);
      expect(h.controller.activeSession, isNull);
      expect(
        h.persistence.clearKeys,
        contains(h.identity),
        reason: '切换要删掉旧伺服器那枚秘密',
      );
    });

    test('位址被清空时回到未登入', () async {
      final Harness h = await wire(mode: SessionTransportMode.native);
      await h.controller.completeLogin(
        ServerAddress.tryParse(h.identity)!,
        exchange(secret: 'SECRET-A'),
      );

      await _switchAddress(h, null);

      expect(h.controller.status, SessionStatus.signedOut);
      expect(h.persistence.clearKeys, contains(h.identity));
    });
  });
}

/// 变更位址设定并触发监听：直接改内存持久化里的值，再走一次会通知订阅者的载入，
/// 控制器据此作废旧会话（与真机上用户在入口页换伺服器后的效果一致）。
/// 末了让出一个微任务，确保「切换时异步入队删除旧凭据」这条支路已执行完毕。
Future<void> _switchAddress(Harness h, String? newUrl) async {
  h.addressStore.url = newUrl;
  await h.settings.restore();
  await Future<void>.delayed(Duration.zero);
}
