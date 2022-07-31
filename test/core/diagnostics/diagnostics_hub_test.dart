/// 失敗收集器的測試：記錄內容安全、容量有界、返回後可重現判定，且不會自我放大。
library;

import 'package:evernightrealm/core/diagnostics/app_failure.dart';
import 'package:evernightrealm/core/diagnostics/diagnostics_hub.dart';
import 'package:evernightrealm/core/diagnostics/redaction.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把日誌行收進清單的假出口。
class _RecordingSink {
  final List<String> lines = <String>[];

  void call(String line) => lines.add(line);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('記錄與呈現', () {
    test('report 建立記錄、寫日誌並成為待呈現失敗', () async {
      final _RecordingSink sink = _RecordingSink();
      final DiagnosticsHub hub = DiagnosticsHub(sink: sink.call);
      int notifications = 0;
      hub.addListener(() => notifications++);

      final AppFailure failure = hub.report(
        StateError('widget blew up'),
        kind: AppFailureKind.widgetBuild,
      );
      await _flush();

      expect(hub.current, isNotNull);
      expect(hub.hasFailure, isTrue);
      expect(hub.current!.diagnosticCode, failure.diagnosticCode);
      expect(failure.kind, AppFailureKind.widgetBuild);
      expect(notifications, 1, reason: '開始與結束各一次，通知落在本幀之後');
      expect(sink.lines, hasLength(1));
      expect(sink.lines.single, contains('code=${failure.diagnosticCode}'));
      expect(sink.lines.single, contains('kind=widgetBuild'));
      expect(sink.lines.single, contains('StateError'));
    });

    test('診斷碼逐筆唯一且帶序號', () {
      final DiagnosticsHub hub = DiagnosticsHub(sink: (String _) {});

      final AppFailure a = hub.report(StateError('one'));
      final AppFailure b = hub.report(StateError('two'));

      expect(a.diagnosticCode, isNot(b.diagnosticCode));
      expect(a.diagnosticCode, startsWith('E001-'));
      expect(b.diagnosticCode, startsWith('E002-'));
    });

    test('記錄不含原始例外物件，日誌行不含憑證', () async {
      final _RecordingSink sink = _RecordingSink();
      final DiagnosticsHub hub = DiagnosticsHub(sink: sink.call);

      hub.report(StateError('password=supersecret token=abcdef123456'));
      await _flush();

      expect(hub.current!.summary, isNot(contains('supersecret')));
      expect(sink.lines.single, isNot(contains('supersecret')));
      expect(sink.lines.single, contains(redactedPlaceholder));
    });

    test('requestId 進記錄也進日誌行', () async {
      final _RecordingSink sink = _RecordingSink();
      final DiagnosticsHub hub = DiagnosticsHub(sink: sink.call);

      hub.report(
        StateError('server rejected'),
        kind: AppFailureKind.apiCall,
        requestId: '01a0d9af-61ba-7898-be81-0ab394666374',
      );
      await _flush();

      expect(hub.current!.requestId, '01a0d9af-61ba-7898-be81-0ab394666374');
      expect(sink.lines.single, contains('request_id=01a0d9af'));
    });
  });

  group('返回與重現', () {
    test('recover 清掉待呈現失敗但保留歷史', () async {
      final DiagnosticsHub hub = DiagnosticsHub(sink: (String _) {});
      hub.report(StateError('boom'));
      await _flush();

      hub.recover();
      await _flush();

      expect(hub.current, isNull);
      expect(hub.hasFailure, isFalse);
      expect(hub.recent, hasLength(1));
      expect(hub.total, 1);
    });

    test('返回後同一失敗立刻重現時標為 repeated', () async {
      final DiagnosticsHub hub = DiagnosticsHub(sink: (String _) {});
      hub.report(StateError('same problem'));
      await _flush();

      hub.recover();
      await _flush();
      final AppFailure again = hub.report(StateError('same problem'));
      await _flush();

      expect(again.repeated, isTrue);
      expect(hub.current!.repeated, isTrue);
    });

    test('不同的失敗不算重現', () async {
      final DiagnosticsHub hub = DiagnosticsHub(sink: (String _) {});
      hub.report(StateError('first'));
      await _flush();
      hub.recover();
      await _flush();

      expect(hub.report(StateError('second')).repeated, isFalse);
    });

    test('沒有失敗時 recover 不通知也不留下歷史', () async {
      final DiagnosticsHub hub = DiagnosticsHub(sink: (String _) {});
      int notifications = 0;
      hub.addListener(() => notifications++);

      hub.recover();
      await _flush();

      expect(notifications, 0);
      expect(hub.recent, isEmpty);
    });
  });

  group('框架錯誤接點', () {
    test('構建階段的回報歸為 widgetBuild', () async {
      final DiagnosticsHub hub = DiagnosticsHub(sink: (String _) {});

      hub.reportFlutterError(
        FlutterErrorDetails(
          exception: StateError('layout failed'),
          library: 'rendering library',
          context: ErrorDescription('during building'),
        ),
      );
      await _flush();

      expect(hub.current!.kind, AppFailureKind.widgetBuild);
      expect(hub.current!.library, 'rendering library');
    });

    test('非構建階段的回報歸為 frameworkReport', () async {
      final DiagnosticsHub hub = DiagnosticsHub(sink: (String _) {});

      hub.reportFlutterError(
        FlutterErrorDetails(
          exception: StateError('channel failed'),
          library: 'services',
        ),
      );
      await _flush();

      expect(hub.current!.kind, AppFailureKind.frameworkReport);
    });

    test('已有失敗呈現時，第二筆只入檔不搶畫面', () async {
      final DiagnosticsHub hub = DiagnosticsHub(sink: (String _) {});
      final AppFailure first = hub.report(StateError('first'));

      hub.reportFlutterError(
        FlutterErrorDetails(
          exception: StateError('second'),
          library: 'widgets',
        ),
      );
      await _flush();

      expect(hub.current!.diagnosticCode, first.diagnosticCode);
      expect(hub.total, 2);
      expect(hub.recent, hasLength(2));
    });
  });

  group('邊界條件', () {
    test('環形緩衝只留最近 capacity 筆，丟最舊的', () {
      final DiagnosticsHub hub = DiagnosticsHub(
        sink: (String _) {},
        capacity: 5,
      );

      for (int i = 0; i < 12; i++) {
        hub.report(StateError('failure $i'));
      }

      expect(hub.recent, hasLength(5));
      expect(hub.recent.first.summary, contains('failure 11'));
      expect(hub.recent.last.summary, contains('failure 7'));
      expect(hub.total, 12, reason: '累計筆數不受緩衝容量影響');
    });

    test('recent 回傳副本，外部改動不影響內部狀態', () {
      final DiagnosticsHub hub = DiagnosticsHub(sink: (String _) {});
      hub.report(StateError('boom'));

      expect(() => hub.recent.clear(), throwsUnsupportedError);
    });

    test('日誌出口抛錯時不外洩，記錄仍成立', () {
      final DiagnosticsHub hub = DiagnosticsHub(
        sink: (String _) => throw StateError('sink is broken'),
      );

      expect(() => hub.report(StateError('boom')), isNot(throwsA(anything)));
      expect(hub.current, isNotNull);
    });

    test('出口裡再報錯誤不會無限遞迴', () {
      late DiagnosticsHub hub;
      int calls = 0;
      hub = DiagnosticsHub(
        sink: (String _) {
          calls++;
          if (calls < 10) {
            hub.report(StateError('nested'));
          }
        },
      );

      hub.report(StateError('outer'));

      expect(calls, 1, reason: '回報進行中時不再寫第二行');
      expect(hub.total, greaterThan(1), reason: '嵌套記錄仍進記憶體');
    });
  });
}
