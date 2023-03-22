/// 結構化錯誤到介面文案的唯一映射。
///
/// 決定（依後端合同與本地化基線）：介面顯示的錯誤文字一律取自本地化資源，
/// 伺服器隨 `Accept-Language` 回傳的 `message` **不直接顯示**——它由後端的語言
/// 資源產出，與使用者此刻選定的介面語言未必一致。機器錯誤碼優先於失敗類別，
/// 因為它講得更準；未收錄的數值（後續 2xxx／3xxx 分段）退回類別文字，
/// 而數值本身一定出現在診斷行，不會因為前端不認得就被吞掉。
library;

import '../core/api/api_error.dart';
import '../l10n/app_localizations.dart';

/// 取得一次失敗請求的介面文字。
String apiErrorText(AppLocalizations l10n, ApiError error) {
  final ApiMachineCode? code = error.knownCode;
  if (code != null) {
    return switch (code) {
      ApiMachineCode.internalError => l10n.errorCodeInternal,
      ApiMachineCode.notFound => l10n.errorCodeNotFound,
      ApiMachineCode.methodNotAllowed => l10n.errorCodeMethodNotAllowed,
      ApiMachineCode.payloadTooLarge => l10n.errorCodePayloadTooLarge,
      ApiMachineCode.invalidBody => l10n.errorCodeInvalidBody,
      ApiMachineCode.unsupportedMediaType => l10n.errorCodeUnsupportedMediaType,
      ApiMachineCode.requestTimeout => l10n.errorCodeRequestTimeout,
      ApiMachineCode.notReady => l10n.errorCodeNotReady,
      ApiMachineCode.invalidCredentials => l10n.errorCodeInvalidCredentials,
      ApiMachineCode.notAuthenticated => l10n.errorCodeNotAuthenticated,
      ApiMachineCode.sessionInvalid => l10n.errorCodeSessionInvalid,
      ApiMachineCode.authMethodConflict => l10n.errorCodeAuthMethodConflict,
      ApiMachineCode.originForbidden => l10n.errorCodeOriginForbidden,
      ApiMachineCode.loginThrottled => l10n.errorCodeLoginThrottled,
      ApiMachineCode.sessionStale => l10n.errorCodeSessionStale,
      ApiMachineCode.deviceLimitReached => l10n.errorCodeDeviceLimitReached,
      ApiMachineCode.deviceNotFound => l10n.errorCodeDeviceNotFound,
      ApiMachineCode.passwordChangeRequired =>
        l10n.errorCodePasswordChangeRequired,
      ApiMachineCode.permissionDenied => l10n.errorCodePermissionDenied,
      ApiMachineCode.loginNameTaken => l10n.errorCodeLoginNameTaken,
      ApiMachineCode.profileConflict => l10n.errorCodeProfileConflict,
      ApiMachineCode.adminStatusConflict => l10n.errorCodeAdminStatusConflict,
      ApiMachineCode.adminDeleted => l10n.errorCodeAdminDeleted,
      ApiMachineCode.accountPolicyModeUnavailable =>
        l10n.errorCodeAccountPolicyModeUnavailable,
      ApiMachineCode.accountCreationDisabled =>
        l10n.errorCodeAccountCreationDisabled,
      ApiMachineCode.guestUpgradeRequired => l10n.errorCodeGuestUpgradeRequired,
      ApiMachineCode.guestNotUpgradable => l10n.errorCodeGuestNotUpgradable,
      ApiMachineCode.bindTicketInvalid => l10n.errorCodeBindTicketInvalid,
      ApiMachineCode.bindPlanStale => l10n.errorCodeBindPlanStale,
      // 2027／2028 是普通帳戶那本目錄的兩句終態拒絕：兩者都只讓人停手重讀，
      // 但退休那句要順帶指出該查的是綁定留痕，否則操作者會去翻刪除記錄。
      ApiMachineCode.accountDeleted => l10n.errorCodeAccountDeleted,
      ApiMachineCode.accountRetired => l10n.errorCodeAccountRetired,
      ApiMachineCode.selfRegisterNameTaken =>
        l10n.errorCodeSelfRegisterNameTaken,
      ApiMachineCode.notAnApplication => l10n.errorCodeNotAnApplication,
      ApiMachineCode.applicationDecided => l10n.errorCodeApplicationDecided,
      ApiMachineCode.inviteAlreadyRevoked => l10n.errorCodeInviteAlreadyRevoked,
      ApiMachineCode.inviteCodeRejected => l10n.errorCodeInviteCodeRejected,
      // 2029～2032 是活動域的三句拒絕加一句終態：四种处置各不相同——
      // 終態要停手、現值過期要重讀、路徑不存在要改意圖、重複指派要換目標。
      ApiMachineCode.activityArchived => l10n.errorCodeActivityArchived,
      ApiMachineCode.activityStatusConflict =>
        l10n.errorCodeActivityStatusConflict,
      ApiMachineCode.activityTransitionInvalid =>
        l10n.errorCodeActivityTransitionInvalid,
      ApiMachineCode.activityManagerTaken => l10n.errorCodeActivityManagerTaken,
      // 2033／2034 是陣營通路的两句：停止是「等重開」（與 2029 的終態分得開），
      // 重名是「換個名字」（與 1001 的換目標分得開）。
      ApiMachineCode.activityClosedWrites => l10n.errorCodeActivityClosedWrites,
      ApiMachineCode.factionNameTaken => l10n.errorCodeFactionNameTaken,
      // 2035 是名冊那一句「他已經是成員了」：處置是去編輯那份既有檔案，
      // 既不是換目標（1001）也不是重讀現值再按一次（2013）。
      ApiMachineCode.activityMemberTaken => l10n.errorCodeActivityMemberTaken,
      // 2036～2039 是玩家自選陣營的四句拒絕，處置四樣都不同：
      // 換一個還開著的陣營（2036）、等管理人打開那一欄配置（2037）、等活動開放（2038）、
      // 這件事已由自己選過一次而自助不再可改（2039）。把任何兩句併在一起都會
      // 讓人對著一顆根本不會變亮的按鈕再按一次。
      ApiMachineCode.factionNotAcceptingMembers =>
        l10n.errorCodeFactionNotAcceptingMembers,
      ApiMachineCode.factionSelectDisabled =>
        l10n.errorCodeFactionSelectDisabled,
      ApiMachineCode.factionSelectNotOpen => l10n.errorCodeFactionSelectNotOpen,
      ApiMachineCode.factionSelectLockedIn =>
        l10n.errorCodeFactionSelectLockedIn,
    };
  }

  return switch (error.kind) {
    ApiErrorKind.notConfigured => l10n.errorKindNotConfigured,
    ApiErrorKind.unreachable => l10n.errorKindUnreachable,
    ApiErrorKind.timeout => l10n.errorKindTimeout,
    ApiErrorKind.httpStatus => l10n.errorKindHttpStatus,
    ApiErrorKind.invalidResponse => l10n.errorKindInvalidResponse,
  };
}
