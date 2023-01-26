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
/// * 重置憑據是子資源 `/password` 上的第三條白名單：本體只有新口令一欄，
///   刻意沒有依據值（Root 拿不出「現行口令」那類誠實錨點；重複提交是又做一次
///   完整重置，不是被拒的陳舊嘗試——所以結果不明時界面絕不自動重發）。
///   確認對話框講完三件效果（舊口令死、舊會話退出、首登必改密）與兩件「不會發生」
///   （不停用/不解除停用、不是刪除）才提交；口令欄 obscureText、送出即清空，
///   成功句的撤銷數量取自回應，交付提醒明確寫著「界面不會再次顯示它」。
/// * 刪除掛在詳情那條路徑的 DELETE 方法上，是第四條、也是最後一條寫入通路：
///   本體是空的，也沒有依據值欄位（第二次刪除回的是 2015「目標已被刪除」，
///   不是 2013/2014 那句「你依據的現值過期了」）。確認對話框要把四件事講完才准提交：
///   動的是誰、會發生什麼（停止新登入、撤銷有效會話、顯示名匿名化）、
///   不會發生什麼（不是停用、沒有恢復通路、登入名仍被佔用）、以及
///   為什麼人還留在目錄裡（既有審計要指回同一個身份）。
///   成功之後這張卡退出編輯態：四個寫入控件（改名、停用/恢復、重置、刪除）一律消失，
///   只留下服務端回傳的刪除後真相——把按鈕留在畫面上對著一個不再接受寫入的人，
///   比少一顆按鈕更糟。
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

  /// 重置口令輸入框識別鍵。
  static const Key resetFieldKey = ValueKey<String>('admin-reset-field');

  /// 重置按鈕識別鍵。
  static const Key resetActionKey = ValueKey<String>('admin-reset-action');

  /// 重置確認對話框肯定按鈕識別鍵。
  static const Key resetConfirmKey = ValueKey<String>('admin-reset-confirm');

  /// 重置確認對話框取消按鈕識別鍵。
  static const Key resetConfirmCancelKey = ValueKey<String>(
    'admin-reset-cancel',
  );

  /// 重置成功摘要識別鍵。
  static const Key resetNoticeKey = ValueKey<String>('admin-reset-notice');

  /// 刪除按鈕識別鍵（目標已被刪除時不再出現）。
  static const Key deleteKey = ValueKey<String>('admin-profile-delete');

  /// 刪除確認對話框的肯定按鈕識別鍵。
  static const Key deleteConfirmKey = ValueKey<String>('admin-delete-confirm');

  /// 刪除確認對話框的取消按鈕識別鍵。
  static const Key deleteConfirmCancelKey = ValueKey<String>(
    'admin-delete-cancel',
  );

  /// 刪除成功摘要識別鍵。
  static const Key deleteNoticeKey = ValueKey<String>('admin-delete-notice');

  /// 已刪除橫幅識別鍵（刪除態下這張卡對「他是誰」唯一的聲明）。
  static const Key deletedBannerKey = ValueKey<String>(
    'admin-profile-deleted-banner',
  );

  /// 已刪除態下的顯示名列識別鍵（佔位值也要如實列出，不能只剩登入名）。
  static const Key deletedDisplayNameKey = ValueKey<String>(
    'admin-profile-deleted-display-name',
  );

  /// 登入名仍被佔用的說明識別鍵（歷史身份保留的可見證據）。
  static const Key identityKeptKey = ValueKey<String>(
    'admin-profile-identity-kept',
  );

  /// 載入中提示識別鍵。
  static const Key loadingKey = ValueKey<String>('admin-profile-loading');

  /// 關閉按鈕識別鍵。
  static const Key closeKey = ValueKey<String>('admin-profile-close');

  @override
  State<AdminProfileCard> createState() => _AdminProfileCardState();
}

class _AdminProfileCardState extends State<AdminProfileCard> {
  final TextEditingController _displayName = TextEditingController();

  /// 重置口令輸入框的控制器：值只活在這一個欄位裡，送出即清空、不進任何展示與緩存。
  final TextEditingController _resetPassword = TextEditingController();

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

  /// 憑據重置進行中：與狀態變更同樣「處理中不得重複提交」——
  /// 對重置而言這不只是防手滑：每一次成功提交都是又做一次真實的重置。
  bool _resetting = false;

  /// 重置成功的摘要（帶伺服器回傳的撤銷數量）。
  String? _resetNotice;

  /// 刪除進行中。它不只是「防手滑」：刪除只允許成功一次，
  /// 界面上沒有一顆按鈕具備「再點一次還是同一件事」的正當含義。
  bool _deleting = false;

  /// 刪除成功的摘要（帶伺服器回傳的撤銷數量與那個時刻）。
  String? _deleteNotice;

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
    _resetPassword.dispose();
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
        // 重讀不把舊的重置句留在畫面上，也不讓口令殘留在欄位裡。
        _resetNotice = null;
        _resetPassword.clear();
        // 刪除句同樣不在重讀後殘留：它講的是「那一次操作撤了幾份會話」，
        // 而重讀之後畫面要說的是現在的真相。
        _deleteNotice = null;
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
      ApiMachineCode.adminDeleted => l10n.adminProfileDeletedNotice,
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
      ApiMachineCode.adminDeleted => l10n.adminProfileDeletedNotice,
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

  /// 重置憑據的確認對話框：先把「動的是誰、三件效果、兩件不會發生、交付歸誰」
  /// 講完才准提交。取消是一條正經出路（一請求都不發）；這裡沒有「重試」按鈕的
  /// 位置——重置沒有依據值，對著不明結果再點一次不是重試，而是又做一次。
  Future<void> _confirmPasswordReset() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AdminAccountReport? profile = _profile;
    if (profile == null || _resetting) {
      return;
    }
    final String password = _resetPassword.text;
    if (password.trim().isEmpty) {
      setState(() => _notice = l10n.adminResetFormIncompleteNotice);
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.adminResetConfirmTitle),
        content: Text(l10n.adminResetConfirmBody(profile.loginName)),
        actions: <Widget>[
          TextButton(
            key: AdminProfileCard.resetConfirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminStatusConfirmCancelAction),
          ),
          FilledButton(
            key: AdminProfileCard.resetConfirmKey,
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
  /// 成功展示與撤銷計數一律換成 PUT 回應，目錄跟著重讀；失敗界面原地不動。
  Future<void> _applyPasswordReset(String password) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AdminAccountReport? profile = _profile;
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
      final AdminPasswordResetReport report = await widget.api
          .resetAdminPassword(
            accountId: profile.accountId,
            password: password,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.admin;
        _resetting = false;
        // 成功句的數字來自回應；交付提醒不寫口令本身，只說「線下交付、界面不再顯示」。
        _resetNotice = l10n.adminResetSuccessNotice(report.revokedSessions);
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

  /// 重置失敗分流：1004 點名口令欄位給單獨一句，目標與權限各說各句。
  /// 刻意沒有「衝突」這一支：本端點不設依據值，重複提交不是被拒的陳舊嘗試。
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
      ApiMachineCode.adminDeleted => l10n.adminProfileDeletedNotice,
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

  /// 刪除的確認對話框：這是本張卡裡唯一不可逆的一條通路，所以確認把四段話講完——
  /// 動的是誰、會發生什麼、不會發生什麼、以及「為什麼他還留在目錄裡」。
  ///
  /// 取消是一條正經出路（一請求都不發）；這裡刻意不放任何「我已知悉風險」的勾選框：
  /// 勾選會讓人以為點確認只是繼續下一步，而這個對話框本身就是最後一道把手。
  /// 界面上也不留「重試」的位置——刪除沒有依據值，對著一個已被刪除的人再點一次
  /// 不是重試，而是對一個不再接受寫入的對象再下一次命令。
  Future<void> _confirmDelete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AdminAccountReport? profile = _profile;
    if (profile == null || _deleting) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.adminDeleteConfirmTitle),
        content: Text(l10n.adminDeleteConfirmBody(profile.loginName)),
        actions: <Widget>[
          TextButton(
            key: AdminProfileCard.deleteConfirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminStatusConfirmCancelAction),
          ),
          FilledButton(
            key: AdminProfileCard.deleteConfirmKey,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminDeleteConfirmOkAction),
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
    await _applyDelete();
  }

  /// 提交刪除：DELETE 沒有本體也沒有依據值；成功的展示一律換成回應，
  /// 並且立刻通知頁面重讀目錄——行與詳情不能各留一份舊真相。
  ///
  /// 成功後這張卡退出編輯態（見 _readyBody 的 isDeleted 分岔）：保留卡片是為了
  /// 讓 Root 看得見「現在他是什麼」，把四顆寫入按鈕留在畫面上則是另一件事——
  /// 那等於界面還在假裝這個人可以被改。
  Future<void> _applyDelete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AdminAccountReport? profile = _profile;
    if (profile == null) {
      return;
    }
    setState(() {
      _deleting = true;
      _notice = null;
      _deleteNotice = null;
    });
    try {
      final AdminDeleteReport report = await widget.api.deleteAdmin(
        accountId: profile.accountId,
        acceptLanguage: _acceptLanguage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.admin;
        _deleting = false;
        // 改名用的那份底稿從此沒有意義：顯示名已是佔位值，輸入框留著只會讓人
        // 以為還能改。清掉它與退出編輯態是同一件事的兩面。
        _displayName.clear();
        _savedNotice = null;
        _statusNotice = null;
        _resetNotice = null;
        _resetPassword.clear();
        // 撤銷數量來自回應：「這次讓 N 臺裝置失去登入狀態」不許界面自己猜。
        _deleteNotice = l10n.adminDeleteSuccessNotice(report.revokedSessions);
      });
      widget.onSaved?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deleting = false;
        _notice = _deleteFailureText(error);
      });
    }
  }

  /// 刪除失敗分流：2015（已是刪除態）與 1001（不在目錄）各說各句，
  /// 後者該換目標、前者該停手——把兩者混成一句，客戶端只剩「再點一次」這把錘子。
  String _deleteFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      // 刪除不該帶任何欄位：會走到這一句代表送出了一個不存在的「選項」，
      // 點名它比假裝沒看見誠實。
      final Object? field = error.details?['field'];
      return switch (field) {
        null || '' => l10n.adminDeleteNoFieldNotice,
        _ => l10n.adminDeleteNoFieldNotice,
      };
    }
    return switch (code) {
      ApiMachineCode.adminDeleted => l10n.adminDeleteAlreadyNotice,
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
    final bool resetting = _resetting;
    final bool deleting = _deleting;
    // 「動哪個按鈕」只由伺服器讀回的現狀決定：界面不自創第三種狀態，
    // 也不在表外值（未來新狀態）上假裝按鈕仍然適用。
    final bool isActive = profile.status == 'active';
    final bool isDisabled = profile.status == 'disabled';
    // 刪除態是第四種、也是唯一不可寫的狀態：它不靠「排掉 active/disabled」推出來，
    // 而是直接認服務端回傳的狀態字串（isDeleted）。
    final bool isDeleted = profile.isDeleted;
    final bool busy = saving || statusChanging || resetting || deleting;
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
        if (isDeleted) ...<Widget>[
          // 已刪除態下這張卡不提供任何寫入控件：他不能改名、不能被停用或恢復、
          // 也不該被重置口令——四個入口在服務端都回同一句 2015，界面若在畫面上
          // 留著那四顆按鈕，就是在假裝這個對象還可以被改。
          const SizedBox(height: 10),
          // 顯示名仍要如實列出——它是服務端給的佔位值，不是本地殘稿。
          // 少了這一行，「活的投影長什麼樣」就只剩標題上的登入名可看。
          Text(
            l10n.labelValuePair(
              l10n.adminProfileDisplayNameLabel,
              profile.displayName,
            ),
            key: AdminProfileCard.deletedDisplayNameKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            profile.deletedAt == null
                ? l10n.adminProfileDeletedBanner
                : l10n.adminProfileDeletedBannerAt(
                    _formatUtcMinute(profile.deletedAt!),
                  ),
            key: AdminProfileCard.deletedBannerKey,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 6),
          // 「為什麼人還留在目錄裡」是這一態唯一需要解釋的事：留行不是遺漏，
          // 而是讓既有審計與記錄仍能指回同一個身份。
          Text(
            l10n.adminProfileIdentityKeptHint,
            key: AdminProfileCard.identityKeptKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ] else ...<Widget>[
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
          const SizedBox(height: 10),
          // 重置憑據：憑據子資源的白名單通路。輸入框只存在這一個控制器裡、
          // obscureText 全開、送出即清空；確認對話框講完效果與「不會發生」才提交。
          // 停用中的目標同樣可以重置（重置不是解除停用），所以這裡不按狀態分岔。
          TextField(
            key: AdminProfileCard.resetFieldKey,
            controller: _resetPassword,
            enabled: !busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n.adminResetPasswordFieldLabel,
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: AdminProfileCard.resetActionKey,
              onPressed: busy ? null : _confirmPasswordReset,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(
                resetting
                    ? l10n.adminResetWorkingHint
                    : l10n.adminResetPasswordAction,
              ),
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
          const SizedBox(height: 14),
          // 刪除：第四條寫入通路，也是唯一不可逆的一條。它放在最後、標成危險色，
          // 而且確認對話框要把「這不是停用」講明白——兩者對界面的差別只有一句話：
          // 停用留有回歸的路，刪除沒有。
          Text(
            l10n.adminDeleteZoneHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: AdminProfileCard.deleteKey,
              onPressed: busy ? null : _confirmDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(
                deleting ? l10n.adminDeleteWorkingHint : l10n.adminDeleteAction,
              ),
            ),
          ),
        ],
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
        if (_resetNotice != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _resetNotice!,
            key: AdminProfileCard.resetNoticeKey,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (_deleteNotice != null) ...<Widget>[
          const SizedBox(height: 8),
          // 刪除成功的句子帶伺服器回傳的撤銷數量：這不是安慰話，
          // 而是「幾臺裝置此刻已失去登入狀態」的唯一權威數字。
          Text(
            _deleteNotice!,
            key: AdminProfileCard.deleteNoticeKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
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
