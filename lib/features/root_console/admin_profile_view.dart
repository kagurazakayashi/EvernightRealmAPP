/// 「Root 管理員詳情與編輯」卡：單筆真相的讀取、顯示名的白名單編輯與各種失敗分流。
///
/// 這張卡把「當前資料必須來自服務端保存結果」落在結構上：
///
/// * 底稿只有一個來源：构造時按標識 GET 詳情；目錄行只是入口，不做編輯底稿。
///   比較-and-set 的 expected_display_name 取的是「上一次從伺服器讀到的值」，
///   不是輸入框裡的字串——本地改到一半的內容沒有任何資格冒充現值。
/// * 保存成功後界面換成的仍是回應（PUT 回的是保存後的資料庫現值），不是請求的迴音；
///   保存失敗時界面維持上一份伺服器真相，一個欄位都不動——不存在樂觀 UI 的窗口。
/// * 衝突（2013）單獨成句並給「重讀這份資料」的出口：那是「你看見的已過期」，
///   與「存不進去」（5xx／連不上）與「你沒這個權限」（2011）是三句不同的話。
/// * 白名單只有顯示名：界面上沒有一個能改旗標、類型或口令的控件，
///   登入名如實標註「不在此處修改」——能力邊界由後端決定，界面只轉述。
/// * 停用與恢復是子資源 `/status` 上的另一條白名單，且必经確認對話框：
///   對話框如實講出目標、影響與「這不是刪除」；提交的 expected_status 取自
///   「上一次從伺服器讀到的現狀」，成功後界面換成的仍是回應；2014（狀態已變）
///   與 2013 同樣只給「重讀」的出口——對著舊畫面再點一次按鈕不是處置。
library;

import 'package:flutter/material.dart';

import '../../app/api_error_labels.dart';
import '../../core/api/api_error.dart';
import '../../core/api/server_api.dart';
import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../l10n/app_localizations.dart';

/// 詳情讀取階段。
enum _ProfilePhase { loading, ready, loadFailed }

/// 保存階段（與讀取階段分開：「正在保存」不降級成「載入中」）。
enum _SavePhase { idle, saving }

/// 管理員詳情與編輯卡。
class AdminProfileCard extends StatefulWidget {
  /// 按標識建立詳情卡；[onClosed] 關閉、[onSaved] 在保存成功後通知頁面重讀目錄。
  const AdminProfileCard({
    super.key,
    required this.api,
    required this.accountId,
    this.onClosed,
    this.onSaved,
  });

  /// 統一端點存取介面。
  final ServerApi api;

  /// 詳情與編輯的目標帳戶標識（來自目錄行的選擇，不是自報）。
  final String accountId;

  /// 關閉本卡的回呼。
  final VoidCallback? onClosed;

  /// 保存成功後的回呼：讓目錄那頁同步重讀，行與詳情不各留一份舊真相。
  final VoidCallback? onSaved;

  /// 標題識別鍵。
  static const Key titleKey = ValueKey<String>('admin-profile-title');

  /// 顯示名輸入框識別鍵。
  static const Key displayNameKey = ValueKey<String>('admin-profile-display');

  /// 保存按鈕識別鍵。
  static const Key submitKey = ValueKey<String>('admin-profile-save');

  /// 提示列（失敗與本地校驗共用）識別鍵。
  static const Key noticeKey = ValueKey<String>('admin-profile-notice');

  /// 保存成功摘要識別鍵。
  static const Key savedKey = ValueKey<String>('admin-profile-saved');

  /// 重讀詳情按鈕識別鍵。
  static const Key reloadKey = ValueKey<String>('admin-profile-reload');

  /// 停用登入按鈕識別鍵（僅目標現狀為 active 時出現）。
  static const Key disableKey = ValueKey<String>('admin-profile-disable');

  /// 恢復登入按鈕識別鍵（僅目標現狀為 disabled 時出現）。
  static const Key restoreKey = ValueKey<String>('admin-profile-restore');

  /// 確認對話框的肯定按鈕識別鍵。
  static const Key confirmKey = ValueKey<String>('admin-status-confirm');

  /// 確認對話框的取消按鈕識別鍵。
  static const Key confirmCancelKey = ValueKey<String>('admin-status-cancel');

  /// 狀態成功摘要識別鍵。
  static const Key statusNoticeKey = ValueKey<String>('admin-status-notice');

  /// 未知狀態提示識別鍵。
  static const Key statusUnknownKey = ValueKey<String>('admin-status-unknown');

  /// 載入中提示識別鍵。
  static const Key loadingKey = ValueKey<String>('admin-profile-loading');

  /// 關閉按鈕識別鍵。
  static const Key closeKey = ValueKey<String>('admin-profile-close');

  @override
  State<AdminProfileCard> createState() => _AdminProfileCardState();
}

class _AdminProfileCardState extends State<AdminProfileCard> {
  final TextEditingController _displayName = TextEditingController();

  _ProfilePhase _phase = _ProfilePhase.loading;
  _SavePhase _savePhase = _SavePhase.idle;

  /// 上一次從伺服器讀到的單筆真相；同時是 CAS 的依據值來源。
  AdminAccountReport? _profile;

  String? _notice;
  String? _savedNotice;

  /// 狀態變更的成功摘要（與顯示名保存分開：一句講改名，一句講撤了幾份會話）。
  String? _statusNotice;

  /// 上一次保存是否因現值過期而落敗：決定要不要露出「重讀」的出口。
  bool _conflicted = false;

  /// 狀態變更進行中：與顯示名保存各自獨立，但共用「處理中不得重複提交」的紀律。
  bool _statusChanging = false;

  /// 上一次狀態變更是否因現狀過期而落敗（2014）：同樣只給「重讀」的出口。
  bool _statusConflicted = false;

  /// 讀取失敗時也要能關閉本卡：失敗態不把人困在一張沒有出口的卡上。
  String? _loadFailureText;

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

  /// 讀取（或重讀）單筆詳情：成功時用回應內容填表，絕不用目錄行湊。
  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = _ProfilePhase.loading;
      _notice = null;
      _savedNotice = null;
    });
    try {
      final AdminDetailReport report = await widget.api.adminDetail(
        accountId: widget.accountId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.admin;
        _displayName.text = report.admin.displayName;
        _loadFailureText = null;
        _phase = _ProfilePhase.ready;
        // 成功讀回什麼就顯示什麼：這裡不清「保存失敗」的殘留提示以外的任何东西。
        _notice = null;
        _statusNotice = null;
        _statusConflicted = false;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadFailureText = _readFailureText(error);
        _phase = _ProfilePhase.loadFailed;
      });
    }
  }

  /// 讀取失敗分流：1001、2011、會話類與其他各說各句。
  String _readFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    return switch (code) {
      ApiMachineCode.notFound => l10n.adminProfileNotFoundNotice,
      ApiMachineCode.permissionDenied => l10n.adminProfileDeniedNotice,
      ApiMachineCode.notAuthenticated ||
      ApiMachineCode.sessionInvalid ||
      ApiMachineCode.sessionStale ||
      ApiMachineCode.passwordChangeRequired =>
        l10n.adminProfileStaleRejectedNotice,
      _ => l10n.adminProfileLoadFailedNotice,
    };
  }

  /// 保存顯示名：本地只擋空值，其余交服務端裁決；失敗逐碼分流。
  Future<void> _save() async {
    if (_savePhase == _SavePhase.saving) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AdminAccountReport? profile = _profile;
    if (profile == null) {
      return;
    }
    final String displayName = _displayName.text.trim();
    if (displayName.isEmpty) {
      setState(() => _notice = l10n.adminProfileFormIncompleteNotice);
      return;
    }

    setState(() {
      _savePhase = _SavePhase.saving;
      _notice = null;
      _savedNotice = null;
    });
    try {
      // CAS 的依據值取自「上一次讀到的伺服器真相」，不是輸入框：
      // 「我打算改成什麼」與「我看見的現值是什麼」必須是兩份資料。
      final AdminDetailReport report = await widget.api.updateAdminProfile(
        accountId: profile.accountId,
        displayName: displayName,
        expectedDisplayName: profile.displayName,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.admin;
        _displayName.text = report.admin.displayName;
        _savePhase = _SavePhase.idle;
        _conflicted = false;
        // 成功句裡的名字來自回應（含後端的空白整理），不是我送出前的那份。
        _savedNotice = l10n.adminProfileSavedNotice(report.admin.displayName);
      });
      widget.onSaved?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savePhase = _SavePhase.idle;
        _conflicted = error.knownCode == ApiMachineCode.profileConflict;
        _notice = _writeFailureText(error);
      });
    }
  }

  /// 保存失敗分流：界面在此之後顯示的仍是上一份伺服器真相。
  String _writeFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'display_name' => l10n.adminProfileInvalidDisplayNameNotice,
        _ => apiErrorText(l10n, error),
      };
    }
    return switch (code) {
      ApiMachineCode.profileConflict => l10n.adminProfileConflictNotice,
      ApiMachineCode.notFound => l10n.adminProfileNotFoundNotice,
      ApiMachineCode.permissionDenied => l10n.adminProfileDeniedNotice,
      ApiMachineCode.notAuthenticated ||
      ApiMachineCode.sessionInvalid ||
      ApiMachineCode.sessionStale ||
      ApiMachineCode.passwordChangeRequired =>
        l10n.adminProfileStaleRejectedNotice,
      _ => l10n.adminProfileUnavailableNotice,
    };
  }

  /// 停用／恢復的確認對話框：先把「動的是誰、會發生什麼、這不會發生什麼」講完，
  /// 才准提交。取消是一條正經出路（關閉對話框，界面停在上一份伺服器真相）；
  /// 確認才發出 PUT——敏感操作不該有「手滑直达」的路徑。
  Future<void> _confirmStatusChange({
    required String targetStatus,
    required String currentStatus,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AdminAccountReport? profile = _profile;
    if (profile == null || _statusChanging) {
      return;
    }
    final bool disabling = targetStatus == 'disabled';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          disabling
              ? l10n.adminStatusConfirmTitleDisable
              : l10n.adminStatusConfirmTitleRestore,
        ),
        content: Text(
          disabling
              ? l10n.adminStatusConfirmDisableBody(profile.loginName)
              : l10n.adminStatusConfirmRestoreBody(profile.loginName),
        ),
        actions: <Widget>[
          TextButton(
            key: AdminProfileCard.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminStatusConfirmCancelAction),
          ),
          FilledButton(
            key: AdminProfileCard.confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              disabling
                  ? l10n.adminStatusConfirmOkDisableAction
                  : l10n.adminStatusConfirmOkRestoreAction,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    await _applyStatusChange(
      targetStatus: targetStatus,
      currentStatus: currentStatus,
    );
  }

  /// 提交狀態變更：expected_status 取「上一次從伺服器讀到的現狀」，
  /// 成功後的展示與撤銷計數一律換成回應；失敗則界面原地不動，逐碼分流。
  Future<void> _applyStatusChange({
    required String targetStatus,
    required String currentStatus,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AdminAccountReport? profile = _profile;
    if (profile == null) {
      return;
    }
    setState(() {
      _statusChanging = true;
      _notice = null;
      _statusConflicted = false;
    });
    try {
      final AdminStatusReport report = await widget.api.updateAdminStatus(
        accountId: profile.accountId,
        status: targetStatus,
        expectedStatus: currentStatus,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.admin;
        _statusChanging = false;
        // 成功句的數字來自回應：「這次讓 N 臺裝置重新登入」不許界面自己猜。
        _statusNotice = report.admin.status == 'disabled'
            ? l10n.adminStatusDisabledNotice(report.revokedSessions)
            : l10n.adminStatusRestoredNotice;
      });
      widget.onSaved?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusChanging = false;
        _statusConflicted =
            error.knownCode == ApiMachineCode.adminStatusConflict;
        _notice = _statusFailureText(error);
      });
    }
  }

  /// 狀態變更失敗分流：2014 要人重讀現狀並重新確認，其餘各說各句。
  String _statusFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    return switch (code) {
      ApiMachineCode.adminStatusConflict => l10n.adminStatusConflictNotice,
      ApiMachineCode.notFound => l10n.adminProfileNotFoundNotice,
      ApiMachineCode.permissionDenied => l10n.adminProfileDeniedNotice,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _profile == null
                      ? l10n.adminProfileTitle('—')
                      : l10n.adminProfileTitle(_profile!.loginName),
                  key: AdminProfileCard.titleKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                key: AdminProfileCard.closeKey,
                onPressed: widget.onClosed,
                child: Text(l10n.adminProfileCloseAction),
              ),
            ],
          ),
          const SizedBox(height: 6),
          switch (_phase) {
            _ProfilePhase.loading => Text(
              l10n.adminProfileLoadingHint,
              key: AdminProfileCard.loadingKey,
              style: theme.textTheme.bodySmall,
            ),
            _ProfilePhase.loadFailed => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _loadFailureText ?? l10n.adminProfileLoadFailedNotice,
                  key: AdminProfileCard.noticeKey,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: AdminProfileCard.reloadKey,
                  onPressed: _load,
                  child: Text(l10n.adminProfileReloadAction),
                ),
              ],
            ),
            _ProfilePhase.ready => _readyBody(l10n, theme),
          },
        ],
      ),
    );
  }

  Widget _readyBody(AppLocalizations l10n, ThemeData theme) {
    final AdminAccountReport? profile = _profile;
    if (profile == null) {
      return const SizedBox.shrink();
    }
    final bool saving = _savePhase == _SavePhase.saving;
    final bool statusChanging = _statusChanging;
    // 「動哪個按鈕」只由伺服器讀回的現狀決定：界面不自創第三種狀態，
    // 也不在表外值（未來新狀態）上假裝按鈕仍然適用。
    final bool isActive = profile.status == 'active';
    final bool isDisabled = profile.status == 'disabled';
    final bool busy = saving || statusChanging;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.labelValuePair(l10n.adminListStatusLabel, profile.status),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminProfileRolesLabel,
            profile.roles.isEmpty ? '—' : profile.roles.join(', '),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.adminGrantedAtLabel,
            _formatUtcMinute(profile.grantedAt),
          ),
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
        Text(
          l10n.labelValuePair(l10n.adminAccountIdLabel, profile.accountId),
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
        if (profile.disabledAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.labelValuePair(
                l10n.adminStatusDisabledAtLabel,
                _formatUtcMinute(profile.disabledAt!),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 10),
        // 停用／恢復：狀態子資源的白名單通路。確認對話框講完目標與影響才提交；
        // 表外狀態不長按鈕——「不確定這算哪種狀態」時界面寧可只說一句實話。
        if (isActive)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: AdminProfileCard.disableKey,
              onPressed: busy
                  ? null
                  : () => _confirmStatusChange(
                      targetStatus: 'disabled',
                      currentStatus: profile.status,
                    ),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(
                statusChanging
                    ? l10n.adminStatusWorkingHint
                    : l10n.adminStatusDisableAction,
              ),
            ),
          ),
        if (isDisabled)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: AdminProfileCard.restoreKey,
              onPressed: busy
                  ? null
                  : () => _confirmStatusChange(
                      targetStatus: 'active',
                      currentStatus: profile.status,
                    ),
              child: Text(
                statusChanging
                    ? l10n.adminStatusWorkingHint
                    : l10n.adminStatusRestoreAction,
              ),
            ),
          ),
        if (!isActive && !isDisabled)
          Text(
            l10n.adminStatusUnsupportedNotice(profile.status),
            key: AdminProfileCard.statusUnknownKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          l10n.adminProfileLoginNameLockedHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: AdminProfileCard.displayNameKey,
          controller: _displayName,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: l10n.adminProfileDisplayNameLabel,
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: AdminProfileCard.submitKey,
            onPressed: busy ? null : _save,
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.adminProfileSubmitAction),
          ),
        ),
        if (_notice != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _notice!,
            key: AdminProfileCard.noticeKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          // 衝突語意給一條出路：重讀伺服器現值，之後再決定要不要再改。
          // 2013（顯示名過期）與 2014（狀態過期）共用這個出口：處置同形——重讀再說。
          if (_conflicted || _statusConflicted) ...<Widget>[
            const SizedBox(height: 6),
            OutlinedButton(
              key: AdminProfileCard.reloadKey,
              onPressed: () {
                setState(() {
                  _conflicted = false;
                  _statusConflicted = false;
                });
                _load();
              },
              child: Text(l10n.adminProfileReloadAction),
            ),
          ],
        ],
        if (_statusNotice != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _statusNotice!,
            key: AdminProfileCard.statusNoticeKey,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (_savedNotice != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _savedNotice!,
            key: AdminProfileCard.savedKey,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// 以「年-月-日 時:分 UTC」呈現，與目錄卡同一寫法：不做本機時區換算。
String _formatUtcMinute(DateTime utc) {
  final String iso = utc.toUtc().toIso8601String();
  return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
}
