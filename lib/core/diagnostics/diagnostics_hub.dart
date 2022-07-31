/// 未處理錯誤的收集與派發：一份給畫面（可返回），一份給本機日誌（已脫敏）。
///
/// 三個設計前提：
/// 1. **不外送**——記錄只寫進本機控制台與記憶體，不發遙測、不發崩潰報告
///    （規格 SEC-014／ADR-015）；
/// 2. **出口只有一條**——所有寫入前都先經 `redactText`，呼叫端無法繞過；
/// 3. **回報本身不能再拋例外**——承接日誌的動作出錯時只吞掉，避免
///    「為了記錄錯誤而把應用弄崩」的二次故障。
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'app_failure.dart';
import 'redaction.dart';

/// 日誌出口：收到一行已脫敏文字並寫到本機某處。
typedef DiagnosticSink = void Function(String line);

/// 預設出口：寫進平台控制台（Web 為瀏覽器 console，桌面為 stderr）。
void consoleDiagnosticSink(String line) =>
    developer.log(line, name: 'evernightrealm');

/// 失敗收集器（可訂閱）。
class DiagnosticsHub extends ChangeNotifier {
  /// 以日誌出口與記憶體保留筆數建立收集器。
  DiagnosticsHub({this.sink = consoleDiagnosticSink, this.capacity = 20});

  /// 日誌出口。測試可換成把行收進清單的假出口。
  final DiagnosticSink sink;

  /// 記憶體裡最多保留的筆數（只供未來的診斷頁與測試斷言，不落檔）。
  final int capacity;

  final List<AppFailure> _recent = <AppFailure>[];
  AppFailure? _current;
  AppFailure? _lastRecovered;
  int _sequence = 0;
  bool _reporting = false;
  bool _notifyScheduled = false;

  /// 目前需要向使用者呈現的失敗；已返回時為 `null`。
  AppFailure? get current => _current;

  /// 是否正在呈現失敗畫面。
  bool get hasFailure => _current != null;

  /// 最近的失敗記錄，由新到舊。
  List<AppFailure> get recent => List<AppFailure>.unmodifiable(_reversed);

  /// 本行程累計收到的失敗筆數。
  int get total => _sequence;

  Iterable<AppFailure> get _reversed => _recent.reversed;

  /// 記錄一次失敗，並把它設為待呈現的畫面內容。
  ///
  /// [summary] 與 [stack] 一律先脫敏再落地；[requestId] 只在是伺服器請求時才有。
  /// 回傳建立的記錄，方便呼叫端直接取用診斷碼。
  AppFailure report(
    Object error, {
    AppFailureKind kind = AppFailureKind.unknown,
    StackTrace? stack,
    String? requestId,
    String? library,
  }) {
    final AppFailure failure = _record(
      kind: kind,
      summary: describeError(error),
      requestId: requestId,
      library: library,
      detail: describeStack(stack),
    );
    _current = failure;
    _notifySafely();
    return failure;
  }

  /// 記錄框架回報的錯誤（`FlutterError.onError` 的接點）。
  ///
  /// 構建階段的錯誤會由框架改畫成 `ErrorWidget`，這裡只負責把同一件事收進
  /// 記錄與日誌，讓畫面能給出可返回的狀態而不是留一塊紅色方框。
  void reportFlutterError(FlutterErrorDetails details) {
    final Object error = details.exception;
    final String? contextText = switch (details.context) {
      final Object? value when value != null => redactText('$value'),
      _ => null,
    };
    final AppFailure failure = _record(
      kind: _kindOfFlutterError(details, contextText: contextText),
      summary: redactText(
        '${error.runtimeType}: $error${contextText == null ? '' : ' ($contextText)'}',
      ),
      requestId: null,
      library: details.library,
      detail: describeStack(details.stack, maxLines: 6),
    );
    // 只有尚未有失敗呈現時才搶佔畫面，否則第二筆錯誤會把使用者從畫面踢回去。
    if (_current == null) {
      _current = failure;
      _notifySafely();
    }
  }

  /// 使用者選擇返回可用頁面：清掉待呈現的失敗，保留歷史。
  void recover() {
    final AppFailure? failure = _current;
    if (failure == null) {
      return;
    }
    _lastRecovered = failure;
    _current = null;
    _notifySafely();
  }

  /// 延到本幀結束後再通知訂閱者。
  ///
  /// 構建階段的錯誤是在 `performRebuild` 的 try/catch 裡回報上來的，此時直接
  /// `notifyListeners()` 等於「在建置過程中把祖先標髒」，框架會另外拋出一個
  /// assertion，真正的錯誤反而被掩蓋。改排到微任務後，通知落在這一幀跑完之後。
  void _notifySafely() {
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (_reporting) {
        return;
      }
      notifyListeners();
    });
  }

  /// 判斷失敗發生在哪一階段。
  ///
  /// 實測注意：元件構建拋出例外時，框架給的 `library` 是 `widgets`，真正的線索在
  /// `context`（「while building X」／「while laying out X」）。只看庫名會把構建錯誤
  /// 誤分成一般框架回報，因此兩者一起看。
  AppFailureKind _kindOfFlutterError(
    FlutterErrorDetails details, {
    String? contextText,
  }) {
    final String haystack = '${details.library ?? ''} ${contextText ?? ''}'
        .toLowerCase();
    const List<String> buildPhaseClues = <String>[
      'building',
      'layout',
      'laying out',
      'rendering',
      'painting',
      'compositing',
    ];
    if (buildPhaseClues.any(haystack.contains)) {
      return AppFailureKind.widgetBuild;
    }
    return AppFailureKind.frameworkReport;
  }

  /// 建立記錄、寫日誌、進環形緩衝；任何一步出錯都不向外拋。
  AppFailure _record({
    required AppFailureKind kind,
    required String summary,
    required String detail,
    String? requestId,
    String? library,
  }) {
    _sequence++;
    final bool repeated =
        _lastRecovered != null &&
        _lastRecovered!.kind == kind &&
        _lastRecovered!.summary == summary;
    final AppFailure failure = AppFailure(
      kind: kind,
      diagnosticCode: _codeFor(_sequence, summary),
      summary: summary,
      requestId: requestId,
      library: library,
      repeated: repeated,
    );

    _recent.add(failure);
    while (_recent.length > capacity) {
      _recent.removeAt(0);
    }

    if (_reporting) {
      return failure;
    }
    _reporting = true;
    try {
      sink(_lineOf(failure, detail));
    } catch (_) {
      // 日誌出口本身故障時不連鎖拋出：記錄已在記憶體裡，畫面仍可返回。
    } finally {
      _reporting = false;
    }
    return failure;
  }

  /// 組成一行可寫入本機日誌的文字（全部欄位都已脫敏）。
  String _lineOf(AppFailure failure, String detail) {
    final StringBuffer buffer = StringBuffer()
      ..write('failure code=${failure.diagnosticCode}')
      ..write(' kind=${failure.kind.name}')
      ..write(' summary=${failure.summary}');
    if (failure.library != null) {
      buffer.write(' library=${failure.library}');
    }
    if (failure.requestId != null) {
      buffer.write(' request_id=${failure.requestId}');
    }
    if (failure.repeated) {
      buffer.write(' repeated=true');
    }
    if (detail.isNotEmpty) {
      buffer.write('\n  ${detail.replaceAll('\n', '\n  ')}');
    }
    return buffer.toString();
  }

  /// 診斷碼：序號加一段內容雜湊，讓同一筆記錄在畫面與日誌上對得起來。
  String _codeFor(int sequence, String summary) {
    const int mask = 0x7FFFFFFF;
    int hash = 7;
    for (final int unit in summary.runes) {
      hash = ((hash * 33) + unit) & mask;
    }
    final String tail = hash.toRadixString(16).padLeft(6, '0');
    return 'E${sequence.toString().padLeft(3, '0')}-${tail.substring(0, 6)}';
  }
}
