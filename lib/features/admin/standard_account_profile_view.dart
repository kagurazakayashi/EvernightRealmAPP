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
/// * 顯示名那一張表單的白名單只有一欄：憑據、來源類型與首次改密旗標在這裡沒有一格可以動
///   （本體多帶那些欄位會被後端打成 1004），界面也就不擺那些控制項。2013 只給
///   「重新讀取這份資料」的出口，不給「再點一次保存」的誘餌。
/// * 登入狀態走另一條白名單（`/status` 子資源，本體只有 status 與 expected_status）：
///   它動的是這個帳戶在整臺伺服器的登入能力——他現有的一切會話（所有裝置、所有活動）
///   會被撤銷、未來的登入會被拒，所以確認對話框必須先把目標與影響範圍講完。
///   按鈕只由服務端讀回的現狀決定；2014 另成一句並只給重讀出口。
/// * 登入憑據走第三條白名單（`/password` 子資源，本體只有 password 一欄）：它交付的是
///   操作者親自交的一次性口令，伺服器不生成也不回顯，因此界面在發出請求前就把輸入框清空，
///   成功之後口令不再出現在任何一處。「刻意沒有依據值」這條語意要講给操作者聽：
///   結果不明時再點一次不是重試，而是又做一次完整重置，所以這裡不擺自動補發。
///   訪戶帳戶不在這條通路的職責裡（後端以 2018 拒），界面據服務端讀回的來源欄位
///   說明「那要等後續那條明確的訪戶升級通路」，而不是讓他按下一顆註定被拒的按鈕。
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

  /// 停用按鈕識別鍵（active 時出現）。
  static const Key disableKey = ValueKey<String>('std-account-status-disable');

  /// 恢復按鈕識別鍵（disabled 時出現）。
  static const Key restoreKey = ValueKey<String>('std-account-status-restore');

  /// 影響範圍說明識別鍵。
  static const Key scopeHintKey = ValueKey<String>('std-account-status-scope');

  /// 確認對話框的肯定按鈕識別鍵。
  static const Key confirmKey = ValueKey<String>('std-account-status-confirm');

  /// 確認對話框的取消按鈕識別鍵。
  static const Key confirmCancelKey = ValueKey<String>(
    'std-account-status-cancel',
  );

  /// 狀態變更成功摘要識別鍵。
  static const Key statusNoticeKey = ValueKey<String>(
    'std-account-status-notice',
  );

  /// 表外狀態說明識別鍵。
  static const Key statusUnknownKey = ValueKey<String>(
    'std-account-status-unknown',
  );

  /// 一次性口令輸入框識別鍵。
  static const Key resetFieldKey = ValueKey<String>('std-account-reset-field');

  /// 憑據區影響範圍說明識別鍵（與狀態那區的範圍句分開：兩句話各自講各自的通路）。
  static const Key resetScopeKey = ValueKey<String>('std-account-reset-scope');

  /// 重置按鈕識別鍵。
  static const Key resetActionKey = ValueKey<String>(
    'std-account-reset-action',
  );

  /// 重置成功摘要識別鍵。
  static const Key resetNoticeKey = ValueKey<String>(
    'std-account-reset-notice',
  );

  /// 重置確認對話框的肯定按鈕識別鍵。
  static const Key resetConfirmKey = ValueKey<String>(
    'std-account-reset-confirm',
  );

  /// 重置確認對話框的取消按鈕識別鍵。
  static const Key resetConfirmCancelKey = ValueKey<String>(
    'std-account-reset-cancel',
  );

  /// 訪戶帳戶「沒有憑據可重置」的說明識別鍵。
  static const Key guestResetNoticeKey = ValueKey<String>(
    'std-account-reset-guest-notice',
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

  /// 狀態變更進行中（進行中不再發第二趟，也不與保存並發——两张卡動的是同一筆）。
  bool _statusChanging = false;

  /// 狀態變更的成功句：數字（撤銷了幾份會話）一律取自 PUT 回應。
  String? _statusNotice;

  /// 2014 之後兩顆狀態按鈕進入停用態：衝突的處置是重讀現狀，不是再點一次。
  bool _statusConflicted = false;

  /// 一次性口令只活在這一個控制器裡，且在發出請求前就清空（成功與失敗都不留）。
  final TextEditingController _resetPassword = TextEditingController();

  /// 重置進行中（進行中不再發第二趟，也不與另兩條白名單並發——三張卡動的是同一筆）。
  bool _resetting = false;

  /// 重置的成功句：撤銷數量一律取自 PUT 回應，而口令本身不在這句話裡。
  String? _resetNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _displayName.dispose();
    _resetPassword.dispose();
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
      _statusNotice = null;
      _statusConflicted = false;
      _resetNotice = null;
      _resetPassword.clear();
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

  /// 重置憑據的確認對話框：先把「動的是誰、三件效果、兩件不會發生、交付歸誰」講完
  /// 才准提交。取消是一條正經出路（一請求都不發，界面停在上一份伺服器真相）。
  /// 這裡沒有「重試」按鈕的位置：重置沒有依據值，對著不明的結果再點一次不是重試，
  /// 而是又做一次完整的重置——那會真的再撤一輪會話、再留一筆審計。
  Future<void> _confirmPasswordReset() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StandardAccountReport? profile = _profile;
    if (profile == null || _resetting) {
      return;
    }
    if (profile.isGuest) {
      // 服務端對訪戶只有一句 2018；界面先按服務端讀回的來源欄位把這句話講出來，
      // 不發一趟注定被拒的請求，也不假裝那是一欄可以填的口令。
      setState(() => _notice = l10n.stdAccountResetGuestNotice);
      return;
    }
    final String password = _resetPassword.text;
    if (password.trim().isEmpty) {
      // 本地只擋「明顯沒填」：口令的域規則由服務端判，界面不抄第二份。
      setState(() => _notice = l10n.adminResetFormIncompleteNotice);
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.stdAccountResetConfirmTitle),
        content: Text(l10n.stdAccountResetConfirmBody(profile.loginName)),
        actions: <Widget>[
          TextButton(
            key: StandardAccountProfileCard.resetConfirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminStatusConfirmCancelAction),
          ),
          FilledButton(
            key: StandardAccountProfileCard.resetConfirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminResetConfirmOkAction),
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
    await _applyPasswordReset(password);
  }

  /// 提交重置：口令在發出請求前就從輸入框清掉（成功與失敗都不留）；
  /// 成功展示與撤銷計數一律換成 PUT 回應，目錄跟著重讀；失敗則界面原地不動。
  Future<void> _applyPasswordReset(String password) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StandardAccountReport? profile = _profile;
    if (profile == null) {
      return;
    }
    setState(() {
      _resetting = true;
      _notice = null;
      _resetNotice = null;
      _resetPassword.clear();
    });
    try {
      final StandardAccountPasswordResetReport report = await widget.api
          .resetStandardAccountPassword(
            accountId: profile.accountId,
            password: password,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.account;
        _displayName.text = report.account.displayName;
        _resetting = false;
        // 成功句的數字來自回應；交付提醒不寫口令本身，只說「線下交付、界面不再顯示」。
        _resetNotice = l10n.stdAccountResetSuccessNotice(
          report.revokedSessions,
        );
      });
      widget.onSaved?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _resetting = false;
        _notice = _resetFailureText(error);
      });
    }
  }

  /// 重置失敗分流：1004 點名口令欄位給單獨一句、2018 是「訪戶今日沒有憑據可重置」，
  /// 1001／2011／會話那一簇各說各句。刻意沒有「衝突」這一支：本端點不設依據值，
  /// 重複提交不是被拒的陳舊嘗試，而是又做一次完整重置。
  String _resetFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'password' => l10n.adminResetInvalidPasswordNotice,
        _ => apiErrorText(l10n, error),
      };
    }
    return switch (code) {
      ApiMachineCode.guestUpgradeRequired => l10n.stdAccountResetGuestNotice,
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

  /// 停用／恢復的確認對話框：先把「動的是誰、影響範圍到哪、這不會發生什麼」講完
  /// 才準提交。取消是一條正經出路（一請求都不發，界面停在上一份伺服器真相）；
  /// 確認才發出 PUT——關掉別人整臺伺服器的登入能力不該有「手滑直达」的路徑。
  Future<void> _confirmStatusChange({
    required String targetStatus,
    required String currentStatus,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StandardAccountReport? profile = _profile;
    if (profile == null || _statusChanging) {
      return;
    }
    final bool disabling = targetStatus == 'disabled';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          disabling
              ? l10n.stdAccountStatusConfirmTitleDisable
              : l10n.stdAccountStatusConfirmTitleRestore,
        ),
        content: Text(
          disabling
              ? l10n.stdAccountStatusConfirmDisableBody(profile.loginName)
              : l10n.stdAccountStatusConfirmRestoreBody(profile.loginName),
        ),
        actions: <Widget>[
          TextButton(
            key: StandardAccountProfileCard.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminStatusConfirmCancelAction),
          ),
          FilledButton(
            key: StandardAccountProfileCard.confirmKey,
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
  /// 成功後的展示與撤銷計數一律換成 PUT 回應；失敗則界面原地不動，逐碼分流。
  Future<void> _applyStatusChange({
    required String targetStatus,
    required String currentStatus,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StandardAccountReport? profile = _profile;
    if (profile == null) {
      return;
    }
    setState(() {
      _statusChanging = true;
      _notice = null;
      _statusNotice = null;
      _statusConflicted = false;
    });
    try {
      final StandardAccountStatusReport report = await widget.api
          .updateStandardAccountStatus(
            accountId: profile.accountId,
            status: targetStatus,
            expectedStatus: currentStatus,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.account;
        _displayName.text = report.account.displayName;
        _statusChanging = false;
        // 成功句的數字來自回應：「這次讓 N 臺裝置重新登入」不許界面自己猜。
        _statusNotice = report.account.status == 'disabled'
            ? l10n.stdAccountStatusDisabledNotice(report.revokedSessions)
            : l10n.stdAccountStatusRestoredNotice;
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

  /// 狀態變更失敗分流：2014 要人重讀現狀並重新確認（與 2013 共用重讀出口、各自成句）、
  /// 1001 是目標根本不在這本目錄、2011 是主體不對，其餘交給機器碼的通用句。
  String _statusFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (error.knownCode) {
      ApiMachineCode.adminStatusConflict => l10n.stdAccountStatusConflictNotice,
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
    // 三條白名單動的是同一筆帳戶：並發提交會讓其中一條的依據值在送出那一刻就過期，
    // 因此這一張卡在任一寫入進行中都停住其餘入口。
    final bool busy =
        _savePhase == _SavePhase.saving || _statusChanging || _resetting;
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
          enabled: !_conflicted && !busy,
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
              onPressed: _conflicted || busy ? null : _save,
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
        const Divider(),
        // 登入狀態：另一條白名單（只有 status 一欄）、另一個確認語意。
        // 這裡動的是這個帳戶在整臺伺服器的登入能力，不是他在某一场活動裡的玩家限制——
        // 這句話必須寫在界面上，因為它決定了操作者按下去之後該期望什麼範圍的影響。
        Text(
          l10n.stdAccountStatusScopeHint,
          key: StandardAccountProfileCard.scopeHintKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        // 「動哪顆按鈕」只由伺服器讀回的現狀決定：表外值不長按鈕，
        // 也不拿「不是 disabled 就當 active」的推測去發一個註定落敗的請求。
        if (profile.isActive)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: StandardAccountProfileCard.disableKey,
              onPressed: busy || _statusConflicted
                  ? null
                  : () => _confirmStatusChange(
                      targetStatus: 'disabled',
                      currentStatus: profile.status,
                    ),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(
                _statusChanging
                    ? l10n.adminStatusWorkingHint
                    : l10n.adminStatusDisableAction,
              ),
            ),
          ),
        if (profile.isDisabled)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: StandardAccountProfileCard.restoreKey,
              onPressed: busy || _statusConflicted
                  ? null
                  : () => _confirmStatusChange(
                      targetStatus: 'active',
                      currentStatus: profile.status,
                    ),
              child: Text(
                _statusChanging
                    ? l10n.adminStatusWorkingHint
                    : l10n.adminStatusRestoreAction,
              ),
            ),
          ),
        if (!profile.isActive && !profile.isDisabled)
          Text(
            l10n.adminStatusUnsupportedNotice(profile.status),
            key: StandardAccountProfileCard.statusUnknownKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (_statusNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _statusNotice!,
              key: StandardAccountProfileCard.statusNoticeKey,
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_statusConflicted)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                key: StandardAccountProfileCard.reloadKey,
                onPressed: _load,
                child: Text(l10n.adminProfileReloadAction),
              ),
            ),
          ),
        const Divider(),
        // 登入憑據：第三條白名單（只有 password 一欄）、另一個確認語意。
        // 停用中的目標同樣可以重置（重置不是解除停用），所以這裡不按狀態分岔；
        // 但訪戶不按分岔的條件出局——他今日沒有密碼可換，寫一個進去是替他升級身分。
        Text(
          l10n.stdAccountResetScopeHint,
          key: StandardAccountProfileCard.resetScopeKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (profile.isGuest)
          Text(
            l10n.stdAccountResetGuestNotice,
            key: StandardAccountProfileCard.guestResetNoticeKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (!profile.isGuest) ...<Widget>[
          // 口令只存在這一個控制器裡：obscureText 全開、送出即清空，
          // 成功與失敗都不回填——界面上不會有第二處把這句話顯示出來。
          TextField(
            key: StandardAccountProfileCard.resetFieldKey,
            controller: _resetPassword,
            enabled: !busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n.adminResetPasswordFieldLabel,
              isDense: true,
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: StandardAccountProfileCard.resetActionKey,
              onPressed: busy ? null : _confirmPasswordReset,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(
                _resetting
                    ? l10n.adminResetWorkingHint
                    : l10n.adminResetPasswordAction,
              ),
            ),
          ),
        ],
        if (_resetNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _resetNotice!,
              key: StandardAccountProfileCard.resetNoticeKey,
              style: theme.textTheme.bodySmall,
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
