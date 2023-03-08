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
///   說明「設口令動的是身分，該走同一張卡上的訪客升級區」，而不是讓他按下一顆註定被拒的按鈕。
/// * 訪客升級走第四條白名單（`/upgrade` 子資源，本體只有 login_name 與 password 兩欄）：
///   這是**原地升級**——同一枚帳戶標識、同一個顯示名、同一批歷史記錄，不新建也不綁定；
///   「綁定到另一個既有正式帳戶」今日沒有通路，界面把兩句話分開講。確認對話框必須唸出
///   目標與新的正式登入名才准提交；按鈕只對「服務端讀回他是訪客且可登入」出現，
///   停用中的訪客看到的是處置說明而不是那顆按鈕（後端對兩種形態都回 2024）。
///   與重置同樣：口令送出前即清空、結果不明不自動補發、成功句的撤銷數量取自 PUT 回應。
///   本人不能自我升級這句話不由界面承擔——訪戶拿自己的會話敲這條端點，後端回 2011。
/// * 綁定預檢是這一張卡上唯一的**純只讀**區（`/bind-preflight`，POST 只帶
///   target_account_id 一格）：它不寫任何資料、不落任何審計，因此不配確認對話框——
///   確認框是寫入通路的門。它講的是另一句與「原地升級」相反相成的話：把訪戶併入
///   **另一個既有正式帳戶**此刻可不可行、被什麼擋著。結果面板第一句永遠是大聲的
///   「尚未綁定」；即便預覽全綠，界面上也沒有那顆「執行綁定」的按鈕——用戶批准的
///   決定是綁定只能由目標帳戶持有人以自己的會話發起，今日不存在那樣通路，
///   而這份預覽對任何人都不是、也不會变成一半的綁定。
/// * 刪除掛在詳情那條路徑的 DELETE 方法上，是這一張卡最後一條寫入通路：本體是空的，
///   也沒有依據值欄位（第二次刪除回的是 2027「他已被刪除」，不是 2013／2014 那句
///   「你依據的現值過期了」）。確認對話框要把四段話講完才准提交：動的是誰（登入名、
///   來源類型與現狀逐一點名）、會發生什麼（停新登入、撤銷有效會話、顯示名匿名化為
///   `DEL_<UTC日期>_<原名>`）、不會發生什麼（不是停用、沒有恢復通路，而且登入名仍被佔用，
///   所以沒人接得走那個名字），以及為什麼帳戶行刻意留下（既有審計要指回同一個人）。
///   影響範圍那一句講在按鈕之前：這一刀動的是整臺伺服器的登入能力，不是活動內的玩家限制。
///   成功之後這張卡退出編輯態：改名框與每一顆寫入鈕一律消失，畫面換成服務端回的刪除後真相。
/// * 刪除與退休是兩種終態，處置相同而來路不同，界面對兩者一律只讀：改名框、停用／恢復、
///   重置口令、訪客升級、綁定預檢與憑證簽發全部收起，只列服務端回傳的現值與那個時刻。
///   「查無此人」（1001）對它們都不成立——這一個人列得出、點得開，只是動不了；把按鈕
///   留在畫面上對著一個不再接受寫入的對象，比少一顆按鈕更容易讓人以為還做得動。
///   退休那句指向的是綁定留痕，不是刪除記錄：他還在，只是以另一個人的一部分存在。
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

  /// 升級區影響範圍說明識別鍵。
  static const Key upgradeScopeKey = ValueKey<String>(
    'std-account-upgrade-scope',
  );

  /// 正式登入名輸入框識別鍵。
  static const Key upgradeLoginKey = ValueKey<String>(
    'std-account-upgrade-login',
  );

  /// 一次性口令輸入框識別鍵。
  static const Key upgradePasswordFieldKey = ValueKey<String>(
    'std-account-upgrade-password',
  );

  /// 升級按鈕識別鍵。
  static const Key upgradeActionKey = ValueKey<String>(
    'std-account-upgrade-action',
  );

  /// 停用中訪客的「此刻不可升級」說明識別鍵。
  static const Key upgradeUnavailableKey = ValueKey<String>(
    'std-account-upgrade-unavailable',
  );

  /// 升級確認對話框的肯定按鈕識別鍵。
  static const Key upgradeConfirmKey = ValueKey<String>(
    'std-account-upgrade-confirm',
  );

  /// 升級確認對話框的取消按鈕識別鍵。
  static const Key upgradeConfirmCancelKey = ValueKey<String>(
    'std-account-upgrade-cancel',
  );

  /// 升級成功摘要識別鍵。
  static const Key upgradeNoticeKey = ValueKey<String>(
    'std-account-upgrade-notice',
  );

  /// 綁定預檢區影響範圍說明識別鍵（常駐句：純只讀、未綁定、沒有執行入口）。
  static const Key bindPreflightScopeKey = ValueKey<String>(
    'std-account-bind-preflight-scope',
  );

  /// 綁定預檢目標標識輸入框識別鍵。
  static const Key bindPreflightTargetKey = ValueKey<String>(
    'std-account-bind-preflight-target',
  );

  /// 綁定預檢按鈕識別鍵。
  static const Key bindPreflightActionKey = ValueKey<String>(
    'std-account-bind-preflight-action',
  );

  /// 綁定預檢結果面板識別鍵（「尚未綁定」的顯著標示落在面板第一句）。
  static const Key bindPreflightResultKey = ValueKey<String>(
    'std-account-bind-preflight-result',
  );

  /// 綁定憑證簽發區的影響範圍說明識別鍵（常駐句：這一動寫什麼、不寫什麼）。
  static const Key bindTicketScopeKey = ValueKey<String>(
    'std-account-bind-ticket-scope',
  );

  /// 綁定憑證簽發按鈕識別鍵（這一區唯一會寫資料的那顆）。
  static const Key bindTicketActionKey = ValueKey<String>(
    'std-account-bind-ticket-action',
  );

  /// 簽發確認對話框的肯定按鈕識別鍵。
  static const Key bindTicketConfirmKey = ValueKey<String>(
    'std-account-bind-ticket-confirm',
  );

  /// 簽發確認對話框的取消按鈕識別鍵。
  static const Key bindTicketConfirmCancelKey = ValueKey<String>(
    'std-account-bind-ticket-confirm-cancel',
  );

  /// 已簽發憑證的展示面板識別鍵（明文只在這一屏出現這一次）。
  static const Key bindTicketResultKey = ValueKey<String>(
    'std-account-bind-ticket-result',
  );

  /// 刪除區影響範圍說明識別鍵（常駐句：按鈕按下去之前就要讀到那一刀動的是什麼）。
  static const Key deleteScopeKey = ValueKey<String>(
    'std-account-delete-scope',
  );

  /// 刪除按鈕識別鍵（目標已是任何終態時不再出現）。
  static const Key deleteKey = ValueKey<String>('std-account-delete-action');

  /// 刪除確認對話框的肯定按鈕識別鍵。
  static const Key deleteConfirmKey = ValueKey<String>(
    'std-account-delete-confirm',
  );

  /// 刪除確認對話框的取消按鈕識別鍵。
  static const Key deleteConfirmCancelKey = ValueKey<String>(
    'std-account-delete-cancel',
  );

  /// 刪除成功摘要識別鍵（帶服務端回傳的撤銷數量）。
  static const Key deleteNoticeKey = ValueKey<String>(
    'std-account-delete-notice',
  );

  /// 已刪除橫幅識別鍵（這一態下這張卡對「他是誰、現在是什麼」的聲明）。
  static const Key deletedBannerKey = ValueKey<String>(
    'std-account-profile-deleted-banner',
  );

  /// 已退休橫幅識別鍵（另一種終態，處置指向綁定留痕）。
  static const Key retiredBannerKey = ValueKey<String>(
    'std-account-profile-retired-banner',
  );

  /// 刪除態下「為什麼帳戶行還在」的說明識別鍵（歷史身份保留的可見證據）。
  static const Key identityKeptKey = ValueKey<String>(
    'std-account-profile-identity-kept',
  );

  /// 退休態下「該去讀綁定留痕」的說明識別鍵。
  static const Key retiredTraceKey = ValueKey<String>(
    'std-account-profile-retired-trace',
  );

  /// 終態拒絕（2027／2028）之後唯一的出口識別鍵：重讀這份資料，不是重發那顆按鈕。
  static const Key terminalReloadKey = ValueKey<String>(
    'std-account-profile-terminal-reload',
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

  /// 升級的兩個輸入：正式登入名與一次性口令。口令與重置同規——
  /// 只活在這一個控制器裡，在發出請求前就清空（成功與失敗都不留）。
  final TextEditingController _upgradeLogin = TextEditingController();
  final TextEditingController _upgradePassword = TextEditingController();

  /// 升級進行中（進行中不再發第二趟，也不與另三條白名單並發——四張卡動的是同一筆）。
  bool _upgrading = false;

  /// 升級的成功句：撤銷數量取自 PUT 回應；口令不在這句話裡，也不在任何一處再出現。
  String? _upgradeNotice;

  /// 綁定預檢的目標帳戶標識輸入：一格 UUID 原文，本地只做「空不發請求」。
  /// 它不是任何寫入的底稿——這條通路沒有寫入。
  final TextEditingController _bindPreflightTarget = TextEditingController();

  /// 綁定預檢進行中（進行中不再發第二趟，也與四條白名單互斥——同一筆資料不並發操作）。
  bool _bindPreflighting = false;

  /// 最近一次預檢的結論快照。純只讀預覽：它不綁定任何人，也不是一张可提交的表單；
  /// 任何寫入成功後一律收起（那份快照描述的事實已經被改變）。
  StandardAccountBindPreflightReport? _bindPreflight;

  /// 綁定憑證簽發進行中（這一動會寫一筆憑證與一筆審計，所以它與四條白名單一樣互斥）。
  bool _ticketIssuing = false;

  /// 最近一次簽發出來的憑證。它與預覽快照的分別是刻意的：預覽描述的是一份會過期的事實，
  /// 而這一枚是已經存在的小票——界面展示它一次，離開這一頁就再也讀不回來（庫裡只有哈希）。
  /// 任何寫入成功後一律收起，避免留下第二處「以為還能拿它做什麼」的畫面。
  GuestBindTicketReport? _issuedTicket;

  /// 刪除進行中。它不只是「防手滑」：刪除只允許成功一次，
  /// 界面上沒有一顆按鈕具備「再點一次還是同一件事」的正當含義。
  bool _deleting = false;

  /// 刪除成功的摘要（撤銷數量與刪除時刻都取自 DELETE 回應）。
  String? _deleteNotice;

  /// 某條通路被「目標已是終態」（2027／2028）擋下來：界面在此之後只給一個出口——
  /// 重讀這份資料。它與 [_conflicted]／[_statusConflicted] 是三種不同的失敗：
  /// 那兩者說「重讀現值之後同一顆按鈕還可以再按」，而終態重讀之後還是終態。
  bool _terminalBlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _displayName.dispose();
    _resetPassword.dispose();
    _upgradeLogin.dispose();
    _upgradePassword.dispose();
    _bindPreflightTarget.dispose();
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
      _upgradeNotice = null;
      _upgradeLogin.clear();
      _upgradePassword.clear();
      // 刪除句同樣不在重讀後殘留：它講的是「那一次操作撤了幾份會話」，
      // 而重讀之後畫面要說的是現在的真相。
      _deleteNotice = null;
      _deleting = false;
      // 終態出口也不殘留：重讀拿到的現值自己會決定這張卡要不要只讀。
      _terminalBlocked = false;
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
    setState(() {
      _savePhase = _SavePhase.saving;
      // 每一次新的嘗試都重新決定「上次是不是被終態擋住」：那個出口只描述最近一趟的結果。
      _terminalBlocked = false;
    });
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
        // 任何寫入成功都收起預覽快照與已簽發的憑證：它們描述的事實已被這一次寫入改變。
        _issuedTicket = null;
        _bindPreflight = null;
      });
      widget.onSaved?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savePhase = _SavePhase.idle;
        _notice = _writeFailureText(error);
        _terminalBlocked = _isTerminalRefusal(error.knownCode);
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
      _terminalBlocked = false;
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
        // 任何寫入成功都收起預覽快照與已簽發的憑證：它們描述的事實已被這一次寫入改變。
        _issuedTicket = null;
        _bindPreflight = null;
      });
      widget.onSaved?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _resetting = false;
        _notice = _resetFailureText(error);
        _terminalBlocked = _isTerminalRefusal(error.knownCode);
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

  /// 升級的確認對話框：原地升級動的是「這個人是哪一類主體」，比改口令與改狀態都重，
  /// 所以必須唸出目標、新的正式登入名、四件效果與兩件不發生，確認才准提交。
  /// 「這是就地轉正、不是綁定到另一個帳戶」這句話寫在確認文裡——兩者對操作者是
  /// 完全不同的處置，混按一次就是一個不可分岔的歷史。取消是一條正經出路。
  /// 這裡沒有「重試」按鈕的位置：對已轉正者再發一次只會拿到 2024，而那不是結果不明。
  Future<void> _confirmUpgrade() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StandardAccountReport? profile = _profile;
    if (profile == null || !profile.isGuest || _upgrading) {
      return;
    }
    final String loginName = _upgradeLogin.text.trim();
    final String password = _upgradePassword.text;
    if (loginName.isEmpty || password.trim().isEmpty) {
      // 本地只擋「明顯沒填」：登入名與口令的域規則由服務端判，界面不抄第二份。
      setState(() => _notice = l10n.stdAccountUpgradeFormIncompleteNotice);
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.stdAccountUpgradeConfirmTitle),
        content: Text(
          l10n.stdAccountUpgradeConfirmBody(profile.loginName, loginName),
        ),
        actions: <Widget>[
          TextButton(
            key: StandardAccountProfileCard.upgradeConfirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminStatusConfirmCancelAction),
          ),
          FilledButton(
            key: StandardAccountProfileCard.upgradeConfirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.stdAccountUpgradeConfirmOkAction),
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
    await _applyUpgrade(loginName, password);
  }

  /// 提交升級：口令在發出請求前就從輸入框清掉（成功與失敗都不留）；
  /// 成功展示與撤銷計數一律換成 PUT 回應，目錄跟著重讀；失敗則界面原地不動。
  Future<void> _applyUpgrade(String loginName, String password) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StandardAccountReport? profile = _profile;
    if (profile == null) {
      return;
    }
    setState(() {
      _upgrading = true;
      _notice = null;
      _upgradeNotice = null;
      _upgradePassword.clear();
      _terminalBlocked = false;
    });
    try {
      final StandardAccountUpgradeReport report = await widget.api
          .upgradeGuestAccount(
            accountId: profile.accountId,
            loginName: loginName,
            password: password,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.account;
        _displayName.text = report.account.displayName;
        _upgradeLogin.clear();
        _upgrading = false;
        // 成功句的數字來自回應：「這次讓 N 臺裝置用新憑據重新登入」不許界面自己猜。
        _upgradeNotice = l10n.stdAccountUpgradeSuccessNotice(
          report.revokedSessions,
        );
        // 任何寫入成功都收起預覽快照與已簽發的憑證：它們描述的事實已被這一次寫入改變。
        _issuedTicket = null;
        _bindPreflight = null;
      });
      widget.onSaved?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _upgrading = false;
        _notice = _upgradeFailureText(error);
        _terminalBlocked = _isTerminalRefusal(error.knownCode);
      });
    }
  }

  /// 升級失敗分流：1004 依 `invalid_field` 說對應那一句；2012 與 2024 交給機器碼的
  /// 專屬句（一個要換名字、一個要重讀現值，處置不同不能混唸）；1001／2011／會話那一簇
  /// 各說各句；2014（併發兜底）也在通用目錄裡。訪戶本人自我升級在正常界面上到不了這裡
  /// ——那句話發生在後端；界面這條分流只服务公司級管理員的真實操作。
  String _upgradeFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'login_name' => l10n.adminProvisionInvalidLoginNameNotice,
        'password' => l10n.adminResetInvalidPasswordNotice,
        _ => apiErrorText(l10n, error),
      };
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

  /// 綁定預檢：讀目標標識、發一趟 POST，結果只是一場**預覽**。
  ///
  /// 本地只擋「明顯沒填」：UUID 是否合法、目標在不在目錄、兩側形態合不合，
  /// 全部由服務端判——界面不抄第二份規則，也不替操作者預筛「誰看起來能綁」。
  /// 這一顆按鈕不弹確認框：確認框是寫入通路的門（停用、重置、升級都動真資料），
  /// 而這條通路一個字都不寫，把人再點一次「確認」當安全装置是錯位；
  /// 代替它的，是結果面板第一句就大聲講明「尚未綁定、這不會執行任何事」。
  Future<void> _runBindPreflight() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StandardAccountReport? profile = _profile;
    if (profile == null || !profile.isGuest || _bindPreflighting) {
      return;
    }
    final String targetAccountId = _bindPreflightTarget.text.trim();
    if (targetAccountId.isEmpty) {
      // 沒填就一個請求都不發：這條路徑不該成為探測服務端是否在听的脈衝。
      setState(() => _notice = l10n.stdAccountBindPreflightIncompleteNotice);
      return;
    }
    setState(() {
      _bindPreflighting = true;
      _notice = null;
      // 新的預覽開始跑，舊的那份快照就退場：兩份「上次結論」並存是第三種真相。
      _bindPreflight = null;
    });
    try {
      final StandardAccountBindPreflightReport report = await widget.api
          .guestBindPreflight(
            accountId: profile.accountId,
            targetAccountId: targetAccountId,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _bindPreflighting = false;
        _bindPreflight = report;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _bindPreflighting = false;
        _notice = _bindPreflightFailureText(error);
      });
    }
  }

  /// 預檢失敗分流：1004 依 `invalid_field` 點名目標標識（改寫法就有用）；
  /// 1001 說「兩側有一方不在這本目錄裡」（來源或目標、不存在或管理員或已刪除，
  /// 服務端刻意同句，界面也就同句——把它拆開等於替預覽接上探照燈）；
  /// 2011 說「這個主體做不了這份預覽」；會話那一簇各說各話。
  /// 「此刻不可綁定」不在這裡：那是 200 預覽本體裡的 blockers，不是錯誤。
  String _bindPreflightFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'target_account_id' => l10n.stdAccountBindPreflightInvalidTargetNotice,
        _ => apiErrorText(l10n, error),
      };
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

  /// 把阻止原因的穩定記號換成界面句子。認不得的記號不崩潰也不靜默：
  /// 顯示通用句並保留原記號——合同只增不刪，新記號抵達的那一天舊界面要能如實
  /// 承認「這一條我还不認得」，而不是拿舊句子套新事實。
  String _bindBlockerText(AppLocalizations l10n, String token) {
    return switch (token) {
      'same_source_target' => l10n.stdAccountBindPreflightBlockerSame,
      'source_not_guest' => l10n.stdAccountBindPreflightBlockerSourceNotGuest,
      'source_not_active' => l10n.stdAccountBindPreflightBlockerSourceNotActive,
      'source_has_grants' => l10n.stdAccountBindPreflightBlockerSourceHasGrants,
      'target_not_standard' =>
        l10n.stdAccountBindPreflightBlockerTargetNotStandard,
      'target_not_active' => l10n.stdAccountBindPreflightBlockerTargetNotActive,
      'unknown_references' => l10n.stdAccountBindPreflightBlockerUnknownRefs,
      _ => l10n.stdAccountBindPreflightUnknownToken(token),
    };
  }

  /// 把影響記號換成界面句子；撤銷那條帶回應里的數量（界面不自己猜會話數）。
  String _bindImpactText(
    AppLocalizations l10n,
    String token,
    StandardAccountBindPreflightReport report,
  ) {
    return switch (token) {
      'revoke_source_sessions' => l10n.stdAccountBindPreflightImpactRevoke(
        report.sourceOpenSessions,
      ),
      'retire_source_account' => l10n.stdAccountBindPreflightImpactRetire,
      'keep_history_references' =>
        l10n.stdAccountBindPreflightImpactKeepHistory,
      'transfer_future_attribution' =>
        l10n.stdAccountBindPreflightImpactFutureAttribution,
      'target_unchanged' => l10n.stdAccountBindPreflightImpactTargetUnchanged,
      _ => l10n.stdAccountBindPreflightUnknownToken(token),
    };
  }

  /// 簽發綁定憑證：把「這份預覽可行」換成一枚限定這一對、15 分鐘、只能用一次的操作憑證。
  ///
  /// 目標標識讀的是預檢那一欄——同一格輸入、兩個動作（先預覽、再簽發），
  /// 不是第二張表單：兩处各放一欄就會出現「預覽的是甲、簽發的是乙」那種拼錯的授權。
  /// 這一動會寫東西，所以它要確認框（預檢不要）：對話框必須唸出「這枚憑證准了誰、
  /// 准的是把訪戶併進他」，並明說這不是綁定本身。
  /// 本地只擋「明顯沒填」；可行性由後端在寫入那一刻重做判定——不可行以 2026 回來，
  /// 界面不假裝「預覽過就一定發得出」。
  Future<void> _runBindTicket() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StandardAccountReport? profile = _profile;
    if (profile == null || !profile.isGuest || _ticketIssuing) {
      return;
    }
    final String targetAccountId = _bindPreflightTarget.text.trim();
    if (targetAccountId.isEmpty) {
      setState(() => _notice = l10n.stdAccountBindTicketIncompleteNotice);
      return;
    }
    // 確認文要點名被准的人是誰：預覽剛讀過這一對就拿它的登入名，
    // 否則退回那枚標識本身——界面不拿「看起來像」冒充「讀過的事實」。
    final StandardAccountBindPreflightReport? snapshot = _bindPreflight;
    final String targetName =
        snapshot != null && snapshot.target.accountId == targetAccountId
        ? snapshot.target.loginName
        : targetAccountId;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.stdAccountBindTicketConfirmTitle),
        content: Text(l10n.stdAccountBindTicketConfirmBody(targetName)),
        actions: <Widget>[
          TextButton(
            key: StandardAccountProfileCard.bindTicketConfirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminStatusConfirmCancelAction),
          ),
          FilledButton(
            key: StandardAccountProfileCard.bindTicketConfirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.stdAccountBindTicketConfirmOkAction),
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
    await _applyBindTicket(targetAccountId);
  }

  /// 發出簽發請求：明文只在成功這一次進到界面（不進任何本地儲存、不進控制器），
  /// 失敗則界面停在原地——這一步不重發，因為「同一對再簽一枚」在後端是合法動作，
  /// 讓操作者自己決定要不要再按一次，比悄悄補發一趟誠實。
  Future<void> _applyBindTicket(String targetAccountId) async {
    final StandardAccountReport? profile = _profile;
    if (profile == null) {
      return;
    }
    setState(() {
      _ticketIssuing = true;
      _notice = null;
      _issuedTicket = null;
    });
    try {
      final GuestBindTicketReport report = await widget.api
          .issueGuestBindTicket(
            accountId: profile.accountId,
            targetAccountId: targetAccountId,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _ticketIssuing = false;
        _issuedTicket = report;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ticketIssuing = false;
        _notice = _bindTicketFailureText(error);
      });
    }
  }

  /// 簽發失敗分流：1004 點名目標標識（改寫法就有用）；2026 交給機器碼的專屬句
  /// （處置是重跑預檢，不是重按這一顆）；1001／2011 與會話那一簇各說各話。
  /// 這裡沒有「不可綁定還是 200」那一形——簽發成功本身就承諾了可行。
  String _bindTicketFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      final Object? field = error.details?['invalid_field'];
      return switch (field) {
        'target_account_id' => l10n.stdAccountBindPreflightInvalidTargetNotice,
        _ => apiErrorText(l10n, error),
      };
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

  /// 已簽發憑證的展示面板：第一句就說明它只在這一個畫面出現一次，離開就再也讀不回來，
  /// 並把「它不是口令、執行只能由目標本人確認」講在同一屏上。
  Widget _bindTicketResultPanel(
    ThemeData theme,
    AppLocalizations l10n,
    GuestBindTicketReport report,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        key: StandardAccountProfileCard.bindTicketResultKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SelectableText(
            l10n.stdAccountBindTicketIssuedNotice(
              report.ticket,
              report.target.loginName,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            l10n.stdAccountBindTicketDeliveryNotice,
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l10n.stdAccountBindTicketExpiresNotice(
              report.expiresAt.toUtc().toIso8601String(),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 結果面板：第一句就是「尚未綁定」的顯著標示，其後逐條唸原因或影響，
  /// 收尾固定講兩件事——綁定需目標本人發起且今日沒有入口、這份預覽按哪一版資料庫跑。
  Widget _bindPreflightResultPanel(
    ThemeData theme,
    AppLocalizations l10n,
    StandardAccountBindPreflightReport report,
  ) {
    final List<Widget> lines = <Widget>[
      Text(
        l10n.stdAccountBindPreflightNotBoundNotice,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(
        report.executable
            ? l10n.stdAccountBindPreflightExecutableHead(
                report.source.loginName,
                report.target.loginName,
              )
            : l10n.stdAccountBindPreflightBlockedHead(
                report.source.loginName,
                report.target.loginName,
              ),
        style: theme.textTheme.bodySmall,
      ),
    ];
    for (final String blocker in report.blockers) {
      lines.add(
        Text(_bindBlockerText(l10n, blocker), style: theme.textTheme.bodySmall),
      );
    }
    for (final String impact in report.impacts) {
      lines.add(
        Text(
          _bindImpactText(l10n, impact, report),
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    lines.add(
      Text(
        l10n.stdAccountBindPreflightConsentNote,
        style: theme.textTheme.bodySmall,
      ),
    );
    lines.add(
      Text(
        l10n.stdAccountBindPreflightDataVersion(report.schemaVersion),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        key: StandardAccountProfileCard.bindPreflightResultKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
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
      _terminalBlocked = false;
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
        // 任何寫入成功都收起預覽快照與已簽發的憑證：它們描述的事實已被這一次寫入改變。
        _issuedTicket = null;
        _bindPreflight = null;
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
        _terminalBlocked = _isTerminalRefusal(error.knownCode);
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

  /// 刪除的確認對話框：這一張卡裡唯一不可逆的一條通路，所以確認要把四段話講完才准提交——
  /// 動的是誰（登入名、來源類型與現狀逐一點名）、會發生哪三件事、哪兩件事不會發生
  /// （不是停用、沒有恢復通路，而且登入名仍被佔用），以及為什麼帳戶行刻意留下。
  ///
  /// 取消是一條正經出路：一個請求都不發，界面停在上一份服務端真相。對話框裡不放
  /// 「我已知悉風險」的勾選框——勾選會讓人以為點確認只是繼續下一步，而這個對話框
  /// 本身就是最後一道把手。這裡也沒有「重試」的位置：刪除沒有依據值，對著一個可能
  /// 已在終態的對象再點一次不是重試，而是又下一次寫入令。
  Future<void> _confirmDelete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StandardAccountReport? profile = _profile;
    if (profile == null || profile.isTerminal || _deleting) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.stdAccountDeleteConfirmTitle),
        content: Text(
          l10n.stdAccountDeleteConfirmBody(
            profile.loginName,
            // 來源與狀態都讀自服務端那一筆：確認文要點名的是「他是哪一類主體、
            // 現在是什麼狀態」，不是界面此刻假設的那樣。
            _typeText(l10n, profile.accountType),
            _statusText(l10n, profile.status),
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: StandardAccountProfileCard.deleteConfirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminStatusConfirmCancelAction),
          ),
          FilledButton(
            key: StandardAccountProfileCard.deleteConfirmKey,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.stdAccountDeleteConfirmOkAction),
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

  /// 提交刪除：DELETE 沒有本體也沒有依據值；成功的展示一律換成回應，並通知頁面重讀目錄
  /// ——行與詳情不能各留一份舊真相。
  ///
  /// 成功後這張卡退出編輯態（見 _readyBody 的 terminal 分岔）：保留卡片是為了讓操作者
  /// 看得見「現在他是什麼」，把那些寫入按鈕留在畫面上則是另一件事。
  ///
  /// 結果不明（連線中斷、逾時）時**絕不自動補發**：那不會是重試，而是對一個可能已進入
  /// 終態的對象再下一次寫入令。操作者要的是重讀——目錄與詳情讀回來的那一份才是證據。
  Future<void> _applyDelete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StandardAccountReport? profile = _profile;
    if (profile == null) {
      return;
    }
    setState(() {
      _deleting = true;
      _notice = null;
      _deleteNotice = null;
      _terminalBlocked = false;
    });
    try {
      final StandardAccountDeleteReport report = await widget.api
          .deleteStandardAccount(
            accountId: profile.accountId,
            acceptLanguage: _acceptLanguage,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = report.account;
        _deleting = false;
        // 改名用的那份底稿從此沒有意義：顯示名已是佔位值，輸入框留著只會讓人以為還能改。
        // 清掉它們與退出編輯態是同一件事的兩面。
        _displayName.clear();
        _resetPassword.clear();
        _upgradeLogin.clear();
        _upgradePassword.clear();
        _bindPreflightTarget.clear();
        _savedNotice = null;
        _statusNotice = null;
        _resetNotice = null;
        _upgradeNotice = null;
        // 預覽快照與已簽發的憑證描述的都已不是現在的事實。
        _bindPreflight = null;
        _issuedTicket = null;
        _conflicted = false;
        _statusConflicted = false;
        // 撤銷數量來自回應：「這次讓 N 臺裝置失去登入狀態」不許界面自己猜。
        _deleteNotice = l10n.stdAccountDeleteSuccessNotice(
          report.revokedSessions,
        );
      });
      widget.onSaved?.call();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deleting = false;
        _notice = _deleteFailureText(error);
        _terminalBlocked = _isTerminalRefusal(error.knownCode);
      });
    }
  }

  /// 刪除失敗分流：2027（已是刪除態）與 2028（已被綁走的退休訪戶）各說各句，
  /// 兩者都只導向「重讀這份資料」；1001 是目標根本不在這本目錄（該換目標）、
  /// 2011 是主體不對，其餘交給機器碼的通用句。
  ///
  /// 把 2027 報成 1001 會讓人對著一份明明列著他的目錄反覆懷疑標識抄錯；報成成功
  /// 則是在審計與真相之間造出一件沒發生過的事。2027 與 2028 也都不冒充 2013／2014
  /// 那句「現值過期了」——那兩句的處置是重讀之後同一顆按鈕還可以再按，而終態不行。
  String _deleteFailureText(ApiError error) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ApiMachineCode? code = error.knownCode;
    if (code == ApiMachineCode.invalidBody) {
      // 刪除不該帶任何欄位：會走到這一句代表送出了一個不存在的「選項」，
      // 點名它比假裝沒看見誠實。
      return l10n.stdAccountDeleteNoBodyNotice;
    }
    return switch (code) {
      ApiMachineCode.accountDeleted => l10n.errorCodeAccountDeleted,
      ApiMachineCode.accountRetired => l10n.errorCodeAccountRetired,
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
    // 四條白名單動的是同一筆帳戶：並發提交會讓其中一條的依據值在送出那一刻就過期，
    // 因此這一張卡在任一寫入進行中都停住其餘入口。綁定預檢本身是純只讀，
    // 但它在飛時一樣停住全部入口（含它自己）——同一筆資料的畫面不並發操作，
    // 而且「預覽正在跑、另一條寫入先落地」會讓那份快照描述一個已不存在的事實。
    final bool busy =
        _savePhase == _SavePhase.saving ||
        _statusChanging ||
        _resetting ||
        _upgrading ||
        _bindPreflighting ||
        _ticketIssuing ||
        _deleting ||
        // 被「目標已是終態」擋下一次之後，這張卡的所有寫入入口都停住，只留一個出口：
        // 重讀。它與 [_conflicted]／[_statusConflicted] 那句「重讀後同一顆按鈕還能再按」
        // 是兩種不同的失敗——終態重讀之後還是終態，把按鈕留在畫面上等於假裝還做得動。
        _terminalBlocked;
    // 兩種終態（已被軟刪除、已被綁走）一律走只讀分支：這個人列得出、點得開，
    // 而每一條寫入通路都會被服務端當場拒絕，界面不把這件事藏成一個錯答案。
    if (profile.isTerminal) {
      return _terminalBody(l10n, theme, profile);
    }
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
        // 訪客升級：第四條白名單（只有 login_name 與 password 兩欄），只由服務端讀回的
        // 來源欄位決定出現與否。「原地升級」與「綁定既有帳戶」是兩句話：這一區只做前者
        // （同一枚標識就地轉正），後者今日沒有通路，說明寫在常駐句裡而不是藏在提示裡。
        // 停用中的訪客不長那顆按鈕——後端對「已轉正」與「已停用」都回 2024，界面按
        // 讀回的狀態把處置先講出來（先恢復登入，再決定要不要升級）。
        if (profile.isGuest) ...<Widget>[
          Text(
            l10n.stdAccountUpgradeScopeHint,
            key: StandardAccountProfileCard.upgradeScopeKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (profile.isActive) ...<Widget>[
            TextField(
              key: StandardAccountProfileCard.upgradeLoginKey,
              controller: _upgradeLogin,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: l10n.stdAccountUpgradeLoginNameLabel,
                isDense: true,
              ),
              maxLength: 64,
            ),
            TextField(
              key: StandardAccountProfileCard.upgradePasswordFieldKey,
              controller: _upgradePassword,
              enabled: !busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.stdAccountUpgradePasswordFieldLabel,
                isDense: true,
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: StandardAccountProfileCard.upgradeActionKey,
                onPressed: busy ? null : _confirmUpgrade,
                child: Text(
                  _upgrading
                      ? l10n.stdAccountUpgradeWorkingHint
                      : l10n.stdAccountUpgradeAction,
                ),
              ),
            ),
          ],
          if (!profile.isActive)
            Text(
              l10n.errorCodeGuestNotUpgradable,
              key: StandardAccountProfileCard.upgradeUnavailableKey,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
        // 成功句掛在來源條件之外：轉正之後那組訪客控件如實收起，
        // 但「這次讓 N 臺裝置重新登入」這句話屬於剛完成的那次操作，不跟著消失。
        if (_upgradeNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _upgradeNotice!,
              key: StandardAccountProfileCard.upgradeNoticeKey,
              style: theme.textTheme.bodySmall,
            ),
          ),
        // 綁定預檢：純只讀的衝突預覽，只由服務端讀回的來源欄決定出現與否。
        // 這一區與上面那條「原地升級」白名單是兩句話——升級動的是這一行人自己，
        // 綁定談的是把這行人併入另一個既有正式帳戶；後者的執行動詞只屬於那個目標帳戶
        // 持有人自己的已認證會話（用戶批准的同意形態），這一側能做到的是「先看清會撞在
        // 哪裡」與「發一枚小票給他」。常駐句、結果面板首句、收尾同意句三處都講明尚未綁定；
        // 界面不拿這份預覽摆任何「完成綁定」的按鈕，也不會有那樣一顆。
        if (profile.isGuest) ...<Widget>[
          const Divider(),
          Text(
            l10n.stdAccountBindPreflightScopeHint,
            key: StandardAccountProfileCard.bindPreflightScopeKey,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            key: StandardAccountProfileCard.bindPreflightTargetKey,
            controller: _bindPreflightTarget,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: l10n.stdAccountBindPreflightTargetLabel,
              hintText: l10n.stdAccountBindPreflightTargetHint,
              isDense: true,
            ),
            maxLength: 36,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: StandardAccountProfileCard.bindPreflightActionKey,
              onPressed: busy ? null : _runBindPreflight,
              child: Text(
                _bindPreflighting
                    ? l10n.stdAccountBindPreflightWorkingHint
                    : l10n.stdAccountBindPreflightAction,
              ),
            ),
          ),
          if (_bindPreflight != null)
            _bindPreflightResultPanel(theme, l10n, _bindPreflight!),
          // 憑證簽發：這一區唯一會寫資料的那顆按鈕。它把「這份預覽可行」換成一枚
          // 交給目標本人的短期小票——仍然不是綁定（訪戶未退休、會話未撤、留痕未追加），
          // 界面也沒有、也永遠不會有「代他完成綁定」的那一動。
          const SizedBox(height: 8),
          Text(
            l10n.stdAccountBindTicketScopeHint,
            key: StandardAccountProfileCard.bindTicketScopeKey,
            style: theme.textTheme.bodySmall,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: StandardAccountProfileCard.bindTicketActionKey,
              onPressed: busy ? null : _runBindTicket,
              child: Text(
                _ticketIssuing
                    ? l10n.stdAccountBindTicketWorkingHint
                    : l10n.stdAccountBindTicketAction,
              ),
            ),
          ),
          if (_issuedTicket != null)
            _bindTicketResultPanel(theme, l10n, _issuedTicket!),
        ],
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
        const Divider(),
        // 刪除：這一張卡最後一條寫入通路，也是唯一一條沒有回去的路。
        // 影響範圍那句寫在按鈕之前而不是只塞進確認框——「這一刀動的是整臺伺服器的
        // 登入能力，不是活動內的玩家限制」必須在按下去之前就讀到，而不是按下之後才看到。
        Text(l10n.stdAccountDeleteZoneTitle, style: theme.textTheme.titleSmall),
        Text(
          l10n.stdAccountDeleteZoneHint,
          key: StandardAccountProfileCard.deleteScopeKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            key: StandardAccountProfileCard.deleteKey,
            onPressed: busy ? null : _confirmDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: Text(
              _deleting
                  ? l10n.stdAccountDeleteWorkingHint
                  : l10n.stdAccountDeleteAction,
            ),
          ),
        ),
        if (_deleteNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _deleteNotice!,
              key: StandardAccountProfileCard.deleteNoticeKey,
              style: theme.textTheme.bodySmall,
            ),
          ),
        // 被 2027／2028 擋下時，本地這份現值還來不及變成終態（那個人是在服務端變的）。
        // 這一格給的是同一張卡唯一的出口：重讀。它不出現的話，操作者面前就只剩
        // 一排变灰的按鈕，而那讀起來像「稍後再試」——對終態沒有稍後。
        if (_terminalBlocked)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: StandardAccountProfileCard.terminalReloadKey,
              onPressed: _load,
              child: Text(l10n.adminProfileReloadAction),
            ),
          ),
      ],
    );
  }

  /// 終態（已刪除／已綁走）的只讀分支：把「他是誰、現在是什麼、那個時刻何時落下」
  /// 一次講完，而且一個寫入控件都不給。
  ///
  /// 這一支存在的意思不是省事：用戶批准的刪除後展示策略是「列得出、點得開、動不了」，
  /// 三件事必須由同一筆資料一次說明。若改成「照原樣渲染、每顆按鈕按下去都吃 2027」，
  /// 操作者拿到的仍是錯的結論——他會以為這個對象還做得動事，只是這次不巧失敗了。
  Widget _terminalBody(
    AppLocalizations l10n,
    ThemeData theme,
    StandardAccountReport profile,
  ) {
    final bool deleted = profile.isDeleted;
    // 時刻只讀服務端那一欄：deleted 帶 deleted_at、retired 帶 retired_at；
    // 缺欄（表外值或舊伺服器）就退回不帶時刻的那句，不拿現在的時間去湊。
    final DateTime? at = deleted ? profile.deletedAt : profile.retiredAt;
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
        if (at != null)
          Text(
            l10n.labelValuePair(
              l10n.stdAccountDeletedAtLabel,
              _formatUtcMinute(at),
            ),
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 6),
        // 橫幅那句是「這一頁現在是什麼」的聲明，兩態各自成句：一個說他已被刪掉、
        // 一個說他被綁走了，混用就會讓人去讀錯那一條記錄。
        Text(
          at == null
              ? (deleted
                    ? l10n.stdAccountProfileDeletedBanner
                    : l10n.stdAccountProfileRetiredBanner)
              : (deleted
                    ? l10n.stdAccountProfileDeletedBannerAt(
                        _formatUtcMinute(at),
                      )
                    : l10n.stdAccountProfileRetiredBannerAt(
                        _formatUtcMinute(at),
                      )),
          key: deleted
              ? StandardAccountProfileCard.deletedBannerKey
              : StandardAccountProfileCard.retiredBannerKey,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          deleted
              ? l10n.stdAccountProfileIdentityKeptHint
              : l10n.stdAccountProfileRetiredTraceHint,
          key: deleted
              ? StandardAccountProfileCard.identityKeptKey
              : StandardAccountProfileCard.retiredTraceKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.stdAccountProfileNoSectionsNotice,
          key: StandardAccountProfileCard.noSectionsKey,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        // 終態之後唯一的出口是重讀：它不承諾「再按一次會不同」，只把現值再拿一份回來。
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            key: StandardAccountProfileCard.terminalReloadKey,
            onPressed: _load,
            child: Text(l10n.adminProfileReloadAction),
          ),
        ),
        if (_deleteNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _deleteNotice!,
              key: StandardAccountProfileCard.deleteNoticeKey,
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

  /// 是否為「目標已是終態」的拒絕（2027／2028）。兩枚碼的處置逐字相同——
  /// 重讀這份資料而不是再按一次——所以界面把它們收成同一個旗標；
  /// 至於「他是被刪了」還是「他被綁走了」，仍由 [_deleteFailureText] 各自成句。
  bool _isTerminalRefusal(ApiMachineCode? code) {
    return code == ApiMachineCode.accountDeleted ||
        code == ApiMachineCode.accountRetired;
  }
}

/// 狀態原字串 → 顯示文字；未知值原樣顯示（與目錄卡同一取向，本地不收緊成枚舉）。
String _statusText(AppLocalizations l10n, String status) {
  return switch (status) {
    'active' => l10n.adminStatusActive,
    'disabled' => l10n.adminStatusDisabled,
    // 兩種終態各有自己的詞：讓它們落到「未知值原樣顯示」那一支，界面就會在最需要
    // 講清楚的地方顯示一個給機器讀的原始字串。
    'deleted' => l10n.adminStatusDeleted,
    'retired' => l10n.adminStatusRetired,
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
