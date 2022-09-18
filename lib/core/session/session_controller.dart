/// 會話狀態的唯一持有者：把「我是誰、這身分屬於哪台伺服器、憑據放哪、換伺服器怎麼辦」
/// 全部收在一處，頁面只讀它的狀態、只在登入／退出流程呼叫它的方法。
///
/// 為什麼必須有這一個物件，而不是讓每個畫面自己去碰 Cookie／令牌／儲存：
/// * 平台分支只有一处——瀏覽器端會話由 HttpOnly Cookie 代管，本層既不讀也不寫任何
///   令牌；原生端秘密經 [SessionPersistence] 保存，並透過 [bearerFor] 回饋給傳輸層注入。
/// * 伺服器隔離只有一处——秘密以「正規化伺服器身份」為鍵保存與取用，位址一變就清空
///   舊憑據與活動上下文，結構上排除了「把甲伺服器的憑據發給乙伺服器」。
/// * 狀態只有一组——[SessionStatus] 的五个值由本層依 `/auth/session` 的結果與本機
///   憑據存在與否判定，復用 [ApiError] 的機器碼映射，不在各畫面重新发明「算不算登入」。
///
/// 两条刻意守住的安全界線：
/// * 儲存／恢复失敗绝不静默当成「未登入」也不降级成明文：前者會把人誤踢，后者直接
///   洩密。读失败时状态停在 [SessionStatus.unknown] 並記下 [lastStorageFailure]，由後續
///   的界面据实提示，控制器不會替伺服器编造一个「你没登录」。
/// * 退出（[signOut]）先向服务器请求撤销、再清本机：Web 端由后端下发删除指令清掉
///   HttpOnly Cookie，原生端删除该服务器的安全储存。网络失败时如实回报
///   [SessionSignOutOutcome.serverUnconfirmed]——本機已清理，但服务端撤销未确认，
///   绝不谎称「已在服务器登出」，也不暗示「所有设备已下线」。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/server_address.dart';
import '../api/server_address_settings.dart';
import '../api/server_api.dart';
import '../api/server_models.dart';
import 'session_persistence.dart';
import 'session_status.dart';

/// 一次登入提交的處置結果，讓呼叫端知道「登入了，但秘密有没有留住」。
enum SessionLoginOutcome {
  /// 已登入，且（原生端）秘密已写入安全儲存。
  established,

  /// 已登入但秘密未能持久化：本次运行仍可用（記憶體中有秘密），重啟後需重新登入。
  ///
  /// 這是刻意分开的一档：把「存不住」和「没登入」混为一谈，會讓界面既骗了使用者
  /// 也騙了後續的恢复流程；這裡如实回報，交由界面提示，且绝不降级成明文保存。
  persistenceFailed,

  /// 原生端沒拿到可保存的秘密（平台读不到 `Set-Cookie`），無法建立原生會話。
  ///
  /// 這属环境不符而非登入被拒：後端已签发會話，但本端拿不到可回傳的憑據，
  /// 只能如实標为「無法確定」，不谎报已登入。
  missingCredential,
}

/// 一次退出請求的處置結果，讓呼叫端知道「伺服器有沒有確認撤銷」。
///
/// 之所以把登出結果分成兩档而不是只回 void，是因为「本機清幹淨了」與「伺服器上那個
/// 會話現在是不是還活著」是兩件不同的事：把前者当成後者，會讓界面在離線或 500 的時候
/// 谎报「已登出」——這正是规格禁止的「把失败呈现为成功」。
enum SessionSignOutOutcome {
  /// 伺服器已確認撤銷：本次登出所綁定的那一枚會話在服务端已失效，且（Web）Cookie
  /// 收到删除指令、（原生）本机保存的秘密也已清除。
  revoked,

  /// 本机凭据与状态已清理，但服务器撤销未确认：连不上、逾时、未就绪或伺服器
  /// 回了非冪等成功以外的错误。此刻不能宣称已在服务器登出，也不能声称
  /// 「所有设备已下线」——退出只针对本请求凭据指向的那一枚会话。
  serverUnconfirmed,
}

/// 已登入會話的可展示事实（不含任何秘密）。
///
/// 欄位全部取自伺服器權威回應，與 [LoginReport]／[CurrentSessionReport] 的合同一致；
/// 這裡没有任何一个欄位是「記得不要顯示」的秘密，因为模型層根本不保存秘密。
class ActiveSession {
  /// 以主體事實建立一份活动會話。
  const ActiveSession({
    required this.subjectKind,
    required this.accountId,
    required this.deviceId,
    required this.expiresAt,
  });

  /// 由登入回應建立。
  ActiveSession.fromLogin(LoginReport report)
    : this(
        subjectKind: report.subjectKind,
        accountId: report.accountId,
        deviceId: report.deviceId,
        expiresAt: report.expiresAt,
      );

  /// 由「當前會話」回應建立。
  ActiveSession.fromCurrentSession(CurrentSessionReport report)
    : this(
        subjectKind: report.subjectKind,
        accountId: report.accountId,
        deviceId: report.deviceId,
        expiresAt: report.expiresAt,
      );

  /// 主體類別（帳戶或 Root）。
  final AuthSubjectKind subjectKind;

  /// 帳戶標識；Root 主體為 `null`。
  final String? accountId;

  /// 可安全展示與保存的設備標識。
  final String deviceId;

  /// 會話到期時刻（UTC，取自伺服器）。
  final DateTime expiresAt;

  /// 是否為 Root 主體。
  bool get isRoot => subjectKind == AuthSubjectKind.root;
}

/// 會話狀態控制器（可訂閱）。
class SessionController extends ChangeNotifier {
  /// 以端點介面、位址設定、傳輸形态與（原生端必需的）持久化協定建立控制器。
  ///
  /// [addresses] 被訂閱：位址一變就作廢当前會話，與連線追蹤器同一條失效規則。
  /// 原生形态必給 [persistence]，否则建立秘密保存無處可去——寧可在組装期就失败，
  /// 也不讓秘密悄悄退化進不安全的儲存。
  SessionController({
    required this._api,
    required this._addresses,
    required SessionTransportMode mode,
    SessionPersistence? persistence,
  }) : assert(
         mode == SessionTransportMode.web || persistence != null,
         '原生形态必须提供会话持久化实作',
       ),
       _mode = mode,
       _persistence = persistence {
    _addresses.addListener(_onAddressChanged);
  }

  final ServerApi _api;
  final ServerAddressSettings _addresses;
  final SessionTransportMode _mode;
  final SessionPersistence? _persistence;

  SessionStatus _status = SessionStatus.unknown;
  ServerAddress? _bound;
  String? _secret;
  ActiveSession? _active;
  String? _activityScope;
  Object? _lastStorageFailure;

  // 會話上下文的「世代」：登出與位址切換都讓它 +1，讓在途的驗證／登出請求在回來時
  // 能認出自己描述的是「上一代」的憑據，從而不把已过时的结果盖回当前状态。
  // 這是「退出時清理未完成請求」的落點：沒有了它，一次在途的 restore 完成時會把
  // 已經登出的界面拉回 signedIn。
  int _generation = 0;

  /// 目前會話狀態。
  SessionStatus get status => _status;

  /// 是否處於已登入。
  bool get isSignedIn => _status == SessionStatus.signedIn;

  /// 已登入時的主體事实；未登入時為 `null`。
  ActiveSession? get activeSession => _active;

  /// 当前會話綁定的伺服器身份（正規化文字）；未綁定時為 `null`。
  String? get boundServerDisplay => _bound?.displayText;

  /// 是否為瀏覽器形态（會話由 Cookie 代管，本層从不經手令牌）。
  bool get isWebTransport => _mode == SessionTransportMode.web;

  /// 最近一次安全儲存／恢复失败的原因；没有失敗時為 `null`。
  ///
  /// 界面据它提示「無法保存／读取登录状态」，但絕不代表已登出或降级为明文。
  Object? get lastStorageFailure => _lastStorageFailure;

  /// 与当前会話を綁定的活動上下文標識；本步不填充，留给活动业务步骤。
  ///
  /// 之所以先占这个位，是为了兑现「换伺服器要清空旧的活动上下文」：活动步骤只需
  /// 在这里写入，切换与登出会自动清空，无须各畫面各自决定哪些资料属于当前伺服器。
  String? get activityScope => _activityScope;

  /// 供傳輸層在每次發出请求前呼叫：只在「请求要打去的伺服器身份」正是本會話綁定的
  /// 那台、且處於原生形态且手上有秘密時，才回傳秘密。
  ///
  /// 任何一条不满足都回 `null`，其中「身份对不上」就是杜绝跨服务器泄漏的那道闸——
  /// 即使调用方拿错地址，也不会把甲伺服器的秘密当成乙伺服器的憑據交出去。
  String? bearerFor(String serverIdentity) {
    if (_mode != SessionTransportMode.native) {
      return null;
    }
    final String? secret = _secret;
    final ServerAddress? bound = _bound;
    if (secret == null || bound == null) {
      return null;
    }
    if (bound.displayText != serverIdentity) {
      return null;
    }
    return secret;
  }

  /// 啟動时恢复既存會話：读本機憑據、向伺服器确认，再把结果写进状态。
  ///
  /// 浏览器端没有可读的本地憑據（Cookie 在 HttpOnly 空间），直接以「带凭据询问」
  /// 确认；原生端先从安全儲存取秘密，取到了才去确认。两条路径都用同一个
  /// [ServerApi.currentSession]，凭据的注入由传输层按形态与身份自行决定。
  /// 本方法不抛異常——一切失败都收敛为状态与 [lastStorageFailure]。
  Future<void> restore() async {
    final ServerAddress? address = _api.config.address;
    if (address == null) {
      _clearLocalSession();
      _status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }

    if (_mode == SessionTransportMode.web) {
      // 不读、不写任何令牌；把当前来源的 Cookie 交给浏览器自动附带，直接向服务器求证。
      _clearLocalSession();
      _status = SessionStatus.verifying;
      notifyListeners();
      await _verify(address);
      return;
    }

    final SessionPersistence persistence = _persistence!;
    // 先把狀態推進「驗證中」再去讀儲存：讀取本身也是一次 await，狀態不提前
    // 落位的話，啟動的第一幀會先閃一下「無法確定」才改口「驗證中」，
    // 讓人在最該穩定呈現的瞬間看到一句多餘的話。
    _status = SessionStatus.verifying;
    notifyListeners();
    String? secret;
    try {
      secret = await persistence.readSecret(address.displayText);
    } catch (error) {
      // 读取失败不等于「没登录」：宁停在未知并记录原因，也不替服务器编造结论把人踢出。
      _clearLocalSession();
      _lastStorageFailure = error;
      _status = SessionStatus.unknown;
      notifyListeners();
      return;
    }
    _lastStorageFailure = null;

    if (secret == null) {
      _status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }

    // 先绑定并交出秘密，随后的 /auth/session 才会由传输层注入 Bearer 走验证。
    _bound = address;
    _secret = secret;
    _status = SessionStatus.verifying;
    notifyListeners();
    await _verify(address);
  }

  /// 提交一次已成功的登入结果，交由控制器完成綁定、保存与状态转换。
  ///
  /// [server] 必须是这笔登入实际打去的位址（由登入流程原样传回，不让控制器猜）。
  /// 浏览器端秘密由 Cookie 代管，本方法不保存任何令牌；原生端把秘密写入安全儲存，
  /// 写不进时如实回报 [SessionLoginOutcome.persistenceFailed]，記憶體中的本次會話仍可用，
  /// 但绝不退化成明文落盘。
  Future<SessionLoginOutcome> completeLogin(
    ServerAddress server,
    LoginExchange exchange,
  ) async {
    // 登入前若还綁着另一台伺服器的會話，先清掉那台的憑據與上下文（结构性隔离）。
    final ServerAddress? previous = _bound;
    if (previous != null && previous.displayText != server.displayText) {
      await _clearPersisted(previous.displayText);
      _clearLocalSession();
    }

    if (_mode == SessionTransportMode.web) {
      _bound = server;
      _secret = null;
      _active = ActiveSession.fromLogin(exchange.report);
      _status = SessionStatus.signedIn;
      notifyListeners();
      return SessionLoginOutcome.established;
    }

    final String? secret = exchange.sessionSecret;
    if (secret == null) {
      _clearLocalSession();
      _status = SessionStatus.unknown;
      notifyListeners();
      return SessionLoginOutcome.missingCredential;
    }

    _bound = server;
    _secret = secret;
    _active = ActiveSession.fromLogin(exchange.report);
    _status = SessionStatus.signedIn;
    notifyListeners();

    try {
      await _persistence!.writeSecret(server.displayText, secret);
      _lastStorageFailure = null;
      return SessionLoginOutcome.established;
    } catch (error) {
      _lastStorageFailure = error;
      return SessionLoginOutcome.persistenceFailed;
    }
  }

  /// 登出：先讓伺服器撤銷本次綁定的會話，再清本机状态与（原生端）保存的秘密。
  ///
  /// 界线与顺序都是刻意的：
  /// * 顺序——「先向服务器发撤销请求、后清本地」。原生路径的 logout 走传输层自动
  ///   注入的 Bearer，它需要 [_secret] 与 [_bound] 仍在原位才能被 [_effectiveBearer]
  ///   命中；先清本地就等于让请求不带凭据地打到 logout 上，冪等地报 2xx 却没真的撤销
  ///   任何东西。Web 路径同理：Cookie 由浏览器自动附带，[boundServerDisplay] 只是
  ///   让 logout 请求知道该打哪台。
  /// * 幂等：后端对「拿一枚早已失效的秘密来登出」回 2xx，不会变成 2003 的「请重新
  ///     登入」；[SessionSignOutOutcome.revoked] 因此也覆盖「其实先前就登出过了」。
  /// * 未确认：logout 请求抛出 [ApiError]（连不上、逾时、5xx、未就绪）时本机会話照清、
  ///   原生储存照删，但回报 [SessionSignOutOutcome.serverUnconfirmed]——呼叫端要
  ///   如实告知「本机已清理，服务器撤销未确认」，绝不宣称所有设备已下线。
  /// * 世代：进入本方法就把 [_generation] 推进一次，任何先前发出的 [_verify] 完成時
  ///   看到世代不同就会把自己的结果丢掉，不会把已登出的界面拉回 signedIn。
  /// * 范围：只撤銷本請求憑據所指向的那一枚會話，不做全設備退出。
  ///
  /// 本方法不抛異常——服务端结果一律收进回传的 [SessionSignOutOutcome]，
  /// 存储层失败经 [_clearPersisted] 收进 [lastStorageFailure]。
  Future<SessionSignOutOutcome> signOut({String? acceptLanguage}) async {
    final ServerAddress? server = _bound;
    final bool canAttempt =
        server != null &&
        (_mode == SessionTransportMode.web || _secret != null);
    // 先推进世代：此刻起任何在途的验证都不准再把结果盖回当前状态。
    _generation++;

    bool confirmed;
    if (canAttempt) {
      try {
        await _api.logout(acceptLanguage: acceptLanguage);
        confirmed = true;
      } on ApiError {
        // 任何 logout 失败都收为「未确认」：本机继续清理，界面如实分层告知。
        confirmed = false;
      }
    } else {
      // 没有可撤销的目标（未绑定，或原生端已无秘密）：直接算作幂等达成。
      confirmed = true;
    }

    _clearLocalSession();
    _status = SessionStatus.signedOut;
    if (_mode == SessionTransportMode.native && server != null) {
      await _clearPersisted(server.displayText);
    }
    notifyListeners();
    return confirmed
        ? SessionSignOutOutcome.revoked
        : SessionSignOutOutcome.serverUnconfirmed;
  }

  /// 向伺服器確認当前憑據是否仍有效，並据回應落状态。
  ///
  /// 完成時先看世代：若 [_generation] 已推进（期间发生过登出或位址切换），
  /// 这笔回应描述的是上一代上下文，一律丢弃——不能把已经登出的界面
  /// 拉回 signedIn，也不能把已经切换到另一台的状态又盖回这台。
  Future<void> _verify(ServerAddress address) async {
    final int generation = _generation;
    CurrentSessionReport? report;
    ApiError? failure;
    try {
      report = await _api.currentSession();
    } on ApiError catch (error) {
      failure = error;
    }
    if (generation != _generation) {
      return;
    }
    if (report != null) {
      _bound = address;
      _active = ActiveSession.fromCurrentSession(report);
      _status = SessionStatus.signedIn;
      _lastStorageFailure = null;
    } else {
      await _handleVerifyFailure(address, failure!, generation);
      if (generation != _generation) {
        return;
      }
    }
    notifyListeners();
  }

  /// 把验证失败按機器码分成「确定未登入／已失效／查不了」三类，绝不含混。
  ///
  /// [generation] 是从 [_verify] 传入的世代快照：`sessionInvalid` 分支要 await 删除
  /// 已存秘密，那一段 await 期间若登出或位址切换发生，本方法后续的同步写入必须整块
  /// 跳过，否则会把已定的 signedOut／新位址状态覆写成 expired。
  Future<void> _handleVerifyFailure(
    ServerAddress address,
    ApiError error,
    int generation,
  ) async {
    switch (error.knownCode) {
      case ApiMachineCode.notAuthenticated:
        // 服务器可达且答复「没有有效憑據」：这是确定的未登入，不是查不了。
        _clearLocalSession();
        _status = SessionStatus.signedOut;
      case ApiMachineCode.sessionInvalid:
        // 憑據已過期／被撤銷：清掉本地與保存的秘密，標為失效，處置是重新登入。
        await _clearPersisted(address.displayText);
        if (generation != _generation) {
          // await 期间发生了登出或位址切换：那一边已经把状态定好了，这里不再回写。
          return;
        }
        _clearLocalSession();
        _status = SessionStatus.expired;
      default:
        // 連不上、逾時、未就緒、內容不合合同等——无法判定，保留既有綁定與秘密，
        // 停在未知，等下一次可達时再验证；不把「查不了」当成「没登入」。
        _status = SessionStatus.unknown;
    }
  }

  /// 位址變更：舊會話不再描述目前這台伺服器，一律清空憑據與活動上下文。
  void _onAddressChanged() {
    final String? current = _api.config.address?.displayText;
    final String? bound = _bound?.displayText;
    if (current == bound) {
      return;
    }
    final ServerAddress? previous = _bound;
    // 推進世代：在途的驗證回應屬於變址前的那台伺服器，回來時必須被丟棄，
    // 否則會把新位址的狀態蓋回「已登入舊伺服器」。
    _generation++;
    _clearLocalSession();
    if (_mode == SessionTransportMode.native && previous != null) {
      // 异步入队删除旧凭据；同步已清掉記憶體秘密，注入闸門当即关闭，不会误发。
      unawaited(_clearPersisted(previous.displayText));
    }
    // 切到另一台真实伺服器时状态为未知（须重新验证）；位址被清空则回到未登入。
    _status = current == null ? SessionStatus.signedOut : SessionStatus.unknown;
    notifyListeners();
  }

  /// 删除某伺服器的已保存秘密；失败只记录原因，不影响本地已清空的事实。
  Future<void> _clearPersisted(String serverIdentity) async {
    if (_mode != SessionTransportMode.native) {
      return;
    }
    try {
      await _persistence!.clearSecret(serverIdentity);
      _lastStorageFailure = null;
    } catch (error) {
      _lastStorageFailure = error;
    }
  }

  /// 清空内存中的會話相关状态（不含状态枚举本身，由调用方设定）。
  void _clearLocalSession() {
    _bound = null;
    _secret = null;
    _active = null;
    _activityScope = null;
  }

  @override
  void dispose() {
    _addresses.removeListener(_onAddressChanged);
    super.dispose();
  }
}
