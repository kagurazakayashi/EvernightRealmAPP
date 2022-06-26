/// 基準位址驗證的測試：不合格的定位一律拒絕，不接受「先試試看」。
library;

import 'package:evernight_realm/core/api/server_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerAddress 接受', () {
    test('帶埠號的 http 位址', () {
      final ServerAddress? address = ServerAddress.tryParse(
        'http://192.168.1.20:5206',
      );

      expect(address, isNotNull);
      expect(address!.displayText, 'http://192.168.1.20:5206');
      expect(
        address.resolve('/health').toString(),
        'http://192.168.1.20:5206/health',
      );
    });

    test('https 與預設埠號', () {
      final ServerAddress? address = ServerAddress.tryParse(
        'https://lan.example',
      );

      expect(address, isNotNull);
      expect(address!.baseUri.scheme, 'https');
      expect(address.resolve('/time').toString(), 'https://lan.example/time');
    });

    test('首尾空白不影響判定', () {
      expect(
        ServerAddress.tryParse('  http://127.0.0.1:5206  ')?.displayText,
        'http://127.0.0.1:5206',
      );
    });

    test('反向代理的路徑前綴保留，且連字號不重複也不丟失', () {
      const String base = 'http://192.168.1.20:8080/evernight';

      expect(
        ServerAddress.tryParse(base)?.resolve('/ready').toString(),
        '$base/ready',
      );
      expect(
        ServerAddress.tryParse('$base/')?.resolve('/ready').toString(),
        '$base/ready',
        reason: '結尾連字號不應產生雙斜線',
      );
    });

    test('上跳段在解析階段即被正規化，不會逃出基準路徑', () {
      // Uri 已把 `/../` 化簡；這裡固定該行為，避免以為還需要自行擋。
      final ServerAddress? address = ServerAddress.tryParse(
        'http://127.0.0.1:5206/../etc',
      );

      expect(
        address?.resolve('/health').toString(),
        'http://127.0.0.1:5206/etc/health',
      );
    });

    test('大寫協定正規化為小寫', () {
      expect(
        ServerAddress.tryParse('HTTP://127.0.0.1:5206')?.displayText,
        'http://127.0.0.1:5206',
      );
    });
  });

  group('ServerAddress 拒絕', () {
    const Map<String, String> rejected = <String, String>{
      '空字串': '',
      '只有空白': '   ',
      '未給協定': '192.168.1.20:5206',
      '非 http 協定': 'ftp://192.168.1.20',
      '檔案協定': 'file:///etc/passwd',
      '透過擴充功能開啟的協定': 'javascript:alert(1)',
      '只有協定沒有主機': 'http://',
      '含使用者名稱與密碼': 'http://root:password@192.168.1.20:5206',
      '含查詢字串': 'http://127.0.0.1:5206?admin=1',
      '含片斷': 'http://127.0.0.1:5206#token',
      '中間含空白': 'http://127.0.0.1:520 6',
      '含製表符': 'http://127.0.0.1:52\t06',
      '含零寬字元': 'http://127.0.0.1:52​06',
      '相對路徑': '/health',
    };

    for (final MapEntry<String, String> entry in rejected.entries) {
      test(entry.key, () {
        expect(ServerAddress.tryParse(entry.value), isNull);
      });
    }

    test('null 輸入', () {
      expect(ServerAddress.tryParse(null), isNull);
    });

    test('拒絕的位址不會因為顯示而漏出憑證', () {
      // 這是「日誌與畫面不泄露憑證」的第一道：不合格的定位根本沒有顯示文字。
      const String withCredentials = 'http://root:secret@192.168.1.20:5206';

      expect(ServerAddress.tryParse(withCredentials), isNull);
      expect(withCredentials.contains('secret'), isTrue);
    });
  });
}
