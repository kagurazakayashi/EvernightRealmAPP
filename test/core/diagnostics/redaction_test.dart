/// 脫敏管線的測試：敏感值必須消失，排錯線索必須留下。
///
/// 兩邊都要驗——只驗「打碼成功」會做出一個把日誌洗成一片馬賽克的規則，
/// 那種日誌等於沒有。
library;

import 'package:evernight_realm/core/diagnostics/redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('永不記錄的欄位', () {
    const Map<String, String> secrets = <String, String>{
      '等號寫法的密碼': 'login failed password=hunter2secret',
      'JSON 寫法的密碼': '{"password":"hunter2secret"}',
      '大寫鍵名': 'PASSWORD: hunter2secret',
      '底線鍵名': 'root_password=hunter2secret',
      // 注：散文裡裸寫的數字（如「PIN 123456」沒有鍵名）無法可靠識別，
      // 這類只能靠來源端不寫進訊息；本管線只處理可判定的鍵值形狀。
      'PIN': 'player pin=123456',
      '恢復碼': 'recovery_code=bravo-1234-word',
      '通行口令': 'passphrase: correct horse',
      '私鑰欄位': 'private_key=MIIEvQIBADANBgqh',
      'TLS 金鑰': 'tls_key=abcdef123456',
      '一般密鑰': 'client_secret=shhhhhhh',
      '簽名金鑰': 'signingkey: shhhhhhh',
    };

    for (final MapEntry<String, String> entry in secrets.entries) {
      test(entry.key, () {
        final String out = redactText(entry.value);
        expect(out, contains(redactedPlaceholder));
        // 原值的一個字元都不留：不只擋開頭，整段都要消失。
        for (final String fragment in _fragments(entry.value)) {
          expect(out, isNot(contains(fragment)), reason: '殘留 $fragment');
        }
      });
    }
  });

  group('只留標識的欄位', () {
    test('Session Token 改記短標識且不可還原', () {
      const String raw = 'session_token=01a0cd4d227f7b42b091e501ecf197c1';

      final String out = redactText(raw);

      expect(out, isNot(contains('01a0cd4d227f7b42b091e501ecf197c1')));
      expect(out, contains(tokenReferencePrefix));
      expect(out, startsWith('session_token='));
    });

    test('同一憑證穩定對應同一標識，不同憑證標識不同', () {
      expect(
        redactText('token=aaaa1111'),
        redactText('token=aaaa1111'),
        reason: '日誌要能把同一憑證的多次出現對起來',
      );
      expect(redactText('token=aaaa1111'), isNot(redactText('token=bbbb2222')));
    });

    test('Cookie 與 Authorization 都只留標識', () {
      final String cookie = redactText('Cookie: sid=abcdef1234567890');
      final String auth = redactText('Authorization: Bearer abcdef1234567890');

      expect(cookie, isNot(contains('abcdef1234567890')));
      expect(auth, isNot(contains('abcdef1234567890')));
      expect(cookie, contains(tokenReferencePrefix));
      expect(auth, contains(tokenReferencePrefix));
    });

    test('API 金鑰與冪等鍵改記標識', () {
      expect(
        redactText('api_key: AKID1234567890abcdef'),
        isNot(contains('AKID1234567890')),
      );
      expect(
        redactText('Idempotency-Key=01a0cd4d-227f-7b42-b091-e501ecf197c1'),
        isNot(contains('01a0cd4d-227f-7b42-b091-e501ecf197c1')),
      );
    });
  });

  group('無鍵名的憑證形狀', () {
    test('PEM 私鑰整段移除', () {
      const String pem =
          '-----BEGIN RSA PRIVATE KEY-----\nMIIEvQIBADANBg...\n-----END RSA PRIVATE KEY-----';

      final String out = redactText(pem);

      expect(out, isNot(contains('MIIEvQIBADANBg')));
      expect(out, contains('private-key'));
    });

    test('JWT 改記標識', () {
      const String jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcDEF123';

      final String out = redactText(jwt);

      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiIs')));
      expect(out, contains(tokenReferencePrefix));
    });

    test('位址裡的憑證被拿掉，主機與埠保留', () {
      final String out = redactText('http://root:sekret@10.0.0.1:5206/health');

      expect(out, isNot(contains('sekret')));
      expect(out, isNot(contains('root:')));
      expect(out, contains('10.0.0.1:5206/health'));
    });

    test('長十六進位與帶填充的 Base64 打碼', () {
      expect(
        redactText('signature 0123456789abcdef0123456789abcdef rejected'),
        contains(maskedSecretPlaceholder),
      );
      expect(
        redactText('key MIIKeyMaterial0123456789abcdef== loaded'),
        contains(maskedSecretPlaceholder),
      );
    });

    test('無分隔符的長英數金鑰打碼', () {
      expect(
        redactText('key AKIAIOSFODNN7EXAMPLE1234567890ABCDEF'),
        isNot(contains('AKIAIOSFODNN7EXAMPLE1234567890ABCDEF')),
      );
    });
  });

  group('不得誤傷排錯線索', () {
    const Map<String, String> kept = <String, String>{
      '中文錯誤描述': '無法連線至伺服器。可能已斷網、地址有誤或服務未啟動。',
      '欄位形状描述': 'ApiResponseShapeException: 欄位 version 不是字串',
      '端點與狀態碼': 'GET /health -> 503 code=1007 retryable=true',
      '正常位址': 'http://127.0.0.1:5206/health',
      '帶連字號的關聯 ID': 'request_id=01a0cd4d-227f-7b42-b091-e501ecf197c1',
      '套件路徑': 'package:flutter/src/widgets/framework.dart 1234:5 State.build',
      '含數字的本機路徑': r'C:/Users/dev2/Projects/FlutterApp2/lib/main.dart 42:7 main',
      '服務名與版本': 'service=evernight-server version=0.1.0-dev',
      '一般英文句子': 'The server could not be reached.',
      '日文句子': 'サーバーに接続できません。',
      '診斷碼': 'code=E001-3ab12c',
    };

    for (final MapEntry<String, String> entry in kept.entries) {
      test(entry.key, () {
        expect(redactText(entry.value), entry.value);
      });
    }
  });

  group('長度封頂', () {
    test('過長文字截斷並留下刪節標記', () {
      final String out = redactText('x' * (maxLoggedTextLength + 500));

      expect(out.length, lessThanOrEqualTo(maxLoggedTextLength + 2));
      expect(out, endsWith('…'));
    });

    test('未超長的文字不受影響', () {
      const String short = 'boom';
      expect(redactText(short), short);
    });
  });

  group('異常與堆疊的描述', () {
    test('describeError 帶型別名且同樣脫敏', () {
      final String out = describeError(StateError('password=supersecret'));

      expect(out, contains('StateError'));
      expect(out, isNot(contains('supersecret')));
    });

    test('describeStack 保留影格並限制行數', () {
      final StackTrace stack = StackTrace.fromString(
        List<String>.generate(30, (int i) => '  #$i  Frame.$i').join('\n'),
      );

      final String out = describeStack(stack, maxLines: 4);

      expect(out, contains('#0  Frame.0'));
      expect(out, contains('另有 26 行'));
      expect(out, isNot(contains('#29')));
    });

    test('空堆疊回傳空字串', () {
      expect(describeStack(null), isEmpty);
    });
  });
}

/// 從原文切出幾個可辨識片段，用來斷言「整段消失」而不是只擋開頭。
List<String> _fragments(String input) {
  final RegExp valuePattern = RegExp(
    r'(?:=|:)\s*"?([A-Za-z0-9][A-Za-z0-9 \-]{4,})',
  );
  return valuePattern
      .allMatches(input)
      .map((RegExpMatch m) => m.group(1)!.trim())
      .where((String v) => v.length > 4)
      .toList();
}
