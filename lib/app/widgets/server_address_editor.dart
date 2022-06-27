/// 伺服器位址輸入卡：輸入、驗證可達、本地保存，並說明目前生效的到底是哪一個。
///
/// 三條硬性規則（對應本步的完成判斷）：
/// 1. **格式錯誤先擋下來**——判定一律走 [ServerAddress.validate] 這唯一入口，
///    不合格時連請求都不發，並按具體原因說一句當地人看得懂的話；
/// 2. **連不通不保存**——先用與探測區相同的判準走一趟 `/health` ＋ `/time`，
///    失敗時保留輸入內容並如實呈現原因，絕不出現「已保存」卻打不通；
/// 3. **來源說清楚**——卡內同時列出「生效位址」與「本機已保存」兩行，必要時說明
///    生效值來自編譯期參數；debug 建置下注入值優先時，明確告訴使用者剛存的值尚未生效。
///
/// 所有顯示文字取自本地化資源；本檔不出現任何語言的硬編碼字串。
library;

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/connection_tracker.dart';
import '../../core/api/server_address.dart';
import '../../core/api/server_address_settings.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';
import '../address_scope.dart';
import '../api_error_labels.dart';
import '../connection_scope.dart';
import '../server_address_labels.dart';

/// 伺服器位址輸入卡。
class ServerAddressEditor extends StatefulWidget {
  /// 建立輸入卡。
  const ServerAddressEditor({super.key});

  /// 位址輸入框的測試識別鍵。
  static const Key inputKey = ValueKey<String>('server-address-input');

  /// 保存按鈕的測試識別鍵。
  static const Key saveKey = ValueKey<String>('server-address-save');

  /// 清除按鈕的測試識別鍵。
  static const Key clearKey = ValueKey<String>('server-address-clear');

  /// 格式錯誤說明的測試識別鍵。
  static const Key issueKey = ValueKey<String>('server-address-issue');

  /// 動作結果說明的測試識別鍵。
  static const Key resultKey = ValueKey<String>('server-address-result');

  @override
  State<ServerAddressEditor> createState() => _ServerAddressEditorState();
}

/// 卡片最近一次動作的結果類別。
enum _FeedbackKind {
  /// 沒有待呈現的結果。
  none,

  /// 已驗證可達並寫入本機。
  saved,

  /// 已寫入本機。
  cleared,

  /// 格式不合格，未發出請求。
  invalid,

  /// 格式合格但連不通，未保存。
  unreachable,

  /// 本機寫入失敗，狀態保持原樣。
  storageFailed,
}

/// 一次動作的結果：類別加上對應的判定依據。
class _Feedback {
  const _Feedback(this.kind, {this.issue, this.error});

  final _FeedbackKind kind;
  final ServerAddressIssue? issue;
  final ApiError? error;

  static const _Feedback none = _Feedback(_FeedbackKind.none);
}

class _ServerAddressEditorState extends State<ServerAddressEditor> {
  final TextEditingController _controller = TextEditingController();

  /// 最近一次動作的結果。
  _Feedback _feedback = _Feedback.none;

  /// 是否正在驗證並保存（此時兩個按鈕都停用）。
  bool _busy = false;

  /// 預填只做一次：語言切換會再次走到 `didChangeDependencies`，
  /// 那時使用者可能已經打了半個位址，覆寫會吃掉他的輸入。
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) {
      return;
    }
    // 以本機已存值預填，讓使用者看見自己現在的設定，而不是面對一個空白框。
    final ServerAddressSettings settings = AddressScope.of(context);
    _controller.text = settings.savedUrl ?? settings.addressDisplay ?? '';
    _prefilled = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 輸入變動後，先前的判定已不適用於當前文字，立即收回提示。
  void _onTextChanged() {
    if (_feedback.kind == _FeedbackKind.none) {
      return;
    }
    setState(() => _feedback = _Feedback.none);
  }

  /// 驗證並保存輸入的位址：不通就不落盤，失敗原因一律如實呈現。
  Future<void> _save() async {
    // 跨入 await 前先把需要的東西取好：異步結束後再取 context，可能落在已卸載的
    // 元件上（DEC-021 的教訓之一：介面層不做無法復原的假設）。
    final ServerAddressSettings settings = AddressScope.of(context);
    final ConnectionTracker connection = ConnectionScope.of(context);
    final AppLocale locale = resolveAppLocale(Localizations.localeOf(context));

    setState(() {
      _busy = true;
      _feedback = _Feedback.none;
    });

    final ServerAddressSaveResult result = await settings.save(
      _controller.text,
      acceptLanguage: locale.tag,
    );
    if (result.isSaved && result.probe != null) {
      // 保存前那趟驗證打的就是同一個位址，直接把結果交給追蹤器，
      // 不必為「剛確認過的數值」再發一次請求。
      connection.adopt(result.probe!);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _feedback = switch (result.status) {
        ServerAddressSaveStatus.saved ||
        ServerAddressSaveStatus.savedInactive => const _Feedback(
          _FeedbackKind.saved,
        ),
        ServerAddressSaveStatus.rejectedByFormat => _Feedback(
          _FeedbackKind.invalid,
          issue: result.issue,
        ),
        ServerAddressSaveStatus.rejectedByConnectivity => _Feedback(
          _FeedbackKind.unreachable,
          error: result.error,
        ),
        ServerAddressSaveStatus.persistenceFailed => const _Feedback(
          _FeedbackKind.storageFailed,
        ),
      };
    });
  }

  /// 清除本機保存的位址；寫入失敗時保持原樣並說明原因。
  Future<void> _clear() async {
    final ServerAddressSettings settings = AddressScope.of(context);
    setState(() {
      _busy = true;
      _feedback = _Feedback.none;
    });

    _FeedbackKind kind = _FeedbackKind.cleared;
    try {
      await settings.clear();
    } catch (_) {
      // 清不掉卻把輸入框留空會呈現與本機不一致的狀態，因此原值不動，只報失敗。
      kind = _FeedbackKind.storageFailed;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (kind == _FeedbackKind.cleared) {
        _controller.clear();
      }
      _busy = false;
      _feedback = _Feedback(kind);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ServerAddressSettings settings = AddressScope.of(context);

    final bool fromInjected = settings.origin == ServerAddressOrigin.injected;
    final bool savedOverridden =
        fromInjected && settings.prefersInjected && settings.savedUrl != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.serverAddressTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(l10n.serverAddressSummary, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            key: ServerAddressEditor.inputKey,
            controller: _controller,
            enabled: !_busy,
            maxLines: 1,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.serverAddressInputHint,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
            onChanged: (_) => _onTextChanged(),
            onSubmitted: (_) {
              if (!_busy) {
                _save();
              }
            },
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton(
                key: ServerAddressEditor.saveKey,
                onPressed: _busy ? null : _save,
                child: Text(
                  _busy
                      ? l10n.serverAddressSaving
                      : l10n.serverAddressSaveAction,
                ),
              ),
              OutlinedButton(
                key: ServerAddressEditor.clearKey,
                onPressed: _busy || settings.savedUrl == null ? null : _clear,
                child: Text(l10n.serverAddressClearAction),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.labelValuePair(
              l10n.serverAddressEffectiveLabel,
              settings.addressDisplay ?? l10n.serverAddressNotSet,
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.labelValuePair(
              l10n.serverAddressSavedLabel,
              settings.savedUrl ?? l10n.serverAddressNotSet,
            ),
            style: theme.textTheme.bodySmall,
          ),
          if (fromInjected)
            _Hint(text: l10n.serverAddressFromBuildNote, tone: theme),
          if (savedOverridden)
            _Hint(text: l10n.serverAddressInactiveNote, tone: theme),
          ..._feedbackLines(l10n, theme),
        ],
      ),
    );
  }

  /// 最近一次動作的結果說明：格式錯誤、連不通、已保存、本機寫入失敗。
  List<Widget> _feedbackLines(AppLocalizations l10n, ThemeData theme) {
    final _Feedback feedback = _feedback;
    switch (feedback.kind) {
      case _FeedbackKind.invalid:
        // 格式不合格：具體原因由唯一出口 addressIssueLabel 給出，未發任何請求。
        final String? issueText = addressIssueLabel(l10n, feedback.issue);
        if (issueText == null) {
          return const <Widget>[];
        }
        return <Widget>[
          _Hint(
            key: ServerAddressEditor.issueKey,
            text: issueText,
            tone: theme,
            error: true,
          ),
        ];
      case _FeedbackKind.unreachable:
        // 連不通：先說「所以沒有保存」，再說伺服器/網路給出的類別文字。
        final ApiError? error = feedback.error;
        return <Widget>[
          _Hint(
            key: ServerAddressEditor.resultKey,
            text: l10n.serverAddressVerifyFailed,
            tone: theme,
            error: true,
          ),
          if (error != null)
            _Hint(text: apiErrorText(l10n, error), tone: theme, error: true),
        ];
      case _FeedbackKind.storageFailed:
        return <Widget>[
          _Hint(
            key: ServerAddressEditor.resultKey,
            text: l10n.serverAddressStorageFailed,
            tone: theme,
            error: true,
          ),
        ];
      case _FeedbackKind.saved:
        return <Widget>[
          _Hint(
            key: ServerAddressEditor.resultKey,
            text: l10n.serverAddressSavedNote,
            tone: theme,
          ),
        ];
      case _FeedbackKind.cleared:
        return <Widget>[
          _Hint(
            key: ServerAddressEditor.resultKey,
            text: l10n.serverAddressCleared,
            tone: theme,
          ),
        ];
      case _FeedbackKind.none:
        return const <Widget>[];
    }
  }
}

/// 一行結果說明：可依成敗著色，並可帶測試識別鍵。
class _Hint extends StatelessWidget {
  /// 以文字建立說明。
  const _Hint({super.key, required this.text, required this.tone, this.error});

  /// 說明文字。
  final String text;

  /// 目前主題（用於取失敗色）。
  final ThemeData tone;

  /// 是否為失敗說明。
  final bool? error;

  @override
  Widget build(BuildContext context) {
    final bool failed = error ?? false;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: tone.textTheme.bodySmall?.copyWith(
          color: failed ? tone.colorScheme.error : null,
        ),
      ),
    );
  }
}
