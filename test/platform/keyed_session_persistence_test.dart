/// 會話秘密儲存的適配測試：用記憶體鍵值替身驗證「按正規化伺服器身份分鍵、
/// 失敗上拋、绝不降级明文」这三条与真实钥匙库无关的逻辑。
///
/// 真实系统级储存（Android Keystore／Apple Keychain／Linux libsecret／Windows DPAPI）
/// 的绑定属 [FlutterSecureKeyValueStore]，需要各平台实机才能验证；本机没有那些宿主，
/// 故本测试只把 [KeyedSessionPersistence] 的鍵名映射与错误透传钉住，实机路径标为未实测。
library;

import 'package:evernightrealm/platform/keyed_session_persistence.dart';
import 'package:evernightrealm/platform/secure_key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可控成败的内存鍵值替身，并记录被触碰的鍵。
class _FakeStore implements SecureKeyValueStore {
  final Map<String, String> backing = <String, String>{};
  final List<String> readKeys = <String>[];
  final List<String> writeKeys = <String>[];
  final List<String> deleteKeys = <String>[];

  Object? failRead;
  Object? failWrite;
  Object? failDelete;

  @override
  Future<String?> read(String key) async {
    if (failRead != null) {
      throw failRead!;
    }
    readKeys.add(key);
    return backing[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite != null) {
      // 失败时必须什么都没写下去——绝不留下明文占位。
      throw failWrite!;
    }
    writeKeys.add(key);
    backing[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete != null) {
      throw failDelete!;
    }
    deleteKeys.add(key);
    backing.remove(key);
  }
}

void main() {
  group('鍵名綁定正規化服务器身份', () {
    test('键名等于统一前缀加服务器身份', () {
      expect(
        KeyedSessionPersistence.keyFor('http://a.invalid:5206'),
        'evernightrealm.session.http://a.invalid:5206',
      );
    });

    test('协议、端口、主机、路径前缀任一不同即为不同键', () {
      const List<String> distinct = <String>[
        'http://a.invalid:5206',
        'https://a.invalid:5206',
        'http://a.invalid:5207',
        'http://b.invalid:5206',
        'http://a.invalid:5206/prefix',
      ];
      final Set<String> keys = distinct
          .map(KeyedSessionPersistence.keyFor)
          .toSet();
      expect(keys.length, distinct.length, reason: '不同身份不得共用一枚秘密槽位');
    });
  });

  group('读写删除透传', () {
    test('写入后再读回同一身份的秘密', () async {
      final _FakeStore store = _FakeStore();
      final persistence = KeyedSessionPersistence(store);
      const String id = 'http://a.invalid:5206';

      await persistence.writeSecret(id, 'S3CRET');
      final String? read = await persistence.readSecret(id);

      expect(read, 'S3CRET');
      expect(store.backing[KeyedSessionPersistence.keyFor(id)], 'S3CRET');
    });

    test('读未写过的身份回 null（确实是“没有值”，不是出错）', () async {
      final _FakeStore store = _FakeStore();
      final persistence = KeyedSessionPersistence(store);

      expect(await persistence.readSecret('http://none.invalid'), isNull);
    });

    test('清除只删除该身份，其他身份不受牵连', () async {
      final _FakeStore store = _FakeStore();
      final persistence = KeyedSessionPersistence(store);
      const String a = 'http://a.invalid:5206';
      const String b = 'http://b.invalid:5206';
      await persistence.writeSecret(a, 'SA');
      await persistence.writeSecret(b, 'SB');

      await persistence.clearSecret(a);

      expect(await persistence.readSecret(a), isNull);
      expect(await persistence.readSecret(b), 'SB');
    });
  });

  group('失败一律上抛，绝不静默降级', () {
    test('写入失败不留下任何明文', () async {
      final _FakeStore store = _FakeStore()
        ..failWrite = StateError('keystore down');
      final persistence = KeyedSessionPersistence(store);

      expect(
        () => persistence.writeSecret('http://a.invalid:5206', 'S'),
        throwsA(isA<StateError>()),
      );
      expect(store.backing, isEmpty, reason: '失败时底层不得落盘任何值');
    });

    test('读取失败上抛而非回 null（null 的语意是“确实没有”）', () async {
      final _FakeStore store = _FakeStore()
        ..failRead = StateError('no keyring');
      final persistence = KeyedSessionPersistence(store);

      expect(
        () => persistence.readSecret('http://a.invalid:5206'),
        throwsA(isA<StateError>()),
      );
    });

    test('删除失败上抛，交由上层记录而非谎报已清除', () async {
      final _FakeStore store = _FakeStore()..failDelete = StateError('locked');
      final persistence = KeyedSessionPersistence(store);

      expect(
        () => persistence.clearSecret('http://a.invalid:5206'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
