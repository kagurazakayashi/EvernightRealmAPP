/// 日誌與畫面文字的脫敏管線（實作根倉庫 ER-SEC-001 §7 的日誌脫敏清單）。
///
/// 為什麼需要這一層：未處理錯誤的本體是任意文字——異常訊息可能把請求內容、
/// 標頭甚至使用者剛輸入的憑證原帶出來，而這些文字會進 stderr、也可能被
/// 顯示到畫面上。這裡的做法是**先假設輸入含有敏感值**，逐規則遮罩後才允許
/// 離開這層，而不是指望拋出例外的人記得避開。
///
/// 三檔處理方式（對應 §7 的分類）：
/// * 永不記錄（密碼、PIN、恢復碼、Root 憑據、TLS 私鑰）→ 值一律換成佔標；
/// * 只留標識（Session Token、Cookie、Authorization、API 金鑰）→ 換成不可還原的短標識；
/// * 其他長隨機串（十六進位／Base64／JWT）→ 視為可疑憑證，直接打碼。
library;

/// 值永不記錄的鍵名（正規化後比對：小寫、去掉底線與連字號）。
const Set<String> _neverRecordKeys = <String>{
  'password',
  'passwd',
  'pwd',
  'pin',
  'pintoken',
  'recoverycode',
  'recoverykey',
  'passphrase',
  'rootpassword',
  'rootpasswordhash',
  'privatekey',
  'tlskey',
  'clientkey',
  'secret',
  'clientsecret',
  'signingkey',
  'passwordhash',
};

/// 值改記短標識的鍵名（同上正規化）。
const Set<String> _referenceKeys = <String>{
  'token',
  'accesstoken',
  'refreshtoken',
  'sessiontoken',
  'sid',
  'cookie',
  'setcookie',
  'authorization',
  'proxyauthorization',
  'csrftoken',
  'csrf',
  'apikey',
  'apitoken',
  'qrcode',
  'qrcodetoken',
  'idempotencykey',
};

/// 單行最長保留字數；超出的部分以刪節標記取代。
const int maxLoggedTextLength = 600;

/// 「永不記錄」的取代標記（語言無關，不引入介面文字）。
const String redactedPlaceholder = '[redacted]';

/// 長隨機字串的打碼標記。
const String maskedSecretPlaceholder = '[masked]';

/// 值被改記為短標識時的前綴。
const String tokenReferencePrefix = 'ref#';

/// 正規化鍵名：小寫並去掉底線、連字號與引號，讓 `session_token` 與
/// `Session-Token` 落到同一個判定上。
String _normalizeKey(String key) =>
    key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// 把值壓成不可還原的短標識。
///
/// **這是關聯識別碼，不是安全摘要**——目的只是讓同一個憑證在日誌裡穩定對應
/// 同一個標記，而不把原值寫出來。乘法刻意控制在 2^53 以內，使 Dart VM 與
/// 瀏覽器（JS number）得到相同結果。
String _referenceOf(String value) {
  const int mask = 0x7FFFFFFF;
  int hash = 5381;
  for (final int unit in value.runes) {
    hash = ((hash * 31) + unit) & mask;
  }
  return hash.toRadixString(16).padLeft(7, '0');
}

/// 比對 `key: value`、`key=value`、`"key": "value"` 三種寫法。
///
/// 值一律抓到「空白、逗號、分號、引號、右大括號」為止，因此匹配是以值結尾的
/// ——下面的重建直接以 `match.end` 定位值，不需要再算偏移。
// 以 "／' 表示引號：Dart 的 raw 字串不處理跳脫，直接把引號寫進去會截斷字串，
// 而 RegExp 自己看得懂這兩個十六進位轉義。
final RegExp _pairPattern = RegExp(
  r'([A-Za-z][A-Za-z0-9_\-]*)[\x22\x27]?\s*[:=]\s*[\x22\x27]?([^\s\x22\x27,;}\]]+)',
);

/// PEM 私鑰區塊（含標頭與結尾）。
final RegExp _pemBlock = RegExp(
  r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)',
);

/// `Bearer xxx`／`Basic xxx` 的憑證值。
final RegExp _schemeToken = RegExp(
  r'\b(Bearer|Basic|Digest|Token)\s+([A-Za-z0-9\-._~+/]{6,}=*)',
  caseSensitive: false,
);

/// URI 的 userinfo 段（`scheme://user:pass@host`）。
final RegExp _uriUserInfo = RegExp(
  r'\b(https?|wss?)://[^\s/?#@]*:[^\s/?@]*@',
  caseSensitive: false,
);

/// JWT 形狀的三段 Base64url。
final RegExp _jwtLike = RegExp(
  r'\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{4,}',
);

/// 長十六進位字串（金鑰、雜湊、簽名的常見形狀）。
final RegExp _longHex = RegExp(r'\b[0-9a-fA-F]{24,}\b');

/// 帶結尾填充的 Base64（`…==`／`…=` 幾乎只出現在金鑰與簽名裡）。
final RegExp _paddedBase64 = RegExp(
  r'\b[A-Za-z0-9+/]{16,}={1,2}(?![A-Za-z0-9+/=])',
);

/// 無分隔符的長英數字串，且同時含大小寫與數字——API 金鑰的常見形狀。
///
/// 刻意不含 `/`：路徑與堆疊影格（如 `package:flutter/src/…2.dart`）都帶斜線，
/// 用同一條規則會把排錯線索一起打碼掉。
final RegExp _longAlnumSecret = RegExp(
  // 只要求「夠長 + 含數字」：全大寫的 API 金鑰（AWS 型）很常見，要求含小寫會漏擋。
  r'\b(?=[A-Za-z0-9]*[0-9])[A-Za-z0-9]{32,}\b',
);

/// 對任意文字做脫敏，回傳可安全寫入日誌或顯示的文字。
///
/// 規例先專後泛：私鑰區塊 → URI 憑證 → Bearer/Basic → JWT → 鍵值對 → 長隨機串，
/// 最後才截斷長度。一般中英文敘述、路徑、數字與函式名不受影響（見測試）。
String redactText(String input) {
  String text = input;
  text = text.replaceAllMapped(
    _pemBlock,
    (_) => '$redactedPlaceholder(private-key)',
  );
  text = text.replaceAllMapped(_uriUserInfo, (Match match) {
    final int separator = match.group(0)!.indexOf('://');
    return '${match.group(0)!.substring(0, separator + 3)}$redactedPlaceholder@';
  });
  text = text.replaceAllMapped(
    _schemeToken,
    (Match match) =>
        '${match.group(1)} $tokenReferencePrefix${_referenceOf(match.group(2)!)}',
  );
  text = text.replaceAllMapped(
    _jwtLike,
    (Match match) => '$tokenReferencePrefix${_referenceOf(match.group(0)!)}',
  );
  text = _redactPairs(text);
  text = text.replaceAllMapped(_longHex, (_) => maskedSecretPlaceholder);
  text = text.replaceAllMapped(_paddedBase64, (_) => maskedSecretPlaceholder);
  text = text.replaceAllMapped(
    _longAlnumSecret,
    (_) => maskedSecretPlaceholder,
  );
  return _truncate(text);
}

/// 遮罩敏感鍵值對中的值，鍵名與分隔符原樣保留（日誌仍要判讀得出來是哪個欄位）。
///
/// 逐字元錨定掃描而不是 `allMatches`：後者會把整個匹配吃掉，於是
/// `StateError: password=xxx` 這種「前一個鍵的值剛好是下一個鍵名」的寫法，
/// 會讓 `password` 被當成 `StateError:` 的值而漏擋（實測踩到過）。
String _redactPairs(String text) {
  final StringBuffer buffer = StringBuffer();
  int cursor = 0;
  while (cursor < text.length) {
    final Match? match = _pairPattern.matchAsPrefix(text, cursor);
    if (match == null) {
      buffer.write(text[cursor]);
      cursor++;
      continue;
    }
    final String key = match.group(1)!;
    final String value = match.group(2)!;
    final String normalized = _normalizeKey(key);
    final bool neverRecord = _neverRecordKeys.contains(normalized);
    if (!neverRecord && !_referenceKeys.contains(normalized)) {
      // 只寫到鍵名結束，讓值的位置有機會被重新識別為下一個鍵。
      buffer.write(key);
      cursor += key.length;
      continue;
    }
    buffer.write(text.substring(cursor, match.end - value.length));
    buffer.write(
      neverRecord
          ? redactedPlaceholder
          : '$tokenReferencePrefix${_referenceOf(value)}',
    );
    cursor = match.end;
  }
  return buffer.toString();
}

/// 截斷過長文字。
String _truncate(String text) {
  if (text.length <= maxLoggedTextLength) {
    return text;
  }
  return '${text.substring(0, maxLoggedTextLength)}…';
}

/// 從異常物件取出一段可安全記錄的描述（不含原始值）。
String describeError(Object error) =>
    redactText('${error.runtimeType}: $error');

/// 堆疊僅供本機排錯：內容只有函式與位置，但仍走同一條脫敏管線並截斷。
String describeStack(StackTrace? stack, {int maxLines = 10}) {
  if (stack == null) {
    return '';
  }
  final List<String> lines = stack
      .toString()
      .split('\n')
      .where((String line) => line.trim().isNotEmpty)
      .toList();
  final List<String> kept = lines.take(maxLines).toList();
  final int dropped = lines.length - kept.length;
  final String suffix = dropped > 0 ? '\n…（另有 $dropped 行）' : '';
  return redactText('${kept.join('\n')}$suffix');
}
