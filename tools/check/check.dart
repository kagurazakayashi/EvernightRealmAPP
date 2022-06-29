/// 前端品質入口：格式化、靜態分析與定向測試一條命令跑完。
///
/// 為什麼要有這個出口：這些命令此前是散在文件裡的手打串（`dart format --output=none
/// --set-exit-if-changed .`、`flutter analyze`、`flutter test --plain-name …`），
/// 每換一次會話就要重新拼一次，而拼錯的方向是「少跑了一道還全綠」。
///
/// 根倉庫的 `go run ./tools/check app` 叫起的也是本檔：閘的定義只寫在這裡一份，
/// 「前端自己跑」與「由後端根目錄跑」因此不會有兩種答案。
///
/// 邊界：只在被叫起時執行。不裝提交鉤子、不執行任何 git 寫操作、不改動任何手寫檔案
/// （格式檢查只報告差異，要不要 `-w` 改寫由人決定）。唯一會寫盤的是 `flutter gen-l10n`
/// 產生的本地化檔——依約定不入版本庫，且少了它們，分析閘與測試閘根本跑不起來。
///
/// 用法：`dart run tools/check/check.dart [旗標] [-- 給 flutter test 的參數...]`
library;

import 'dart:io';

/// 錯誤訊息的前綴，與倉庫內其他工具命令同形。
const String _tool = 'check';

/// 退出碼：0 通過、1 有閘未過或跑不起來、2 命令列參數錯誤。
const int exitOk = 0;
const int exitFailure = 1;
const int exitUsage = 2;

/// 三道閘的名稱；順序即執行順序（便宜且訊息最直的在前）。
const List<String> gateNames = <String>['fmt', 'analyze', 'test'];

/// 格式閘的引數：只報告差異，絕不改寫。
const List<String> formatArgs = <String>[
  'format',
  '--output=none',
  '--set-exit-if-changed',
  '.',
];

/// 一道要在專案根目錄執行的外部命令。
class Gate {
  /// 建立一道閘。
  const Gate({
    required this.name,
    required this.desc,
    required this.exe,
    required this.args,
  });

  /// 閘名，供 --gate 過濾與摘要使用。
  final String name;

  /// 給人看的說明，同時用於進度列與錯誤訊息；刻意不含引數。
  final String desc;

  /// 可執行檔路徑。
  final String exe;

  /// 引數清單。
  final List<String> args;
}

/// 一次品質檢查的輸入。
class Invocation {
  /// 建立一筆輸入。
  const Invocation({
    this.gates = const <String>[],
    this.plainName = '',
    this.flutterPath = '',
    this.testArgs = const <String>[],
  });

  /// 要跑的閘；空清單表示全跑。
  final List<String> gates;

  /// 定向測試關鍵字（對應 `flutter test --plain-name`）。
  final String plainName;

  /// 明指的 flutter 可執行檔；空表示依 PATH、再退回 FLUTTER_ROOT/bin。
  final String flutterPath;

  /// 原樣附加給 `flutter test` 的參數。
  final List<String> testArgs;

  /// 是否要跑某道閘。
  bool wants(String gate) => gates.isEmpty || gates.contains(gate);
}

/// 命令列解析結果。分成三種而不是「回傳 null 表示錯」：
/// 說明、錯誤、成功各自的退出碼不同（0／2／繼續），混在一起就會出現打錯字卻回 0。
sealed class ParseResult {
  /// 結果類型可當常值使用，測試與回傳路徑上不必每次新建物件。
  const ParseResult();
}

/// 解析成功。
final class ParseOkay extends ParseResult {
  /// 帶入解析結果。
  const ParseOkay(this.value);

  /// 檢查輸入。
  final Invocation value;
}

/// 要求說明——這是正當查詢，退出碼 0。
final class ParseHelp extends ParseResult {
  /// 說明不需要任何資料，但仍要能當常值回傳。
  const ParseHelp();
}

/// 參數打錯——說明加上退出碼 2。
final class ParseFailed extends ParseResult {
  /// 帶入原因。
  const ParseFailed(this.reason);

  /// 一句指得打錯在哪裡的說明。
  final String reason;
}

/// 工具鏈或專案狀態不對，無法開始檢查。
///
/// 單獨一個例外類型，是為了讓「某道閘不過」與「工具鏈根本不存在」在 main 裡
/// 走同一個出口：前者已由 runCheck 回報退出碼，後者要先把原因講成人話再結束。
final class CheckSetupFailure implements Exception {
  /// 帶入原因。
  const CheckSetupFailure(this.message);

  /// 給人的原因，含下一步。
  final String message;

  @override
  String toString() => message;
}

Future<void> main(List<String> args) async {
  final ParseResult parsed = parseInvocation(args);
  switch (parsed) {
    case ParseHelp():
      stdout.writeln(usageText());
      exitCode = exitOk;
    case ParseFailed(reason: final String reason):
      stderr.writeln('$_tool: $reason');
      stderr.writeln(usageText());
      exitCode = exitUsage;
    case ParseOkay(value: final Invocation invocation):
      exitCode = await _runGuarded(invocation);
  }
}

/// 把「根本沒跑起來」與「某道閘不過」都收成一行錯誤與退出碼。
///
/// 不包這一層，工具鏈缺席會拋未處理例外、印出一段 Dart 堆疊——那是本入口最該避免的
/// 輸出格式：它把一個環境問題講得像程式錯誤。
Future<int> _runGuarded(Invocation invocation) async {
  try {
    return await runCheck(invocation);
  } on CheckSetupFailure catch (failure) {
    stderr.writeln('$_tool: ${failure.message}');
    return exitFailure;
  } on ProcessException catch (failure) {
    // 命令叫不起來與命令跑了但不過是兩件事：前者要說清是哪一支、路徑是什麼，否則一段
    // Dart 堆疊會把一個環境問題講得像程式錯誤（實測推無副檔名的 sh 腳本正是如此）。
    stderr.writeln('$_tool: 無法啟動 ${failure.executable}：${failure.message}');
    return exitFailure;
  }
}

/// 依「定位專案根 → 解析工具鏈 → 產生本地化資源 → 組閘 → 依序執行」跑一趟檢查。
///
/// 定位與工具鏈全部先查完才下第一道命令：跑到一半才發現找不到 flutter，會留下
/// 「前半綠、後半沒跑」的結果，那種輸出比直接失敗更容易被誤讀成通過。
Future<int> runCheck(Invocation invocation) async {
  final Directory root = projectRoot();
  final String flutterExe = resolveFlutter(invocation.flutterPath);
  // 格式閘要用「同套工具鏈的 dart」：拿 flutter 頂替的話 `flutter format` 不是命令，
  // 報錯會指到與真正原因無關的地方。
  final String dartExe = resolveDart(flutterExe);

  final List<Gate> gates = buildGates(
    invocation,
    flutterExe: flutterExe,
    dartExe: dartExe,
  );
  if (gates.isEmpty) {
    stderr.writeln('$_tool: --gate 過濾後沒有可執行的閘（可用：${gateNames.join('、')}）');
    return exitUsage;
  }
  stdout.writeln('前端品質檢查：${root.path}');
  stdout.writeln('flutter：$flutterExe');
  stdout.writeln('範圍：${gates.map((Gate g) => g.name).join('、')}');

  final int prepared = await prepareLocalizations(root, flutterExe, gates);
  if (prepared != exitOk) {
    return prepared;
  }

  final Stopwatch watch = Stopwatch()..start();
  for (int index = 0; index < gates.length; index++) {
    final Gate gate = gates[index];
    stdout.writeln(
      '── ${index + 1}/${gates.length} ${gate.desc}：'
      '${_baseName(gate.exe)} ${gate.args.join(' ')}',
    );
    final int code = await runGate(gate, root);
    if (code != 0) {
      if (gate.name == 'fmt') {
        stderr.writeln('下一步：dart format .（本入口不自動改寫）');
      }
      stderr.writeln(
        '$_tool: 第 ${index + 1}/${gates.length} 道未過：'
        '${gate.desc}（退出碼 $code）',
      );
      return exitFailure;
    }
  }

  stdout.writeln(
    '品質檢查通過：${gates.length} 道閘，'
    '歷時 ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒',
  );
  return exitOk;
}

/// 產生本地化資源（只有分析閘與測試閘需要）。
///
/// 為什麼由入口做而不是留給人：實測（Flutter 3.47.5）`flutter analyze` 與 `flutter test`
/// 都不會自動跑 gen-l10n，而生成物依約定不入版本庫——一份剛 check out 的倉庫因此會讓分析
/// 噴出上百條「找不到 AppLocalizations」，看起來像程式寫壞了，實際缺的只是一步產生。
/// 這裡只重寫 .gitignore 已排除的生成檔，不動任何手寫程式碼。
Future<int> prepareLocalizations(
  Directory root,
  String flutterExe,
  List<Gate> gates,
) async {
  final bool needed = gates.any(
    (Gate gate) => gate.name == 'analyze' || gate.name == 'test',
  );
  if (!needed) {
    return exitOk;
  }
  if (!File('${root.path}${Platform.pathSeparator}l10n.yaml').existsSync()) {
    return exitOk; // 未採用 gen-l10n 的專案沒有這一步。
  }

  stdout.writeln('準備：flutter gen-l10n（生成物不入版本庫）');
  final int code = await runGate(
    Gate(
      name: 'gen-l10n',
      desc: '產生本地化資源',
      exe: flutterExe,
      args: const <String>['gen-l10n'],
    ),
    root,
  );
  if (code != 0) {
    stderr.writeln('$_tool: 產生本地化資源失敗（退出碼 $code）');
    return exitFailure;
  }
  return exitOk;
}

/// 依輸入組出要跑的閘（純函數，便於測試）。
List<Gate> buildGates(
  Invocation invocation, {
  required String flutterExe,
  required String dartExe,
}) {
  final List<String> testArgs = <String>[
    'test',
    if (invocation.plainName.isNotEmpty) ...<String>[
      '--plain-name',
      invocation.plainName,
    ],
    ...invocation.testArgs,
  ];

  return <Gate>[
    if (invocation.wants('fmt'))
      Gate(name: 'fmt', desc: 'Dart 格式檢查', exe: dartExe, args: formatArgs),
    if (invocation.wants('analyze'))
      Gate(
        name: 'analyze',
        desc: 'Flutter 靜態分析',
        exe: flutterExe,
        args: const <String>['analyze'],
      ),
    if (invocation.wants('test'))
      Gate(name: 'test', desc: 'Flutter 測試', exe: flutterExe, args: testArgs),
  ];
}

/// 執行一道閘，回傳退出碼。
///
/// 用 inheritStdio 而不是 process.run：格式差異、分析訊息、測試進度必須直接進終端機，
///  buffering 全收再轉只會把進度變成「跑完才一次爆出」，也可能在編碼上出錯。
Future<int> runGate(Gate gate, Directory workingDirectory) async {
  final Process process = await Process.start(
    gate.exe,
    gate.args,
    workingDirectory: workingDirectory.path,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

/// 找專案根目錄：自本檔所在位置向上找 pubspec.yaml，找不到才退回目前目錄。
///
/// 不直接用 cwd，是因為 `dart run` 允許在子目錄裡叫起腳本；屆時 `.` 會變成「只檢查
/// tools 目錄」，格式閘與分析閘都跑了錯的範圍還全綠。
Directory projectRoot() {
  final String scriptDir = _scriptDirectory();
  Directory? dir = scriptDir.isEmpty ? null : Directory(scriptDir);
  while (dir != null) {
    if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  return Directory.current;
}

/// 本檔所在目錄；拿不到時回空字串，交給 projectRoot 退回 cwd。
String _scriptDirectory() {
  try {
    return File.fromUri(Platform.script).parent.absolute.path;
  } on Object {
    return '';
  }
}

/// 依序以明指路徑、PATH、FLUTTER_ROOT/bin 解析 flutter 可執行檔。
///
/// 明指優先是必要的：根倉庫叫起本檔時會把它解析到的 flutter 傳進來，兩邊用同一套工具鏈，
/// 檢查結果才與建置結果同源。傳進來的路徑不存在時直接失敗，不悄悄退回 PATH——
/// 那會讓「明明指定了另一套 SDK 卻沒生效」變成一個看不見的差異。
String resolveFlutter(String explicit) {
  if (explicit.trim().isNotEmpty) {
    final String path = explicit.trim();
    if (!File(path).existsSync()) {
      throw CheckSetupFailure('指定的 flutter 不存在：$path');
    }
    return path;
  }
  return findOnPath('flutter') ?? _fromFlutterRoot();
}

/// 由 FLUTTER_ROOT/bin 推得 flutter 可執行檔；沒有時報可判讀的錯。
String _fromFlutterRoot() {
  final String root = (Platform.environment['FLUTTER_ROOT'] ?? '').trim();
  if (root.isNotEmpty) {
    for (final String candidate in executableCandidates('$root/bin/flutter')) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
  }
  throw CheckSetupFailure(
    '找不到 flutter 可執行檔（查過：PATH${root.isEmpty ? '' : '、$root/bin'}）；'
    '請以 --flutter 指定路徑',
  );
}

/// 取得與 flutter 同套工具鏈的 dart 可執行檔：先取同目錄，再退回 PATH。
///
/// 不直接用 PATH 上的 dart：那可能是另一套 SDK，檢查結果就會與建置結果來自兩套工具鏈。
String resolveDart(String flutterExe) {
  final String? sibling = siblingExecutable(flutterExe, 'dart');
  if (sibling != null) {
    // 同目錄可能同時存在 `dart`（sh 腳本）與 `dart.bat`；走同一份 PATHEXT 候選規則，
    // 否則拿無副檔名那個去叫 CreateProcess 就是「不是有效的 Win32 應用程式」。
    for (final String candidate in executableCandidates(sibling)) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
  }
  final String? onPath = findOnPath('dart');
  if (onPath != null) {
    return onPath;
  }
  throw CheckSetupFailure(
    '找不到 dart 可執行檔（查過：${sibling ?? '（無法由 flutter 路徑推得）'}、PATH）',
  );
}

/// 在 PATH 上找可執行檔；Windows 需自行補 PATHEXT 副檔名。
///
/// Dart 的 Process 不做 Windows 的檔名解析：實測（本機 Windows）以裸名 flutter 叫起拋
/// 「系統找不到指定的文件」；而 Flutter SDK 的 bin 目錄同時有 `flutter`（給 sh 用的腳本）
/// 與 `flutter.bat`，「先存在就用」會得到「%1 不是有效的 Win32 應用程式」。
/// 因此這裡按 PATHEXT 的順序補齊候選，再把確切路徑交下去。
String? findOnPath(String name) {
  final String path = Platform.environment['PATH'] ?? '';
  final String separator = Platform.isWindows ? ';' : ':';
  for (final String entry in path.split(separator)) {
    if (entry.trim().isEmpty) {
      continue;
    }
    for (final String candidate in executableCandidates(
      '$entry${Platform.pathSeparator}$name',
    )) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
  }
  return null;
}

/// 產生一個基準路徑的可執行檔候選（Windows 依 PATHEXT 順序補檔名）。
///
/// 裸名不進候選清單：Windows 上沒有副檔名的檔案不是可執行檔。基準路徑本身已帶 PATHEXT
/// 認可的副檔名時（例如 --flutter 直接給 flutter.bat）則保留它，且排在最先。
List<String> executableCandidates(String base) {
  if (!Platform.isWindows) {
    return <String>[base];
  }
  final String raw = Platform.environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD';
  final List<String> known = raw
      .toUpperCase()
      .split(';')
      .where((String ext) => ext.isNotEmpty)
      .toList();
  final String upper = base.toUpperCase();
  return <String>[
    if (known.any(upper.endsWith)) base,
    // 先試小寫副檔名：PATHEXT 通常是大寫，而實際檔案叫 flutter.bat。比對本來就不分大小寫，
    // 但取到的小寫路徑會讓摘要與錯誤訊息讀起來正常（實測過 big 寫法會印成 flutter.BAT）。
    for (final String ext in known) '$base${ext.toLowerCase()}',
    for (final String ext in known) '$base$ext',
  ];
}

/// 由某個可執行檔路徑推得同目錄的另一支（例如 flutter → dart）。
///
/// 保留副檔名，是因為這支工具鏈在 Windows 上是 .bat、在 Unix 上沒有副檔名；
/// 推不出來（路徑不含目錄或檔名異常）時回 null，由呼叫端決定退回哪裡。
String? siblingExecutable(String exe, String sibling) {
  final int sep = _lastSeparator(exe);
  if (sep < 0) {
    return null;
  }
  final String dir = exe.substring(0, sep + 1);
  final String base = exe.substring(sep + 1);
  final int dot = base.lastIndexOf('.');
  if (dot <= 0) {
    return '$dir$sibling';
  }
  return '$dir$sibling${base.substring(dot)}';
}

int _lastSeparator(String path) {
  int index = -1;
  for (int i = 0; i < path.length; i++) {
    if (path[i] == '/' || path[i] == r'\') {
      index = i;
    }
  }
  return index;
}

/// 取路徑的檔名，供進度列使用（整列被絕對路徑撐開就很難讀）。
String _baseName(String path) {
  final int sep = _lastSeparator(path);
  return sep < 0 ? path : path.substring(sep + 1);
}

/// 旗標可置於任意位置；`--` 之後全部原樣轉給 flutter test。
ParseResult parseInvocation(List<String> args) {
  final List<String> gates = <String>[];
  final List<String> testArgs = <String>[];
  String plainName = '';
  String flutterPath = '';
  bool passthrough = false;

  for (int i = 0; i < args.length; i++) {
    final String arg = args[i];
    if (passthrough) {
      testArgs.add(arg);
      continue;
    }
    if (arg == '--') {
      passthrough = true;
      continue;
    }
    if (!arg.startsWith('-') || arg == '-') {
      return const ParseFailed('本入口不接受位置參數；要給 flutter test 的附加參數請放在 -- 之後');
    }

    final _Flag flag = _splitFlag(arg);
    switch (flag.name) {
      case 'h':
      case 'help':
        return const ParseHelp();
      case 'gate':
        final ({bool ok, String value}) taken = _flagValue(flag, args, i);
        if (!taken.ok) {
          return ParseFailed('--gate 缺少值');
        }
        i++;
        for (String item in taken.value.split(',')) {
          item = item.trim().toLowerCase();
          if (item.isEmpty) {
            continue;
          }
          if (!gateNames.contains(item)) {
            return ParseFailed('不認識的閘 $item（可用：${gateNames.join('、')}）');
          }
          if (!gates.contains(item)) {
            gates.add(item);
          }
        }
      case 'plain-name':
        final ({bool ok, String value}) taken = _flagValue(flag, args, i);
        if (!taken.ok) {
          return ParseFailed('--plain-name 缺少值');
        }
        i++;
        plainName = taken.value;
      case 'flutter':
        final ({bool ok, String value}) taken = _flagValue(flag, args, i);
        if (!taken.ok) {
          return ParseFailed('--flutter 缺少值');
        }
        i++;
        flutterPath = taken.value;
      default:
        return ParseFailed('不認識的旗標 $arg（可用：--gate、--plain-name、--flutter、-h）');
    }
  }

  return ParseOkay(
    Invocation(
      gates: gates,
      plainName: plainName,
      flutterPath: flutterPath,
      testArgs: testArgs,
    ),
  );
}

/// 一個拆好的旗標。
class _Flag {
  /// 帶入名稱與等號值。
  const _Flag(this.name, this.value, this.hasValue);

  /// 不含橫線的旗標名。
  final String name;

  /// `--k=v` 寫法裡的值。
  final String value;

  /// 是否已帶值。
  final bool hasValue;
}

/// 拆 `--name`、`--name=value`、`-name value` 三種寫法。
_Flag _splitFlag(String arg) {
  final String body = arg.replaceFirst(RegExp(r'^-+'), '');
  final int equals = body.indexOf('=');
  if (equals < 0) {
    return _Flag(body, '', false);
  }
  return _Flag(body.substring(0, equals), body.substring(equals + 1), true);
}

/// 取值：等號寫法直接可用，否則吃掉下一個引數。
({bool ok, String value}) _flagValue(_Flag flag, List<String> args, int index) {
  if (flag.hasValue) {
    return (ok: true, value: flag.value);
  }
  if (index + 1 >= args.length) {
    return (ok: false, value: '');
  }
  return (ok: true, value: args[index + 1]);
}

/// 說明文字。手寫而非套件產生：要用的是「閘名與兩側規則」，模板給不出來。
String usageText() {
  return <String>[
    '用法：dart run tools/check/check.dart [旗標] [-- 給 flutter test 的參數...]',
    '',
    '旗標：',
    '  --gate LIST       僅跑指定閘：${gateNames.join('、')}（逗號分隔，可重複）',
    '  --plain-name TXT  定向測試，對應 flutter test --plain-name',
    '  --flutter PATH    指定 flutter 可執行檔（預設：PATH，再退回 FLUTTER_ROOT/bin）',
    '  -h, --help        顯示本說明',
    '',
    '三道閘的順序固定：格式 → 分析 → 測試（便宜且訊息最直的在前，失敗即停止）。',
    '位置參數一律被拒絕：要附加給 flutter test 的參數請放在 -- 之後，原樣轉發。',
    '',
    '範例：',
    '  dart run tools/check/check.dart                      三道全跑',
    '  dart run tools/check/check.dart --gate fmt,analyze   只檢查格式與分析',
    '  dart run tools/check/check.dart --gate test --plain-name 路由',
    '  dart run tools/check/check.dart -- --coverage        直接把參數給 flutter test',
    '',
    '本入口只在被叫起時執行：不裝提交鉤子、不執行任何 git 寫操作。',
    '分析與測試前會先跑 flutter gen-l10n（只重寫不入版本庫的生成檔）；除此之外不改動檔案。',
  ].join('\n');
}
