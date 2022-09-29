/// 會話秘密儲存的適配測試：用記憶體鍵值替身驗證「按正規化伺服器身份分鍵、
/// 失敗上拋、绝不降级明文」这三条与真实钥匙库无关的逻辑。
///
/// 真实系统级储存（Android Keystore／Apple Keychain／Linux libsecret／Windows DPAPI）
/// 的绑定属 [FlutterSecureKeyValueStore]，需要各平台实机才能验证；本机没有那些宿主，
/// 故本测试只把 [KeyedSessionPersistence] 的鍵名映射与错误透传钉住，实机路径标为未实测。
library;

import 'package:evernightrealm/core/session/session_persistence.dart';
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

  group('讀寫刪除透傳', () {
    test('寫入後再讀回同一身份的憑據', () async {
      final _FakeStore store = _FakeStore();
      final persistence = KeyedSessionPersistence(store);
      const String id = 'http://a.invalid:5206';

      await persistence.writeCredential(
        id,
        const SessionCredential(secret: 'S3CRET', rotationSeq: 3),
      );
      final SessionCredential? read = await persistence.readCredential(id);

      expect(read?.secret, 'S3CRET');
      expect(read?.rotationSeq, 3);
      expect(store.backing[KeyedSessionPersistence.keyFor(id)], '3:S3CRET');
    });

    test('讀未寫過的身份回 null（確實是“沒有值”，不是出錯）', () async {
      final _FakeStore store = _FakeStore();
      final persistence = KeyedSessionPersistence(store);

      expect(await persistence.readCredential('http://none.invalid'), isNull);
    });

    test('清除只删除该身份，其他身份不受牵连', () async {
      final _FakeStore store = _FakeStore();
      final persistence = KeyedSessionPersistence(store);
      const String a = 'http://a.invalid:5206';
      const String b = 'http://b.invalid:5206';
      await persistence.writeCredential(
        a,
        const SessionCredential(secret: 'SA', rotationSeq: 0),
      );
      await persistence.writeCredential(
        b,
        const SessionCredential(secret: 'SB', rotationSeq: 0),
      );

      await persistence.clearCredential(a);

      expect(await persistence.readCredential(a), isNull);
      expect((await persistence.readCredential(b))?.secret, 'SB');
    });
  });

  group('值編碼形狀', () {
    test('世代號在前、秘密在後，以第一個冒號分隔', () {
      expect(
        KeyedSessionPersistence.encode(
          const SessionCredential(secret: 'abc-DEF_123', rotationSeq: 12),
        ),
        '12:abc-DEF_123',
      );
    });

    test('完整的複合字串可解回憑據（秘密以 base64url 字元集為主）', () {
      final SessionCredential? decoded = KeyedSessionPersistence.decode(
        '7:xYz-._~',
      );
      expect(decoded?.rotationSeq, 7);
      expect(decoded?.secret, 'xYz-._~');
    });

    test('更早版本的裸秘密一律回 null（不猜它是第幾代）', () {
      // 升級前存的是沒有世代號的裸秘密；猜它屬於第幾代會讓一個倒序送達的
      // 舊輪換結果有機會蓋掉新憑據。代價是原生端要重登一次，比猜錯安全。
      expect(KeyedSessionPersistence.decode('S3CRETWITHOUTSEQ'), isNull);
      expect(KeyedSessionPersistence.decode(''), isNull);
      expect(KeyedSessionPersistence.decode(null), isNull);
    });

    test('形狀不合格一律回 null（缺分隔、缺秘密、世代號不是整數）', () {
      expect(KeyedSessionPersistence.decode('0:'), isNull, reason: '分隔號後沒有秘密');
      expect(
        KeyedSessionPersistence.decode(':secret'),
        isNull,
        reason: '分隔號前沒有世代號',
      );
      expect(KeyedSessionPersistence.decode('x:secret'), isNull);
      expect(KeyedSessionPersistence.decode('-1:secret'), isNull);
    });

    test('儲存裡是裸秘密時，讀取回 null（當成沒有值）', () async {
      final _FakeStore store = _FakeStore();
      final persistence = KeyedSessionPersistence(store);
      const String id = 'http://a.invalid:5206';
      store.backing[KeyedSessionPersistence.keyFor(id)] = 'LEGACY-RAW-SECRET';

      expect(await persistence.readCredential(id), isNull);
    });
  });

  group('失敗一律上拋，絕不靜默降級', () {
    test('寫入失敗不留下任何明文', () async {
      final _FakeStore store = _FakeStore()
        ..failWrite = StateError('keystore down');
      final persistence = KeyedSessionPersistence(store);

      expect(
        () => persistence.writeCredential(
          'http://a.invalid:5206',
          const SessionCredential(secret: 'S', rotationSeq: 0),
        ),
        throwsA(isA<StateError>()),
      );
      expect(store.backing, isEmpty, reason: '失敗時底層不得落盤任何值');
    });

    test('讀取失敗上拋而非回 null（null 的語意是“確實沒有”）', () async {
      final _FakeStore store = _FakeStore()
        ..failRead = StateError('no keyring');
      final persistence = KeyedSessionPersistence(store);

      expect(
        () => persistence.readCredential('http://a.invalid:5206'),
        throwsA(isA<StateError>()),
      );
    });

    test('刪除失敗上拋，交由上層記錄而非謊報已清除', () async {
      final _FakeStore store = _FakeStore()..failDelete = StateError('locked');
      final persistence = KeyedSessionPersistence(store);

      expect(
        () => persistence.clearCredential('http://a.invalid:5206'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
