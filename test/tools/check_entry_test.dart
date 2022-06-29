/// 前端品質入口自身的回測試。
///
/// 檢查「跑檢查的東西」是必要的：這個入口一旦把閘名打錯、把 `-w` 混進格式閘、或讓
/// `--` 之後的參數被吃掉，回報的「全部通過」就不再可信。這裡只驗純函數（解析與組命令），
/// 真跑三道閘屬程序級驗證（見根倉庫 ER-OPS-002）。
library;

// 入口在 tools/ 之下，不在 lib/ 裡，因此只能用相對路徑匯入（package: 前綴指向 lib/）。
import '../../tools/check/check.dart' as entry;

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('命令列解析', () {
    test('空參數為三道全跑', () {
      final entry.ParseResult parsed = entry.parseInvocation(<String>[]);
      expect(parsed, isA<entry.ParseOkay>());
      final entry.Invocation value = (parsed as entry.ParseOkay).value;
      expect(value.gates, isEmpty);
      expect(value.plainName, isEmpty);
      expect(value.flutterPath, isEmpty);
      expect(value.testArgs, isEmpty);
    });

    test('旗標可置於任意位置', () {
      final entry.ParseResult parsed = entry.parseInvocation(<String>[
        '--gate',
        'analyze',
        '--plain-name',
        '路由',
        '--gate',
        'test',
      ]);
      final entry.Invocation value = (parsed as entry.ParseOkay).value;
      expect(value.gates, <String>['analyze', 'test']);
      expect(value.plainName, '路由');
    });

    test('等號寫法與空格寫法同結果', () {
      final entry.Invocation spaced = (entry.parseInvocation(<String>[
        '--gate=fmt',
      ]) as entry.ParseOkay).value;
      final entry.Invocation equals = (entry.parseInvocation(<String>[
        '--gate',
        'fmt',
      ]) as entry.ParseOkay).value;
      expect(spaced.gates, equals.gates);
    });

    test('-- 之後原樣轉發，連旗標也不解釋', () {
      final entry.Invocation value = (entry.parseInvocation(<String>[
        '--',
        '--gate',
        'analyze',
        '--coverage',
        '--plain-name',
        '不該被吃掉',
      ]) as entry.ParseOkay).value;
      expect(value.gates, isEmpty, reason: '轉發段的 --gate 不屬本入口');
      expect(value.plainName, isEmpty);
      expect(value.testArgs, <String>[
        '--gate',
        'analyze',
        '--coverage',
        '--plain-name',
        '不該被吃掉',
      ]);
    });

    test('重複閘名去重且保留首次順序', () {
      final entry.Invocation value = (entry.parseInvocation(<String>[
        '--gate',
        'test,fmt',
        '--gate',
        'test',
      ]) as entry.ParseOkay).value;
      expect(value.gates, <String>['test', 'fmt']);
    });

    test('未知閘名被拒絕並列出可用名稱', () {
      final entry.ParseResult parsed = entry.parseInvocation(<String>[
        '--gate',
        'lint',
      ]);
      expect(parsed, isA<entry.ParseFailed>());
      expect(
        (parsed as entry.ParseFailed).reason,
        allOf(contains('lint'), contains('analyze')),
      );
    });

    test('缺少值與未知旗標都算參數錯誤', () {
      expect(
        entry.parseInvocation(<String>['--gate']),
        isA<entry.ParseFailed>(),
      );
      expect(
        entry.parseInvocation(<String>['--flutter']),
        isA<entry.ParseFailed>(),
      );
      expect(
        entry.parseInvocation(<String>['--nope']),
        isA<entry.ParseFailed>(),
      );
    });

    test('位置參數一律拒絕並指出該放在 -- 之後', () {
      final entry.ParseResult parsed = entry.parseInvocation(<String>['test']);
      expect(parsed, isA<entry.ParseFailed>());
      expect((parsed as entry.ParseFailed).reason, contains('--'));
    });

    test('--help 走說明而不是錯誤', () {
      expect(entry.parseInvocation(<String>['--help']), isA<entry.ParseHelp>());
      expect(entry.parseInvocation(<String>['-h']), isA<entry.ParseHelp>());
    });
  });

  group('閘的組裝', () {
    const entry.Invocation all = entry.Invocation();

    test('三道依固定順序且各用其工具鏈', () {
      final List<entry.Gate> gates = entry.buildGates(
        all,
        flutterExe: r'D:\SDK\flutter\bin\flutter.bat',
        dartExe: r'D:\SDK\flutter\bin\dart.bat',
      );
      expect(gates.map((entry.Gate g) => g.name), <String>[
        'fmt',
        'analyze',
        'test',
      ]);
      expect(
        gates.first.exe,
        r'D:\SDK\flutter\bin\dart.bat',
        reason: '格式閘走 dart',
      );
      expect(
        gates[1].exe,
        r'D:\SDK\flutter\bin\flutter.bat',
        reason: '分析閘走 flutter',
      );
      expect(gates[2].exe, gates[1].exe, reason: '測試閘走 flutter');
    });

    test('格式閘只報告差異，絕不改寫', () {
      final List<entry.Gate> gates = entry.buildGates(
        const entry.Invocation(gates: <String>['fmt']),
        flutterExe: 'flutter',
        dartExe: 'dart',
      );
      expect(gates.single.args, entry.formatArgs);
      expect(gates.single.args, isNot(contains('-w')), reason: '品質入口不自動改動工作樹');
    });

    test('定向測試同時接受關鍵字與轉發參數', () {
      final List<entry.Gate> gates = entry.buildGates(
        const entry.Invocation(
          gates: <String>['test'],
          plainName: '狀態條',
          testArgs: <String>['--coverage'],
        ),
        flutterExe: r'/opt/flutter/bin/flutter',
        dartExe: r'/opt/flutter/bin/dart',
      );
      expect(gates.single.args, <String>[
        'test',
        '--plain-name',
        '狀態條',
        '--coverage',
      ]);
    });

    test('過濾後只剩被選取的閘', () {
      final List<entry.Gate> gates = entry.buildGates(
        const entry.Invocation(gates: <String>['analyze']),
        flutterExe: r'/opt/flutter/bin/flutter',
        dartExe: r'/opt/flutter/bin/dart',
      );
      expect(gates.map((entry.Gate g) => g.name), <String>['analyze']);
    });

    test('說明文字點出不做的事', () {
      expect(
        entry.usageText(),
        allOf(contains('提交鉤子'), contains('--plain-name')),
      );
      expect(entry.usageText(), contains('dart run tools/check/check.dart'));
    });
  });

  group('工具鏈路徑推導', () {
    test('由 flutter 推同目錄的 dart 並保留副檔名', () {
      expect(
        entry.siblingExecutable(r'D:\SDK\flutter\bin\flutter.bat', 'dart'),
        r'D:\SDK\flutter\bin\dart.bat',
      );
      expect(
        entry.siblingExecutable('/opt/flutter/bin/flutter', 'dart'),
        '/opt/flutter/bin/dart',
      );
    });

    test('裸名推不出目錄時回傳空值而不是猜 PATH', () {
      expect(entry.siblingExecutable('flutter', 'dart'), isNull);
    });
  });
}
