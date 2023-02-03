/// 「管理員端普通帳戶詳情與資料編輯」卡：按標識重讀單筆真相，
/// 再以白名單（只有一欄 display_name）與 compare-and-set 保存改動。
///
/// 這一張卡的幾條規則是刻意的，不是排版偏好：
///
/// * 表單只在「已经从伺服器讀到這一筆」之後才出現。目錄行是投影，詳情才過實體校驗；
///   拿行資料預填表單會讓「你看到的現值」與「資料庫的現值」各說各話。
/// * CAS 的依據值取「上一次從伺服器讀到的那個顯示名」（[_profile] 本身），
///   不是本地輸入框的當前內容——否則使用者改到一半再保存時，依據值就成了他自己打的字，
///   衝突永遠測不到，那正是 2013 要擋的情況。
/// * 保存成功的句子和輸入框都換成 PUT 回應裡的資料庫現值：回應是「保存之後」的真相，
///   不是請求的迴音（後端的空白整理因此看得見）。
/// * 這裡沒有一格可以動憑據、狀態、首次改密旗標或來源類型：本體多帶那些欄位會被後端
///   打成 1004，界面也就不擺那些控制項。2013 只給「重新讀取這份資料」的出口，
///   不給「再點一次保存」的誘餌。
/// * 活動、資產與訊息都不在這一頁：那些模組尚未實作，擺一個空清單或 0 就是假資料。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 階段：載入中、就緒、載入失敗（讀不到這份資料）。
enum _ProfilePhase { loading, ready, loadFailed }

/// 保存階段：空閒、進行中（進行中不再發第二趟）。
enum _SavePhase { idle, saving }

/// 普通帳戶詳情與編輯卡。
class StandardAccountProfileCard extends StatefulWidget {
  /// 以端點介面與目標標識建立詳情卡。
  ///
  /// [accountId] 變動時（頁面以 `ValueKey(accountId)` 重建本卡）一律重新讀取，
  /// 界面不沿用上一個人的那份資料。
  const StandardAccountProfileCard({
    super.key,
    required this.api,
    required this.accountId,
    this.onClosed,
    this.onSaved,
  });

  /// 統一端點存取介面。
  final ServerApi api;

  /// 目標帳戶標識（UUIDv7 字串）。
  final String accountId;

  /// 關閉本卡的回呼（由頁面清掉選中的標識）。
  final VoidCallback? onClosed;

  /// 保存成功的回呼（由頁面重讀目錄；清單資料變了就要重新取服務端結果）。
  final VoidCallback? onSaved;

  /// 標題識別鍵。
  static const Key titleKey = ValueKey<String>('std-account-profile-title');

  /// 載入中提示識別鍵。
  static const Key loadingKey = ValueKey<String>('std-account-profile-loading');

  /// 載入失敗提示識別鍵。
  static const Key loadFailedKey = ValueKey<String>(
    'std-account-profile-load-failed',
  );

  /// 顯示名輸入框識別鍵。
  static const Key displayNameKey = ValueKey<String>(
    'std-account-profile-display-name',
  );

  /// 保存鈕識別鍵。
  static const Key submitKey = ValueKey<String>('std-account-profile-submit');

  /// 提示文字識別鍵。
  static const Key noticeKey = ValueKey<String>('std-account-profile-notice');

  /// 保存成功摘要識別鍵。
  static const Key savedKey = ValueKey<String>('std-account-profile-saved');

  /// 衝突後的重讀出口識別鍵。
  static const Key reloadKey = ValueKey<String>('std-account-profile-reload');

  /// 來源欄位識別鍵。
  static const Key sourceKey = ValueKey<String>('std-account-profile-source');

  /// 狀態欄位識別鍵。
  static const Key statusKey = ValueKey<String>('std-account-profile-status');

  /// 「憑據與安全狀態不在這裡改」那句說明的識別鍵。
  static const Key securityHintKey = ValueKey<String>(
    'std-account-profile-security-hint',
  );

  /// 「活動／資產／訊息尚未實作」那句說明的識別鍵。
  static const Key noSectionsKey = ValueKey<String>(
    'std-account-profile-no-sections',
  );

  @override
  State<StandardAccountProfileCard> createState() =>
      _StandardAccountProfileCardState();
}

class _StandardAccountProfileCardState
    extends State<StandardAccountProfileCard> {
  _ProfilePhase _phase = _ProfilePhase.loading;
  _SavePhase _savePhase = _SavePhase.idle;

  final TextEditingController _displayName = TextEditingController();

  /// 上一次從伺服器讀到的單筆真相；同時是 CAS 的依據值來源。
  ///
  /// 目錄行不算這份資料（它是投影），本地輸入也不算（它是要提交的意圖）。
  StandardAccountReport? _profile;

  String? _notice;
  String? _savedNotice;

  /// 2013 之後表單進入「只給重讀出口」的狀態：再點保存對衝突不是處置。
  bool _conflicted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  /// 讀（或重讀）這份資料：表單的底稿只能由它填。
  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = _ProfilePhase.loading;
      _notice = null;
      _savedNotice = null;
      _conflicted = false;
    });
    try {
      final StandardAccountDetailReport report = await widget.api
          .standardAccountDetail(
            accountId: widget.accountId,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.account;
        _displayName.text = report.account.displayName;
        _phase = _ProfilePhase.ready;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _ProfilePhase.loadFailed;
        _notice = _readFailureText(error);
      });
    }
  }

  /// 讀取失敗分流：1001（不在這本目錄裡）、2011（主體不對）、
  /// 會話與門閂那一簇各說各句；其餘交給機器碼的通用句。
  String _readFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (error.knownCode) {
      ApiMachineCode.notFound => l10n.stdAccountProfileNotFoundNotice,
      ApiMachineCode.permissionDenied => l10n.stdAccountProfileDeniedNotice,
      ApiMachineCode.notAuthenticated ||
      ApiMachineCode.sessionInvalid ||
      ApiMachineCode.sessionStale ||
      ApiMachineCode.passwordChangeRequired =>
        l10n.adminProfileStaleRejectedNotice,
      _ => apiErrorText(l10n, error),
    };
  }

  /// 保存顯示名：本體只有新值與它所依據的現值兩欄，目標在路徑上。
  Future<void> _save() async {
    final StandardAccountReport? profile = _profile;
    if (profile == null || _savePhase == _SavePhase.saving || _conflicted) {
      // 讀不到這份資料時不發請求；進行中不發第二趟；衝突後不拿舊依據值再撞一次。
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String displayName = _displayName.text.trim();
    if (displayName.isEmpty) {
      // 本地只擋「明顯沒填」：域規則（長度、控制字元）由服務端判，界面不抄一份。
      setState(() => _notice = l10n.adminProfileFormIncompleteNotice);
      return;
    }
    setState(() => _savePhase = _SavePhase.saving);
    try {
      final StandardAccountDetailReport report = await widget.api
          .updateStandardAccountProfile(
            accountId: profile.accountId,
            displayName: displayName,
            expectedDisplayName: profile.displayName,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.account;
        _displayName.text = report.account.displayName;
        _savePhase = _SavePhase.idle;
        _notice = null;
        _savedNotice = l10n.adminProfileSavedNotice(report.account.displayName);
      });
      widget.onSaved?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savePhase = _SavePhase.idle;
        _notice = _writeFailureText(error);
      });
    }
  }

  /// 寫入失敗分流：1004 依 `invalid_field` 說對應那一句、2013 單獨成句並鎖住重發、
  /// 1001／2011／會話那一簇各說各句；其餘交給機器碼的通用句。
  String _writeFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'display_name' => l10n.adminProfileInvalidDisplayNameNotice,
        'expected_display_name' => l10n.stdAccountProfileMissingAnchorNotice,
        _ => apiErrorText(l10n, error),
      };
    }
    if (code == ApiMachineCode.profileConflict) {
      _conflicted = true;
      return l10n.adminProfileConflictNotice;
    }
    return switch (code) {
      ApiMachineCode.notFound => l10n.stdAccountProfileNotFoundNotice,
      ApiMachineCode.permissionDenied => l10n.stdAccountProfileDeniedNotice,
      ApiMachineCode.notAuthenticated ||
      ApiMachineCode.sessionInvalid ||
      ApiMachineCode.sessionStale ||
      ApiMachineCode.passwordChangeRequired =>
        l10n.adminProfileStaleRejectedNotice,
      _ => apiErrorText(l10n, error),
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final StandardAccountReport? profile = _profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                profile == null
                    ? l10n.stdAccountProfileTitle(widget.accountId)
                    : l10n.stdAccountProfileTitle(profile.loginName),
                key: StandardAccountProfileCard.titleKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: widget.onClosed,
              child: Text(l10n.adminProfileCloseAction),
            ),
          ],
        ),
        switch (_phase) {
          _ProfilePhase.loading => _loadingRow(l10n, theme),
          _ProfilePhase.loadFailed => _loadFailedColumn(l10n),
          _ProfilePhase.ready => _readyBody(l10n, theme, profile!),
        },
      ],
    );
  }

  Widget _loadingRow(AppLocalizations l10n, ThemeData theme) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.adminProfileLoadingHint,
            key: StandardAccountProfileCard.loadingKey,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _loadFailedColumn(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _notice ?? l10n.adminProfileLoadFailedNotice,
          key: StandardAccountProfileCard.loadFailedKey,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _load,
          child: Text(l10n.adminProfileReloadAction),
        ),
      ],
    );
  }

  Widget _readyBody(
    AppLocalizations l10n,
    ThemeData theme,
    StandardAccountReport profile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.labelValuePair(
            l10n.adminListDisplayNameLabel,
            profile.displayName,
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.stdAccountSourceLabel,
            _typeText(l10n, profile.accountType),
          ),
          key: StandardAccountProfileCard.sourceKey,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListStatusLabel,
            _statusText(l10n, profile.status),
          ),
          key: StandardAccountProfileCard.statusKey,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(l10n.adminAccountIdLabel, profile.accountId),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListCreatedLabel,
            _formatUtcMinute(profile.createdAt),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminListLastLoginLabel,
            profile.lastLoginAt == null
                ? l10n.adminListNeverLoggedInValue
                : _formatUtcMinute(profile.lastLoginAt!),
          ),
          style: theme.textTheme.bodySmall,
        ),
        if (profile.disabledAt != null)
          Text(
            l10n.labelValuePair(
              l10n.adminStatusDisabledAtLabel,
              _formatUtcMinute(profile.disabledAt!),
            ),
            style: theme.textTheme.bodySmall,
          ),
        if (profile.mustChangePassword)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.adminListMustChangeBadge,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          l10n.stdAccountProfileSecurityHint,
          key: StandardAccountProfileCard.securityHintKey,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.adminProfileLoginNameLockedHint,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.stdAccountProfileNoSectionsNotice,
          key: StandardAccountProfileCard.noSectionsKey,
          style: theme.textTheme.bodySmall,
        ),
        const Divider(),
        TextField(
          key: StandardAccountProfileCard.displayNameKey,
          controller: _displayName,
          enabled: !_conflicted && _savePhase != _SavePhase.saving,
          decoration: InputDecoration(
            labelText: l10n.adminProfileDisplayNameLabel,
            isDense: true,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            FilledButton(
              key: StandardAccountProfileCard.submitKey,
              onPressed: _conflicted || _savePhase == _SavePhase.saving
                  ? null
                  : _save,
              child: _savePhase == _SavePhase.saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.adminProfileSubmitAction),
            ),
            if (_conflicted) ...<Widget>[
              const SizedBox(width: 10),
              OutlinedButton(
                key: StandardAccountProfileCard.reloadKey,
                onPressed: _load,
                child: Text(l10n.adminProfileReloadAction),
              ),
            ],
          ],
        ),
        if (_savedNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _savedNotice!,
              key: StandardAccountProfileCard.savedKey,
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _notice!,
              key: StandardAccountProfileCard.noticeKey,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// 狀態原字串 → 顯示文字；未知值原樣顯示（與目錄卡同一取向，本地不收緊成枚舉）。
String _statusText(AppLocalizations l10n, String status) {
  return switch (status) {
    'active' => l10n.adminStatusActive,
    'disabled' => l10n.adminStatusDisabled,
    _ => status,
  };
}

/// 來源原字串 → 顯示文字；未知值原樣顯示。
String _typeText(AppLocalizations l10n, String accountType) {
  return switch (accountType) {
    'standard' => l10n.stdAccountTypeStandard,
    'guest' => l10n.stdAccountTypeGuest,
    _ => accountType,
  };
}

/// 以「年-月-日 時:分 UTC」呈現；與目錄卡同一寫法，不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}
