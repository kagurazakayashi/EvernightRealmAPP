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
