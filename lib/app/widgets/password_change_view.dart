/// 本人改密面板：交出現行口令、寫兩次新口令，成功即進入退出態。
///
/// 界線全部在會話層與後端合同上，這裡只做表單與呈現：
///
/// * 再認證是口令本身：面板把現行口令交給 [SessionController.changePassword]，
///   「已登入」從來不構成改密授權；請求裡也沒有任何欄位能指定「改誰」。
/// * 三個輸入都只活在這個對話框的控制器裡：不落任何狀態、緩存或日誌；
///   全部 `obscureText`，成功或被拒後都不回填、不復述。
/// * 本地先擋兩件事（沒填齊、兩次新口令不一致）——它們不值得發一次請求；
///   伺服器說的不外乎現行口令不對（2001）、新口令等於現行或不合形狀（1004）、
///   會話已失效（2003／2002）、查不了。每一支各說各句，不把任何一種講成改密成功。
/// * 成功按已批準策略讓名下全部會話退出（含這一臺）：面板關閉，後方會話卡
///   呈現退出態，提示經 [ScaffoldMessenger] 送達——面板自己已經不在了。
///
/// 內容在對話框內自行滾動：對話框是一條覆蓋式路由，不歸應用殼的滾動區管。
library;

import 'package:flutter/material.dart';

import '../../core/app_locale.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';

/// 從現有上下文開啟改密面板。[session] 由已登入的會話卡顯式帶進來
/// （對話框自己的路由可能取不到會話作用域，不在樹上向後要）。
Future<void> showChangePasswordDialog(
  BuildContext context,
  SessionController session,
) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext _) => PasswordChangeDialog(session: session),
  );
}

/// 本人改密對話框。
class PasswordChangeDialog extends StatefulWidget {
  /// 以會話控制器建立面板。
  const PasswordChangeDialog({super.key, required this.session});

  /// 改密請求經這個控制器發出；狀態收斂（退出態）全部在它那裡，頁面不各寫一套。
  final SessionController session;

  /// 現行口令輸入框識別鍵。
  static const Key currentFieldKey = ValueKey<String>('password-current');

  /// 新口令輸入框識別鍵。
  static const Key newFieldKey = ValueKey<String>('password-new');

  /// 新口令確認輸入框識別鍵。
  static const Key confirmFieldKey = ValueKey<String>('password-confirm');

  /// 提交按鈕識別鍵。
  static const Key submitKey = ValueKey<String>('password-submit');

  /// 結果提示行識別鍵。
  static const Key noticeKey = ValueKey<String>('password-notice');

  @override
  State<PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<PasswordChangeDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _new = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  /// 進行中的提示文字（本地校驗與伺服器結論都收在這一行）。
  String? _notice;

  /// 提交進行中標記：進行中按鈕停用，防連點產生第二趟改密請求。
  bool _submitting = false;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void dispose() {
    // 三個輸入框的明文口令隨面板一起消散：不留任何欄位的抄本。
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// 一次提交：本地校驗先擋，再交會話層，依結果分岔（關閉／提示）。
  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    final AppLocalizations l10n = _l10n;
    final String current = _current.text;
    final String newer = _new.text;
    final String confirm = _confirm.text;
    if (current.isEmpty || newer.isEmpty || confirm.isEmpty) {
      setState(() => _notice = l10n.passwordChangeIncompleteNotice);
      return;
    }
    if (newer != confirm) {
      setState(() => _notice = l10n.passwordChangeMismatchNotice);
      return;
    }
    setState(() {
      _submitting = true;
      _notice = null;
    });
    final SessionPasswordChangeOutcome outcome = await widget.session
        .changePassword(
          currentPassword: current,
          newPassword: newer,
          acceptLanguage: resolveAppLocale(Localizations.localeOf(context)).tag,
        );
    if (!mounted) {
      return;
    }
    // 口令欄一律清空：不論成敗，明文都不該在面板裡多待一毫秒。
    _current.clear();
    _new.clear();
    _confirm.clear();
    setState(() => _submitting = false);

    switch (outcome) {
      case SessionPasswordChangeOutcome.changed:
        // 本人全部會話已在伺服器端失效，會話層已進入退出態：關閉面板，
        // 那句「請用新密碼重新登入」由 SnackBar 講完——面板自己已經不在了。
        _snack(l10n.passwordChangeSuccessSignedOutNotice);
        Navigator.of(context).pop();
      case SessionPasswordChangeOutcome.invalidCurrent:
        setState(() => _notice = l10n.passwordChangeInvalidCurrentNotice);
      case SessionPasswordChangeOutcome.samePassword:
        setState(() => _notice = l10n.passwordChangeSameNotice);
      case SessionPasswordChangeOutcome.invalidNew:
        setState(() => _notice = l10n.passwordChangeInvalidNewNotice);
      case SessionPasswordChangeOutcome.expired:
        // 自己這枚憑據在嘗試期間失效：會話層已收斂，關閉面板交給後方卡片呈現。
        _snack(l10n.passwordChangeExpiredNotice);
        Navigator.of(context).pop();
      case SessionPasswordChangeOutcome.unavailable:
        setState(() => _notice = l10n.passwordChangeUnavailableNotice);
      case SessionPasswordChangeOutcome.notSignedIn:
        // 沒有可改的會話上下文（面板開著期間登出了）：如實關閉。
        Navigator.of(context).pop();
    }
  }

  /// 把一句提示經 ScaffoldMessenger 送達（面板即將關閉時，SnackBar 才講得完）。
  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = _l10n;
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.passwordChangeDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: PasswordChangeDialog.currentFieldKey,
              controller: _current,
              obscureText: true,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: l10n.passwordChangeCurrentLabel,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: PasswordChangeDialog.newFieldKey,
              controller: _new,
              obscureText: true,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: l10n.passwordChangeNewLabel,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: PasswordChangeDialog.confirmFieldKey,
              controller: _confirm,
              obscureText: true,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: l10n.passwordChangeConfirmLabel,
              ),
            ),
            if (_notice != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _notice!,
                key: PasswordChangeDialog.noticeKey,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.devicesRevokeCancelAction),
        ),
        FilledButton(
          key: PasswordChangeDialog.submitKey,
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.passwordChangeSubmitAction),
        ),
      ],
    );
  }
}
