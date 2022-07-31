/// 未處理錯誤安全畫面的測試：接得住、回得去、且不把憑證帶到畫面上。
///
/// 完成判斷有兩條，逐條對驗：
/// * 「使用者可返回可用頁面」→ 按下後失敗畫面消失、導航清回起始路由；
/// * 「介面與日誌不洩露憑證」→ 把憑證塞進異常訊息，再掃整棵文字元件與日誌行，
///   要求原值一個字元都不出現。
///
/// 手法說明：`flutter_test` 綁定自己佔用 `FlutterError.onError` 記錄例外，且會
/// 檢查 `ErrorWidget.builder` 是否還原；在測試裡讓頁面真的反覆拋出例外，會變成
/// 「第二筆例外沒人消費」而整批失敗，驗到的卻是綁定的帳務而不是本步的行為。
/// 因此這裡分兩層：接點用一般測試直接呼叫（那正是 binding 調用的同一個函式），
/// 畫面用收集器驅動。
library;

import 'package:evernightrealm/app/app_failure_labels.dart';
import 'package:evernightrealm/app/bootstrap.dart';
import 'package:evernightrealm/app/error_boundary.dart';
import 'package:evernightrealm/app/widgets/safe_error_view.dart';
import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/diagnostics/app_failure.dart';
import 'package:evernightrealm/core/diagnostics/diagnostics_hub.dart';
import 'package:evernightrealm/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 測試固定語言與由此取得的文案。
const Locale _locale = Locale('en', 'US');

/// 塞進異常訊息裡的憑證樣本：任何一處漏出去都算失敗。
const List<String> _secrets = <String>[
  'supersecret',
  'abcdef1234567890',
  'AKIAIOSFODNN7EXAMPLE1234567890ABCDEF',
];

/// 記錄自己被掛載了幾次。
class _RemountCounter {
  /// 目前被掛載的次數。
  int mounts = 0;
}

/// 會回報掛載次數的頁面：用來觀察子樹有沒有被重新掛載。
class _CountingPage extends StatefulWidget {
  /// 以計數器建立頁面。
  const _CountingPage({required this.counter});

  /// 累計掛載次數的容器。
  final _RemountCounter counter;

  @override
  State<_CountingPage> createState() => _CountingPageState();
}

/// `_CountingPage` 的狀態。
class _CountingPageState extends State<_CountingPage> {
  @override
  void initState() {
    super.initState();
    widget.counter.mounts++;
  }

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('counting page'));
  }
}

/// 正常頁面：返回後應該看得見它。
class _HealthyPage extends StatelessWidget {
  /// 建立頁面。
  const _HealthyPage();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('healthy page', key: Key('healthy-page')));
  }
}

/// 以真實接線（navigatorKey + ErrorBoundary）組裝測試應用。
Widget _harness({
  required DiagnosticsHub hub,
  required GlobalKey<NavigatorState> navigatorKey,
  Widget? page,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: _locale,
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorKey: navigatorKey,
    // 起始路由走 routes['/'] 而不是 home：返回動作用的是 pushNamedAndRemoveUntil，
    // 與真實應用（AppRouter.routes 註冊了入口層）保持一致。
    initialRoute: '/',
    routes: <String, WidgetBuilder>{
      '/': (BuildContext context) => page ?? const _HealthyPage(),
      '/other': (BuildContext context) => const _HealthyPage(),
    },
    builder: (BuildContext context, Widget? child) => ErrorBoundary(
      diagnostics: hub,
      navigatorKey: navigatorKey,
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

/// 收集畫面上所有可見文字。
List<String> _allTexts(WidgetTester tester) {
  return find
      .byType(Text)
      .evaluate()
      .map((Element element) => (element.widget as Text).data ?? '')
      .where((String text) => text.isNotEmpty)
      .toList();
}

/// 一次構建階段失敗的框架回報樣本（訊息裡埋著憑證）。
FlutterErrorDetails _buildFailure() => FlutterErrorDetails(
  exception: StateError(
    'failed to load profile password=supersecret token=abcdef1234567890 '
    'key AKIAIOSFODNN7EXAMPLE1234567890ABCDEF',
  ),
  library: 'widgets',
  context: ErrorDescription('while building a ProfileCard'),
  stack: StackTrace.current,
);

void main() {
  late AppLocalizations l10n;
  late List<String> logLines;
  late DiagnosticsHub hub;
  late GlobalKey<NavigatorState> navigatorKey;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(_locale);
  });

  setUp(() {
    logLines = <String>[];
    hub = DiagnosticsHub(sink: (String line) => logLines.add(line));
    navigatorKey = GlobalKey<NavigatorState>();
  });

  group('框架接點', () {
    test('安裝後兩個來源都收口到收集器', () {
      final ErrorWidgetBuilder originalBuilder = ErrorWidget.builder;
      final void Function(FlutterErrorDetails)? originalHandler =
          FlutterError.onError;
      addTearDown(() {
        FlutterError.onError = originalHandler!;
        ErrorWidget.builder = originalBuilder;
      });

      installFrameworkErrorCapture(hub);

      FlutterError.onError!(_buildFailure());

      expect(hub.current, isNotNull);
      expect(hub.current!.kind, AppFailureKind.widgetBuild);
      expect(logLines, hasLength(1));
      expect(logLines.single, contains('kind=widgetBuild'));
      for (final String secret in _secrets) {
        expect(
          logLines.single,
          isNot(contains(secret)),
          reason: '日誌漏出 $secret',
        );
      }

      expect(
        ErrorWidget.builder(
          FlutterErrorDetails(exception: StateError('x'), library: 'y'),
        ),
        isA<SilentErrorPlaceholder>(),
      );
    });

    testWidgets('取代元件本身不帶任何文字', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SilentErrorPlaceholder())),
      );

      expect(find.byType(SilentErrorPlaceholder), findsOneWidget);
      expect(
        find
            .descendant(
              of: find.byType(SilentErrorPlaceholder),
              matching: find.byType(Text),
            )
            .evaluate(),
        isEmpty,
        reason: '它拿不到 BuildContext：出現文字會觸發線上取字，也可能漏出異常內容',
      );
    });
  });

  group('失敗時接管整頁', () {
    testWidgets('構建階段失敗顯示安全畫面與診斷碼', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(hub: hub, navigatorKey: navigatorKey));

      hub.reportFlutterError(_buildFailure());
      await tester.pump();

      expect(find.byType(SafeErrorView), findsOneWidget);
      expect(find.text(l10n.safeErrorTitle), findsOneWidget);
      expect(find.text(l10n.safeErrorKindUi), findsOneWidget);
      expect(find.text(l10n.safeErrorBody), findsOneWidget);
      expect(
        find.text(
          l10n.labelValuePair(
            l10n.safeErrorDiagnosticCodeLabel,
            hub.current!.diagnosticCode,
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(SafeErrorView.returnKey), findsOneWidget);
    });

    testWidgets('畫面與日誌都不出現憑證原值', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(hub: hub, navigatorKey: navigatorKey));

      hub.reportFlutterError(_buildFailure());
      await tester.pump();

      final List<String> onScreen = _allTexts(tester);
      expect(onScreen, isNotEmpty, reason: '至少要有標題與按鈕，否則這支等於沒驗');
      for (final String secret in _secrets) {
        expect(
          onScreen.any((String text) => text.contains(secret)),
          isFalse,
          reason: '畫面漏出：${onScreen.join(' | ')}',
        );
        expect(
          logLines.join('\n'),
          isNot(contains(secret)),
          reason: '日誌漏出 $secret',
        );
      }
      // 原始異常文字與堆疊影格也不進畫面：它們是日誌的內容，不是使用者的。
      expect(onScreen.any((String t) => t.contains('StateError')), isFalse);
      expect(onScreen.any((String t) => t.contains('#0')), isFalse);
      expect(onScreen.any((String t) => t.contains('password')), isFalse);
    });

    testWidgets('安全畫面蓋住原內容而不是並列', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(hub: hub, navigatorKey: navigatorKey));
      expect(find.text('healthy page'), findsOneWidget);

      hub.report(StateError('boom'), kind: AppFailureKind.uncaughtAsync);
      await tester.pump();

      expect(find.byType(SafeErrorView), findsOneWidget);
      // 被蓋住的子樹刻意保持掛載：返回時不必重建整頁。驗的是覆蓋順序而非消失。
      final Stack stack = tester.widget<Stack>(
        find
            .ancestor(
              of: find.byType(SafeErrorView),
              matching: find.byType(Stack),
            )
            .first,
      );
      expect(stack.children, hasLength(2));
      expect(
        (stack.children.last as Positioned).child,
        isA<SafeErrorView>(),
        reason: '安全畫面必須是最上層，否則蓋不住壞掉的內容',
      );
      expect(find.text('healthy page'), findsOneWidget);
    });

    testWidgets('返回後頁面整體可用，出錯那一格允許短暫留白', (WidgetTester tester) async {
      // 實測限制：拋出例外的元件會被留在佔位元件上，要等祖先重建才回來。
      // 換 Key 與 pushNamedAndRemoveUntil 兩種強制重建都試過，都不觸發 initState
      // （說明見 ErrorBoundary 的文件註解）。這裡固定「返回後頁面可用」這個可達成
      // 的事實，不把留白偽裝成已解決。
      final _RemountCounter counter = _RemountCounter();
      await tester.pumpWidget(
        _harness(
          hub: hub,
          navigatorKey: navigatorKey,
          page: _CountingPage(counter: counter),
        ),
      );
      hub.report(StateError('slot exploded'), kind: AppFailureKind.widgetBuild);
      await tester.pump();
      expect(find.byType(SafeErrorView), findsOneWidget);

      await tester.tap(find.byKey(SafeErrorView.returnKey));
      await tester.pump();

      expect(find.byType(SafeErrorView), findsNothing);
      expect(find.text('counting page'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isFalse);
      expect(counter.mounts, 1, reason: '如實記錄：目前不會重新掛載該頁');
    });

    testWidgets('診斷碼與關聯 ID 同時存在時不重複掛鍵', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(hub: hub, navigatorKey: navigatorKey));

      hub.report(
        StateError('server problem'),
        kind: AppFailureKind.apiCall,
        requestId: '01a0d9af-61ba-7898-be81-0ab394666374',
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(SafeErrorView.diagnosticsKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(SafeErrorView.diagnosticsKey),
          matching: find.byType(Text),
        ),
        findsNWidgets(2),
      );
    });
  });

  group('返回可用頁面', () {
    testWidgets('按下後失敗畫面消失、導航清回起始路由', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(hub: hub, navigatorKey: navigatorKey));
      navigatorKey.currentState!.pushNamed('/other');
      await tester.pump();
      hub.report(StateError('first problem'), kind: AppFailureKind.widgetBuild);
      await tester.pump();
      expect(find.byType(SafeErrorView), findsOneWidget);

      await tester.tap(find.byKey(SafeErrorView.returnKey));
      await tester.pump();

      expect(find.byType(SafeErrorView), findsNothing);
      expect(hub.current, isNull);
      expect(
        navigatorKey.currentState!.canPop(),
        isFalse,
        reason: '返回後必須只剩一層，否則使用者又會回到剛才那一頁',
      );
      expect(find.text('healthy page'), findsOneWidget);
    });

    testWidgets('返回後同一失敗重現時改口請重新載入', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(hub: hub, navigatorKey: navigatorKey));
      hub.report(StateError('same problem'), kind: AppFailureKind.widgetBuild);
      await tester.pump();

      await tester.tap(find.byKey(SafeErrorView.returnKey));
      await tester.pump();
      expect(find.byType(SafeErrorView), findsNothing);

      hub.report(StateError('same problem'), kind: AppFailureKind.widgetBuild);
      await tester.pump();

      expect(hub.current!.repeated, isTrue);
      expect(find.byType(SafeErrorView), findsOneWidget);
      expect(find.text(l10n.safeErrorRepeatedHint), findsOneWidget);
    });

    testWidgets('返回後收集器仍可繼續服務', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(hub: hub, navigatorKey: navigatorKey));
      hub.report(StateError('one'));
      await tester.pump();
      await tester.tap(find.byKey(SafeErrorView.returnKey));
      await tester.pump();
      expect(hub.hasFailure, isFalse);

      hub.report(StateError('later problem'));
      await tester.pump();

      expect(find.byType(SafeErrorView), findsOneWidget);
      expect(hub.recent, hasLength(2));
    });
  });

  group('伺服器失敗的呈現', () {
    testWidgets('帶請求關聯 ID 時一併顯示', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(hub: hub, navigatorKey: navigatorKey));

      hub.report(
        ApiError(
          kind: ApiErrorKind.unreachable,
          path: '/health',
          cause: 'no route to host',
        ),
        kind: AppFailureKind.apiCall,
        requestId: '01a0d9af-61ba-7898-be81-0ab394666374',
      );
      await tester.pump();

      expect(find.text(l10n.safeErrorKindServer), findsOneWidget);
      expect(
        find.text(
          l10n.labelValuePair(
            l10n.diagnosticRequestId,
            '01a0d9af-61ba-7898-be81-0ab394666374',
          ),
        ),
        findsOneWidget,
      );
    });

    test('ApiError 的基準位址不會進記錄', () {
      hub.report(
        ApiError(kind: ApiErrorKind.notConfigured, path: '/health'),
        kind: AppFailureKind.apiCall,
      );

      expect(hub.current!.summary, isNot(contains('http')));
      expect(hub.current!.summary, contains('path=/health'));
    });
  });

  group('文案對照', () {
    test('五種失敗類別收斂成三句話', () {
      expect(
        failureKindLabel(l10n, AppFailureKind.widgetBuild),
        l10n.safeErrorKindUi,
      );
      expect(
        failureKindLabel(l10n, AppFailureKind.uncaughtAsync),
        l10n.safeErrorKindBackground,
      );
      expect(
        failureKindLabel(l10n, AppFailureKind.frameworkReport),
        l10n.safeErrorKindBackground,
      );
      expect(
        failureKindLabel(l10n, AppFailureKind.unknown),
        l10n.safeErrorKindBackground,
      );
      expect(
        failureKindLabel(l10n, AppFailureKind.apiCall),
        l10n.safeErrorKindServer,
      );
    });

    test('診斷列一定含診斷碼，沒有關聯 ID 時不硬湊', () {
      const AppFailure failure = AppFailure(
        kind: AppFailureKind.unknown,
        diagnosticCode: 'E001-abc123',
        summary: 'x',
      );

      expect(failureDiagnostics(l10n, failure), hasLength(1));
      expect(
        failureDiagnostics(l10n, failure).single,
        l10n.labelValuePair(l10n.safeErrorDiagnosticCodeLabel, 'E001-abc123'),
      );
    });
  });
}
