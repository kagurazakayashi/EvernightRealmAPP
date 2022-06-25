/// 伺服器位址的值型別：把「能不能作為請求基準」的判定集中到唯一入口。
///
/// 位址輸入介面與本地保存屬後續能力，但任何來源（編譯期注入、使用者輸入、
/// 設定檔）都必須先經 [ServerAddress.tryParse] 才算有效；無效位址一律回傳
/// `null`，由呼叫端如實呈現「未設定」或「位址無效」，不得退半個位址去試。
///
/// 只接受 http(s) 且不帶憑證的絕對位址：使用者名稱與密碼不得出現在位址裡
/// （日誌、錯誤訊息與畫面都可能重現這段文字，任何途徑都不該讓它帶出憑證）。
library;

/// 已驗證的伺服器基準位址。
class ServerAddress {
  /// 僅供 [tryParse] 使用；先以驗證再建立實例。
  ServerAddress._(this.baseUri, this.displayText);

  /// 解析並驗證位址字串；不合格時回傳 `null`（不擲例外，讓表單端可直接判定）。
  static ServerAddress? tryParse(String? input) {
    if (input == null) {
      return null;
    }
    final String trimmed = input.trim();
    if (trimmed.isEmpty || _hasWhitespace(trimmed)) {
      return null;
    }

    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority) {
      return null;
    }

    final String scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return null;
    }
    // 查詢與片斷對基準位址沒有意義；路徑只作為前綴保留（給反向代理用）。
    if (uri.hasQuery || uri.hasFragment) {
      return null;
    }
    if (uri.pathSegments.any(
      (String segment) => segment == '.' || segment == '..',
    )) {
      return null;
    }

    return ServerAddress._(uri, _displayText(scheme, uri));
  }

  /// 判斷字串中間是否含有任何空白字元（含製表符）。
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
  Uri resolve(String path) {
    final String prefix = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(path: '$prefix$path');
  }

  @override
  String toString() => displayText;
}
