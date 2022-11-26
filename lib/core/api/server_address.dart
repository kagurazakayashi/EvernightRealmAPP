/// 伺服器位址的值型別與來源抽象：把「能不能作為請求基準」的判定集中到唯一入口。
///
/// 位址可以來自多個途徑（編譯期注入、使用者輸入、之後的設定檔），但任何來源
/// 都必須先經 [ServerAddress.tryParse] 才算有效；無效位址一律回傳 `null`，
/// 由呼叫端如實呈現「未設定」或「格式不合格」，不得退半個位址去試。
/// 要給使用者看的具體原因走 [ServerAddress.validate]，它與 `tryParse` 共用同一
/// 份判定，因此「顯示為可接受」與「實際能發出請求」永遠是同一個答案。
///
/// 只接受 http(s) 且不帶憑證的絕對位址：使用者名稱與密碼不得出現在位址裡
/// （日誌、錯誤訊息與畫面都可能重現這段文字，任何途徑都不該讓它帶出憑證）。
///
/// 本檔刻意不 import Flutter 與傳輸套件，使 `dart run` 的工具腳本能直接重用
/// 同一份判定，不會出現「畫面說可以、腳本說不行」的兩套規則。
library;

/// 伺服器位址的編譯期參數名稱。
///
/// 建置指令注入：`--dart-define=ER_SERVER_BASE_URL=http://127.0.0.1:5206`。
/// 未注入即如實呈現「伺服器位址未設定」，不猜測任何預設主機。
const String kServerBaseUrlEnvironmentKey = 'ER_SERVER_BASE_URL';

/// 編譯期注入的基準位址，未注入時為空字串。
const String injectedServerBaseUrl = String.fromEnvironment(
  kServerBaseUrlEnvironmentKey,
);

/// [ServerAddress.validate] 的判定結果。
///
/// 每個值都對應一句能對使用者說清楚的話；[ok] 之外一律不會發出請求。
enum ServerAddressIssue {
  /// 合格，可作為請求基準。
  ok,

  /// 沒有任何輸入內容。
  empty,

  /// 缺少 `http://` 或 `https://` 前綴（區域名與埠號寫在一起最常見）。
  missingScheme,

  /// 協定不是 http 或 https。
  unsupportedScheme,

  /// 中間夾帶空白、製表符或零寬字元。
  embeddedWhitespace,

  /// 無法解析成帶主機的絕對位址。
  unresolved,

  /// 協定與斜線齊全，但主機名稱為空。
  hostMissing,

  /// 位址內含使用者名稱或密碼（一律拒絕，憑證不入位址）。
  credentials,

  /// 位址內含查詢字串或片段標記，對基準位址沒有意義。
  queryOrFragment;

  /// 是否代表合格的位址。
  bool get isOk => this == ServerAddressIssue.ok;
}

/// 已驗證的伺服器基準位址。
class ServerAddress {
  /// 僅供 [tryParse] 使用；先以驗證再建立實例。
  ServerAddress._(this.baseUri, this.displayText);

  /// 解析並驗證位址字串；不合格時回傳 `null`（不擲例外，讓表單端可直接判定）。
  static ServerAddress? tryParse(String? input) {
    final Uri? uri = _parse(input);
    if (uri == null) {
      return null;
    }
    return ServerAddress._(uri, _displayText(uri.scheme.toLowerCase(), uri));
  }

  /// 判定輸入是否合格並給出具體原因；供介面顯示「為什麼這個位址不能用」。
  ///
  /// 判定順序與 [tryParse] 完全相同（兩者共用 [_issueOf]），因此回傳 [ServerAddressIssue.ok]
  /// 時 [tryParse] 必定建立出實例，不會出現「提示說可以、請求卻發不出去」。
  static ServerAddressIssue validate(String? input) {
    final String trimmed = input?.trim() ?? '';
    if (trimmed.isEmpty) {
      return ServerAddressIssue.empty;
    }
    if (_hasWhitespace(trimmed)) {
      return ServerAddressIssue.embeddedWhitespace;
    }
    return _issueOf(trimmed);
  }

  /// 驗證通過時回傳 URI，否則回傳 `null`；[validate] 與 [tryParse] 的共同實作。
  static Uri? _parse(String? input) {
    final String trimmed = input?.trim() ?? '';
    if (trimmed.isEmpty || _hasWhitespace(trimmed)) {
      return null;
    }
    if (!_issueOf(trimmed).isOk) {
      return null;
    }
    return Uri.tryParse(trimmed);
  }

  /// 對已去空白、已確認無內嵌空白的字串逐項判定。
  static ServerAddressIssue _issueOf(String trimmed) {
    final String? scheme = _schemeOf(trimmed);
    if (scheme == null) {
      return _schemelessIssue(trimmed);
    }

    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority) {
      return ServerAddressIssue.unresolved;
    }
    if (scheme != 'http' && scheme != 'https') {
      return ServerAddressIssue.unsupportedScheme;
    }
    if (uri.host.isEmpty) {
      return ServerAddressIssue.hostMissing;
    }
    if (uri.userInfo.isNotEmpty) {
      return ServerAddressIssue.credentials;
    }
    // 查詢與片斷對基準位址沒有意義；路徑只作為前綴保留（給反向代理用）。
    if (uri.hasQuery || uri.hasFragment) {
      return ServerAddressIssue.queryOrFragment;
    }
    // 不再單獨判定 `.`／`..`：Uri 解析階段就把上跳段正規化掉了（含 %2e%2e 寫法），
    // 留一個永遠不會命中的分類只會多一份沒被驗證過的文案。
    return ServerAddressIssue.ok;
  }

  /// 取出 `協定://` 寫法裡的協定（已轉小寫）；沒有這種寫法時回傳 `null`。
  static String? _schemeOf(String trimmed) {
    if (!_schemePattern.hasMatch(trimmed)) {
      return null;
    }
    return trimmed.substring(0, trimmed.indexOf('://')).toLowerCase();
  }

  /// 對「沒有寫 `協定://`」的輸入分清兩件事：忘了加協定，還是加了別的協定。
  ///
  /// 這一步值得多寫幾行：只輸 `localhost:5206` 是最常見的錯法，回一句
  /// 「不支持的協定」使用者無從改起；回「要以 http:// 開頭」才知道怎麼修。
  static ServerAddressIssue _schemelessIssue(String trimmed) {
    final int colon = trimmed.indexOf(':');
    if (colon <= 0) {
      return ServerAddressIssue.missingScheme;
    }
    final String head = trimmed.substring(0, colon);
    final String tail = trimmed.substring(colon + 1);
    if (!_hostLikePattern.hasMatch(head)) {
      // 冒號前不是主機形的文字（例如 `192.168.1.20:5206`），仍是少了協定。
      return ServerAddressIssue.missingScheme;
    }
    if (_portOnlyPattern.hasMatch(tail)) {
      return ServerAddressIssue.missingScheme;
    }
    // 冒號前像協定名、後面又不是埠號：那是另一種協定（如 javascript:）。
    return ServerAddressIssue.unsupportedScheme;
  }

  /// 協定前綴的形貌：以字母開頭，後接 `://`。
  static final RegExp _schemePattern = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://');

  /// 看起來像主機名或協定名的形貌。
  static final RegExp _hostLikePattern = RegExp(r'^[A-Za-z][A-Za-z0-9.\-]*$');

  /// 冒號之後只剩數字：那是埠號，不是別的協定。
  static final RegExp _portOnlyPattern = RegExp(r'^\d+$');

  /// 判斷字串中間是否含有任何空白字元（含製表符與零寬字元）。
  static bool _hasWhitespace(String value) {
    for (final int rune in value.runes) {
      if (rune <= 0x20 || rune == 0x7F || rune == 0x200B || rune == 0xFEFF) {
        return true;
      }
    }
    return false;
  }

  /// 去掉結尾多餘的連字號並組成顯示用的正規文字。
  static String _displayText(String scheme, Uri uri) {
    final String prefix = '$scheme://${uri.authority}';
    final String path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return '$prefix$path';
  }

  /// 驗證過的基準 URI（可能帶有路徑前綴）。
  final Uri baseUri;

  /// 供畫面與日誌顯示的正規文字：不含使用者名稱、密碼、查詢與片斷。
  final String displayText;

  /// 接上端點路徑，組成實際請求的 URI。
  ///
  /// [path] 一律以 `/` 開頭，呼叫端不自行字串相加，避免前綴連字號被重複或丟失。
  /// [path] 若自帶查詢串（第一個 `?` 之後的部分），它會被放進 URI 的 query 組件
  /// 而不是路徑——否則 `?` 會被百分號編碼成 `%3F`，伺服器看到的是「一個名字很長
  /// 的端點」而不是「端點加引數」。查詢值本身应已由呼叫端正规化與轉義
  /// （見 server_api 的引數拼接），這裡不再重寫一編碼規則，免得兩處各編一次。
  Uri resolve(String path) {
    final String prefix = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final int queryStart = path.indexOf('?');
    if (queryStart < 0) {
      return baseUri.replace(path: '$prefix$path');
    }
    final Uri withoutQuery = baseUri.replace(
      path: '$prefix${path.substring(0, queryStart)}',
    );
    return withoutQuery.replace(query: path.substring(queryStart + 1));
  }

  @override
  bool operator ==(Object other) {
    return other is ServerAddress && other.displayText == displayText;
  }

  @override
  int get hashCode => displayText.hashCode;

  @override
  String toString() => displayText;
}

/// 基準位址的即時來源。
///
/// 存取層每次發出請求前才取值，因此「位址換了」不需要重建客戶端或追蹤器，
/// 也不可能出現舊位址與新位址同時生效的兩套事實。實作有三種：
/// 固定文字（[StaticServerAddressSource]）、編譯期注入（[InjectedServerAddressSource]）、
/// 以及跟隨使用者設定的 `ServerAddressSettings`。
abstract interface class ServerAddressSource {
  /// 目前生效的基準位址原值；未設定時回傳 `null`。
  ///
  /// 回傳值不保證合格——判定一律由 [ServerAddress.tryParse] 負責，
  /// 來源只負責「此刻是哪一段文字」。
  String? currentUrl();
}

/// 以固定文字作為來源：測試、工具腳本，以及驗證「尚未保存的候選位址」。
class StaticServerAddressSource implements ServerAddressSource {
  /// 以位址文字建立來源（空字串視為未設定）。
  const StaticServerAddressSource(this.url);

  /// 位址原值。
  final String? url;

  @override
  String? currentUrl() {
    final String? value = url;
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}

/// 以編譯期注入參數作為來源（未注入即未設定）。
///
/// 位址輸入與本地保存上線後，本來源僅用於工具腳本與未接入使用者設定的場合；
/// 應用本體一律走 `ServerAddressSettings`，否則注入值與已保存值會各說各話。
class InjectedServerAddressSource implements ServerAddressSource {
  /// 建立來源。
  const InjectedServerAddressSource();

  @override
  String? currentUrl() =>
      StaticServerAddressSource(injectedServerBaseUrl).currentUrl();
}
