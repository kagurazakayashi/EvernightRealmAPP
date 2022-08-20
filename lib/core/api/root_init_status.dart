/// 首次啟動引導的狀態判定：把「初始化狀態端點的回答」或「它沒回答」收斂成
/// 一個介面能直接照著分支的列舉。
///
/// 分成兩個判定函式而不是回一個帶可空欄位的物件，是因為這裡的每一個值都必須
/// 對應到一句真話：介面拿到 `initialized` 就准說「已完成初始化」，拿到 `unknown`
/// 就只能說「這次的結果不明確」。會出事的錯法是「查不到但照樣顯示一個狀態」，
/// 而那正是把可空欄位攤給頁面自己判斷時最容易發生的一件事。
///
/// 本檔不保存任何語言的顯示字串（DEC-017）；文字一律由元件向本地化資源取得。
library;

import 'api_error.dart';
import 'server_models.dart';

/// 引導卡片目前所處的階段。
enum RootInitPhase {
  /// 基準位址尚未設定或格式不合格，狀態無從查起。
  notConfigured,

  /// 查詢進行中。
  checking,

  /// 伺服器可達且回報「還沒有 Root」：本頁因此顯示本機的初始化步驟。
  uninitialized,

  /// 伺服器可達且回報已有 Root 憑據：初始化那扇門已經關上，本頁不再提供步驟。
  initialized,

  /// 連不上伺服器（離線、服務未啟動、位址不可達、逾時）：狀態因此無從得知。
  ///
  /// 這與「尚未初始化」必須分開講——前者叫人已去查網路，後者叫人去跑命令；
  /// 混為一談時操作者會對著一個根本沒啟動的服務嘗試初始化。
  unreachable,

  /// 伺服器有回應，但拒絕把狀態交給這個呼叫端。
  ///
  /// 本步的端點是匿名可讀的，正常部署下不會走到這裡；會出現的原因是部署把這個
  /// 路徑放進了需要身分或需要來源的策略之後（中介層、未來加的閘門）。
  /// 那個時候畫面要講的是「伺服器不肯說」，不是「還沒有 Root」。
  forbidden,

  /// 伺服器答了但這次的結果不可信（內容與合同不符，或回的是其他錯誤）。
  ///
  /// 這個階段的處置只有一個：再問一次。它刻意不重複任何「寫」的動作——
  /// 初始化結果不明時反覆提交才是危險的那件事，而本應用根本沒有提交通路。
  unknown,
}

/// 把一次成功的狀態查詢換成介面階段。
///
/// 只看 `root_initialized` 這一欄：`configExists` 決定的是「未初始化」那一句
/// 要怎麼講（有沒有組態檔是兩句不同的指引），由元件另外讀，不在這裡折合成第三種階段。
RootInitPhase classifyInitStatus(InitStatusReport report) {
  return report.rootInitialized
      ? RootInitPhase.initialized
      : RootInitPhase.uninitialized;
}

/// 把一次失敗的狀態查詢換成介面階段。
///
/// 分界只有一條：伺服器到底有沒有回話。
/// 沒回話（連不上、逾時）是 `unreachable`；回了話但內容不可信是 `unknown`；
/// 回話且明確指出「這個呼叫端不該拿到答案」才是 `forbidden`。
/// 判定以 [ApiError.kind]（在哪一步失敗）為準，不以「有沒有 HTTP 狀態碼」為準：
/// 後者只是前者的副產品，拿它當依據會把「200 但內容對不上合同」折進連不上，
/// 於是一張「查不到」的卡片同時掩蓋了「服務沒開」與「合同的這一欄不合」
/// 兩件完全不同的事，而操作者對這兩件事該做的動作並不一樣。
///
/// 其餘的 HTTP 錯誤（路徑不存在、方法不支援、伺服器內部故障）一律收斂成
/// `unknown` 而不另造第四種狀態：介面對它們的處置本來就一樣——再問一次，
/// 或去查那個部署到底怎麼裝的。
RootInitPhase classifyInitStatusFailure(ApiError error) {
  if (error.kind == ApiErrorKind.notConfigured) {
    return RootInitPhase.notConfigured;
  }
  if (error.kind == ApiErrorKind.unreachable ||
      error.kind == ApiErrorKind.timeout) {
    return RootInitPhase.unreachable;
  }
  if (error.kind == ApiErrorKind.invalidResponse) {
    return RootInitPhase.unknown;
  }
  final ApiMachineCode? code = error.knownCode;
  if (code == ApiMachineCode.notAuthenticated ||
      code == ApiMachineCode.sessionInvalid ||
      code == ApiMachineCode.originForbidden) {
    return RootInitPhase.forbidden;
  }
  final int status = error.httpStatus ?? 0;
  if (status == 401 || status == 403) {
    return RootInitPhase.forbidden;
  }
  return RootInitPhase.unknown;
}
